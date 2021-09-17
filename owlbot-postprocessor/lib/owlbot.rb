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
require_relative "version"

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
    def initialize patterns, block, name
      @patterns = Array(patterns || //)
      @block = block
      @name = name || "(unnamed)"
    end

    attr_reader :name

    def call src, dest, path
      return src unless @patterns.any? { |pattern| pattern === path }
      @block.call src, dest, path
    end
  end

  class << self
    ##
    # The full path to the root of the repository clone
    #
    # @return [String]
    #
    attr_reader :repo_dir

    ##
    # The full path to the staging directory where OwlBot has staged the
    # generated client, i.e. the "source" directory.
    #
    # @return [String]
    #
    attr_reader :staging_dir

    ##
    # The name of the gem.
    #
    # @return [String]
    #
    attr_reader :gem_name

    ##
    # The full path to the gem directory, i.e. the "destination" directory.
    #
    # @return [String]
    #
    attr_reader :gem_dir

    ##
    # The full path to the script file, if present; otherwise `nil`.
    #
    # @return [String,nil]
    #
    attr_reader :script_path

    ##
    # The full path to the manifest file.
    #
    # @return [String]
    #
    attr_reader :manifest_path

    ##
    # A list of files that were generated the last time OwlBot ran.
    # This will be empty if OwlBot has not run on this library before.
    #
    # @return [Array<String>]
    #
    attr_reader :previous_generated_files

    ##
    # A list of files that were present in the library but not generated the
    # last time OwlBot ran.
    # This will be empty if OwlBot has not run on this library before.
    #
    # @return [Array<String>]
    #
    attr_reader :previous_static_files

    ##
    # A list of paths and path regexes that will be preserved during this run.
    # That is, they will not be overwritten by any newly generated files, nor
    # will they be deleted if they were previously generated but were not
    # generated during this run.
    #
    # @return [Array<String,Regexp>]
    #
    attr_reader :preserved_paths

    ##
    # A list of content modifiers that will be applied while moving files.
    #
    # @return [Array<OwlBot::ContentModifier>]
    #
    attr_reader :content_modifiers

    ##
    # Quietness of logging.
    #
    # * `0` (the default) indicates normal logging, displaying for each file
    #   the move decision made and any modifications done
    # * `1` indicates quiet mode, displaying only warnings and fatal exceptions
    # * `2` indicates extra-quiet mode, displaying only fatal exceptions
    #
    attr_accessor :quiet_level

    ##
    # The version of the Ruby postprocessor
    #
    # @return [String]
    #
    def version
      VERSION
    end

    ##
    # Add paths and/or regexes identifying files that should be preserved
    # when {#move_files} is later performed. A preserved file (or directory)
    # will not be overwritten by newly generated files, nor will it be deleted
    # if it was previously generated but was not generated during this run.
    #
    # @param path [String,Regexp,Array<String,Regexp>]
    #
    def preserve path: nil
      @preserved_paths.concat Array(path)
      self
    end

    ##
    # Add a modifier to the pipeline that runs as files are processed when
    # {#move_files} is later performed.
    #
    # As every file is being moved, each modifier in the pipeline is applied to
    # it. First, a modifier determines whether it will activate for that file
    # based on whether the file matches any of the given paths, which may be
    # strings or regexes. If no paths are specified, the modifier activates for
    # every file.
    #
    # If the modifier is active for a file, the newly generated file, as well
    # as the existing file (if any) are read, and the two strings plus the file
    # path are passed to the given block: `(new_str, existing_str, path)`. If
    # no existing file is present, `nil` is passed for `existing_str`. The
    # block must then return the content to actually use for the moved file.
    # If additional modifiers are present in the pipeline, the next modifier
    # will received this returned string as `new_str`.
    #
    # @param path [String,Regexp,Array<String,Regexp>] Optional path filter(s)
    #     determining whether this modifier will run. If not present, this
    #     modifier will run for all paths.
    # @param name [String] Optional name for this modifier, identifying it in
    #     the list of objects returned from {#content_modifiers}.
    # @param block [Proc] The modifier itself, which should take up to three
    #     arguments: `(new_str, existing_str, path)`.
    #
    def modifier path: nil, name: nil, &block
      @content_modifiers << ContentModifier.new(path, block, name)
      self
    end

    ##
    # Move files from the staging directory to the gem directory.
    # Any customization of the {#preserve} paths or the {#modifier} functions
    # should be done prior to calling this.
    #
    # After this call is complete, the staged files will be moved into the gem
    # directory, the staging directory will be deleted, and the manifest file
    # will be written.
    #
    def move_files
      copy_dir []
      ::FileUtils.rm_rf @staging_root_dir
      write_manifest
      self
    end

    # ---- Private implementation below this point ----

    # @private
    def entrypoint quiet_level: 0
      @quiet_level = quiet_level
      setup
      apply_default_config
      if script_path
        load script_path
      else
        move_files
      end
      self
    end

    private

    def setup
      @repo_dir = ::Dir.getwd
      @staging_root_dir = ::File.join @repo_dir, STAGING_ROOT_NAME
      staging_dirs = ::Dir.children @staging_root_dir
      raise "Unexpected staging dirs: #{staging_dirs.inspect}" unless staging_dirs.size == 1
      @staging_dir = ::File.join @staging_root_dir, staging_dirs.first
      @gem_name = ::File.basename @staging_dir
      @gem_dir = ::File.join @repo_dir, @gem_name
      path = ::File.join @gem_dir, SCRIPT_NAME
      @script_path = ::File.file?(path) ? path : nil
      @manifest_path = ::File.join @gem_dir, MANIFEST_NAME
      @previous_generated_files = []
      @previous_static_files = []
      @next_generated_files = []
      @next_static_files = []
      if ::File.file? @manifest_path
        manifest = ::JSON.load_file @manifest_path
        @previous_generated_files = manifest["generated"] || []
        @previous_static_files = manifest["static"] || []
      end
      @preserved_paths = []
      @content_modifiers = []
    end

    def apply_default_config
      preserve path: ["CHANGELOG.md", "lib/#{gem_name.tr '-', '/'}/version.rb"]

      copyright_regex = /^# Copyright (\d{4}) Google LLC$/
      ruby_patterns = [/Rakefile$/, /\.rb$/, /\.gemspec$/, /Gemfile$/]
      modifier path: ruby_patterns, name: "copyright year preserver" do |src, dest|
        match = copyright_regex.match dest
        src = src.sub copyright_regex, "# Copyright #{match[1]} Google LLC" if match
        src
      end
    end

    def copy_dir arr
      src_children = ::Dir.children(::File.join(staging_dir, *arr)).sort
      dest_children = ::Dir.children(::File.join(gem_dir, *arr)).sort
      (dest_children - src_children).each do |child|
        object_removed arr + [child]
      end
      (src_children - dest_children).each do |child|
        object_added arr + [child]
      end
      (src_children & dest_children).each do |child|
        object_changed arr + [child]
      end
    end

    def object_removed arr
      path = arr.join "/"
      if preserved_paths.any? { |pattern| pattern === path }
        path_info path, "preserved and not deleted"
        recursively_add_to_next_static path
        return false
      end
      dest = ::File.join gem_dir, path
      if ::File.file? dest
        if previous_generated_files.include? path
          path_info path, "deleted file"
          ::FileUtils.rm_f dest
          true
        else
          path_info path, "retained existing non-generated file"
          @next_static_files << path
          false
        end
      elsif ::File.directory? dest
        all_deleted = ::Dir.children(dest).reduce(true) do |running, child|
          object_removed(arr + [child]) && running
        end
        if all_deleted
          ::FileUtils.rm_rf dest
          path_info path, "deleted directory"
        end
        all_deleted
      end
    end

    def object_added arr
      path = arr.join "/"
      src = ::File.join staging_dir, path
      if ::File.file? src
        copy_file path
        @next_generated_files << path
      elsif ::File.directory? src
        ::FileUtils.mkdir ::File.join(gem_dir, path)
        ::Dir.children(src).each { |child| object_added arr + [child] }
      end
    end

    def object_changed arr
      path = arr.join "/"
      if preserved_paths.any? { |pattern| pattern === path }
        path_info path, "preserved and not copied"
        recursively_add_to_next_static path
        return
      end
      src = ::File.join staging_dir, path
      dest = ::File.join gem_dir, path
      if ::File.file? src
        if ::File.directory? dest
          path_warning path, "removed directory to make way for generated file"
          ::FileUtils.rm_rf dest
        end
        copy_file path
        @next_generated_files << path
      elsif ::File.directory? src
        if ::File.file? dest
          path_warning path, "removed file to make way for generated directory"
          ::FileUtils.rm_rf dest
          object_added arr
        elsif ::File.directory? dest
          copy_dir arr
        end
      end
    end

    def recursively_add_to_next_static path
      full_path = ::File.join gem_dir, path
      if ::File.file? full_path
        @next_static_files << path
      elsif ::File.directory? full_path
        ::Dir.children(full_path).each do |child|
          recursively_add_to_next_static ::File.join(path, child)
        end
      end
    end

    def copy_file path
      src = ::File.join staging_dir, path
      dest = ::File.join gem_dir, path
      content = src_content = ::File.read(src).freeze
      dest_content = ::File.file?(dest) ? ::File.read(dest).freeze : nil
      content_modifiers.each do |modifier|
        next_content = modifier.call content.dup, dest_content, path
        if next_content != content
          path_info path, "modifier #{modifier.name.inspect} changed the content"
          content = next_content
        end
      end
      label = content == src_content ? "" : " with modifications"
      if content == dest_content
        path_info path, "staged file#{label} identical to existing file"
      else
        ::FileUtils.cp src, dest
        ::File.open(dest, "w") { |file| file.write content } unless content == src_content
        path_info path, "copied staged file#{label}"
      end
    end

    def write_manifest
      manifest = {
        "generated" => @next_generated_files.sort,
        "static" => @next_static_files.sort
      }
      ::File.open manifest_path, "w" do |file|
        file.write ::JSON.pretty_generate manifest
      end
    end

    def path_info path, str
      puts "#{path}: #{str}" if quiet_level <= 0
    end

    def path_warning path, str
      puts "#{path}: WARNING: #{str}" if quiet_level <= 1
    end
  end
end
