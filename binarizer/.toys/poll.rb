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

desc "Poll RubyGems for binary build jobs"

required_arg :gem_name do |arg|
  arg.desc "Name of the gem to poll"
end

flag :max_age, "--max-age=DAYS" do |flag|
  flag.desc "Maximum age to check, in days (defaults to 7)"
  flag.accept Integer
  flag.default 7
end
flag :omit_versions, "--omit-versions=VERSIONS" do |flag|
  flag.desc "Comma-delimited list of versions to omit"
  flag.accept Array
  flag.default []
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
flag :yes do |flag|
  flag.desc "Auto-confirm"
end

include :exec, e: true
include :gems
include :terminal

def run
  worklist = compute_worklist
  confirm_worklist worklist
  run_worklist worklist
end

def compute_worklist
  find_needed_builds analyze_version_platforms truncated_rubygems_data
end

def truncated_rubygems_data
  gem "gems", Binarizer::GEMS_VERSION
  require "gems"
  records = Gems.versions gem_name
  cutoff_timestamp =
    if max_age <= 0
      "0"
    else
      (Time.now - max_age * 86400).utc.strftime "%Y-%m-%dT%H:%M:%S"
    end
  records.find_all do |record|
    !omit_versions.include?(record["number"]) && record["created_at"] > cutoff_timestamp
  end
end

def analyze_version_platforms records
  results = {}
  records.each do |record|
    (results[record["number"]] ||= []) << record["platform"]
  end
  results
end

def find_needed_builds versions
  results = {}
  versions.each do |version, version_platforms|
    next unless version_platforms.include? "ruby"
    needed_platforms = platforms - version_platforms
    next if needed_platforms.empty?
    results[version] = needed_platforms
  end
  results.to_a
end

def confirm_worklist worklist
  if worklist.empty?
    puts "Nothing to build", :bold
    exit
  end
  puts "Will build the following:", :bold
  worklist.each do |(version, plats)|
    plats.each do |plat|
      puts "#{gem_name}-#{version}-#{plat}"
    end
  end
  exit 1 unless yes || confirm("Proceed? ", default: true)
end

def run_worklist worklist
  common_args = ["--yes", "--ruby", ruby_versions.join(",")]
  common_args << "--extensions" << extensions.join(",") if extensions
  common_args << "--rubygems-key" << rubygems_key if rubygems_key
  common_args << "--workspace-dir" << workspace_dir if workspace_dir
  common_args << "--clean" if clean
  worklist.each do |(version, plats)|
    cli.run("build", "--platform", plats.join(","), *common_args, gem_name, version, verbosity: verbosity)
  end
end
