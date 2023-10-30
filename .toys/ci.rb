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

toys_version! "~> 0.14"

desc "Run CI checks"

CHECKS = [:test, :rubocop]

flag :only
CHECKS.each do |name|
  flag name, "--[no-]#{name}"
end

include :exec, result_callback: :handle_result
include :terminal

def handle_result result
  if result.success?
    puts "** #{result.name} passed\n\n", :green, :bold
  else
    puts "** CI terminated: #{result.name} failed!", :red, :bold
    exit 1
  end
end

def run
  
  # Temporary hack to allow minitest-rg 5.2.0 to work in minitest 5.19 or
  # later. This should be removed if we have a better solution or decide to
  # drop rg.
  ENV["MT_COMPAT"] = "true"
  
  Dir.chdir context_directory
  CHECKS.each { |name| set name, !only if get(name).nil? }
  if test
    Dir.chdir "owlbot-postprocessor" do
      exec_separate_tool ["test"], name: "OwlBot postprocessor tests"
    end
    Dir.chdir "gas" do
      exec_separate_tool ["system", "test"], name: "GAS tests"
    end
  end
  exec_tool ["rubocop"], name: "Rubocop" if rubocop
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
