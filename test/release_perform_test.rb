# frozen_string_literal: true

# Copyright 2026 Google LLC
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

require "minitest/autorun"
require "toys"
require "fileutils"
require "tmpdir"
require "gems"
require "json"

module Gems
  class Client
    def info _gem_name = nil
      { "version" => "0.1.0" }
    end

    def push _file = nil
      raise "Gems::Client#push should NOT be called"
    end
  end
end

class ReleasePerformTest < Minitest::Test
  def setup
    @orig_cwd = Dir.pwd
    @tmpdir = Dir.mktmpdir
    @dummy_gem_dir = File.join @tmpdir, "dummy_gem"
    FileUtils.mkdir_p @dummy_gem_dir
    setup_dummy_gem_files
  end

  def teardown
    Dir.chdir @orig_cwd if @orig_cwd
    FileUtils.rm_rf @tmpdir
  end

  def test_docs_only_behavior
    cli = Toys::StandardCLI.new
    cli.loader.lookup ["release", "perform"]
    performer_class = find_performer_class cli

    calls = {}
    with_mocked_performer performer_class, calls do
      args = ["dummy_gem", "--base-dir=#{@dummy_gem_dir}", "--docs-only", "--dry-run"]
      exit_code = cli.run "release", "perform", *args

      assert_equal 0, exit_code
      refute calls[:publish_gem], "publish_gem should NOT be called"
      assert calls[:publish_docs], "publish_docs SHOULD be called"
      assert calls[:publish_rad], "publish_rad SHOULD be called"
    end
  end

  def test_normal_release_publishes_gem_when_outdated
    cli = Toys::StandardCLI.new
    cli.loader.lookup ["release", "perform"]
    performer_class = find_performer_class cli

    calls = {}
    with_mocked_performer performer_class, calls, current_version: "0.0.0" do
      args = [
        "dummy_gem",
        "--base-dir=#{@dummy_gem_dir}",
        "--enable-docs",
        "--enable-rad",
        "--dry-run"
      ]
      exit_code = cli.run "release", "perform", *args

      assert_equal 0, exit_code
      assert calls[:publish_gem], "publish_gem SHOULD be called"
      assert calls[:publish_docs], "publish_docs SHOULD be called"
      assert calls[:publish_rad], "publish_rad SHOULD be called"
    end
  end

  def test_normal_release_skips_when_up_to_date
    cli = Toys::StandardCLI.new
    cli.loader.lookup ["release", "perform"]
    performer_class = find_performer_class cli

    calls = {}
    with_mocked_performer performer_class, calls, current_version: "0.1.0" do
      args = [
        "dummy_gem",
        "--base-dir=#{@dummy_gem_dir}",
        "--enable-docs",
        "--enable-rad",
        "--dry-run"
      ]
      exit_code = cli.run "release", "perform", *args

      assert_equal 0, exit_code
      refute calls[:publish_gem], "publish_gem should NOT be called"
      refute calls[:publish_docs], "publish_docs should NOT be called (skipped early)"
      refute calls[:publish_rad], "publish_rad should NOT be called (skipped early)"
    end
  end

  private

  def setup_dummy_gem_files
    gemspec_content = <<~RUBY
      Gem::Specification.new do |s|
        s.name        = "dummy_gem"
        s.version     = "0.1.0"
        s.summary     = "Dummy Gem for testing"
        s.authors     = ["Test"]
      end
    RUBY
    metadata = { "name_pretty" => "Dummy Gem", "is_cloud" => true }
    File.write File.join(@dummy_gem_dir, "dummy_gem.gemspec"), gemspec_content
    File.write File.join(@dummy_gem_dir, ".repo-metadata.json"), JSON.dump(metadata)
    File.write File.join(@dummy_gem_dir, ".yardopts"), "# Empty yardopts\n"
    FileUtils.mkdir_p File.join(@dummy_gem_dir, "doc")
  end

  def find_performer_class cli
    tool, = cli.loader.lookup ["release", "perform"]
    tool_class = tool.tool_class
    Toys::InputFile.constants.each do |const_name|
      mod = Toys::InputFile.const_get const_name
      next unless mod.is_a?(Module) && mod.instance_variable_get(:@__tool_class) == tool_class

      return mod.const_get :Performer if mod.const_defined? :Performer, false
    end
    nil
  end

  def with_mocked_performer performer_class, calls, current_version: nil
    orig_methods = save_original_methods performer_class
    apply_mock_methods performer_class, calls, current_version
    yield
  ensure
    restore_original_methods performer_class, orig_methods if performer_class && orig_methods
  end

  def save_original_methods performer_class
    {
      run_aux_task: performer_class.instance_method(:run_aux_task),
      publish_gem: performer_class.instance_method(:publish_gem),
      publish_docs: performer_class.instance_method(:publish_docs),
      publish_rad: performer_class.instance_method(:publish_rad),
      current_rubygems_version: performer_class.instance_method(:current_rubygems_version)
    }
  end

  def apply_mock_methods performer_class, calls, current_version
    performer_class.class_eval do
      define_method :run_aux_task do |*_args|
        nil
      end
      define_method :publish_gem do |*_args|
        calls[:publish_gem] = true
      end
      define_method :publish_docs do |*_args|
        calls[:publish_docs] = true
      end
      define_method :publish_rad do |*_args|
        calls[:publish_rad] = true
      end
      if current_version
        define_method :current_rubygems_version do
          Gem::Version.new current_version
        end
      end
    end
  end

  def restore_original_methods performer_class, orig_methods
    performer_class.class_eval do
      orig_methods.each do |name, method|
        define_method name, method
      end
    end
  end
end
