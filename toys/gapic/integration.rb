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

flag :project, "--project=PROJECT", desc: "The project for integration tests"
flag :keyfile, "--keyfile=KEYFILE", desc: "Credentials JSON file or content"

flag :acceptance, desc: "Run acceptance tests"
flag :smoke, desc: "Run only smoke tests"
flag :samples_latest, desc: "Run sample tests against the latest release"
flag :samples_main, desc: "Run sample tests against the main branch"
flag :samples_bundle_update, desc: "Update rather than install the samples bundle"

include :exec, e: true

def run
  Dir.chdir context_directory
  clean_credentials_env
  setup_project
  setup_keyfile

  if acceptance
    run_acceptance smoke_only: false
  elsif smoke
    run_acceptance smoke_only: true
  end
  run_samples main_branch: false if samples_latest
  run_samples main_branch: true if samples_main
end

def service_env_prefix
  unless defined? @service_env_prefix
    require "json"
    repo_metadata = JSON.load_file ".repo-metadata.json"
    @service_env_prefix = repo_metadata["ruby-cloud-env-prefix"]
  end
  @service_env_prefix
end

def clean_credentials_env
  env_vars = [
    "GOOGLE_CLOUD_CREDENTIALS",
    "GOOGLE_CLOUD_CREDENTIALS_JSON",
    "GOOGLE_CLOUD_KEYFILE",
    "GOOGLE_CLOUD_KEYFILE_JSON",
    "GCLOUD_KEYFILE",
    "GCLOUD_KEYFILE_JSON"
  ]
  if service_env_prefix
    env_vars += [
      "#{service_env_prefix}_CREDENTIALS",
      "#{service_env_prefix}_CREDENTIALS_JSON",
      "#{service_env_prefix}_KEYFILE",
      "#{service_env_prefix}_KEYFILE_JSON"
    ]
  end
  env_vars.each do |var|
    ENV[var] = nil
  end
end

def setup_project
  env_vars = []
  env_vars.append "#{service_env_prefix}_TEST_PROJECT" if service_env_prefix
  env_vars += ["GOOGLE_CLOUD_TEST_PROJECT", "GCLOUD_TEST_PROJECT"]
  effective_project = env_vars.inject(project) { |current, var| current || ENV[var] }
  unless effective_project
    puts "You must provide a project, either using the --project= command " \
         "line flag, or by setting one of the environment variables: " \
         "#{env_vars.join ', '}."
    exit 1
  end
  if service_env_prefix
    ENV["#{service_env_prefix}_TEST_PROJECT"] = ENV["#{service_env_prefix}_PROJECT"] = effective_project
  end
  ENV["GOOGLE_CLOUD_PROJECT"] = effective_project
end

def setup_keyfile
  env_vars = []
  env_vars.append "#{service_env_prefix}_TEST_KEYFILE" if service_env_prefix
  env_vars += ["GOOGLE_CLOUD_TEST_KEYFILE", "GCLOUD_TEST_KEYFILE"]
  json_env_vars = env_vars.map { |var| "#{var}_JSON" }
  effective_keyfile = env_vars.inject(keyfile) { |current, var| current || ENV[var] }
  effective_keyfile =
    if effective_keyfile
      File.read effective_keyfile
    else
      json_env_vars.inject(nil) { |var, current| current || ENV[var] }
    end
  unless effective_keyfile
    puts "You must provide a keyfile, either using the --keyfile= command " \
         "line flag, or by setting one of the environment variables: " \
         "#{env_vars.join ', '}, #{json_env_vars.join ', '}."
    exit 1
  end
  effective_prefix = service_env_prefix || "GOOGLE_CLOUD"
  ENV["#{effective_prefix}_KEYFILE_JSON"] = effective_keyfile
end

def run_acceptance smoke_only:
  unless File.directory? "acceptance"
    puts "No acceptance tests present"
    exit 0
  end
  result = cli.run "integration", smoke_only ? "_smoke" : "_acceptance"
  exit result unless result.zero?
end

def run_samples main_branch:
  unless File.directory? "samples"
    puts "No samples present"
    exit 0
  end
  Dir.chdir "samples" do
    saved_selector = ENV["GOOGLE_CLOUD_SAMPLES_TEST"]
    ENV["GOOGLE_CLOUD_SAMPLES_TEST"] = main_branch ? "master" : "not_master"
    begin
      exec ["bundle", samples_bundle_update ? "update" : "install"]
      result = exec_separate_tool ["system", "tools", "show", "test", "--local"], e: false, out: :null
      if result.success?
        exec_separate_tool ["test"]
      else
        exec ["bundle", "exec", "rake", "test"]
      end
    ensure
      ENV["GOOGLE_CLOUD_SAMPLES_TEST"] = saved_selector
    end
  end
end

expand :minitest do |t|
  t.name = "_acceptance"
  t.libs = ["lib", "acceptance"]
  t.use_bundler
  t.files = "acceptance/**/*_test.rb"
end

expand :minitest do |t|
  t.name = "_smoke"
  t.libs = ["lib", "acceptance"]
  t.use_bundler
  t.files = "acceptance/**/*smoke_test.rb"
end
