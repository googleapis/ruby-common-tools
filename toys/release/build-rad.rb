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

require "yaml"
require "rubygems"
require "json"

desc "Build cloud-rad yardoc"

flag :bundle
flag :yardopts, "--yardopts=PATH"
flag :gem_name, "--gem-name=NAME"
flag :friendly_api_name, "--friendly-api-name=NAME"

include :exec, e: true
include :gems, on_missing: :install
include :fileutils

def run
  unless gem_name
    logger.error "--gem-name argument is required"
    exit 1
  end
  set :yardopts, (File.file?(".yardopts-cloudrad") ? ".yardopts-cloudrad" : ".yardopts") unless yardopts
  logger.info "Reading yardopts from #{yardopts}"
  rm_rf ".yardoc"
  rm_rf "doc"
  unless bundle
    gem "yard", "~> 0.9", ">= 0.9.26"
    gem "redcarpet", "~> 3.5", ">= 3.5.1"
  end

  if gem_name == "help"
    return build_help
  end
  yardopts_content = File.read yardopts
  cmd = ["yard", "doc", "--no-yardopts"] + build_options(yardopts_content)
  cmd = ["bundle", "exec"] + cmd if bundle
  env = { "CLOUDRAD_GEM_NAME" => gem_name, "CLOUDRAD_FRIENDLY_API_NAME" => friendly_api_name }
  exec cmd, env: env
  sanity_check
end

def build_options yardopts_content
  orig_options = yardopts_content.split "\n"
  final_options = [
    "--format", "yaml",
    "--template-path", find_data("rad-yard-templates")
  ]
  in_format = false
  orig_options.each do |opt|
    if in_format
      in_format = false
      next
    end
    case opt
    when "--format"
      in_format = true
      next
    when /^--format[= ]/, "", "CONTRIBUTING.md", "CODE_OF_CONDUCT.md", /^LICENSE(\.md)?/
      next
    when /^(--[a-z-]+)\s+(.+)$/
      final_options << "#{Regexp.last_match[1]}=#{Regexp.last_match[2]}"
    else
      final_options << opt
    end
  end
  final_options
end

def build_help
  mkdir "doc"
  write_toc
  write_metadata
  sanity_check
end

def write_toc
  custom_names = {
    "index.md" => "Getting started",
    "occ_for_iam.md" => "OCC for IAM"
  }
  guides = {
    "./../README.md" => "index.md"
  }
  Dir.glob("*.md").each do |file|
    guides[file] = File.basename(file).downcase
  end
  toc_items = []
  guides.each do |path, filename|
    cp path, "doc/#{filename}"
    toc_items << {
      "name" => custom_names[filename] || File.basename(filename, ".*").tr("_-", " ").capitalize,
      "href" => filename
    }
  end
  toc_data = [
    {
      "uid" => "product-neutral-guides",
      "name" => "Client library help",
      "items" => toc_items
    }
  ]
  File.write "doc/toc.yaml", YAML.dump(toc_data)
end

def write_metadata
  gemspec = Gem::Specification.load "help.gemspec"
  version = gemspec.version.to_s
  metadata = {
    "language" => "ruby",
    "name" => "product-neutral-guides",
    "version" => version
  }
  File.write "doc/docs.metadata.json", JSON.pretty_generate(metadata)
end

def sanity_check
  Dir.glob "doc/*.yml" do |path|
    YAML.load_file path
  end
end
