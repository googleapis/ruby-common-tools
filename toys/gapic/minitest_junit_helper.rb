# frozen_string_literal: true

# Copyright 2026 Google LLC
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

require "fileutils"

##
# Helper module to automatically format minitest execution output into JUnit XML
# reports. This enables centralized test result indexing, flake tracing, and
# build health metrics reporting inside TestGrid dashboards.
#
# If a package does not natively declare `minitest-reporters` as a dependency,
# this helper dynamically wraps the bundle Gemfile at execution time and activates it.
#
module MinitestJunitHelper
  ##
  # Dynamically wraps the original Gemfile with a wrapper Gemfile containing
  # the `minitest-reporters` dependency. This is skipped if the original Gemfile
  # or lockfile already declares the dependency natively.
  #
  # @param gemfile_path [String, nil] Path to original Gemfile
  # @return [String] Path to active Gemfile (original or wrapper)
  #
  def setup_minitest_junit_wrapper gemfile_path: nil
    ctx_dir = context_directory || Dir.getwd
    original_gemfile = File.expand_path(gemfile_path || "Gemfile", ctx_dir)
    return original_gemfile unless ENV["CI"] || ENV["KOKORO_JOB_NAME"]
    return original_gemfile unless File.file? original_gemfile

    # Prepend this checkout's lib directory to RUBYLIB so that spawned subprocesses
    # can require gapic/minitest_junit_preloader natively without parent-directory climbing.
    lib_path = File.expand_path "../../lib", __dir__
    ENV["RUBYLIB"] = [lib_path, ENV["RUBYLIB"]].compact.join File::PATH_SEPARATOR

    # Check if minitest-reporters is already defined natively
    lockfile = "#{original_gemfile}.lock"
    has_dep = File.read(original_gemfile).include?("minitest-reporters")
    has_dep ||= File.read(lockfile).include?("minitest-reporters") if File.file? lockfile

    if has_dep
      return original_gemfile
    end

    @wrapper_gemfile = File.join ctx_dir, "Gemfile.junit"
    wrapper_content = <<~GEMFILE
      eval_gemfile #{original_gemfile.inspect}
      gem "minitest-reporters", "~> 1.5.0", require: false
    GEMFILE

    File.write @wrapper_gemfile, wrapper_content
    ENV["BUNDLE_GEMFILE"] = @wrapper_gemfile
    @wrapper_gemfile
  end

  ##
  # Cleans up any generated wrapper Gemfile and its lockfile from the directory.
  #
  def cleanup_minitest_junit_wrapper
    return unless @wrapper_gemfile
    FileUtils.rm_f @wrapper_gemfile
    FileUtils.rm_f "#{@wrapper_gemfile}.lock"
  end
end
