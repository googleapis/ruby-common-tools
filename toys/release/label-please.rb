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

desc "Adds the release-please force label."

flag :pr_number, "--pr-number=NUMBER"
flag :github_event_name, "--github-event-name=VAL"

include :exec, e: true
include :terminal

def run
  if github_event_name == "schedule" && !ENV["RELEASE_PLEASE_DISABLE"].to_s.empty?
    puts "Release-please is disabled", :yellow
    exit 0
  end
  ensure_pr_number
  exec ["gh", "issue", "edit", pr_number, "--add-label", "release-please:force-run"]
end

def ensure_pr_number
  return if pr_number
  require "json"
  sha = capture(["git", "rev-parse", "HEAD"]).strip
  results = JSON.parse capture(["gh", "pr", "list", "--search", "#{sha} is:merged", "--json", "number"])
  if results.empty?
    puts "Unable to find latest pull request", :bold, :red
    exit 1
  end
  set :pr_number, results.first["number"]
end
