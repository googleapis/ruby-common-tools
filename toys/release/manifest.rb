# frozen_string_literal: true

# Copyright 2022 Google LLC
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

desc "Runs release-please using the current manifest config."

flag :install
flag :global_node_package
flag :release_please_version, "--release-please-version=VERSION", default: "latest"
flag :use_fork, "--fork"
flag :base_dir, "--base-dir=PATH"
flag :release_type, "--release-type=TYPE", default: "ruby-yoshi"
flag :repo_url, "--repo-url=NAME"
flag :skip_labeling
flag :dry_run
flag :delay, "--delay=SECS", default: 2, accept: Numeric
flag :github_event_name, "--github-event-name=NAME"
flag :github_token, "--github-token=TOKEN"

remaining_args :input_packages do
  desc "Release the specified packages. If no specific packages are provided, all are checked."
end

include :exec, e: true
include :terminal, styled: true

def run
  check_github_context
  Dir.chdir context_directory
  handle_install
  init_repo

  @errors = []
  if input_packages.empty?
    run_release_please
  else
    input_packages.each do |input|
      package, version = input.split ":"
      run_release_please package: package, version: version
      sleep delay
    end
  end
  return if @errors.empty?

  logger.error "**** FINAL ERRORS: ****"
  @errors.each { |msg| logger.error msg }
  exit 1
end

def check_github_context
  return if github_event_name == "workflow_dispatch"
  return if ENV["RELEASE_PLEASE_DISABLE"].to_s.empty?
  logger.warn "Scheduled release-please jobs have been disabled"
  exit 0
end

def handle_install
  return unless install
  cmd = ["npm", "install"]
  cmd << "-g" if global_node_package
  cmd << "release-please@#{release_please_version}"
  exec cmd
  exit 0
end

def init_repo
  require "json"
  set :repo_url, default_repo_url unless repo_url
  set :github_token, default_github_token unless github_token
  return unless use_fork
  exec ["gh", "repo", "fork", "--remote=false"]
  repo = ::JSON.parse(capture(["gh", "repo", "view", "--json=name"]))["name"]
  owner = ::JSON.parse(capture(["gh", "api", "/user"]))["login"]
  exec ["gh", "repo", "sync", "#{owner}/#{repo}"]
end

def run_release_please package: nil, version: nil # rubocop:disable Metrics/CyclomaticComplexity
  job_name = package ? "Release-please global run" : "Release please for #{package} only"
  cmd = []
  cmd += ["npx", "-p", "release-please@#{release_please_version}"] unless global_node_package
  cmd += ["release-please", "release-pr", "--repo-url", repo_url]
  cmd += ["--fork"] if use_fork
  cmd += ["--token", github_token] if github_token
  cmd += ["--path", package] if package && !package.empty?
  cmd += ["--release-as", version] if version && !version.empty?
  cmd += ["--skip-labeling"] if skip_labeling
  cmd += ["--dry-run"] if dry_run
  cmd += ["--debug"] if verbosity.positive?
  log_cmd = "exec: #{cmd.inspect}"
  log_cmd.sub! github_token, "****" if github_token
  result = exec cmd, log_cmd: log_cmd, e: false
  return if result.success?
  logger.error "Error running #{job_name}"
  @errors << "Error running #{job_name}"
end

def default_repo_url
  url = capture(["git", "remote", "get-url", "origin"]).strip
  return Regexp.last_match[1] if url =~ %r{github\.com[:/]([\w-]+/[\w-]+)(?:\.git|/)?$}

  logger.error "Unable to determine current github repo"
  exit 1
end

def default_github_token
  value = ENV["GITHUB_TOKEN"].to_s
  return value unless value.empty?
  result = exec ["gh", "auth", "status", "-t"], out: :capture, err: :capture
  match = /Token: (\w+)/.match(result.captured_out + result.captured_err)
  match ? match[1] : nil
end
