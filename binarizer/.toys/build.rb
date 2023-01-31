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
    "the ext/ directory, and using extconf.rb as the configuration file.) " \
    "The tool can also optionally push the built binary gems to RubyGems."

required_arg :gem_name do |arg|
  arg.desc "Name of the gem to build"
end
required_arg :gem_version do |arg|
  arg.desc "Version of the gem to build"
end

flag :platforms, "--platform=PLATFORMS" do |flag|
  flag.desc "Comma-delimited list of platforms to build"
  flag.accept Array
  flag.default Binarizer::DEFAULT_PLATFORMS
end
flag :ruby_versions, "--ruby=VERSIONS" do |flag|
  flag.desc "Comma-delimited list of ruby minor versions to build"
  flag.accept Array
  flag.default Binarizer::DEFAULT_RUBIES
end
flag :extensions, "--extensions=NAMES" do |flag|
  flag.desc "Comma-delimited list of extensions to build (all gem extensions if not provided)"
  flag.accept Array
end
flag :rubygems_key, "--rubygems-key=KEY" do |flag|
  flag.desc "API key for pushing to RubyGems (pushes disabled if not provided)"
end
flag :workspace_dir, "--workspace-dir=PATH" do |flag|
  flag.desc 'Workspace directory path (defaults to "workspace")'
  flag.default "workspace"
end
flag :clean do |flag|
  flag.desc "Clean out the workspace directory before running"
end
flag :source_gem, "--source-gem=PATH" do |flag|
  flag.desc "Path to source gem (fetches from rubygems if not provided)"
end
flag :yes do |flag|
  flag.desc "Auto-confirm"
end

include :exec, e: true
include :fileutils
include :gems
include :terminal

def run
  do_setup
  do_builds
  do_pushes
end

def do_setup
  setup_workspace
  setup_source
  determine_extensions
  expand_templates
  confirm_configuration
  precache_bundle
end

def do_builds
  gem "rake-compiler-dock", Binarizer::RAKE_COMPILER_DOCK_VERSION
  require "rake_compiler_dock"
  ruby_cc_version = ruby_versions.map { |ruby| "#{ruby}.0" }.join ":"
  platforms.each do |platform|
    logger.info "Building #{platform} ..."
    script = "bundle install --local && bundle exec rake native:#{platform} gem RUBY_CC_VERSION=#{ruby_cc_version}"
    RakeCompilerDock.sh script, platform: platform
    logger.info "Built: #{workspace_dir}/#{gem_name}-#{gem_version}/pkg/#{gem_name}-#{gem_version}-#{platform}.gem"
  end
end

def do_pushes
  return unless rubygems_key
  gem "gems", Binarizer::GEMS_VERSION
  require "gems"
  Gems.configure do |config|
    config.key = rubygems_key
  end
  platforms.each do |platform|
    gem_file_name = "pkg/#{gem_name}-#{gem_version}-#{platform}.gem"
    logger.info "Pushing to RubyGems: #{gem_file_name} ..."
    Gems.push File.new "pkg/#{gem_file_name}"
    logger.info "Pushed: #{workspace}/#{gem_name}-#{gem_version}/pkg/#{gem_file_name}"
  end
end

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

def gemspec
  @gemspec ||= begin
    require "yaml"
    permitted_classes = [Gem::Specification, Gem::Dependency, Gem::Version, Gem::Requirement, Time, Symbol]
    YAML.load_file "#{gem_name}-#{gem_version}.gemspec", permitted_classes: permitted_classes
  end
end

def expand_templates
  require "erb"
  rakefile_template = File.read find_data "rakefile.erb"
  rakefile_content = ERB.new(rakefile_template).result(binding)
  File.write "Rakefile", rakefile_content
  gemfile_template = File.read find_data "gemfile.erb"
  gemfile_content = ERB.new(gemfile_template).result(binding)
  File.write "Gemfile", gemfile_content
end

def precache_bundle
  exec ["bundle", "cache"]
  rm_f "Gemfile.lock"
end

def confirm_configuration
  puts "Workspace directory: #{workspace_dir}", :bold
  puts "Gem name: #{gem_name}", :bold
  puts "Gem version: #{gem_version}", :bold
  puts "Platforms: #{platforms.inspect}", :bold
  puts "Ruby versions: #{ruby_versions.inspect}", :bold
  puts "Extensions: #{extensions.inspect}", :bold
  puts "Push to rubygems: #{rubygems_key ? 'enabled' : 'disabled'}", :bold
  exit 1 unless yes || confirm("Proceed? ", default: true)
end
