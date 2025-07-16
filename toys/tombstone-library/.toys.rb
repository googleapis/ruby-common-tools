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

load File.join(File.dirname(__dir__), "yoshi")

desc "Transform a gem into a tombstone after we think it's no longer useful"

required_arg :gem_name do
  desc "Name of the gem to tombstone"
end
optional_arg :gem_version do
  desc "Gem version to use for the tombstone"
end
flag :info_url, "--info-url=URL" do
  default ""
  desc "URL to use for more information"
end
flag :gem_dir, "--dir=DIR" do
  desc "Gem directory name, if different from the gem name"
end
flag :git_remote, "--remote=NAME" do
  desc "The name of the git remote to use as the pull request head. If omitted, does not open a pull request."
end
flag :enable_fork, "--fork" do
  desc "Use a fork to open the pull request"
end

include :exec, e: true
include :terminal
include :fileutils
include "yoshi-pr-generator"

DEFAULT_INFO_URL = "https://cloud.google.com/terms/deprecation"

def run
  setup
  branch_name = "pr/tombstone/#{gem_name}"
  message = "feat!: Replace #{gem_name} with a tombstone"
  result = yoshi_pr_generator.capture enabled: !git_remote.nil?,
                                      remote: git_remote,
                                      branch_name: branch_name,
                                      commit_message: message do
    delete_files
    generate_files
  end
  puts "Pull request creation: #{result}", :bold
end

def setup
  cd context_directory
  yoshi_utils.git_ensure_identity
  if enable_fork
    set :git_remote, "pull-request-fork" unless git_remote
    yoshi_utils.gh_ensure_fork remote: git_remote
  end
  set :gem_dir, gem_name if gem_dir.to_s.empty?
  set :info_url, DEFAULT_INFO_URL if info_url.to_s.empty?
  ensure_gem_version
  require "erb"
end

def ensure_gem_version
  unless gem_version
    require "json"
    content = capture ["curl", "https://rubygems.org/api/v1/gems/#{gem_name}.json"], err: :null
    last_version = JSON.parse(content)["version"]
    logger.info "Last released version for #{gem_name} was #{last_version}"
    last_version = last_version.split(".").first.to_i
    set :gem_version, "#{last_version + 1}.0.0"
  end
  logger.info "Tombstone will be #{gem_name} version #{gem_version}"
end

def delete_files
  Dir.each_child gem_dir do |child|
    rm_rf "#{gem_dir}/#{child}"
    logger.info "Deleted #{child}"
  end
end

def generate_files
  cd gem_dir do
    generate_one "README.md", "readme-template.erb"
    generate_one "LICENSE.md", "license-template.erb"
    generate_one "#{gem_name}.gemspec", "gemspec-template.erb"
    generate_one ".yardopts", "yardopts-template.erb"
    mkdir_p "lib/#{namespace_dir}"
    generate_one "lib/#{namespace_dir}/version.rb", "version-template.erb"
  end
end

def generate_one filename, template_name
  template = File.read find_data template_name
  File.write filename, ERB.new(template).result(binding)
  logger.info "Generated #{filename} from #{template_name}"
end

def cur_year
  Time.now.year.to_s
end

def namespace_modules
  @namespace_modules ||= gem_name.split("-").map { |segment| segment.split("_").map(&:capitalize).join }
end

def namespace
  @namespace ||= namespace_modules.join "::"
end

def namespace_dir
  @namespace_dir ||= gem_name.tr "-", "/"
end

def version_lines
  lines = []
  indent = 0
  namespace_modules.each do |mod|
    lines << "#{' ' * indent}module #{mod}"
    indent += 2
  end
  lines << "#{' ' * indent}VERSION = \"#{gem_version}\""
  while indent.positive?
    indent -= 2
    lines << "#{' ' * indent}end"
  end
  lines.join "\n"
end
