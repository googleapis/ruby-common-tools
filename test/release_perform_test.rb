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

# Ensure gems are activated before mocking
gem "gems", "~> 1.3"
require "gems"

# Mock Gems::Client globally for tests
class Gems::Client
  def info(gem_name)
    { "version" => "0.1.0" }
  end
  def push(file)
    raise "Gems::Client#push should NOT be called"
  end
end

class ReleasePerformTest < Minitest::Test
  def setup
    @orig_cwd = Dir.pwd
    @tmpdir = Dir.mktmpdir
    @dummy_gem_dir = File.join(@tmpdir, "dummy_gem")
    FileUtils.mkdir_p(@dummy_gem_dir)
    
    # Create dummy gem structure
    File.write(File.join(@dummy_gem_dir, "dummy_gem.gemspec"), <<~RUBY)
      Gem::Specification.new do |s|
        s.name        = 'dummy_gem'
        s.version     = '0.1.0'
        s.summary     = "Dummy Gem for testing"
        s.authors     = ["Test"]
      end
    RUBY

    File.write(File.join(@dummy_gem_dir, ".repo-metadata.json"), <<~JSON)
      {
        "name_pretty": "Dummy Gem",
        "is_cloud": true
      }
    JSON

    File.write(File.join(@dummy_gem_dir, ".yardopts"), "# Empty yardopts")
    FileUtils.mkdir_p(File.join(@dummy_gem_dir, "doc"))
  end

  def teardown
    Dir.chdir(@orig_cwd) if @orig_cwd
    FileUtils.rm_rf(@tmpdir)
  end

  def find_performer_class(cli)
    tool, _ = cli.loader.lookup(["release", "perform"])
    tool_class = tool.tool_class
    Toys::InputFile.constants.each do |const_name|
      mod = Toys::InputFile.const_get(const_name)
      if mod.is_a?(Module) && mod.instance_variable_get(:@__tool_class) == tool_class
        return mod.const_get(:Performer) if mod.const_defined?(:Performer, false)
      end
    end
    nil
  end

  def test_docs_only_behavior
    cli = Toys::StandardCLI.new
    # Force load the tool
    cli.loader.lookup(["release", "perform"])
    
    performer_class = find_performer_class(cli)
    assert performer_class, "Performer class not found"

    publish_gem_called = false
    publish_docs_called = false
    publish_rad_called = false
    
    orig_run_aux_task = nil
    orig_publish_gem = nil
    orig_publish_docs = nil
    orig_publish_rad = nil

    # Save original methods to restore after test
    orig_run_aux_task = performer_class.instance_method(:run_aux_task)
    orig_publish_gem = performer_class.instance_method(:publish_gem)
    orig_publish_docs = performer_class.instance_method(:publish_docs)
    orig_publish_rad = performer_class.instance_method(:publish_rad)

    performer_class.class_eval do
      define_method(:run_aux_task) { |*args, **opts| } # Mock to do nothing
      define_method(:publish_gem) { |*args, **opts| publish_gem_called = true }
      define_method(:publish_docs) { |*args, **opts| publish_docs_called = true }
      define_method(:publish_rad) { |*args, **opts| publish_rad_called = true }
    end

    args = ["dummy_gem", "--base-dir=#{@dummy_gem_dir}", "--docs-only", "--dry-run"]
    exit_code = cli.run("release", "perform", *args)
    
    assert_equal 0, exit_code
    refute publish_gem_called, "publish_gem should NOT be called"
    assert publish_docs_called, "publish_docs SHOULD be called"
    assert publish_rad_called, "publish_rad SHOULD be called"

  ensure
    # Restore original methods to avoid cross-test pollution
    if performer_class
      performer_class.class_eval do
        define_method(:run_aux_task, orig_run_aux_task) if orig_run_aux_task
        define_method(:publish_gem, orig_publish_gem) if orig_publish_gem
        define_method(:publish_docs, orig_publish_docs) if orig_publish_docs
        define_method(:publish_rad, orig_publish_rad) if orig_publish_rad
      end
    end
  end

  def test_normal_release_publishes_gem_when_outdated
    cli = Toys::StandardCLI.new
    cli.loader.lookup(["release", "perform"])
    performer_class = find_performer_class(cli)
    
    publish_gem_called = false
    publish_docs_called = false
    publish_rad_called = false
    
    orig_run_aux_task = nil
    orig_publish_gem = nil
    orig_publish_docs = nil
    orig_publish_rad = nil
    orig_current_version = nil

    orig_run_aux_task = performer_class.instance_method(:run_aux_task)
    orig_publish_gem = performer_class.instance_method(:publish_gem)
    orig_publish_docs = performer_class.instance_method(:publish_docs)
    orig_publish_rad = performer_class.instance_method(:publish_rad)
    orig_current_version = performer_class.instance_method(:current_rubygems_version)

    performer_class.class_eval do
      define_method(:run_aux_task) { |*args, **opts| }
      define_method(:publish_gem) { |*args, **opts| publish_gem_called = true }
      define_method(:publish_docs) { |*args, **opts| publish_docs_called = true }
      define_method(:publish_rad) { |*args, **opts| publish_rad_called = true }
      define_method(:current_rubygems_version) { Gem::Version.new "0.0.0" } # Force need publish
    end

    args = ["dummy_gem", "--base-dir=#{@dummy_gem_dir}", "--enable-docs", "--enable-rad", "--dry-run"]
    exit_code = cli.run("release", "perform", *args)
    
    assert_equal 0, exit_code
    assert publish_gem_called, "publish_gem SHOULD be called"
    assert publish_docs_called, "publish_docs SHOULD be called"
    assert publish_rad_called, "publish_rad SHOULD be called"

  ensure
    if performer_class
      performer_class.class_eval do
        define_method(:run_aux_task, orig_run_aux_task) if orig_run_aux_task
        define_method(:publish_gem, orig_publish_gem) if orig_publish_gem
        define_method(:publish_docs, orig_publish_docs) if orig_publish_docs
        define_method(:publish_rad, orig_publish_rad) if orig_publish_rad
        define_method(:current_rubygems_version, orig_current_version) if orig_current_version
      end
    end
  end

  def test_normal_release_skips_when_up_to_date
    cli = Toys::StandardCLI.new
    cli.loader.lookup(["release", "perform"])
    performer_class = find_performer_class(cli)
    
    publish_gem_called = false
    publish_docs_called = false
    publish_rad_called = false
    
    orig_run_aux_task = nil
    orig_publish_gem = nil
    orig_publish_docs = nil
    orig_publish_rad = nil
    orig_current_version = nil

    orig_run_aux_task = performer_class.instance_method(:run_aux_task)
    orig_publish_gem = performer_class.instance_method(:publish_gem)
    orig_publish_docs = performer_class.instance_method(:publish_docs)
    orig_publish_rad = performer_class.instance_method(:publish_rad)
    orig_current_version = performer_class.instance_method(:current_rubygems_version)

    performer_class.class_eval do
      define_method(:run_aux_task) { |*args, **opts| }
      define_method(:publish_gem) { |*args, **opts| publish_gem_called = true }
      define_method(:publish_docs) { |*args, **opts| publish_docs_called = true }
      define_method(:publish_rad) { |*args, **opts| publish_rad_called = true }
      define_method(:current_rubygems_version) { Gem::Version.new "0.1.0" } # Up to date (same as gemspec)
    end

    args = ["dummy_gem", "--base-dir=#{@dummy_gem_dir}", "--enable-docs", "--enable-rad", "--dry-run"]
    exit_code = cli.run("release", "perform", *args)
    
    assert_equal 0, exit_code
    refute publish_gem_called, "publish_gem should NOT be called"
    refute publish_docs_called, "publish_docs should NOT be called (skipped early)"
    refute publish_rad_called, "publish_rad should NOT be called (skipped early)"

  ensure
    if performer_class
      performer_class.class_eval do
        define_method(:run_aux_task, orig_run_aux_task) if orig_run_aux_task
        define_method(:publish_gem, orig_publish_gem) if orig_publish_gem
        define_method(:publish_docs, orig_publish_docs) if orig_publish_docs
        define_method(:publish_rad, orig_publish_rad) if orig_publish_rad
        define_method(:current_rubygems_version, orig_current_version) if orig_current_version
      end
    end
  end
end
