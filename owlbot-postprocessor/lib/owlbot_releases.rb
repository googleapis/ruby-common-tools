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

require "toys/utils/exec"

##
# @private
#
# A postprocessor task that should be run on release pull requests.
# This updates repo metadata and snippet metadata files when a release occurs.
# The repo metadata file needs to know whether the current version is a preview
# or stable (i.e. pre or post 1.0) version. Snippet metadata files need to know
# the actual current release version.
#
class OwlBotReleases
  def initialize exec_service: nil, logger: nil
    @logger = logger
    @exec_service = exec_service || ::Toys::Utils::Exec.new
  end

  attr_reader :logger
  attr_reader :exec_service

  def single_gem gem_name
    return unless ::File.file? "#{gem_name}/#{gem_name}.gemspec"
    logger&.info "Checking gem directory for #{gem_name}"
    gem_version = current_gem_version gem_name
    logger&.info "Gem version: #{gem_version}"
    update_repo_metadata gem_name, gem_version
    update_snippetgen_metadata gem_name, gem_version
  end

  def all_gems
    ::Dir.glob("*/*.gemspec").each do |gemspec_path|
      gem_name = ::File.dirname gemspec_path
      next unless ::File.file?("#{gem_name}/.repo-metadata.json") || ::File.directory?("#{gem_name}/snippets")
      single_gem gem_name
    end
  end

  def changed_gems
    exec_service.capture(["git", "diff", "--name-only", "HEAD^"])
                .split("\n")
                .map(&:strip)
                .map { |path| path.split("/").first }
                .uniq
                .each { |dir| single_gem dir }
  end

  private

  def current_gem_version gem_name
    func = proc do
      ::Dir.chdir gem_name do
        spec = ::Gem::Specification.load "#{gem_name}.gemspec"
        puts spec.version
      end
    end
    exec_service.capture_proc(func).strip
  end

  def update_repo_metadata gem_name, gem_version
    release_level =
      if gem_version.start_with? "0.0."
        "unreleased"
      elsif gem_version.start_with? "0."
        "preview"
      else
        "stable"
      end
    path = ::File.join gem_name, ".repo-metadata.json"
    return unless ::File.file? path
    metadata = ::File.read path
    updated_metadata = metadata.sub(/"release_level": "\w+"/, "\"release_level\": \"#{release_level}\"")
    return if metadata == updated_metadata
    ::File.write path, updated_metadata
    logger&.info "Updated #{path}"
  end

  def update_snippetgen_metadata gem_name, gem_version
    ::Dir.glob "#{gem_name}/snippets/snippet_metadata_*.json" do |path|
      metadata = ::File.read path
      gem_version = "" if gem_version.start_with? "0.0."
      updated_metadata = metadata.sub(/"version": "(\d+\.\d+\.\d+)?"/, "\"version\": \"#{gem_version}\"")
      next if metadata == updated_metadata
      ::File.write path, updated_metadata
      logger&.info "Updated #{path}"
    end
  end
end
