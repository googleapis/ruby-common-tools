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

desc "Performs a gem release"

optional_arg :package
flag :dry_run, default: ENV["RELEASE_DRY_RUN"] == "true"
flag :base_dir, "--base-dir=PATH"
flag :all, "--all=REGEX"
flag :enable_docs
flag :enable_rad
flag :gems, "--gems=NAMES" do |f|
  f.accept Array
  f.desc "Run for the given gems (comma-delimited)"
end
flag :force_republish
flag :report_to_pr, "--report-to-pr=LINK", default: ENV["AUTORELEASE_PR"]
flag :reporter_org, "--reporter-org=VALUE"
flag :reporter_app, "--reporter-app=VALUE"
flag :reporter_installation, "--reporter-installation=VALUE"
flag :reporter_pem, "--reporter-pem=VALUE"
flag :rubygems_api_token, "--rubygems-api-token=VALUE", default: ENV["RUBYGEMS_API_TOKEN"]
flag :docs_staging_bucket, "--docs-staging-bucket=VALUE", default: ENV["STAGING_BUCKET"]
flag :rad_staging_bucket, "--rad-staging-bucket=VALUE", default: ENV["V2_STAGING_BUCKET"]
flag :docuploader_credentials, "--docuploader-credentials=VALUE", default: ENV["DOCUPLOADER_CREDENTIALS"]

include :exec, e: true
include :gems

def run
  Dir.chdir context_directory
  Dir.chdir base_dir if base_dir
  load_deps
  load_env
  start_report
  @success = false
  perform_release
  @success = true
ensure
  finish_report
end

def load_deps
  # TODO: Update gems to "~> 1.3" after we drop Ruby 3.0 support and can vendor
  # gems 1.3.0 in the docker image.
  gem "gems", "~> 1.2"
  gem "jwt", "~> 2.10"
  require "fileutils"
  require "gems"
  require "json"
  require "jwt"
  require "net/http"
  require "tmpdir"
end

def load_env
  raise "Did not find KOKORO_GFILE_DIR" unless ENV["KOKORO_GFILE_DIR"]
  secret_manager_dir = File.join ENV["KOKORO_GFILE_DIR"], "secret_manager"
  keystore_dir = ENV["KOKORO_KEYSTORE_DIR"]
  logger.warn "Did not find KOKORO_KEYSTORE_DIR" unless keystore_dir

  # TODO: We may be able to stop loading this from secret manager, as we've
  # confirmed that ADC creds (at least on the google-cloud-ruby release jobs)
  # are sufficient for docuploader. Strip this out once we've confirmed that
  # is also the case for other release jobs we support.
  load_param :docuploader_credentials, secret_manager_dir, "docuploader_service_account", from: :path
  load_param :rubygems_api_token, keystore_dir, "73713_rubygems-publish-key" if keystore_dir
  load_param :rubygems_api_token, secret_manager_dir, "ruby-rubygems-token"

  if reporter_org && report_to_pr
    load_param :reporter_app, secret_manager_dir, "releasetool-publish-reporter-app"
    load_param :reporter_installation, secret_manager_dir, "releasetool-publish-reporter-#{reporter_org}-installation"
    load_param :reporter_pem, secret_manager_dir, "releasetool-publish-reporter-pem"
    ENV["GITHUB_TOKEN"] = ENV["GH_TOKEN"] = @reporter_token = acquire_reporter_token
    extract_pr_info
  end

  nil
end

def load_param param_name, dir, file_name, from: :content
  return if self[param_name]
  file_path = File.join dir, file_name
  if File.file? file_path
    value =
      case from
      when :content
        File.read file_path
      when :path
        file_path
      else
        raise ArgumentError, "Unknown value set from #{from.inspect}"
      end
    set param_name, value
    logger.info "Read #{param_name} from environment #{file_name}"
  else
    logger.warn "#{param_name} not available from environment #{file_name}"
  end
end

def acquire_reporter_token
  return unless reporter_app && reporter_installation && reporter_pem
  logger.info "Acquiring pull request reporter token from GitHub..."
  uri = URI "https://api.github.com/app/installations/#{reporter_installation}/access_tokens"
  response = Net::HTTP.post uri, "", build_oauth_headers
  unless response.is_a? Net::HTTPSuccess
    logger.error "Failed GitHub oauth exchange. Response of type #{response.class}"
    return nil
  end
  content = JSON.parse response.body rescue {}
  if content["token"]
    logger.info "Token acquired"
  else
    logger.error "Token couldn't be found in GitHub oauth response"
  end
  content["token"]
end

