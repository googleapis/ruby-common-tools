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

toys_version! ">= 0.15.3"

expand :clean, paths: :gitignore

expand :rubocop, bundler: true

expand :yardoc do |t|
  t.generate_output_flag = true
  t.fail_on_warning = true
  t.use_bundler
end

tool "yard", delegate_to: "yardoc"

expand :gem_build

expand :gem_build, name: "install", install_gem: true

expand :minitest do |t|
  t.libs = ["lib", "test"]
  t.use_bundler
  t.files = "test/**/*_test.rb"
end

tool "bundle" do
  flag :update, desc: "Update rather than install the bundle"

  include :exec, e: true

  def run
    Dir.chdir context_directory
    Bundler.with_clean_env do
      exec ["bundle", update ? "update" : "install"]
    end
  end
end

tool "acceptance" do
  desc "Run integration acceptance tests"

  flag :project, "--project=PROJECT", desc: "The project for integration tests"
  flag :keyfile, "--keyfile=KEYFILE", desc: "Credentials JSON file or content"

  def run
    exit cli.run("integration", *args, "--acceptance")
  end
end

tool "smoke" do
  desc "Run integration smoke tests"

  flag :project, "--project=PROJECT", desc: "The project for integration tests"
  flag :keyfile, "--keyfile=KEYFILE", desc: "Credentials JSON file or content"

  def run
    exit cli.run("integration", *args, "--smoke")
  end
end

tool "samples-latest" do
  flag :project, "--project=PROJECT", desc: "The project for integration tests"
  flag :keyfile, "--keyfile=KEYFILE", desc: "Credentials JSON file or content"
  flag :samples_bundle_update, desc: "Update rather than install the samples bundle"

  def run
    exit cli.run("integration", *args, "--samples-latest")
  end
end

tool "samples-main" do
  flag :project, "--project=PROJECT", desc: "The project for integration tests"
  flag :keyfile, "--keyfile=KEYFILE", desc: "Credentials JSON file or content"
  flag :samples_bundle_update, desc: "Update rather than install the samples bundle"

  def run
    exit cli.run("integration", *args, "--samples-main")
  end
end

tool "samples-bundle" do
  desc "Install the bundle used for samples"

  flag :update, desc: "Update rather than install the bundle"
  flag :main_branch, "--[no-]main", desc: "Include the HEAD of the main branch instead of the latest client release"

  include :exec, e: true

  def run
    Dir.chdir context_directory
    unless File.directory? "samples"
      puts "No samples present"
      exit 0
    end
    Dir.chdir "samples"
    saved_selector = ENV["GOOGLE_CLOUD_SAMPLES_TEST"]
    ENV["GOOGLE_CLOUD_SAMPLES_TEST"] = main_branch ? "master" : "not_master"
    begin
      exec ["bundle", update ? "update" : "install"]
    ensure
      ENV["GOOGLE_CLOUD_SAMPLES_TEST"] = saved_selector
    end
  end
end
