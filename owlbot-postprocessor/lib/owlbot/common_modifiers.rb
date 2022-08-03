# frozen_string_literal: true

# Copyright 2022 Google LLC
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

module OwlBot
  ##
  # Class methods added to the OwlBot module, implementing common modifiers and
  # other tools useful for most OwlBot uses.
  #
  module CommonModifiers
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
  end
end
