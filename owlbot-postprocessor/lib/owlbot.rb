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

require_relative "owlbot/impl"
require_relative "owlbot/ruby_content"
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
  # Exception thrown in the case of fatal postprocessor errors
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
    # The exec service in use.
    #
    # @return [Toys::Utils::Exec]
    #
    def exec_service
      @impl.exec_service
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
    # Return an {OwlBot::RubyContent} instance for the given string, which can
    # be used to manipulate Ruby source files.
    #
    # @param content [String]
    # @return [OwlBot::RubyContent]
    #
    def ruby_content content
      OwlBot::RubyContent.new content, logger: logger
    end

    ##
    # Execute a toys tool.
    #
    # Pass the tool name and arguments, and any options recognized by the Toys
    # exec util. For more info on arguments and return values, see
    # [Toys::Utils::Exec#exec](https://dazuma.github.io/toys/gems/toys/latest/Toys/Utils/Exec.html#exec-instance_method).
    #
    # @param cmd [String,Array<String>] The tool name and arguments.
    # @param opts [keywords] The command options.
    # @yieldparam controller [Toys::Utils::Exec::Controller] A controller for
    #     the subprocess streams.
    #
    # @return [Toys::Utils::Exec::Controller] The subprocess controller, if the
    #     process is running in the background.
    # @return [Toys::Utils::Exec::Result] The result, if the process ran in the
    #     foreground.
    #
    def toys cmd, **opts, &block
      @toys_bin_path ||= `which toys`.strip
      cmd = [@toys_bin_path] + cmd
      @impl.exec_service.exec cmd, **opts, &block
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
    def entrypoint logger: nil, exec_service: nil, gem_name: nil
      @impl = Impl.new logger, exec_service, gem_name
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
    def multi_entrypoint logger: nil, exec_service: nil
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
        entrypoint logger: logger, exec_service: exec_service, gem_name: child
      end
      self
    end
  end
end
