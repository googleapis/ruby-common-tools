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

require "toys/utils/gems"
require_relative "../.preload"

describe "gas publish" do
  include Toys::Testing

  Toys::Utils::Gems.activate "gems", Gas::GEMS_VERSION
  require "gems"

  toys_custom_paths File.dirname File.dirname __dir__
  toys_include_builtins false

  let(:data_dir_path) { File.join __dir__, "data2" }
  let(:keyfile_path) { File.join data_dir_path, "keyfile.txt" }
  let(:gem_archive_path) { File.join data_dir_path, "fake-gem-1.0.gem" }
  let(:gem_archive_content) { File.read gem_archive_path }
  let(:gem_archive2_path) { File.join data_dir_path, "fake-gem-2.0.gem" }
  let(:gem_archive2_content) { File.read gem_archive2_path }

  def quiet_publish *args, noisy: false, allow_errors: false
    result = 0
    out = err = nil
    block = proc do
      result = toys_run_tool(["gas", "publish", "--yes"] + args)
    end
    if noisy
      block.call
    else
      out, err = capture_subprocess_io(&block)
    end
    if !allow_errors && !result.zero?
      puts out
      puts err
      flunk "Failed to run gas publish: result = #{result}"
    end
    result
  end

  after do
    Gems.reset
  end

  it "uses the given rubygems keyfile" do
    quiet_publish "--rubygems-key-file", keyfile_path
    assert_equal "0123456789abcdef", Gems.key
  end

  it "publishes a gem specified by archive path" do
    found_content = []
    fake_push = proc do |file|
      found_content << file.read
      file.close
    end
    Gems.stub :push, fake_push do
      quiet_publish gem_archive_path
    end
    assert_equal [gem_archive_content], found_content
  end

  it "publishes multiple gems found by directory search" do
    found_content = []
    fake_push = proc do |file|
      found_content << file.read
      file.close
    end
    Gems.stub :push, fake_push do
      quiet_publish data_dir_path
    end
    assert_equal [gem_archive_content, gem_archive2_content], found_content
  end

  it "aborts on error" do
    found_content = []
    fake_push = proc do |file|
      file_content = file.read
      file.close
      raise Gems::GemError, "Whoops" if file_content == gem_archive_content
      found_content << file_content
    end
    result = nil
    Gems.stub :push, fake_push do
      result = quiet_publish data_dir_path, allow_errors: true
    end
    assert_equal 1, result
    assert_equal [], found_content
  end

  it "continues on error if forced" do
    found_content = []
    fake_push = proc do |file|
      file_content = file.read
      file.close
      raise Gems::GemError, "Whoops" if file_content == gem_archive_content
      found_content << file_content
    end
    Gems.stub :push, fake_push do
      quiet_publish "--force", data_dir_path
    end
    assert_equal [gem_archive2_content], found_content
  end

  it "respects dry-run" do
    fake_push = proc do |file|
      flunk "Dry-run didn't work"
    end
    Gems.stub :push, fake_push do
      quiet_publish "--dry-run", data_dir_path
    end
  end
end
