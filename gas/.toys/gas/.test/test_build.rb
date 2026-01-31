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

  let(:use_older_example) {
    match = /^(\d+)\.(\d+)/.match host_ruby_version
    version = match[1].to_i * 100 + match[2].to_i
    version < 302
  }
  let(:gem_version) { @gem_version_override || (use_older_example ? "3.21.12" : "3.25.2") }
  let(:gem_and_version) { "google-protobuf-#{gem_version}" }
  let(:gem_data_dir) { @gem_version_override ? "data33" : use_older_example ? "data31" : "data32" }
  let(:source_gem) { File.join __dir__, gem_data_dir, "#{gem_and_version}.gem" }
  let(:workspace_dir) { Dir.mktmpdir }
  let(:linux_platforms_without_variants) { ["x86_64-linux", "x86-linux", "aarch64-linux", "arm-linux"] }
  let(:linux_platforms_with_variants) {
    [
      "x86_64-linux-gnu", "x86_64-linux-musl",
      "x86-linux-gnu", "x86-linux-musl",
      "aarch64-linux-gnu", "aarch64-linux-musl",
      "arm-linux-gnu", "arm-linux-musl"
    ]
  }
  let(:darwin_platforms) { ["x86_64-darwin", "arm64-darwin"] }
  let(:windows_platforms) { ["x86-mingw32", "x64-mingw-ucrt"] }
  let(:all_platforms) { linux_platforms_without_variants + linux_platforms_with_variants + darwin_platforms + windows_platforms }
  let(:exec_service) { Toys::Utils::Exec.new }
  let(:windows_ruby_versions) { ["3.1", "4.0"] }
  let(:host_platform) { "#{`uname -m`.strip}-#{`uname -s`.strip.downcase}" }
  let(:host_ruby_version) { RUBY_VERSION.sub(/^(\d+\.\d+).*$/, "\\1") }
  let(:multi_rubies) { ["3.1", "3.2", "3.3", "3.4", "4.0" ]}
  let(:gem_version_for_multi_rubies) { "4.29.2" }
  let(:platform_for_multi_rubies) { "x86_64-linux-gnu" }

  # Invoke the gas build tool within the test
  def quiet_build platforms, rubies
    result = 0
    out, err = capture_subprocess_io do
      result = toys_run_tool([
        "gas", "build", "google-protobuf", gem_version,
        "--workspace-dir", workspace_dir,
        "--source-gem", source_gem,
        "--platform", Array(platforms).join(","),
        "--ruby", Array(rubies).join(","),
        "--yes",
        "--verbose"
      ])
    end
    unless result.zero?
      puts "\n******** OUT"
      puts out
      puts "******** ERR"
      puts err
      flunk "Failed to run gas build: result = #{result}"
    end
  end

  # Clean out the temporary workspace directory between tests to ensure that
  # earlier test results don't pollute later test inputs.
  after do
    FileUtils.rm_rf workspace_dir
  end

  it "generates various Ruby versions for protobuf" do
    @gem_version_override = gem_version_for_multi_rubies
    quiet_build platform_for_multi_rubies, multi_rubies
    Dir.chdir "#{workspace_dir}/#{gem_and_version}/pkg/" do
      assert File.exist? "#{gem_and_version}-#{platform_for_multi_rubies}.gem"
      FileUtils.rm_r "#{gem_and_version}-#{platform_for_multi_rubies}"
      exec_service.exec ["gem", "unpack", "#{gem_and_version}-#{platform_for_multi_rubies}.gem"], out: :null
      multi_rubies.each do |ruby|
        assert File.exist? "#{gem_and_version}-#{platform_for_multi_rubies}/lib/google/#{ruby}/protobuf_c.so"
      end
    end
  end

  it "generates linux platforms without libc variants for protobuf" do
    quiet_build linux_platforms_without_variants, host_ruby_version
    Dir.chdir "#{workspace_dir}/#{gem_and_version}/pkg/" do
    linux_platforms_without_variants.each do |platform|
        assert File.exist? "#{gem_and_version}-#{platform}.gem"
        FileUtils.rm_r "#{gem_and_version}-#{platform}"
        exec_service.exec ["gem", "unpack", "#{gem_and_version}-#{platform}.gem"], out: :null
        assert File.exist? "#{gem_and_version}-#{platform}/lib/google/protobuf_c.so"
      end
    end
  end

  it "generates linux platforms with libc variants for protobuf" do
    quiet_build linux_platforms_with_variants, host_ruby_version
    Dir.chdir "#{workspace_dir}/#{gem_and_version}/pkg/" do
    linux_platforms_with_variants.each do |platform|
        assert File.exist? "#{gem_and_version}-#{platform}.gem"
        FileUtils.rm_r "#{gem_and_version}-#{platform}"
        exec_service.exec ["gem", "unpack", "#{gem_and_version}-#{platform}.gem"], out: :null
        assert File.exist? "#{gem_and_version}-#{platform}/lib/google/protobuf_c.so"
      end
    end
  end

  it "generates darwin platforms for protobuf" do
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

  it "generates windows platforms for protobuf" do
    quiet_build windows_platforms, windows_ruby_versions
    Dir.chdir "#{workspace_dir}/#{gem_and_version}/pkg/" do
      windows_platforms.each do |platform|
        assert File.exist? "#{gem_and_version}-#{platform}.gem"
        FileUtils.rm_r "#{gem_and_version}-#{platform}"
        exec_service.exec ["gem", "unpack", "#{gem_and_version}-#{platform}.gem"], out: :null
        windows_ruby_versions.each do |ruby|
          assert File.exist? "#{gem_and_version}-#{platform}/lib/google/#{ruby}/protobuf_c.so"
        end
      end
    end
  end

  it "loads on the current platform" do
    skip unless all_platforms.include? host_platform
    quiet_build host_platform, [host_ruby_version, "3.2"]
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
      result = exec_service.exec_ruby ["-e", script], out: :capture, err: :capture
      assert result.success?
    end
  end
end
