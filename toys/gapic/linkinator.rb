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

include :exec, e: true
include :terminal

def run
  Dir.chdir context_directory
  gem_name = determine_gem
  input_dir = determine_input gem_name
  skip_regexes = determine_skips gem_name
  output_lines = run_linkinator input_dir, skip_regexes
  interpret_output output_lines
end

def determine_gem
  require "json"
  repo_metadata = JSON.load_file ".repo-metadata.json"
  repo_metadata["distribution_name"]
end

def determine_input gem_name
  if File.directory?("node_modules") || !File.file?("../.gitignore") || File.basename(context_directory) != gem_name
    # Run from current directory
    "./doc"
  else
    # Run from parent directory
    Dir.chdir File.dirname context_directory
    "./#{gem_name}/doc"
  end
end

def determine_skips gem_name
  wrapper_gem_name = gem_name.sub(/-v\d\w*$/, "")
  skip_regexes = [
    "\\w+\\.md$",
    "^https://rubygems\\.org/gems/#{wrapper_gem_name}",
    "^https://cloud\\.google\\.com/ruby/docs/reference/#{gem_name}/latest$",
    "^https://rubydoc\\.info/gems/#{gem_name}",
    "^https?://stackoverflow\\.com/questions/tagged/google-cloud-platform\\+ruby$",
    "^https://console\\.cloud\\.google\\.com/apis/library/\\\w+\\.googleapis\\.com$"
  ]
  if gem_name == wrapper_gem_name
    skip_regexes << "^https://cloud\\.google\\.com/ruby/docs/reference/#{gem_name}-v\\d\\w*/latest$"
    skip_regexes << "^https://rubydoc\\.info/gems/#{gem_name}-v\\d\\w*"
  end
  skip_regexes
end

def run_linkinator input_dir, skip_regexes
  linkinator_cmd = ["npx", "linkinator", input_dir, "--retry-errors", "--skip", skip_regexes.join(" ")]
  result = exec linkinator_cmd, out: [:tee, :capture, :inherit], err: [:child, :out], in: :null
  result.captured_out.split "\n"
end

def interpret_output output_lines
  allowed_http_codes = ["200", "202"]
  output_lines.select! { |link| link =~ /^\[(\d+)\]/ && !allowed_http_codes.include?(::Regexp.last_match[1]) }
  output_lines.each do |link|
    puts link, :yellow
  end
  exit 1 unless output_lines.empty?
end
