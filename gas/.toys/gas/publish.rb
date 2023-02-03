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

desc "Publish gems to rubygems.org"

long_desc \
  "This tool publishes a set of gems to rubygems.org.",
  "",
  "You can specify individual gem archive files on the command line, or " \
    "search recursively through a directory."

remaining_args :gem_archive_paths do |arg|
  arg.desc "Individual gem archive files, or directories to search."
end

flag :rubygems_key_file, "--rubygems-key-file=PATH" do |flag|
  flag.desc "Path to a file containing the API key for pushing to RubyGems"
end
flag :force, "--force", "-f" do |flag|
  flag.desc "Ignore errors when pushing"
end
flag :dry_run do |flag|
  flag.desc "Do not actually publish gems"
end
flag :yes do |flag|
  flag.desc "Auto-confirm"
end

include :fileutils
include :gems
include :terminal

# Entrypoint
def run
  setup
  search_gems
  confirm_gems
  configure_credentials
  publish_gems
end

# Set up dependencies and environment
def setup
  cd context_directory
  gem "gems", Gas::GEMS_VERSION
  require "gems"
end

# Interpret the command line arguments, doing any requested directory searches
# to get a final list of gem archives to publish.
def search_gems
  @gems = []
  gem_archive_paths.each do |path|
    path = File.expand_path path
    if File.file?(path) && File.extname(path) == ".gem"
      @gems << path
    elsif File.directory?(path)
      Dir.glob("#{path}/**/*.gem").sort.each do |found|
        @gems << found if File.file?(found)
      end
    end
  end
end

# Interactive confirmation.
def confirm_gems
  puts "Ready to publish the following gems:", :bold
  @gems.each { |path| puts path, :bold }
  exit 1 unless yes || confirm("Proceed? ", default: true)
end

# Set up RubyGems credentials
def configure_credentials
  if rubygems_key_file
    Gems.configure do |config|
      config.key = File.read(rubygems_key_file).strip
    end
  end
end

# Iterate over the gem archive files and publish to RubyGems.
def publish_gems
  @gems.each do |path|
    if dry_run
      logger.warn "Dry-run mode: Would have published #{path}"
      next
    end
    logger.info "Pushing to RubyGems: #{path} ..."
    begin
      Gems.push File.new path
      logger.info "Pushed: #{path}"
    rescue Gems::GemError => e
      if force
        logger.warn "Failed to push: #{path}. Continuing."
        logger.warn e
      else
        logger.fatal "Failed to push: #{path}. Aborting."
        logger.fatal e
        exit 1
      end
    end
  end
end