def build_oauth_headers
  now = Time.now.to_i - 1
  payload = { "iat" => now, "exp" => now + 600, "iss" => reporter_app }
  private_key = OpenSSL::PKey::RSA.new reporter_pem
  jwt = JWT.encode payload, private_key, "RS256"
  {
    "Authorization" => "Bearer #{jwt}",
    "Accept" => "application/vnd.github.machine-man-preview+json"
  }
end

def extract_pr_info
  @pr_org = @pr_repo = @pr_number = nil
  return unless report_to_pr
  match = report_to_pr.match %r{^https://github\.com/([^/]+)/([^/]+)/pull/(\d+)$}
  return unless match
  @pr_org = match[1]
  @pr_repo = match[2]
  @pr_number = match[3].to_i
end

def start_report
  return unless @pr_number && @reporter_token
  build_url = ENV["CLOUD_LOGGING_URL"]
  unless build_url
    kokoro_build_id = ENV["KOKORO_BUILD_ID"]
    build_url = "http://sponge/#{kokoro_build_id}" if kokoro_build_id
  end
  message =
    if build_url
      "The release build has started. The log can be viewed [here](#{build_url}) (internal Google URL). :sunflower:"
    else
      "The release build has started, but the build log URL could not be determined. :broken_heart:"
    end
  result = exec ["gh", "pr", "comment", @pr_number, "--repo=#{@pr_org}/#{@pr_repo}", "--body", message], e: false
  report_exec_errors result, "Initial comment on PR"
end

def finish_report
  return unless @pr_number && @reporter_token
  if @success
    message = ":egg: You hatched a release! The release build finished successfully! :purple_heart:"
    add_label = "autorelease: published"
    remove_label = "autorelease: tagged"
  else
    message = "The release build failed! Please investigate!"
    add_label = "autorelease: failed"
    remove_label = nil
  end
  cmd = ["gh", "pr", "comment", @pr_number, "--repo=#{@pr_org}/#{@pr_repo}", "--body", message]
  result = exec cmd, e: false
  report_exec_errors result, "Final comment on PR"
  cmd = ["gh", "issue", "edit", @pr_number, "--repo=#{@pr_org}/#{@pr_repo}"]
  cmd += ["--add-label", add_label] if add_label
  cmd += ["--remove-label", remove_label] if remove_label
  result = exec cmd, e: false
  report_exec_errors result, "Label update on PR"
end

def perform_release
  if gems
    gems.each do |gem|
      gem_name, gem_version = (lookup_current_versions Regexp.new "^#{gem}$").first
      perform_release_gem name: gem_name, version: gem_version
    end
  else
    determine_packages.each do |name, version|
      perform_release_gem name: name, version: version
    end
  end
end

def perform_release_gem name:, version:
  releaser = Performer.new name,
                           last_version: version,
                           logger: logger,
                           tool_name: tool_name,
                           cli: cli,
                           rubygems_api_token: rubygems_api_token,
                           docs_staging_bucket: docs_staging_bucket || "docs-staging",
                           rad_staging_bucket: rad_staging_bucket || "docs-staging-v2",
                           docuploader_credentials: docuploader_credentials,
                           docuploader_tries: 2

  releaser.run force_republish: force_republish,
               enable_rad: enable_rad,
               dry_run: dry_run
end

def determine_packages
  packages = {}
  if all
    regex = Regexp.new all
    current_versions = lookup_current_versions regex
    Dir.glob "*/*.gemspec" do |path|
      name = File.dirname path
      packages[name] = current_versions[name] if regex.match? name
    end
  else
    packages[package || package_from_context] = nil
  end
  packages
end

def package_from_context
  return ENV["RELEASE_PACKAGE"] unless ENV["RELEASE_PACKAGE"].to_s.empty?
  tags = Array(ENV["KOKORO_GIT_COMMIT"])
  logger.info "Got #{tags.inspect} from KOKORO_GIT_COMMIT"
  tags += capture(["git", "describe", "--exact-match", "--tags"], err: :null, e: false).strip.split
  logger.info "All tags: #{tags.inspect}"
  tags.each do |tag|
    if tag =~ %r{^([^/]+)/v\d+\.\d+\.\d+$}
      return Regexp.last_match[1]
    end
  end
  logger.error "Unable to determine package from context"
  exit 1
end

def lookup_current_versions regex
  versions = {}
  lines = capture(["gem", "search", regex.source]).split "\n"
  lines.each do |line|
    next unless line =~ /^([\w-]+) \((\d+(?:\.\w+)+)\)/
    gem_name = Regexp.last_match[1]
    gem_version = Regexp.last_match[2]
    versions[gem_name] = gem_version if regex.match? gem_name
  end
  raise "Something went wrong getting all current gem versions" if versions.empty?
  versions
end

def report_exec_errors result, description
  return if result.success?
  logger.error "#{description} failed with ex=#{result.exception.inspect} code=#{result.exit_code.inspect}"
end

class Performer
  def initialize gem_name,
                 gem_dir: nil,
                 rubygems_api_token: nil,
                 docs_staging_bucket: nil,
                 rad_staging_bucket: nil,
                 docuploader_credentials: nil,
                 docuploader_tries: nil,
                 last_version: nil,
                 logger: nil,
                 tool_name: nil,
                 cli: nil
    @gem_name = gem_name
    @logger = logger
    @tool_name = tool_name
    @cli = cli
    result_callback = proc { |result| raise "Command failed" unless result.success? }
    @executor = Toys::Utils::Exec.new logger: @logger, result_callback: result_callback
    @gem_dir = gem_dir
    @gem_dir ||= (File.file?("#{@gem_name}/#{@gem_name}.gemspec") ? File.expand_path(@gem_name) : Dir.getwd)
    @rubygems_api_token = rubygems_api_token
    @docs_staging_bucket = docs_staging_bucket
    @rad_staging_bucket = rad_staging_bucket
    @docuploader_credentials = docuploader_credentials
    @current_rubygems_version = Gem::Version.new last_version if last_version
    @docuploader_tries = docuploader_tries || 1
    @bundle_updated = false
  end

  attr_reader :gem_name
  attr_reader :gem_dir
  attr_reader :rubygems_api_token
  attr_reader :docs_staging_bucket
  attr_reader :rad_staging_bucket
  attr_reader :docuploader_credentials
  attr_reader :logger
  attr_reader :tool_name
  attr_reader :cli

  def needs_gem_publish?
    gem_version > current_rubygems_version
  end

  def run force_republish: false,
          enable_docs: false,
          enable_rad: false,
          dry_run: false
    if !force_republish && !needs_gem_publish?
      logger.warn "**** Gem #{gem_name} is already up to date at version #{gem_version}. Skipping."
      return
    end
    transformation_info = transform_links
    begin
      publish_gem dry_run: dry_run
      publish_docs dry_run: dry_run if enable_docs
      publish_rad dry_run: dry_run if enable_rad
    ensure
      detransform_links transformation_info
    end
  end

  def transform_links
    logger.info "**** Transforming links for #{gem_name}"
    transformation_info = {}
    Dir.chdir gem_dir do
      Dir.glob "*.md" do |filename|
        content = File.read filename
        transformation_info[filename] = content
        transformed_content = content.gsub(/\[([^\]]*)\]\(([^):]*\.md)\)/, "{file:\\2 \\1}")
        File.open(filename, "w") { |file| file << transformed_content }
      end
    end
    transformation_info
  end

  def detransform_links transformation_info
    Dir.chdir gem_dir do
      transformation_info.each do |filename, content|
        File.open(filename, "w") { |file| file << content }
      end
    end
  end

  def publish_gem dry_run: false
    Dir.chdir gem_dir do
      unless needs_gem_publish?
        logger.warn "**** Already published. Skipping gem publish of #{gem_name}"
        return
      end
      logger.info "**** Starting publish_gem for #{gem_name}"
      run_aux_task "build", remove: "pkg"
      built_gem_path = "pkg/#{gem_name}-#{gem_version}.gem"
      raise "Failed to build #{built_gem_path}" unless File.file? built_gem_path
      if dry_run
        logger.warn "**** In dry run mode. Skipping gem publish of #{gem_name}"
        return
      end
      response = gems_client.push File.new built_gem_path
      logger.info response
      raise "Failed to publish gem" unless response.include? "Successfully registered gem:"
    end
  end

  def publish_docs dry_run: false
    Dir.chdir gem_dir do
      unless File.file? ".yardopts"
        logger.warn "**** No .yardopts file present. Skipping publish_docs for #{gem_name}"
        return
      end
      logger.info "**** Starting publish_docs for #{gem_name}"
      run_aux_task "yard", remove: ["doc", ".yardoc"]
      run_docuploader staging_bucket: docs_staging_bucket,
                      dry_run: dry_run
    end
  end

  def publish_rad dry_run: false
    Dir.chdir gem_dir do
      if repo_metadata["is_cloud"] == false
        logger.info "**** Disabled publish_rad for #{gem_name} because repo-metadata sets is_cloud to false."
        return
      end
      unless File.file? ".yardopts"
        logger.warn "**** No .yardopts file present. Skipping publish_rad for #{gem_name}"
        return
      end
      logger.info "**** Starting publish_rad for #{gem_name}"
      result = cli.run(*tool_name[0..-2], "build-rad", "--gem-name", gem_name, "--friendly-api-name", friendly_api_name)
      unless result.zero?
        logger.error "**** build-rad failed! Aborting publish_rad."
        return
      end
      run_docuploader staging_bucket: rad_staging_bucket,
                      dest_prefix: "docfx-",
                      dry_run: dry_run
    end
  end

  def run_docuploader staging_bucket:, dest_prefix: "", dry_run: false
    logger.info "**** Starting docuploader"
    Dir.mktmpdir do |tmpdir|
      archive_path = File.join tmpdir, "archive.tar.gz"
      Dir.chdir "doc" do
        metadata_path = "./docs.metadata"
        write_docs_metadata metadata_path: metadata_path
        make_docs_archive archive_path: archive_path
      end
      if dry_run
        logger.warn "**** In dry run mode. Skipping upload"
      else
        upload_docs_archive archive_path: archive_path, staging_bucket: staging_bucket, dest_prefix: dest_prefix
      end
    end
  end

  def write_docs_metadata metadata_path:
    update_time = Time.now
    content = <<~CONTENT
      update_time {
        seconds: #{update_time.to_i}
        nanos: #{update_time.nsec}
      }
      name: "#{gem_name}"
      version: "v#{gem_version}"
      language: "ruby"
      distribution_name: "#{gem_name}"
    CONTENT
    File.write metadata_path, content
    logger.info "**** Created docs.metadata"
  end

  def make_docs_archive archive_path:
    logger.info "**** Creating docs archive..."
    cmd = [
      "tar", "--create",
      "--directory=.",
      "--file=#{archive_path}",
      "--force-local",
      "--gzip",
      "--verbose",
      "."
    ]
    result = @executor.exec cmd, result_callback: nil
    unless result.success?
      logger.warn "**** Failed to create docs archive. Retrying without --force-local."
      cmd.delete "--force-local"
      @executor.exec cmd
    end
    logger.info "**** Created docs archive: #{archive_path}"
  end

  def upload_docs_archive archive_path:, staging_bucket:, dest_prefix:
    logger.info "**** Uploading archive..."
    dest_url = "gs://#{staging_bucket}/#{dest_prefix}ruby-#{gem_name}-v#{gem_version}.tar.gz"
    cmd = ["gcloud", "storage", "cp", archive_path, dest_url]
    opts = { result_callback: nil }
    opts[:env] = { "GOOGLE_APPLICATION_CREDENTIALS" => docuploader_credentials } if docuploader_credentials
    tries = @docuploader_tries
    loop do
      result = @executor.exec cmd, **opts
      if result.success?
        logger.info "**** Uploaded archive to: #{dest_url}"
        break
      end
      tries -= 1
      unless tries.positive?
        logger.error "**** Upload failed after retries"
        raise "Failed"
      end
      logger.warn "**** Retrying command after error"
    end
  end

  def run_aux_task task_name, remove: []
    Array(remove).each { |path| FileUtils.rm_rf path }
    if File.file? "Rakefile"
      isolate_bundle do
        @executor.exec ["bundle", "exec", "rake", task_name]
      end
    else
      @executor.exec ["toys", task_name]
    end
  end

  def current_rubygems_version
    @current_rubygems_version ||= begin
      value = gems_client.info(gem_name)["version"]
      logger.info "Existing gem version = #{value}"
      Gem::Version.new value
    rescue Gems::NotFound
      logger.info "No existing gem version"
      Gem::Version.new "0.0.0"
    end
  end

  def gem_version
    @gem_version ||= begin
      func = proc do
        Dir.chdir gem_dir do
          spec = Gem::Specification.load "#{gem_name}.gemspec"
          puts spec.version
        end
      end
      value = @executor.capture_proc(func).strip
      logger.info "Specification gem version = #{value}"
      Gem::Version.new value
    end
  end

  def gems_client
    @gems_client ||= begin
      if rubygems_api_token
        Gems.configure do |config|
          config.key = rubygems_api_token
        end
        logger.info "Configured rubygems api token of length #{rubygems_api_token.length}"
      end
      Gems::Client.new
    end
  end

  def repo_metadata
    @repo_metadata ||= begin
      repo_metadata_path = File.join gem_dir, ".repo-metadata.json"
      JSON.parse File.read repo_metadata_path rescue {}
    end
  end

  def friendly_api_name
    @friendly_api_name ||= repo_metadata["name_pretty"] || gem_name
  end

  def isolate_bundle
    block = proc do
      @executor.exec ["bundle", "update"] unless @bundle_updated
      @bundle_updated = true
      yield
    end
    if defined?(Bundler)
      if Bundler.respond_to? :with_unbundled_env
        Bundler.with_unbundled_env(&block)
      else
        Bundler.with_clean_env(&block)
      end
    else
      block.call
    end
  end
end
