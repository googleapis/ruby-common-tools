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
require_relative "version"

##
# Tools useful for implementing an OwlBot postprocessor.
#
module OwlBot
  ##
  # The name of the optional Ruby OwlBot customization script.
  # A library can provide a file of this name to customize postprocessing.
  #
  SCRIPT_NAME = ".owlbot.rb"

  ##
  # The name of the manifest file that the Ruby OwlBot postprocessor usees to
  # keep track of what files are generated. Used to determine if the
  # postprocessor should delete any files that were previously generated but
  # are no longer.
  #
  MANIFEST_NAME = ".owlbot-manifest.json"

  ##
  # The name of the root directory in the repo under which staging directories
  # should be located.
  #
  STAGING_ROOT_NAME = "owl-bot-staging"

  ##
  # The class for content modifiers. These provide a way to customize how newly
  # generated code replaces existing code. The content from the old and new
  # files can be combined, and/or additional changes/substitutions can be made.
  #
  class ContentModifier
    ##
    # The name given to this modifier. May be the empty string if the modifier
    # was not given a name.
    #
    # @return [String]
    #
    attr_reader :name

    # @private
    def initialize patterns, block, name
      @patterns = Array(patterns || //)
      @block = block
      @name = name.to_s
    end

    # @private
    def call src, dest, path
      return src unless @patterns.any? { |pattern| pattern === path }
      @block.call src, dest, path
    end
  end

  ##
  # Exception thrown in the case of fatal preprocessor errors
  #
  class Error < ::StandardError
  end

  class << self
    ##
    # The full path to the root of the repository clone
    #
    # @return [String]
    #
    def repo_dir
      @impl.repo_dir
    end

    ##
    # The full path to the staging directory where OwlBot has staged the
    # generated client, i.e. the "source" directory.
    #
    # @return [String]
    #
    def staging_dir
      @impl.staging_dir
    end

    ##
    # The name of the gem.
    #
    # @return [String]
    #
    def gem_name
      @impl.gem_name
    end

    ##
    # The full path to the gem directory, i.e. the "destination" directory.
    #
    # @return [String]
    #
    def gem_dir
      @impl.gem_dir
    end

    ##
    # The full path to the script file, if present; otherwise `nil`.
    #
    # @return [String,nil]
    #
    def script_path
      @impl.script_path
    end

    ##
    # The full path to the manifest file. Always set even if the manifest file
    # is not yet present.
    #
    # @return [String]
    #
    def manifest_path
      @impl.manifest_path
    end

    ##
    # A list of files that were generated the last time OwlBot ran.
    # This will be empty if OwlBot has not run on this library before.
    #
    # @return [Array<String>]
    #
    def previous_generated_files
      @impl.previous_generated_files
    end

    ##
    # A list of files that were present in the library but not generated (i.e.
    # static or handwritten files) the last time OwlBot ran.
    # This will be empty if OwlBot has not run on this library before.
    #
    # @return [Array<String>]
    #
    def previous_static_files
      @impl.previous_static_files
    end

    ##
    # A list of files that were generated during the current OwlBot run.
    #
    # Normally this is populated by the call to {OwlBot.move_files}, and
    # generally you should not modify this array. If you need to update the
    # manifest because you changed things after {OwlBot.move_files} was called,
    # use {OwlBot.update_manifest}.
    #
    # @return [Array<String>]
    #
    def next_generated_files
      @impl.next_generated_files
    end

    ##
    # A list of files that were present in the library but not generated (i.e.
    # static or handwritten files) during the current OwlBot run.
    #
    # Normally this is populated by the call to {OwlBot.move_files}, and
    # generally you should not modify this array. If you need to update the
    # manifest because you changed things after {OwlBot.move_files} was called,
    # use {OwlBot.update_manifest}.
    #
    # @return [Array<String>]
    #
    def next_static_files
      @impl.next_static_files
    end

    ##
    # A list of content modifiers that will be applied while moving files.
    # See {OwlBot.modifier}.
    #
    # @return [Array<OwlBot::ContentModifier>]
    #
    def content_modifiers
      @impl.content_modifiers
    end

    ##
    # The logger in use.
    #
    # @return [Logger]
    #
    def logger
      @impl.logger
    end

    ##
    # Set the logger.
    #
    # @param [Logger] new_logger
    #
    def logger= new_logger
      @impl.logger = new_logger
    end

    ##
    # The version of the Ruby postprocessor.
    #
    # @return [String]
    #
    def version
      VERSION
    end

    ##
    # Add a modifier to the modifier pipeline. This pipeline runs as files are
    # processed during {OwlBot.move_files} and provides a way to customize file
    # handling.
    #
    # As files from the staging directory are processed and reconciled against
    # the gem directory, every resulting file operation (creation,
    # modification, and deletion) is passed through the modifier pipeline. That
    # is, every generated file coming from the staging directory is processed,
    # _and_ every file that was previously generated (i.e. is in the generated
    # file list in the manifest) but is not present in staging. Files that are
    # neither currently nor previously generated are not touched.
    #
    # When a file is processed, each modifier in the pipeline is applied to it.
    # First, a modifier determines whether it will activate for that file based
    # on whether the file matches any of the given paths, which may be strings
    # or regexes. If no paths are specified, the modifier activates for every
    # file.
    #
    # If the modifier is active for a file, both the newly generated file and
    # the existing file are read, if present, and the contents plus the file
    # path are passed to the given block: `(new_str, existing_str, path)`. If
    # the new or existing file is not present (i.e. a file being created or
    # deleted), the corresponding content string is `nil`. The block must then
    # return the content to actually use for the moved file, or `nil` to
    # indicate the file should be deleted or not created. This result is then
    # passed to the next modifier in the pipeline as `new_str`. The final
    # result controls the handling of the file.
    #
    # @param path [String,Regexp,Array<String,Regexp>] Optional path filter(s)
    #     determining whether this modifier will run. If not present, this
    #     modifier will run for all paths.
    # @param name [String] Optional name for this modifier, identifying it in
    #     the list of objects returned from {OwlBot.content_modifiers}.
    # @param block [Proc] The modifier itself, which should take up to three
    #     arguments: `(new_str, existing_str, path)`.
    #
    def modifier path: nil, name: nil, &block
      @impl.content_modifiers << ContentModifier.new(path, block, name)
      self
    end

    ##
    # A convenience method that removes any modifiers matching the given name
    # from the modifier pipeline. The name may be a string or a regex. This is
    # typically used to remove one of the default modifiers installed by
    # {OwlBot.install_default_modifiers}.
    #
    # @param name [String,Regexp]
    #
    def remove_modifiers_named name
      @impl.content_modifiers.delete_if { |modifier| name === modifier.name }
      self
    end

    ##
    # A convenience method that installs a modifier preserving copyright years
    # in existing files.
    #
    # @param path [String,Regexp,Array<String,Regexp>] Optional path filter(s)
    #     determining whether this modifier will run. Defaults to
    #     `[/Rakefile$/, /\.rb$/, /\.gemspec$/, /Gemfile$/]`.
    # @param name [String] Optional name for the modifier to add. Defaults to
    #     `"preserve_existing_copyright_years"`.
    #
    def preserve_existing_copyright_years path: nil, name: nil
      path ||= [/Rakefile$/, /\.rb$/, /\.gemspec$/, /Gemfile$/]
      name ||= "preserve_existing_copyright_years"
      modifier path: path, name: name do |src, dest|
        if src && dest
          regex = /^# Copyright (\d{4}) Google LLC$/
          match = regex.match dest
          src = src.sub regex, "# Copyright #{match[1]} Google LLC" if match
        end
        src
      end
    end

    ##
    # A convenience method that installs a modifier preserving `release_level`
    # fields in existing `.repo-metadata.json` files.
    #
    # @param name [String] Optional name for the modifier to add. Defaults to
    #     `"preserve_repo_metadata_release_levels"`.
    #
    def preserve_repo_metadata_release_levels name: nil
      path = [/\.repo-metadata\.json$/]
      name ||= "preserve_repo_metadata_release_levels"
      modifier path: path, name: name do |src, dest|
        if src && dest
          regex = /"release_level": "(\w+)"/
          match = regex.match dest
          src = src.sub regex, "\"release_level\": \"#{match[1]}\"" if match
        end
        src
      end
    end

    ##
    # A convenience method that installs a modifier preserving gem release
    # `version` fields in existing snippet metadata files.
    #
    # @param name [String] Optional name for the modifier to add. Defaults to
    #     `"preserve_snippet_metadata_release_versions"`.
    #
    def preserve_snippet_metadata_release_versions name: nil
      path = [%r{^snippets/snippet_metadata_[\w.]+\.json$}]
      name ||= "preserve_snippet_metadata_release_versions"
      modifier path: path, name: name do |src, dest|
        if src && dest
          match = /"version": "(\d+\.\d+\.\d+)"/.match dest
          src = src.sub(/"version": "(\d+\.\d+\.\d+)?"/, "\"version\": \"#{match[1]}\"") if match
        end
        src
      end
    end

    ##
    # A convenience method that installs a modifier preventing overwriting of
    # certain files, if they exist, by newly generated files. This is commonly
    # used to prevent `CHANGELOG.md` and `version.rb` files from being
    # overwritten.
    #
    # @param path [String,Regexp,Array<String,Regexp>] Path filter(s)
    #     determining which files are affected. Required.
    # @param name [String] Optional name for the modifier to add. A default
    #     will be supplied if omitted.
    #
    def prevent_overwrite_of_existing path, name: nil
      name ||= "prevent_overwrite_of_existing #{path}"
      modifier path: path, name: name do |src, dest|
        dest || src
      end
    end

    ##
    # Install the default modifiers. This includes:
    #
    # * A modifier named `"preserve_existing_copyright_years"` which ensures
    #   the copyright year of existing files is not modified.
    # * A modifier named `"preserve_repo_metadata_release_levels"` which
    #   ensures the `"release_level"` field of `.repo-metadata.json` files is
    #   not modified.
    # * A modifier named `"preserve_snippet_metadata_release_versions"` which
    #   ensures the `"version"` field of snippet metadata files is not modified.
    # * A modifier named `"prevent_overwrite_of_existing_changelog_file"` which
    #   ensures that an existing changelog file is not replaced by the empty
    #   generated changelog.
    # * A modifier named `"prevent_overwrite_of_existing_gem_version_file"`
    #   which ensures that an existing gem version file (`version.rb`) is not
    #   replaced by the generated file with the initial version.
    #
    # This is called automatically for every run. You generally don't need to
    # call it a second time unless you've cleared the modifier list and need to
    # reinstall them. However, you can use {OwlBot.remove_modifiers_named} to
    # remove the individual defaults if you want to disable or replace them.
    #
    def install_default_modifiers
      preserve_existing_copyright_years
      preserve_repo_metadata_release_levels
      preserve_snippet_metadata_release_versions
      prevent_overwrite_of_existing "CHANGELOG.md",
                                    name: "prevent_overwrite_of_existing_changelog_file"
      prevent_overwrite_of_existing "lib/#{@impl.gem_name.tr '-', '/'}/version.rb",
                                    name: "prevent_overwrite_of_existing_gem_version_file"
    end

    ##
    # Move files from the staging directory to the gem directory.
    # Any customizations such as installing {OwlBot.modifier} functions should
    # be done prior to calling this.
    #
    # After this call is complete, the staged files will be moved into the gem
    # directory, the staging directory will be deleted, and you will be able to
    # review the tentative manifest via {OwlBot.next_generated_files} and
    # {OwlBot.next_static_files}. The manifest file itself will not yet be
    # updated.
    #
    def move_files
      @impl.do_move
      self
    end

    ##
    # Updates the tentative manifest (i.e. {OwlBot.next_generated_files} and
    # {OwlBot.next_static_files}) to match the current state of the gem
    # directory. Often called if you made changes after {OwlBot.move_files}.
    # Does not write the manifest file itself.
    #
    def update_manifest
      @impl.update_manifest
      self
    end

    ##
    # You may call this method to report a fatal error.
    #
    # @param message [String]
    #
    def error message
      @impl.error message
    end

    # ---- Private implementation below this point ----

    # @private
    def entrypoint logger: nil, gem_name: nil
      @impl = Impl.new logger, gem_name
      @impl.sanity_check
      install_default_modifiers
      if @impl.script_path
        save_dir = ::Dir.getwd
        begin
          load @impl.script_path
        ensure
          ::Dir.chdir save_dir unless save_dir == ::Dir.getwd
        end
      else
        @impl.do_move
      end
      @impl.finish
      self
    end

    # @private
    def multi_entrypoint logger: nil
      unless ::File.directory? STAGING_ROOT_NAME
        logger&.warn "No staging root dir #{STAGING_ROOT_NAME}. Nothing for the Ruby postprocessor to do."
        return self
      end
      children = ::Dir.children STAGING_ROOT_NAME
      if children.empty?
        logger&.warn "No staging dirs under #{STAGING_ROOT_NAME}. Nothing for the Ruby postprocessor to do."
        return self
      end
      logger&.info "Multi-entrypoint found staging directories: #{children}"
      children.each do |child|
        entrypoint logger: logger, gem_name: child
      end
      self
    end
  end

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

  # @private
  class Impl
    def initialize logger, gem_name
      @logger = logger
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
      @exec_service = ::Toys::Utils::Exec.new
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
    attr_accessor :logger
    attr_accessor :exec_service

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
