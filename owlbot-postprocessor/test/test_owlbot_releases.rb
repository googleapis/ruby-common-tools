# frozen_string_literal: true

# Copyright 2021 Google LLC
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

require "helper"
require "fileutils"

describe OwlBotReleases do
  let(:image_name) { "owlbot-postprocessor-test" }
  let(:default_gem_name) { "my-gem" }
  let(:default_api_id) { "my.service.v1" }
  let(:alt_api_id) { "my.service.v2" }
  let(:repo_metadata_file_name) { ".repo-metadata.json" }
  let(:repo_dir) { ::File.join __dir__, "tmp" }
  let(:owlbot_releases) { ::OwlBotReleases.new }
  let(:exec_service) { owlbot_releases.exec_service }

  def run_process cmd, output: false
    result = exec_service.exec cmd, out: :capture, err: :capture
    if output
      puts "**** OUT ****"
      puts result.captured_out
      puts "**** ERR ****"
      puts result.captured_err
    end
    result.success?
  end

  before do
    ::FileUtils.rm_rf repo_dir
    ::FileUtils.mkdir_p repo_dir
    ::Dir.chdir repo_dir do
      run_process ["git", "init"]
      run_process ["git", "commit", "--allow-empty", "-m", "commit 1"]
      run_process ["git", "commit", "--allow-empty", "-m", "commit 2"]
    end
  end

  after do
    ::FileUtils.rm_rf repo_dir
  end

  def create_gem_file path:, content:, gem_name: nil
    gem_name ||= default_gem_name
    path = ::File.join repo_dir, gem_name, path
    ::FileUtils.mkdir_p ::File.dirname path
    ::File.open path, "w" do |file|
      file.write content
    end
  end

  def create_gemspec version:, gem_name: nil
    gem_name ||= default_gem_name
    content = <<~CONTENT
      Gem::Specification.new do |gem|
        gem.name = "#{gem_name}"
        gem.version = "#{version}"
      end
    CONTENT
    create_gem_file gem_name: gem_name, path: "#{gem_name}.gemspec", content: content
  end

  def create_repo_metadata release_level: "unreleased", gem_name: nil, path: nil
    gem_name ||= default_gem_name
    path ||= repo_metadata_file_name
    content = <<~CONTENT
      {
        "distribution_name": "#{gem_name}",
        "release_level": "#{release_level}"
      }
    CONTENT
    create_gem_file gem_name: gem_name, path: path, content: content
  end

  def create_snippet_metadata version: nil, api_id: nil, gem_name: nil, path: nil
    gem_name ||= default_gem_name
    version ||= ""
    api_id ||= default_api_id
    path ||= "snippets/snippet_metadata_#{api_id}.json"
    api_version = api_id.split(".").last
    content = <<~CONTENT
      {
        "client_library": {
          "name": "#{gem_name}",
          "version": "#{version}",
          "language": "RUBY",
          "apis": [
            {
              "id": "#{api_id}",
              "version": "#{api_version}"
            }
          ]
        }
      }
    CONTENT
    create_gem_file gem_name: gem_name, path: path, content: content
  end

  def git_commit message: "."
    ::Dir.chdir repo_dir do
      run_process ["git", "add", "."]
      run_process ["git", "commit", "-m", message]
    end
  end

  def git_ensure_identity
    ::Dir.chdir repo_dir do
      return if run_process(["git", "config", "--get", "user.name"]) &&
                run_process(["git", "config", "--get", "user.email"])
      run_process ["git", "config", "--local", "user.email", "ruby@example.com"]
      run_process ["git", "config", "--local", "user.name", "Ruby Owlbot"]
    end
  end

  def invoke_single_gem gem_name: nil
    gem_name ||= default_gem_name
    ::Dir.chdir repo_dir do
      owlbot_releases.single_gem gem_name
    end
  end

  def invoke_all_gems
    ::Dir.chdir repo_dir do
      owlbot_releases.all_gems
    end
  end

  def invoke_changed_gems
    ::Dir.chdir repo_dir do
      owlbot_releases.changed_gems
    end
  end

  def assert_repo_metadata expected_release_level, gem_name: nil, path: nil
    gem_name ||= default_gem_name
    path ||= repo_metadata_file_name
    data = ::JSON.parse ::File.read "#{repo_dir}/#{gem_name}/#{path}"
    assert_equal expected_release_level, data["release_level"]
  end

  def assert_snippet_metadata expected_library_version: nil, expected_api_version: nil,
                              api_id: nil, gem_name: nil, path: nil
    gem_name ||= default_gem_name
    api_id ||= default_api_id
    path ||= "snippets/snippet_metadata_#{api_id}.json"
    data = ::JSON.parse ::File.read "#{repo_dir}/#{gem_name}/#{path}"
    assert_equal expected_library_version, data["client_library"]["version"] if expected_library_version
    assert_equal expected_api_version, data["client_library"]["apis"][0]["version"] if expected_api_version
  end

  it "updates repo metadata to stable" do
    create_gemspec version: "1.2.3"
    create_repo_metadata
    assert_repo_metadata "unreleased"
    invoke_single_gem
    assert_repo_metadata "stable"
  end

  it "updates repo metadata to preview" do
    create_gemspec version: "0.2.3"
    create_repo_metadata
    assert_repo_metadata "unreleased"
    invoke_single_gem
    assert_repo_metadata "preview"
  end

  it "updates repo metadata to unreleased" do
    create_gemspec version: "0.0.1"
    create_repo_metadata release_level: "preview"
    assert_repo_metadata "preview"
    invoke_single_gem
    assert_repo_metadata "unreleased"
  end

  it "does not touch non-repo-metadata files" do
    create_gemspec version: "1.2.3"
    create_repo_metadata path: "blah.json"
    invoke_single_gem
    assert_repo_metadata "unreleased", path: "blah.json"
  end

  it "updates the snippet metadata version from blank" do
    create_gemspec version: "1.2.4"
    create_snippet_metadata
    assert_snippet_metadata expected_library_version: "", expected_api_version: "v1"
    invoke_single_gem
    assert_snippet_metadata expected_library_version: "1.2.4", expected_api_version: "v1"
  end

  it "updates the snippet metadata version from an existing version" do
    create_gemspec version: "1.2.4"
    create_snippet_metadata version: "1.2.3"
    assert_snippet_metadata expected_library_version: "1.2.3", expected_api_version: "v1"
    invoke_single_gem
    assert_snippet_metadata expected_library_version: "1.2.4", expected_api_version: "v1"
  end

  it "updates the snippet metadata version to blank from an existing version" do
    create_gemspec version: "0.0.1"
    create_snippet_metadata version: "1.2.3"
    assert_snippet_metadata expected_library_version: "1.2.3", expected_api_version: "v1"
    invoke_single_gem
    assert_snippet_metadata expected_library_version: "", expected_api_version: "v1"
  end

  it "does not touch non-snippet-metadata files" do
    create_gemspec version: "1.2.4"
    create_snippet_metadata version: "1.2.3", path: "wtf.json"
    assert_snippet_metadata expected_library_version: "1.2.3", expected_api_version: "v1", path: "wtf.json"
    invoke_single_gem
    assert_snippet_metadata expected_library_version: "1.2.3", expected_api_version: "v1", path: "wtf.json"
  end

  it "finds all gems" do
    create_repo_metadata gem_name: "my-gem1"
    create_repo_metadata gem_name: "my-gem2"
    create_snippet_metadata version: "0.2.3", gem_name: "my-gem1"
    create_snippet_metadata version: "0.4.5", gem_name: "my-gem2"
    create_snippet_metadata version: "0.4.5", gem_name: "my-gem2", api_id: alt_api_id
    create_gemspec version: "1.0.0", gem_name: "my-gem1"
    create_gemspec version: "0.4.6", gem_name: "my-gem2"
    invoke_all_gems
    assert_repo_metadata "stable", gem_name: "my-gem1"
    assert_repo_metadata "preview", gem_name: "my-gem2"
    assert_snippet_metadata expected_library_version: "1.0.0", gem_name: "my-gem1"
    assert_snippet_metadata expected_library_version: "0.4.6", gem_name: "my-gem2"
    assert_snippet_metadata expected_library_version: "0.4.6", gem_name: "my-gem2", api_id: alt_api_id
  end

  it "finds changed gems" do
    git_ensure_identity
    create_repo_metadata gem_name: "my-gem1"
    create_repo_metadata gem_name: "my-gem2"
    create_snippet_metadata version: "0.2.3", gem_name: "my-gem1"
    create_snippet_metadata version: "0.4.5", gem_name: "my-gem2"
    create_gemspec version: "1.0.0", gem_name: "my-gem1"
    create_gemspec version: "0.4.6", gem_name: "my-gem2"
    git_commit
    create_gem_file path: "CHANGELOG.md", gem_name: "my-gem1", content: "Hello\n"
    git_commit
    invoke_changed_gems
    assert_repo_metadata "stable", gem_name: "my-gem1"
    assert_repo_metadata "unreleased", gem_name: "my-gem2"
    assert_snippet_metadata expected_library_version: "1.0.0", gem_name: "my-gem1"
    assert_snippet_metadata expected_library_version: "0.4.5", gem_name: "my-gem2"
  end

  describe "using the image" do
    def invoke_image *args
      cmd = [
        "docker", "run",
        "--rm",
        "--user", "#{::Process.uid}:#{::Process.gid}",
        "-v", "#{repo_dir}:/repo",
        "-w", "/repo",
        image_name,
        "--no-owlbot-tasks",
        "-qq"
      ] + args
      assert run_process cmd
    end

    it "finds changed gems" do
      git_ensure_identity
      create_repo_metadata gem_name: "my-gem1"
      create_repo_metadata gem_name: "my-gem2"
      create_snippet_metadata version: "0.2.3", gem_name: "my-gem1"
      create_snippet_metadata version: "0.4.5", gem_name: "my-gem2"
      create_gemspec version: "1.0.0", gem_name: "my-gem1"
      create_gemspec version: "0.4.6", gem_name: "my-gem2"
      git_commit
      create_gem_file path: "CHANGELOG.md", gem_name: "my-gem1", content: "Hello\n"
      git_commit

      invoke_image

      assert_repo_metadata "stable", gem_name: "my-gem1"
      assert_repo_metadata "unreleased", gem_name: "my-gem2"
      assert_snippet_metadata expected_library_version: "1.0.0", gem_name: "my-gem1"
      assert_snippet_metadata expected_library_version: "0.4.5", gem_name: "my-gem2"
    end

    it "finds all gems" do
      create_repo_metadata gem_name: "my-gem1"
      create_repo_metadata gem_name: "my-gem2"
      create_snippet_metadata version: "0.2.3", gem_name: "my-gem1"
      create_snippet_metadata version: "0.4.5", gem_name: "my-gem2"
      create_snippet_metadata version: "0.4.5", gem_name: "my-gem2", api_id: alt_api_id
      create_gemspec version: "1.0.0", gem_name: "my-gem1"
      create_gemspec version: "0.4.6", gem_name: "my-gem2"

      invoke_image "--all-gems"

      assert_repo_metadata "stable", gem_name: "my-gem1"
      assert_repo_metadata "preview", gem_name: "my-gem2"
      assert_snippet_metadata expected_library_version: "1.0.0", gem_name: "my-gem1"
      assert_snippet_metadata expected_library_version: "0.4.6", gem_name: "my-gem2"
      assert_snippet_metadata expected_library_version: "0.4.6", gem_name: "my-gem2", api_id: alt_api_id
    end

    it "selects a single gem" do
      create_repo_metadata gem_name: "my-gem1"
      create_repo_metadata gem_name: "my-gem2"
      create_snippet_metadata version: "0.2.3", gem_name: "my-gem1"
      create_snippet_metadata version: "0.4.5", gem_name: "my-gem2"
      create_gemspec version: "1.0.0", gem_name: "my-gem1"
      create_gemspec version: "0.4.6", gem_name: "my-gem2"

      invoke_image "--gem=my-gem1"

      assert_repo_metadata "stable", gem_name: "my-gem1"
      assert_repo_metadata "unreleased", gem_name: "my-gem2"
      assert_snippet_metadata expected_library_version: "1.0.0", gem_name: "my-gem1"
      assert_snippet_metadata expected_library_version: "0.4.5", gem_name: "my-gem2"
    end
  end
end
