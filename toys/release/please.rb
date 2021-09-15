# frozen_string_literal: true

# Copyright 2021 Google LLC
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

desc "Runs release-please."

flag :install
flag :use_fork, "--fork"
flag :base_dir, "--base-dir=PATH"
flag :release_type, "--release-type=TYPE", default: "ruby"
flag :non_gem, "--non-gem"
flag :version_file, "--version-file=PATH"
flag :version_expr, "--version-expr=EXPR"
flag :repo_url, "--repo-url=NAME"
flag :retries, "--retries=TIMES", default: 1, accept: Integer
flag :delay, "--delay=SECS", default: 2, accept: Numeric
flag :retry_delay, "--retry-delay=SECS", default: 4, accept: Numeric
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
  package_info = init_info

  @errors = []
  package_info.each do |name, version, dir|
    release_please name, version, dir
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
  exec ["npm", "install", "release-please"]
  exit 0
end

def init_info
  set :repo_url, default_repo_url unless repo_url
  set :github_token, default_github_token unless github_token
  package_info = input_packages.empty? ? find_all_packages : interpret_input_packages
  raise "Cannot provide --version-file with multiple packages" if package_info.size > 1 && version_file
  raise "Cannot provide --version-expr with multiple packages" if package_info.size > 1 && version_expr
  package_info
end

def find_all_packages
  prefix = base_dir ? "#{base_dir}/" : ""
  if non_gem
    Dir.glob("#{prefix}*/CHANGELOG.md").map do |path|
      dir = File.dirname path
      [File.basename(dir), nil, dir]
    end
  else
    (Dir.glob("#{prefix}*.gemspec") + Dir.glob("#{prefix}*/*.gemspec")).map do |path|
      [File.basename(path, ".gemspec"), nil, File.dirname(path)]
    end
  end
end

def interpret_input_packages
  prefix = base_dir ? "#{base_dir}/" : ""
  input_packages.map do |input|
    name, version = input.split ":"
    version = nil if version == ""
    path =
      if non_gem
        unless File.file? "#{prefix}#{name}/CHANGELOG.md"
          logger.error "Unable to find package directory #{name} in the repo"
          exit 1
        end
        "#{prefix}#{name}"
      else
        paths = Dir.glob("#{prefix}#{name}.gemspec") + Dir.glob("#{prefix}*/#{name}.gemspec")
        if paths.empty?
          logger.error "Unable to find gem #{name} in the repo"
          exit 1
        elsif paths.size > 1
          logger.error "Found multiple gemspecs for gem #{name} in the repo"
          exit 1
        else
          paths.first
        end
      end
    [name, version, path]
  end
end

def release_please package_name, release_as, dir
  version_path = version_file || default_version_path(dir, package_name)
  cur_version = package_version package_name, dir, version_path
  job_name = "release-please for #{package_name} from version #{cur_version}"
  job_name = "#{job_name} as version #{release_as}" if release_as
  logger.info "Running #{job_name}"

  cmd = build_command dir, package_name, cur_version, release_as, version_path
  log_cmd = cmd.inspect
  log_cmd.sub! github_token, "****" if github_token

  cur_retry_delay = retry_delay
  cur_retries = retries
  error_msg = nil
  loop do
    result = exec cmd, log_cmd: log_cmd, e: false
    break if result.success?
    error_msg = "Error running #{job_name}"
    logger.error error_msg
    break if cur_retries <= 0
    sleep cur_retry_delay
    logger.warn "Retrying..."
    cur_retries -= 1
    cur_retry_delay *= 2
  end
  @errors << error_msg if error_msg
  sleep delay
end

def package_version package_name, dir, version_path
  func =
    if non_gem
      raise "Need --version-path for a non-gem package release" unless version_path
      expr = version_expr || default_version_expr(package_name)
      constants = expr.split "::"
      proc do
        Dir.chdir dir do
          load version_path
          puts constants.reduce(::Object) { |cur, name| cur.const_get name.to_sym }
        end
      end
    else
      proc do
        Dir.chdir dir do
          spec = Gem::Specification.load "#{package_name}.gemspec"
          puts spec.version.to_s
        end
      end
    end
  version = capture_proc(func).strip
  version == "0.0.1alpha" ? nil : version
end

def build_command dir, package_name, cur_version, release_as, version_path
  cmd = [
    "npx", "release-please", "release-pr",
    "--package-name", package_name,
    "--path", dir,
    "--release-type", release_type,
    "--repo-url", repo_url,
    "--bump-minor-pre-major",
    "--monorepo-tags",
    "--debug"
  ]
  cmd += ["--fork"] if use_fork
  cmd += ["--last-package-version", cur_version] if cur_version && cur_version >= "0.1"
  cmd += ["--release-as", release_as] if release_as
  cmd += ["--token", github_token] if github_token
  cmd += ["--version-file", version_path] if version_path
  cmd
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

def default_version_path dir, package_name
  path = nil
  Dir.chdir dir do
    path = File.join "lib", package_name.gsub("-", "/"), "version.rb"
    path = nil unless File.file? path
    if path.nil?
      paths = Dir.glob "lib/**/version.rb"
      path = paths[0] if paths.size == 1
    end
  end
  if path
    logger.info "Updating version at #{path}"
  else
    logger.warn "Unable to find version.rb!"
  end
  path
end

def default_version_expr package_name
  namespace = package_name
              .split("-")
              .map { |segment| segment.split("_").map(&:capitalize).join }
              .join "::"
  "#{namespace}::VERSION"
end
