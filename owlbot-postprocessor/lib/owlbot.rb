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
    # The full path to the manifest file. Always set even if the manifest file
    # is not yet present.
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
    # A list of files that were present in the library but not generated (i.e.
    # static or handwritten files) the last time OwlBot ran.
    # This will be empty if OwlBot has not run on this library before.
    #
    # @return [Array<String>]
    #
    attr_reader :previous_static_files

    ##
    # A list of content modifiers that will be applied while moving files.
    # See {#modifier}.
    #
    # @return [Array<OwlBot::ContentModifier>]
    #
    attr_reader :content_modifiers

    ##
    # The logger in use.
    #
    # @return [Logger]
    #
    attr_accessor :logger

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
    # processed during {#move_files} and provides a way to customize file
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
    #     the list of objects returned from {#content_modifiers}.
    # @param block [Proc] The modifier itself, which should take up to three
    #     arguments: `(new_str, existing_str, path)`.
    #
    def modifier path: nil, name: nil, &block
      @content_modifiers << ContentModifier.new(path, block, name)
      self
    end

    ##
    # A convenience method that removes any modifiers matching the given name
    # from the modifier pipeline. The name may be a string or a regex. This is
    # typically used to remove one of the default modifiers installed by
    # {#install_default_modifiers}.
    #
    # @param name [String,Regexp]
    #
    def remove_modifiers_named name
      @content_modifiers.delete_if { |modifier| name === modifier.name }
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
          copyright_regex = /^# Copyright (\d{4}) Google LLC$/
          match = copyright_regex.match dest
          src = src.sub copyright_regex, "# Copyright #{match[1]} Google LLC" if match
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
    # * A modifier named `"prevent_overwrite_of_existing_changelog_file"` which
    #   ensures that an existing changelog file is not replaced by the empty
    #   generated changelog.
    # * A modifier named `"prevent_overwrite_of_existing_gem_version_file"`
    #   which ensures that an existing gem version file (`version.rb`) is not
    #   replaced by the generated file with the initial version.
    #
    # This is called automatically for every run. You generally don't need to
    # call it a second time unless you've cleared the modifier list and need to
    # reinstall them. However, you can use {#remove_modifiers_named} to remove
    # the individual defaults if you want to disable or replace them.
    #
    def install_default_modifiers
      preserve_existing_copyright_years
      prevent_overwrite_of_existing "CHANGELOG.md",
                                    name: "prevent_overwrite_of_existing_changelog_file"
      prevent_overwrite_of_existing "lib/#{gem_name.tr '-', '/'}/version.rb",
                                    name: "prevent_overwrite_of_existing_gem_version_file"
    end

    ##
    # Move files from the staging directory to the gem directory.
    # Any customizations such as installing {#modifier} functions should be
    # done prior to calling this.
    #
    # After this call is complete, the staged files will be moved into the gem
    # directory, the staging directory will be deleted, and the manifest file
    # will be written.
    #
    def move_files
      copy_dir []
      ::FileUtils.rm_rf staging_dir
      write_manifest
      self
    end

    ##
    # You may call this method to report a fatal error
    #
    # @param message [String]
    #
    def error message
      raise Error, message
    end

    # ---- Private implementation below this point ----

    # @private
    def entrypoint logger: nil, gem_name: nil
      setup logger, gem_name
      sanity_check
      install_default_modifiers
      if script_path
        load script_path
      else
        move_files
      end
      self
    end

    private

    def setup logger, gem_name
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
    end

    def find_staged_gem_name staging_root_dir
      error "No staging root dir #{staging_root_dir}" unless ::File.directory? staging_root_dir
      staging_dirs = ::Dir.children staging_root_dir
      error "No staging dirs under #{staging_root_dir}" if staging_dirs.empty?
      if staging_dirs.size > 1
        error "You need to specify which gem to postprocess because there are multiple staging dirs: #{staging_dirs}"
      end
      staging_dirs.first
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

    def sanity_check
      error "No staging directory #{staging_dir}" unless ::File.directory? staging_dir
      error "No gem directory #{gem_dir}" unless ::File.directory? gem_dir
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
      dest = ::File.join gem_dir, path
      if ::File.file? dest
        if previous_generated_files.include? path
          !handle_file path
        elsif gitignored? path
          path_warning path, "retained existing gitignored file"
          false
        elsif path == MANIFEST_NAME
          path_info path, "retained manifest"
          false
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
        handle_file path
      elsif ::File.directory? src
        ::FileUtils.mkdir ::File.join(gem_dir, path)
        ::Dir.children(src).each { |child| object_added arr + [child] }
      end
    end

    def object_changed arr
      path = arr.join "/"
      if path == MANIFEST_NAME
        path_warning path, "prevented generated file from overwriting the manifest"
        return
      end
      src = ::File.join staging_dir, path
      dest = ::File.join gem_dir, path
      if ::File.file? src
        if ::File.file? dest
          if gitignored? path
            path_warning path, "previously gitignored file being replaced with generated file"
          elsif !previous_generated_files.empty? && !previous_generated_files.include?(path)
            path_warning path, "previously static file being replaced with generated file"
          end
        else
          path_warning path, "removed non-file to make way for generated file"
          ::FileUtils.rm_rf dest
        end
        handle_file path
      elsif ::File.directory? src
        if ::File.directory? dest
          copy_dir arr
        else
          path_warning path, "removed non-directory to make way for generated directory"
          ::FileUtils.rm_rf dest
          object_added arr
        end
      end
    end

    def handle_file path
      src = ::File.join staging_dir, path
      dest = ::File.join gem_dir, path
      src_content = ::File.file?(src) ? ::File.read(src).freeze : nil
      dest_content = ::File.file?(dest) ? ::File.read(dest).freeze : nil
      content = apply_modifiers path, src_content, dest_content
      if content.nil?
        if dest_content.nil?
          path_info path, "new staged file removed"
        else
          ::FileUtils.rm_f dest
          path_info path, "deleted existing file"
        end
      else
        label = content == src_content ? "" : " with modifications"
        if content == dest_content
          path_info path, "staged file#{label} identical to existing file"
        else
          ::FileUtils.cp src, dest
          ::File.open(dest, "w") { |file| file.write content } unless content == src_content
          path_info path, "moved staged file#{label}"
        end
        (src_content ? @next_generated_files : @next_static_files) << path
      end
      !content.nil?
    end

    def apply_modifiers path, content, dest_content
      content_modifiers.each do |modifier|
        next_content = modifier.call content.dup, dest_content, path
        if next_content != content
          path_info path, "modifier #{modifier.name.inspect} changed the content"
          content = next_content
        end
      end
      content
    end

    def gitignored? path
      !`git check-ignore #{::File.join gem_name, path}`.empty?
    end

    def write_manifest
      manifest = {
        "generated" => @next_generated_files.sort,
        "static" => @next_static_files.sort
      }
      ::File.open manifest_path, "w" do |file|
        file.puts ::JSON.pretty_generate manifest
      end
    end

    def path_info path, str
      logger&.info "#{path}: #{str}"
    end

    def path_warning path, str
      logger&.warn "#{path}: #{str}"
    end
  end
end
