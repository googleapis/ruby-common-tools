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

desc "Build cloud-rad yardoc"

flag :bundle
flag :yardopts, "--yardopts=PATH", default: ".yardopts"
flag :gem_name, "--gem-name=NAME"

include :exec, e: true
include :gems, on_missing: :install

def run
  unless gem_name
    logger.error "--gem-name argument is required"
    exit 1
  end
  unless bundle
    gem "yard", "~> 0.9", ">= 0.9.26"
    gem "redcarpet", "~> 3.5", ">= 3.5.1"
  end
  yardopts_content = File.read yardopts
  cmd = ["yard", "doc"] + build_options(yardopts_content)
  cmd = ["bundle", "exec"] + cmd if bundle
  env = { "CLOUDRAD_GEM_NAME" => gem_name }
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
    when /^--format[= ]/, ""
      next
    when /^(--[a-z-]+)\s+(.+)$/
      final_options << "#{Regexp.last_match[1]}=#{Regexp.last_match[2]}"
    else
      final_options << opt
    end
  end
  final_options
end

def sanity_check
  require "yaml"
  Dir.glob "doc/*.yml" do |path|
    YAML.load_file path
  end
end
