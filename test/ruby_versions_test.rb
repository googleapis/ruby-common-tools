# frozen_string_literal: true

# Copyright 2026 Google LLC
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

require "bundler"
require "fileutils"
require "minitest/autorun"
require "open3"
require "tmpdir"
require "yaml"

class RubyVersionsTest < Minitest::Test
  REPO_ROOT = File.expand_path "..", __dir__
  KOKORO_GAS_CONFIGS = [
    ".kokoro/gas/trigger-cloud.cfg",
    ".kokoro/gas/trigger-generic.cfg",
    ".kokoro/gas/trigger-protobuf.cfg"
  ].freeze

  def setup
    @config = YAML.load_file File.join(REPO_ROOT, "ruby_versions.yml")
    @minimum = @config.fetch "minimum"
    @supported = @config.fetch "supported"
  end

  def test_ruby_versions_config_is_well_formed
    assert_kind_of String, @minimum
    assert_match(/\A\d+\.\d+\z/, @minimum)
    assert_kind_of Array, @supported
    refute_empty @supported
    @supported.each do |ver|
      assert_kind_of String, ver
      assert_match(/\A\d+\.\d+\z/, ver)
    end
    sorted = @supported.sort_by { |ver| Gem::Version.new ver }
    assert_equal sorted, @supported
    assert_equal @minimum, @supported.first
  end

  def test_rubocop_target_ruby_version_matches_minimum
    rubocop_config = YAML.load_file File.join(REPO_ROOT, ".rubocop.yml")
    target = rubocop_config.dig("AllCops", "TargetRubyVersion").to_s
    assert_equal @minimum, target
  end

  def test_github_ci_matrix_matches_supported_versions
    ci_config = YAML.load_file File.join(REPO_ROOT, ".github", "workflows", "ci.yml")
    matrix = ci_config.dig "jobs", "CI", "strategy", "matrix", "include"
    test_rubies = matrix.select { |entry| entry["jobs"] == "--only --test" }.map { |entry| entry["ruby"].to_s }
    rubocop_rubies = matrix.select { |entry| entry["jobs"] == "--only --rubocop" }.map { |entry| entry["ruby"].to_s }

    assert_equal @supported, test_rubies
    refute_empty rubocop_rubies
    assert_empty rubocop_rubies - @supported
  end

  def test_kokoro_gas_configs_match_supported_versions
    expected = @supported.join ":"
    KOKORO_GAS_CONFIGS.each do |rel_path|
      content = File.read File.join(REPO_ROOT, rel_path)
      match = /key:\s*"GAS_RUBY_VERSIONS"\s+value:\s*"([^"]+)"/.match content
      refute_nil match, "Expected GAS_RUBY_VERSIONS in #{rel_path}"
      assert_equal expected, match[1], "Mismatch in #{rel_path}"
    end
  end

  def test_gas_preload_loads_versions_from_config
    require File.join(REPO_ROOT, "gas", ".toys", "gas", ".preload.rb")
    assert_equal @minimum, Gas::MINIMUM_RUBY
    assert_equal @supported, Gas::DEFAULT_RUBIES
  end

  def test_tombstone_library_uses_minimum_ruby_version
    gem_name = "google-cloud-sample-v1"
    version_rel = "lib/google/cloud/sample/v1/version.rb"
    version_src = <<~RUBY
      module Google
        module Cloud
          module Sample
            module V1
              VERSION = "1.0.0"
            end
          end
        end
      end
    RUBY

    Dir.mktmpdir do |dir|
      setup_tombstone_repo dir, gem_name

      out, status = run_unbundled dir, { "RUBY_COMMON_TOOLS" => REPO_ROOT }, "toys", "tombstone-library", gem_name
      assert status.success?, "toys tombstone-library failed: #{out}"

      FileUtils.mkdir_p File.join(dir, gem_name, File.dirname(version_rel))
      File.write File.join(dir, gem_name, version_rel), version_src

      gemspec_path = File.join dir, gem_name, "#{gem_name}.gemspec"
      gemspec_content = File.read gemspec_path
      assert_includes gemspec_content, "gem.required_ruby_version = \">= #{@minimum}\""

      spec = Gem::Specification.load gemspec_path
      assert_equal Gem::Requirement.new(">= #{@minimum}"), spec.required_ruby_version
    end
  end

  def test_tombstone_library_reflects_updated_ruby_versions_file
    gem_name = "google-cloud-sample-v1"
    Dir.mktmpdir do |dir|
      tools_copy = File.join dir, "ruby-common-tools"
      FileUtils.mkdir_p File.join(tools_copy, "toys")
      FileUtils.cp_r File.join(REPO_ROOT, "toys", "tombstone-library"), File.join(tools_copy, "toys")
      FileUtils.cp_r File.join(REPO_ROOT, "toys", "yoshi"), File.join(tools_copy, "toys")
      File.write File.join(tools_copy, "ruby_versions.yml"), <<~YAML
        minimum: "3.9"
        supported:
          - "3.9"
      YAML

      work_dir = File.join dir, "repo"
      setup_tombstone_repo work_dir, gem_name

      out, status = run_unbundled work_dir, { "RUBY_COMMON_TOOLS" => tools_copy }, "toys", "tombstone-library", gem_name
      assert status.success?, "toys tombstone-library failed: #{out}"

      gemspec_content = File.read File.join(work_dir, gem_name, "#{gem_name}.gemspec")
      assert_includes gemspec_content, "gem.required_ruby_version = \">= 3.9\""
    end
  end

  private

  def setup_tombstone_repo dir, gem_name
    FileUtils.mkdir_p File.join(dir, gem_name)
    FileUtils.mkdir_p File.join(dir, ".toys")
    File.write File.join(dir, ".toys", "tombstone-library.rb"), <<~RUBY
      load File.join(File.expand_path(ENV.fetch("RUBY_COMMON_TOOLS")), "toys", "tombstone-library")
    RUBY
    out, status = run_unbundled dir, "git", "init"
    assert status.success?, "git init failed: #{out}"
  end

  def run_unbundled chdir, *args
    env = args.first.is_a?(Hash) ? args.shift : {}
    Bundler.with_unbundled_env do
      Open3.capture2e env, *args, chdir: chdir
    end
  end
end
