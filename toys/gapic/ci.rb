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

CI_TASKS = {
  "test" => [],
  "rubocop" => [],
  "build" => [],
  "yard" => [],
  "linkinator" => [],
  "acceptance" => [:project, :keyfile],
  "samples-main" => [:project, :keyfile, :samples_bundle_update],
  "samples-latest" => [:project, :keyfile, :samples_bundle_update]
}.freeze

at_least_one_required desc: "Tasks" do
  CI_TASKS.each_key do |task|
    flag "task-#{task}", "--[no-]#{task}", desc: "Run the #{task} task"
  end
  flag :all_tasks, "--all", desc: "Run all tasks"
end

flag :project, "--project=PROJECT", desc: "The project for integration tests"
flag :keyfile, "--keyfile=KEYFILE", desc: "Credentials JSON file or content"
flag :samples_bundle_update, desc: "Update rather than install the samples bundle"

include :exec, e: true
include :terminal

def run
  Dir.chdir context_directory
  failures = run_tasks
  report_result failures
end

def run_tasks
  failures = []
  CI_TASKS.each do |task, opts|
    next unless all_tasks || get("task-#{task}")
    puts "RUNNING: #{task}", :bold, :cyan
    result = exec_separate_tool [task, *build_args(opts)], e: false
    if result.success?
      puts "SUCCEEDED: #{task}", :bold, :green
    else
      puts "FAILED: #{task}", :bold, :red
      failures << task
    end
  end
  failures
end

def build_args opts
  opts.map do |opt|
    opt_flag = opt.to_s.tr "_", "-"
    val = get opt
    if val.is_a? String
      "--#{opt_flag}=#{val}"
    elsif val
      "--#{opt_flag}"
    end
  end.compact
end

def report_result failures
  if failures.empty?
    puts "CI PASSED", :bold, :green
  else
    puts "CI FAILED:", :bold, :red
    failures.each do |failure|
      puts "FAILED: #{failure}", :bold, :red
    end
    exit 1
  end
end
