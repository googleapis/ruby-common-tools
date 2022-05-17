# frozen_string_literal: true

# Copyright 2021 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "fileutils"
require "json"
require "toys/utils/exec"

module OwlBot
  ##
  # Internal implementation of the Ruby OwlBot postprocessor
  # @private
  #
  class Impl
    ##
    # Helper object for getting info on a particular path in the source and
    # destination directories
    # @private
    #
    class Path
      def initialize src_dir, dest_dir, local_path = nil
        @src_dir = src_dir
        @dest_dir = dest_dir
        @local_path = local_path
      end

      attr_reader :local_path

      def child name
        Path.new(@src_dir, @dest_dir, @local_path ? ::File.join(@local_path, name) : name)
      end

      def src_path
        @src_path ||= @local_path ? ::File.join(@src_dir, @local_path) : @src_dir
      end

      def dest_path
        @dest_path ||= @local_path ? ::File.join(@dest_dir, @local_path) : @dest_dir
      end

      def src_stat
        unless defined? @src_stat
          @src_stat = ::File.lstat src_path rescue nil
        end
        @src_stat
      end

      def dest_stat
        unless defined? @dest_stat
          @dest_stat = ::File.lstat dest_path rescue nil
        end
        @dest_stat
      end

      def src_symlink?
        src_stat&.symlink?
      end

      def dest_symlink?
        dest_stat&.symlink?
      end

      def src_exist?
        src_stat ? true : false
      end

      def dest_exist?
        dest_stat ? true : false
      end

      def src_file?
        src_stat&.file? && !src_stat&.symlink?
      end

      def dest_file?
        dest_stat&.file? && !dest_stat&.symlink?
      end

      def src_directory?
        src_stat&.directory? && !src_stat&.symlink?
      end

      def dest_directory?
        dest_stat&.directory? && !dest_stat&.symlink?
      end

      def src_content
        return nil unless src_file?
        @src_content ||= ::File.read(src_path).freeze
      end

      def dest_content
        return nil unless dest_file?
        @dest_content ||= ::File.read(dest_path).freeze
      end

      def src_children
        return [] unless src_directory?
        @src_children ||= ::Dir.children(src_path).sort.map { |name| child name }
      end

      def dest_children
        return [] unless dest_directory?
        @dest_children ||= ::Dir.children(dest_path).sort.map { |name| child name }
      end

      def eql? other
        Path === other && @local_path == other.local_path
      end
      alias == eql?

      def hash
        @local_path.hash
      end
    end

    def initialize logger, exec_service, gem_name
      @logger = logger
      @exec_service = exec_service || ::Toys::Utils::Exec.new
      @repo_dir = ::Dir.getwd
      @staging_root_dir = ::File.join @repo_dir, STAGING_ROOT_NAME
      @gem_name = gem_name || find_staged_gem_name(@staging_root_dir)
      @staging_dir = ::File.join @staging_root_dir, @gem_name
      @gem_dir = ::File.join @repo_dir, @gem_name
      @script_path = find_custom_script gem_dir
      @manifest_path = ::File.join @gem_dir, MANIFEST_NAME
      @previous_generated_files, @previous_static_files = load_existing_manifest @manifest_path
      @next_generated_files = []
      @next_static_files = []
      @content_modifiers = []
    end

    attr_reader :repo_dir
    attr_reader :staging_dir
    attr_reader :gem_name
    attr_reader :gem_dir
    attr_reader :script_path
    attr_reader :manifest_path
    attr_reader :previous_generated_files
    attr_reader :previous_static_files
    attr_reader :content_modifiers
    attr_reader :next_generated_files
    attr_reader :next_static_files
    attr_reader :exec_service
    attr_accessor :logger

    def sanity_check
      error "No staging directory #{staging_dir}" unless ::File.directory? staging_dir
      error "No gem directory #{gem_dir}" unless ::File.directory? gem_dir
      logger&.info "Processing #{gem_name}"
      logger&.info "Moving from #{staging_dir} to #{gem_dir}"
      logger&.info "Using custom script #{script_path}" if script_path
    end

    def do_move
      error "Already moved!" unless ::File.directory? staging_dir
      copy_dir Path.new staging_dir, gem_dir
      ::FileUtils.rm_rf staging_dir
    end

    def update_manifest
      filter_next_manifest @next_generated_files, "generated"
      filter_next_manifest @next_static_files, "static"
      walk_add_to_manifest Path.new staging_dir, gem_dir
    end

    def finish
      if ::File.directory? staging_dir
        logger&.warn "Move was never called! Doing nothing."
        return
      end
      manifest = {
        "generated" => @next_generated_files.sort,
        "static" => @next_static_files.sort
      }
      ::File.open manifest_path, "w" do |file|
        file.puts ::JSON.pretty_generate manifest
      end
    end

    private

    def filter_next_manifest local_paths, type
      local_paths.delete_if do |local_path|
        path = Path.new staging_dir, gem_dir, local_path
        if path.dest_file? || path.dest_symlink?
          false
        else
          path_info local_path, "#{type} file was remmoved after move"
          true
        end
      end
    end

    def walk_add_to_manifest path
      if path.dest_directory?
        path.dest_children.each { |child| walk_add_to_manifest child }
      elsif (path.dest_file? || path.dest_symlink?) &&
            path.local_path != MANIFEST_NAME &&
            !(@next_generated_files + @next_static_files).include?(path.local_path) &&
            !gitignored?(path)
        path_info path, "static file was added after move"
        @next_static_files << path.local_path
      end
    end

    def find_staged_gem_name staging_root_dir
      error "No staging root dir #{staging_root_dir}" unless ::File.directory? staging_root_dir
      children = ::Dir.children staging_root_dir
      error "No staging dirs under #{staging_root_dir}" if children.empty?
      if children.size > 1
        error "You need to specify which gem to postprocess because there are multiple staging dirs: #{children}"
      end
      children.first
    end

    def find_custom_script gem_dir
      path = ::File.join gem_dir, SCRIPT_NAME
      ::File.file?(path) ? path : nil
    end

    def load_existing_manifest manifest_path
      if ::File.file? manifest_path
        manifest = begin
          ::JSON.load_file manifest_path
        rescue ::JSON::ParserError
          logger.warn "Ignoring malformed manifest file"
          {}
        end
        [manifest["generated"] || [], manifest["static"] || []]
      else
        [[], []]
      end
    end

    def copy_dir path
      (path.dest_children - path.src_children).each do |child|
        object_removed child
      end
      (path.src_children - path.dest_children).each do |child|
        object_added child
      end
      (path.src_children & path.dest_children).each do |child|
        object_changed child
      end
    end

    def object_removed path
      if path.dest_directory?
        directory_removed path
      elsif path.dest_file? || path.dest_symlink?
        file_removed path
      else
        path_warning path, "deleted unknown type object"
        ::FileUtils.rm_f path.dest_path
        true
      end
    end

    def directory_removed path
      all_deleted = path.dest_children.reduce true do |running, child|
        object_removed(child) && running
      end
      if all_deleted
        ::FileUtils.rm_rf path.dest_path
        path_info path, "deleted directory"
      end
      all_deleted
    end

    def file_removed path
      if previous_generated_files.include? path.local_path
        if path.dest_symlink?
          path_info path, "deleted existing symlink"
          ::FileUtils.rm_f path.dest_path
          true
        else
          !handle_file path
        end
      elsif gitignored? path
        path_warning path, "retained existing gitignored file"
        false
      elsif path.local_path == MANIFEST_NAME
        path_info path, "retained manifest"
        false
      else
        path_info path, "retained existing non-generated file"
        @next_static_files << path.local_path
        false
      end
    end

    def object_added path
      if path.src_symlink?
        ::FileUtils.copy_entry path.src_path, path.dest_path
        path_info path, "moved staged symlink"
        @next_generated_files << path.local_path
      elsif path.src_file?
        handle_file path
      elsif path.src_directory?
        ::FileUtils.mkdir path.dest_path
        path.src_children.each { |child| object_added child }
      end
    end

    def object_changed path
      if path.local_path == MANIFEST_NAME
        path_warning path, "prevented generated file from overwriting the manifest"
        return
      end
      if path.src_directory?
        directory_changed path
      elsif path.src_symlink?
        symlink_changed path
      elsif path.src_file?
        file_changed path
      else
        path_warning path, "ignored unknown source object"
      end
    end

    def directory_changed path
      if path.dest_directory?
        copy_dir path
      else
        path_warning path, "removed non-directory to make way for generated directory"
        ::FileUtils.rm_rf path.dest_path
        object_added path
      end
    end

    def symlink_changed path
      if path.dest_symlink?
        path_info path, "moved staged symlink"
      else
        path_warning path, "removed non-symlink to make way for generated symlink"
      end
      ::FileUtils.rm_f path.dest_path
      ::FileUtils.copy_entry path.src_path, path.dest_path
      @next_generated_files << path.local_path
    end

    def file_changed path
      if path.dest_file?
        if gitignored? path
          path_warning path, "previously gitignored file being replaced with generated file"
        elsif !previous_generated_files.empty? && !previous_generated_files.include?(path.local_path)
          path_warning path, "previously static file being replaced with generated file"
        end
      else
        path_warning path, "removed non-file to make way for generated file"
        ::FileUtils.rm_rf path.dest_path
      end
      handle_file path
    end

    def handle_file path
      content = apply_modifiers path
      if content.nil?
        if path.dest_content.nil?
          path_info path, "new staged file removed"
        else
          ::FileUtils.rm_f path.dest_path
          path_info path, "deleted existing file"
        end
      else
        label = content == path.src_content ? "" : " with modifications"
        if content == path.dest_content
          path_info path, "staged file#{label} identical to existing file"
        else
          ::FileUtils.cp path.src_path, path.dest_path
          ::File.open(path.dest_path, "w") { |file| file.write content } unless content == path.src_content
          path_info path, "moved staged file#{label}"
        end
        (path.src_content ? @next_generated_files : @next_static_files) << path.local_path
      end
      !content.nil?
    end

    def apply_modifiers path
      content = path.src_content
      content_modifiers.each do |modifier|
        next_content = modifier.call content.dup, path.dest_content, path.local_path
        if next_content != content
          path_info path, "modifier #{modifier.name.inspect} changed the content"
          content = next_content
        end
      end
      content
    end

    def gitignored? path
      full_path = ::File.join gem_name, path.local_path
      !exec_service.capture(["git", "check-ignore", full_path]).empty?
    end

    def error message
      raise Error, message
    end

    def path_info path, str
      logger&.info "#{path.local_path}: #{str}"
    end

    def path_warning path, str
      logger&.warn "#{path.local_path}: #{str}"
    end
  end
end
