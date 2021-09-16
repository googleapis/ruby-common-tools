# Copyright 2021 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

expand :minitest do |t|
  t.use_bundler
  t.libs = ["lib", "test"]
  t.files = "test/**/test_*.rb"
end

expand :rubocop, bundler: true

tool "ci" do
  desc "Run CI checks"

  flag :only
  flag :test, "--[no-]test"
  flag :rubocop, "--[no-]rubocop"

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
    ::Dir.chdir context_directory
    set :test, !only if test.nil?
    set :rubocop, !only if rubocop.nil?
    exec_tool ["test"], name: "Unit tests" if test
    exec_tool ["rubocop"], name: "Rubocop" if rubocop
  end
end

tool "build" do
  include :exec, e: true

  flag :image_name, "--image-name=NAME", default: "owlbot-postprocessor-test"

  def run
    ::Dir.chdir context_directory
    logger.info "Building #{image_name} ..."
    exec ["docker", "build", "-t", image_name, "."]
    logger.info "... Done"
  end
end
