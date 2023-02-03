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

desc "Script for a Kokoro-based trigger"

long_desc \
  "This tool is designed to be called as the entrypoint for a Kokoro job " \
    "that participates in a release pipeline. It reads its input from " \
    "environment variables, and executes build and publish non-interactively.",
  "",
  "The following environment variables should be set when invoking:",
  "",
  "KOKORO_GFILE_DIR - Base directory for gfile inclusion. Should be set by " \
    "the Kokoro environment. (Required.)",
  "GAS_SOURCE_GEM - The gfile path (i.e. relative to KOKORO_GFILE_DIR) for " \
    "the source gem input. Required.",
  "GAS_ADDITIONAL_GEMS - The gfile paths for any additional gems that do " \
    "not need further building but should be released. Multiple gem paths " \
    "should be delimited by colons. Optional.",
  "GAS_PLATFORMS - Colon-delimited list of gem platforms that should be " \
    "built into binary gems. Optional.",
  "GAS_RUBY_VERSIONS - Colon-delimited list of Ruby versions that should " \
    "be built against. Optional.",
  "GAS_RUBYGEMS_KEY_FILE - The gfile path to a file that contains the API " \
    "token for Rubygems, to use for publication. Required."

include :fileutils
include :exec, e: true

# Entrypoint
def run
  cd context_directory
  read_input
  analyze_source
  build_binaries
  upload_gems
end

# Read input and configuration from the environment.
# See the long description for details.
def read_input
  gfile_dir = ENV["KOKORO_GFILE_DIR"]
  @source_gem = File.join gfile_dir, ENV["GAS_SOURCE_GEM"]
  @additional_gems = ENV["GAS_ADDITIONAL_GEMS"].to_s.split(":").map { |path| File.join gfile_dir, path }
  @platforms = ENV["GAS_PLATFORMS"].tr ":", ","
  @ruby_versions = ENV["GAS_RUBY_VERSIONS"].tr ":", ","
  @rubygems_key_file = File.join gfile_dir, ENV["GAS_RUBYGEMS_KEY_FILE"]
  @dry_run = !ENV["GAS_DRY_RUN"].to_s.empty?
  @workspace_dir = ENV["GAS_WORKSPACE_DIR"] || "workspace"
end

# Read the gem name and version from the source gem metadata
def analyze_source
  require "yaml"
  rm_rf @workspace_dir
  mkdir_p @workspace_dir
  cd @workspace_dir do
    exec ["gem", "unpack", "--spec", @source_gem]
    gemspec_file = Dir.glob("*.gemspec").first
    permitted_classes = [Gem::Specification, Gem::Dependency, Gem::Version, Gem::Requirement, Time, Symbol]
    gemspec = YAML.load_file gemspec_file, permitted_classes: permitted_classes
    @gem_name = gemspec.name
    @gem_version = gemspec.version.to_s
    raise "Wrong platform for source gem!" unless gemspec.platform == "ruby"
  end
end

# Invoke gas build to build .gem files from the provided source gem
def build_binaries
  tool = [
    "gas", "build",
    *verbosity_flags, "--yes",
    "--clean",
    "--workspace-dir", @workspace_dir,
    "--platform", @platforms,
    "--ruby", @ruby_versions,
    "--source-gem", @source_gem,
    @gem_name, @gem_version
  ]
  result = cli.run tool
  unless result.zero?
    logger.fatal "gas build failed with result #{result}"
    exit result
  end
end

# Invoke gas publish to publish all gems to rubygems.org, unless dry run has
# been requested
def upload_gems
  pkg_dir = File.join @workspace_dir, "#{@gem_name}-#{@gem_version}", "pkg"
  tool = [
    "gas", "publish",
    *verbosity_flags, "--yes",
    "--force",
    "--rubygems-key-file", @rubygems_key_file,
    pkg_dir, @source_gem, *@additional_gems
  ]
  tool << "--dry-run" if @dry_run
  result = cli.run tool
  unless result.zero?
    logger.fatal "gas publish failed with result #{result}"
    exit result
  end
end
