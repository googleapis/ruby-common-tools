# frozen_string_literal: true

# Copyright 2023 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

desc "Build binary gems given a source gem"

long_desc \
  "This tool builds a set of platform-specific binary gems given a source gem.",
  "",
  "Typically, you can specify just gem name and version, and the tool by " \
    "default will download the source gem from RubyGems, and build all the " \
    "gem's extensions that follow the standard configuration (i.e. inside " \
    "the ext/ directory, and using extconf.rb as the configuration file.)" \
    "You can also provide the source gem in a command line argument."

required_arg :gem_name do |arg|
  arg.desc "Name of the gem to build"
end
required_arg :gem_version do |arg|
  arg.desc "Version of the gem to build"
end

flag :platforms, "--platform=PLATFORMS" do |flag|
  flag.desc "Comma-delimited list of platforms to build"
  flag.accept Array
  flag.default Gas::DEFAULT_PLATFORMS
end
flag :ruby_versions, "--ruby=VERSIONS" do |flag|
  flag.desc "Comma-delimited list of ruby minor versions to build"
  flag.accept Array
  flag.default Gas::DEFAULT_RUBIES
end
flag :extensions, "--extensions=NAMES" do |flag|
  flag.desc "Comma-delimited list of extensions to build (all gem extensions if not provided)"
  flag.accept Array
end
flag :workspace_dir, "--workspace-dir=PATH" do |flag|
  flag.desc 'Workspace directory path (defaults to "workspace")'
  flag.default "workspace"
end
flag :clean do |flag|
  flag.desc "Clean out the workspace directory before running"
end
flag :source_gem, "--source-gem=PATH" do |flag|
  flag.desc "Path to source gem archive (fetches from rubygems if not provided)"
end
flag :yes do |flag|
  flag.desc "Auto-confirm"
end

include :exec, e: true
include :fileutils
include :gems
include :terminal

# Main entrypoint
def run
  setup_workspace
  setup_source
  determine_extensions
  expand_templates
  confirm_configuration
  precache_bundle
  perform_builds
end

# Ensure a clean workspace directory
def setup_workspace
  cd context_directory
  mkdir_p workspace_dir
  if clean
    Dir.children(workspace_dir).each do |child|
      rm_rf child
    end
  end
  cd workspace_dir
end

# Unpack the source gem, extracting the contents and metadata in the workspace
def setup_source
  gem_dir_name = "#{gem_name}-#{gem_version}"
  gem_file_name = "#{gem_name}-#{gem_version}.gem"
  gemspec_file_name = "#{gem_name}-#{gem_version}.gemspec"
  rm_f gem_file_name
  rm_rf gem_dir_name
  rm_f gemspec_file_name
  if source_gem
    cp File.absolute_path(source_gem, context_directory), gem_file_name
  else
    exec ["gem", "fetch", gem_name, "--version=#{gem_version}", "--platform=ruby"]
  end
  exec ["gem", "unpack", gem_file_name]
  exec ["gem", "unpack", "--spec", gem_file_name]
  mv gemspec_file_name, "#{gem_dir_name}/#{gemspec_file_name}"
  rm gem_file_name
  cd gem_dir_name
end

# Determine which extensions to build, either those specified on the command
# line, or grab a list from the metadata.
def determine_extensions
  return if extensions
  set :extensions, []
  gemspec.extensions.each do |extconf|
    match = %r{^ext/(.*)/extconf\.rb$}.match extconf
    if match
      logger.info "Found standard extension: #{match[1]}"
      extensions << match[1]
    else
      logger.warn "Skipping nonstandard extconf: #{extconf}"
    end
  end
end

# Generate the necessary Rakefile and Gemfile given configuration and metadata
def expand_templates
  require "erb"
  rakefile_template = File.read find_data "rakefile.erb"
  rakefile_content = ERB.new(rakefile_template).result(binding)
  File.write "Rakefile", rakefile_content
  gemfile_template = File.read find_data "gemfile.erb"
  gemfile_content = ERB.new(gemfile_template).result(binding)
  File.write "Gemfile", gemfile_content
end

# Confirm the job on the command line, unless --yes is given.
def confirm_configuration
  puts "Workspace directory: #{workspace_dir}", :bold
  puts "Gem name: #{gem_name}", :bold
  puts "Gem version: #{gem_version}", :bold
  puts "Platforms: #{platforms.inspect}", :bold
  puts "Ruby versions: #{ruby_versions.inspect}", :bold
  puts "Extensions: #{extensions.inspect}", :bold
  exit 1 unless yes || confirm("Proceed? ", default: true)
end

# Download the dependency gems into the bundle cache once, so we don't hit
# rubygems separately for every platform build.
# TODO(dazuma): Consider just vendoring these directly into the source tree.
def precache_bundle
  exec ["bundle", "cache"]
  rm_f "Gemfile.lock"
end

# Iterate through the requested platforms and build each binary gem
def perform_builds
  gem "rake-compiler-dock", Gas::RAKE_COMPILER_DOCK_VERSION
  require "rake_compiler_dock"
  success = true
  platforms.each do |platform|
    success &&= build_platform(platform)
  end
  exit 1 unless success
end

# Build a single binary gem for a given platform. Uses the docker image URL
# hard-coded into our configuration.
def build_platform platform
  old_rcd_image = ENV["RCD_IMAGE"]
  begin
    logger.info "Building #{platform} ..."
    ENV["RCD_IMAGE"] = Gas::RAKE_COMPILER_DOCK_IMAGE[platform]
    script = "bundle install --local && bundle exec rake native:#{platform} gem RUBY_CC_VERSION=#{ruby_cc_version}"
    RakeCompilerDock.sh script, platform: platform
    artifact_name = "pkg/#{gem_name}-#{gem_version}-#{platform}.gem"
    raise "Expected artifact #{artifact_name} not produced" unless File.file? artifact_name
    logger.info "Built: #{artifact_name}"
    true
  rescue StandardError => e
    logger.error "Failed to build platform #{platform}"
    logger.error e
    false
  ensure
    ENV["RCD_IMAGE"] = old_rcd_image
  end
end

# Load and memoize the gem metadata
def gemspec
  @gemspec ||= begin
    require "yaml"
    permitted_classes = [Gem::Specification, Gem::Dependency, Gem::Version, Gem::Requirement, Time, Symbol]
    YAML.load_file "#{gem_name}-#{gem_version}.gemspec", permitted_classes: permitted_classes
  end
end

# Construct the RUBY_CC_VERSION environment variable format
def ruby_cc_version
  ruby_versions.map { |ruby| "#{ruby}.0" }.join ":"
end
