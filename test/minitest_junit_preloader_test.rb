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

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "English"

class MinitestJunitPreloaderTest < Minitest::Test
  def test_preloader_generates_xml_in_current_directory
    Dir.mktmpdir do |dir|
      write_dummy_test dir
      output = run_subprocess dir

      # Assert subprocess succeeded
      assert $CHILD_STATUS.success?, "Dummy test execution in subprocess failed. Output:\n#{output}"

      # Assert sponge_log.xml was generated directly inside `dir` (current directory)
      xml_file = File.join dir, "sponge_log.xml"
      assert File.exist?(xml_file), "Expected sponge_log.xml to be generated at the current directory"

      # Assert no tmp/reports directory was created
      refute File.exist?(File.join(dir, "tmp")), "Expected no tmp/ directory to be created"

      # Verify XML content
      xml_content = File.read xml_file
      assert_includes xml_content, "<testsuite name=\"DummyTest\""
      assert_includes xml_content, "<testcase name=\"test_success\""
    end
  end

  private

  def write_dummy_test dir
    test_file = File.join dir, "dummy_test.rb"
    File.write test_file, <<~RUBY
      require "gapic/minitest_junit_preloader"
      require "minitest/autorun"

      class DummyTest < Minitest::Test
        def test_success
          assert true
        end
      end
    RUBY
  end

  def run_subprocess dir
    lib_dir = File.expand_path "../toys/gapic/lib", __dir__
    test_file = File.join dir, "dummy_test.rb"
    cmd = [
      "bundle", "exec", "ruby",
      "-I", lib_dir,
      test_file
    ]
    env = {
      "CI" => "true",
      "KOKORO_JOB_NAME" => "test"
    }

    IO.popen env, cmd, chdir: dir, &:read
  end
end
