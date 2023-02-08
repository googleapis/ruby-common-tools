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

describe "gas build" do
  include Toys::Testing

  toys_custom_paths File.dirname File.dirname __dir__
  toys_include_builtins false

  let(:gem_and_version) { "google-protobuf-3.21.12" }
  let(:source_gem) { File.join __dir__, "data", "#{gem_and_version}.gem" }
  let(:workspace_dir) { Dir.mktmpdir }
  let(:linux_platforms) { ["x86_64-linux", "x86-linux"] }
  let(:darwin_platforms) { ["x86_64-darwin", "arm64-darwin"] }
  let(:windows_platforms) { ["x86-mingw32", "x64-mingw32", "x64-mingw-ucrt"] }
  let(:all_platforms) { linux_platforms + darwin_platforms + windows_platforms }
  let(:exec_service) { Toys::Utils::Exec.new }
  let(:windows_ruby_versions) { ["2.7", "3.1"] }
  let(:excluded_combinations) { [["x64-mingw32", "3.1"], ["x64-mingw-ucrt", "2.7"]] }
  let(:host_platform) { "#{`uname -m`.strip}-#{`uname -s`.strip.downcase}" }
  let(:host_ruby_version) { RUBY_VERSION.sub(/^(\d+\.\d+).*$/, "\\1") }

  # Invoke the gas build tool within the test
  def quiet_build platforms, rubies
    result = 0
    out, err = capture_subprocess_io do
      result = toys_run_tool [
        "gas", "build", "google-protobuf", "3.21.12",
        "--workspace-dir", workspace_dir,
        "--source-gem", source_gem,
        "--platform", Array(platforms).join(","),
        "--ruby", Array(rubies).join(","),
        "--yes"
      ]
    end
    unless result.zero?
      puts out
      puts err
      flunk "Failed to run gas build: result = #{result}"
    end
  end

  # Clean out the temporary workspace directory between tests to ensure that
  # earlier test results don't pollute later test inputs.
  after do
    FileUtils.rm_rf workspace_dir
  end

  it "generates linux platforms for protobuf v21" do
    quiet_build linux_platforms, host_ruby_version
    Dir.chdir "#{workspace_dir}/#{gem_and_version}/pkg/" do
      linux_platforms.each do |platform|
        assert File.exist? "#{gem_and_version}-#{platform}.gem"
        FileUtils.rm_r "#{gem_and_version}-#{platform}"
        exec_service.exec ["gem", "unpack", "#{gem_and_version}-#{platform}.gem"], out: :null
        assert File.exist? "#{gem_and_version}-#{platform}/lib/google/protobuf_c.so"
      end
    end
  end

  it "generates darwin platforms for protobuf v21" do
    quiet_build darwin_platforms, host_ruby_version
    Dir.chdir "#{workspace_dir}/#{gem_and_version}/pkg/" do
      darwin_platforms.each do |platform|
        assert File.exist? "#{gem_and_version}-#{platform}.gem"
        FileUtils.rm_r "#{gem_and_version}-#{platform}"
        exec_service.exec ["gem", "unpack", "#{gem_and_version}-#{platform}.gem"], out: :null
        assert File.exist? "#{gem_and_version}-#{platform}/lib/google/protobuf_c.bundle"
      end
    end
  end

  it "generates windows platforms for protobuf v21" do
    quiet_build windows_platforms, windows_ruby_versions
    Dir.chdir "#{workspace_dir}/#{gem_and_version}/pkg/" do
      windows_platforms.each do |platform|
        assert File.exist? "#{gem_and_version}-#{platform}.gem"
        FileUtils.rm_r "#{gem_and_version}-#{platform}"
        exec_service.exec ["gem", "unpack", "#{gem_and_version}-#{platform}.gem"], out: :null
        windows_ruby_versions.each do |ruby|
          next if excluded_combinations.include? [platform, ruby]
          assert File.exist? "#{gem_and_version}-#{platform}/lib/google/#{ruby}/protobuf_c.so"
        end
      end
    end
  end

  it "loads on the current platform" do
    skip unless all_platforms.include? host_platform
    quiet_build host_platform, host_ruby_version
    Dir.chdir workspace_dir do
      gem_file = "#{gem_and_version}/pkg/#{gem_and_version}-#{host_platform}.gem"
      exec_service.exec ["gem", "install", gem_file], env: { "GEM_HOME" => "vendor" }, out: :null
      # Use an empty bundle to ensure that no gems other than the test gem
      # are loaded.
      File.write "Gemfile", <<~GEMFILE
        source "https://rubygems.org"
      GEMFILE
      script = <<~RUBY
        require "bundler"
        Bundler.setup
        $:.unshift "vendor/gems/#{gem_and_version}-#{host_platform}/lib"
        require "google/protobuf"
        require "google/protobuf/timestamp_pb"
        timestamp = Google::Protobuf::Timestamp.new seconds: 12345
        exit 1 unless timestamp.seconds == 12345
      RUBY
      result = exec_service.exec_ruby ["-e", script], out: :null
      assert result.success?
    end
  end
end
