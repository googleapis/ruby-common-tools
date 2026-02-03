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

toys_version! "~> 0.15"

desc "Run CI checks"

CHECKS = [:test, :rubocop]
DIRS = ["owlbot-postprocessor", "gas"]

flag :only
CHECKS.each do |name|
  flag name, "--[no-]#{name}"
end
flag :dirs, "--dirs=NAMES" do |f|
  f.accept Array
  f.desc "Test the given dirs (comma-delimited) instead of analyzing changes."
end
flag :all_dirs do |f|
  f.desc "Test all dirs."
end
flag :include_owlbot_build do |f|
  f.desc "Build owlbot postprocessor"
end
flag :github_event_name, "--github-event-name=EVENT" do |f|
  f.default ""
  f.desc "Name of the github event triggering this job. Optional."
end
flag :github_event_payload, "--github-event-payload=PATH" do |f|
  f.default ""
  f.desc "Path to the github event payload JSON file. Optional."
end
flag :head_commit, "--head=COMMIT" do |f|
  f.desc "Ref or SHA of the head commit when analyzing changes. Defaults to the current commit."
end
flag :base_commit, "--base=COMMIT" do |f|
  f.desc "Ref or SHA of the base commit when analyzing changes. If omitted, uses uncommitted diffs."
end

include :exec
include :terminal

def run
  Dir.chdir context_directory
  CHECKS.each { |name| set name, !only if get(name).nil? }
  @errors = []
  run_test if test
  run_rubocop if rubocop
  if @errors.empty?
    puts "ALL TESTS PASSED", :bold, :green
  else
    puts "FAILURES:", :bold, :red
    @errors.each { |err| puts err, :red }
    exit 1
  end
end

def run_rubocop
  puts "RUNNING: rubocop", :bold, :cyan
  result = exec_separate_tool ["rubocop"], name: "Rubocop"
  if result.success?
    puts "PASSED: rubocop", :bold, :green
  else
    puts "FAILED: rubocop", :bold, :red
    @errors << "rubocop"
  end
end

def run_test
  determine_dirs.each do |dir|
    name = "#{dir}: test"
    Dir.chdir dir do
      puts "RUNNING: #{name}", :bold, :cyan
      if dir == "owlbot-postprocessor" && include_owlbot_build
        result = exec_separate_tool ["build"] + verbosity_flags, name: "owlbot postprocessor build"
        unless result.success?
          puts "FAILED BUILD: #{name}", :bold, :red
          next
        end
      end
      result = exec_separate_tool ["test", "--minitest-mock"], name: "Tests in #{dir}"
      if result.success?
        puts "PASSED: #{name}", :bold, :green
      else
        puts "FAILED: #{name}", :bold, :red
        @errors << name
      end
    end
  end
end

def determine_dirs
  return dirs & DIRS if dirs
  return DIRS if all_dirs || github_event_name == "schedule"
  dirs_from_changes
end

def dirs_from_changes
  puts "Evaluating changes.", :bold
  base_ref, head_ref = interpret_github_event
  ensure_checkout head_ref unless head_ref.nil?
  files = find_changed_files base_ref
  if files.empty?
    puts "No files changed.", :bold
  else
    puts "Files changed:", :bold
    files.each { |file| puts "  #{file}" }
  end

  dirs = find_changed_dirs files
  if dirs.empty?
    puts "No changed dirs found.", :bold
  else
    puts "Changed dirs found: #{dirs}", :bold
  end
  dirs
end

def interpret_github_event
  require "json"
  payload = JSON.parse File.read github_event_payload unless github_event_payload.empty?
  base_ref, head_ref =
    case github_event_name
    when "pull_request"
      logger.info "Getting commits from pull_request event"
      [payload["pull_request"]["base"]["ref"], nil]
    when "push"
      logger.info "Getting commits from push event"
      [payload["before"], nil]
    when "workflow_dispatch"
      logger.info "Getting inputs from workflow_dispatch event"
      [payload["inputs"]["base"], payload["inputs"]["head"]]
    else
      logger.info "Using local commits"
      [base_commit, head_commit]
    end
  base_ref = nil if base_ref&.empty?
  head_ref = nil if head_ref&.empty?
  [base_ref, head_ref]
end

def ensure_checkout head_ref
  logger.info "Checking for head ref: #{head_ref}"
  head_sha = ensure_fetched head_ref
  current_sha = capture(["git", "rev-parse", "HEAD"], e: true).strip
  if head_sha == current_sha
    logger.info "Already at head SHA: #{head_sha}"
  else
    logger.info "Checking out head SHA: #{head_sha}"
    exec ["git", "checkout", head_sha], e: true
  end
end

def find_changed_files base_ref
  if base_ref.nil?
    logger.info "No base ref. Using local diff."
    capture(["git", "status", "--porcelain"], e: true).split("\n").map { |line| line.split.last }
  else
    logger.info "Diffing from base ref: #{base_ref}"
    base_sha = ensure_fetched base_ref
    capture(["git", "diff", "--name-only", base_sha], e: true).split("\n").map(&:strip)
  end
end

def ensure_fetched ref
  result = exec ["git", "show", "--no-patch", "--format=%H", ref], out: :capture, err: :capture
  if result.success?
    result.captured_out.strip
  elsif ref == "HEAD^"
    # Common special case
    current_sha = capture(["git", "rev-parse", "HEAD"], e: true).strip
    exec ["git", "fetch", "--depth=2", "origin", current_sha], e: true
    capture(["git", "rev-parse", "HEAD^"], e: true).strip
  else
    logger.info "Fetching ref: #{ref}"
    exec ["git", "fetch", "--depth=1", "origin", "#{ref}:refs/temp/#{ref}"], e: true
    capture(["git", "show", "--no-patch", "--format=%H", "refs/temp/#{ref}"], e: true).strip
  end
end

def find_changed_dirs files
  require "set"
  dirs = Set.new
  files.each do |file|
    next unless file =~ %r{^([^/]+)/.+$}
    dir = Regexp.last_match[1]
    dirs << dir
  end
  dirs.to_a & DIRS
end

tool "build" do
  include :exec, e: true

  def run
    Dir.chdir context_directory
    Dir.chdir "owlbot-postprocessor" do
      exec_separate_tool ["build"] + verbosity_flags
    end
  end
end
