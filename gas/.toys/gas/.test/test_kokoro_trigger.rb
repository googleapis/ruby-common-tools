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

require "fileutils"
require "tmpdir"
require "toys/utils/exec"
require "toys/utils/gems"
require_relative "../.preload"

describe "gas kokoro-trigger" do
  include Toys::Testing

  Toys::Utils::Gems.activate "gems", Gas::GEMS_VERSION
  require "gems"

  toys_custom_paths File.dirname File.dirname __dir__
  toys_include_builtins false

  let(:exec_service) { Toys::Utils::Exec.new }
  let(:workspace_dir) { Dir.mktmpdir }
  let(:gem_platforms) do
    [
      "arm64-darwin",
      "x64-mingw-ucrt",
      "x64-mingw32",
      "x86-linux",
      "x86-mingw32",
      "x86_64-darwin",
      "x86_64-linux"
    ]
  end
  let(:ruby_versions) { ["2.7", "3.0", "3.1", "3.2"] }
  let(:gem_and_version) { "google-protobuf-3.21.12" }
  let(:protobuf_env) do
    {
      "KOKORO_GFILE_DIR" => __dir__,
      "GAS_SOURCE_GEM" => "data/#{gem_and_version}.gem",
      "GAS_ADDITIONAL_GEMS" => "data2/fake-gem-1.0.gem:data2/fake-gem-2.0.gem",
      "GAS_PLATFORMS" => gem_platforms.join(":"),
      "GAS_RUBY_VERSIONS" => ruby_versions.join(":"),
      "GAS_RUBYGEMS_KEY_FILE" => "data2/keyfile.txt",
      "GAS_WORKSPACE_DIR" => workspace_dir
    }
  end
  let(:excluded_versions) do
    {
      "x64-mingw32" => ["3.1", "3.2"],
      "x64-mingw-ucrt" => ["2.7", "3.0"]
    }
  end

  def temp_set_env hash
    old_env = hash.to_h do |key, val|
      old_val = ENV[key]
      ENV[key] = val
      [key, old_val]
    end
    begin
      yield
    ensure
      old_env.each do |key, val|
        ENV[key] = val
      end
    end
  end

  def quiet_trigger noisy: false
    result = 0
    out = err = nil
    block = proc do
      result = toys_run_tool ["gas", "kokoro-trigger", "-v"]
    end
    if noisy
      block.call
    else
      out, err = capture_subprocess_io(&block)
    end
    unless result.zero?
      puts out
      puts err
      flunk "Failed to run gas kokoro-trigger: result = #{result}"
    end
  end

  after do
    Gems.reset
    FileUtils.rm_rf workspace_dir
  end

  it "runs on a protobuf release" do
    found_content = []
    temp_set_env protobuf_env do
      fake_push = proc do |file|
        found_content << file.read
        file.close
      end
      Gems.stub :push, fake_push do
        quiet_trigger noisy: true
      end
    end

    # Make sure we used the correct RubyGems API token
    assert_equal "0123456789abcdef", Gems.key

    # Make sure we "published" the expected gems
    assert_equal 10, found_content.size
    assert_includes found_content, "fake gem 1.0"
    assert_includes found_content, "fake gem 2.0"

    # Make sure we built the expected gems
    Dir.chdir "#{workspace_dir}/#{gem_and_version}/pkg/" do
      gem_platforms.each do |platform|
        assert File.exist? "#{gem_and_version}-#{platform}.gem"
        FileUtils.rm_r "#{gem_and_version}-#{platform}"
        exec_service.exec ["gem", "unpack", "#{gem_and_version}-#{platform}.gem"], out: :null
        suffix = platform.include?("darwin") ? "bundle" : "so"
        actual_ruby_versions = ruby_versions - excluded_versions.fetch(platform, [])
        actual_ruby_versions.each do |ruby|
          assert File.exist? "#{gem_and_version}-#{platform}/lib/google/#{ruby}/protobuf_c.#{suffix}"
        end
      end
    end
  end
end
