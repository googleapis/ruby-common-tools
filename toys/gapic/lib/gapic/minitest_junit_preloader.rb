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

if ENV["CI"] || ENV["KOKORO_JOB_NAME"]
  begin
    require "fileutils"
    require "minitest/reporters"

    unless defined? SpongeReporter
      # Custom subclass of JUnitReporter that always outputs to a single sponge_log.xml
      # file inside the reports directory, to comply with Kokoro telemetry indexing.
      #
      # @note This class overrides private methods of Minitest::Reporters::JUnitReporter
      #   and is coupled to its internal structure. If upgrading the minitest-reporters
      #   dependency beyond 1.8.x, ensure these overrides are reviewed for compatibility.
      class SpongeReporter < Minitest::Reporters::JUnitReporter
        private

        def filename_for _suite
          File.join @reports_path, "sponge_log.xml"
        end

        # Overrides the parent method to orchestrate test suite XML generation.
        #
        # @param xml [Builder::XmlMarkup] The XML builder instance.
        # @param suite [String] The name of the test suite class.
        # @param tests [Array<Minitest::Result>] List of test cases in the suite.
        def parse_xml_for xml, suite, tests
          suite_result = analyze_suite tests
          file_path = get_relative_path tests.first
          attributes = build_suite_attributes suite, file_path, suite_result

          xml.testsuite attributes do
            tests.each do |test|
              parse_xml_testcase xml, test, suite, file_path
            end
          end
        end

        # Constructs the attributes hash for the `<testsuite>` XML element.
        # Overrides the default behavior of Minitest::Reporters::JUnitReporter,
        # which falls back to scientific notation for very small duration values
        # (e.g. 4.63e-05). Sponge's strict XSD schema validation for XML logs
        # rejects scientific exponents in decimal attributes.
        #
        # @param suite [String] The name of the test suite.
        # @param file_path [String] Relative path to the test file.
        # @param suite_result [Hash] Analyzed results from the test suite.
        # @return [Hash] Key-value attributes for the XML element.
        def build_suite_attributes suite, file_path, suite_result
          attributes = {
            name: suite, filepath: file_path, skipped: suite_result[:skip_count],
            failures: suite_result[:fail_count], errors: suite_result[:error_count],
            tests: suite_result[:test_count], assertions: suite_result[:assertion_count],
            time: format("%.6f", suite_result[:time])
          }
          attributes[:timestamp] = suite_result[:timestamp] if @timestamp_report
          attributes
        end

        # Generates the XML node for a single `<testcase>` element.
        # Overrides the default behavior of Minitest::Reporters::JUnitReporter,
        # which falls back to scientific notation for very small duration values
        # (e.g. 4.63e-05). Sponge's strict XSD schema validation for XML logs
        # rejects scientific exponents in decimal attributes.
        #
        # @param xml [Builder::XmlMarkup] The XML builder instance.
        # @param test [Minitest::Result] The specific test execution result.
        # @param suite [String] The name of the test suite.
        # @param file_path [String] Relative path to the test file.
        def parse_xml_testcase xml, test, suite, file_path
          lineno = get_source_location(test).last
          xml.testcase(
            name: test.name, lineno: lineno, classname: suite,
            assertions: test.assertions, time: format("%.6f", test.time), file: file_path
          ) do
            xml << xml_message_for(test) unless test.passed?
            if test.respond_to?("metadata") && test.metadata[:failure_screenshot_path]
              xml << xml_attachment_for(test)
            end
          end
        end
      end
    end

    # Monkey-patch Minitest::Reporters.use! to force inclusion of SpongeReporter
    # regardless of downstream helper configurations.
    module Minitest
      module Reporters
        class << self
          alias original_use! use!

          def use! reporters = nil
            reporters = Array(reporters)

            if reporters.empty?
              reporters << SpecReporter.new
            end

            has_junit = reporters.any? do |r|
              name = r.class.name
              name && (name.include?("SpongeReporter") || name.include?("JUnitReporter"))
            end

            unless has_junit
              reporters << SpongeReporter.new(".", false, { single_file: true })
            end

            original_use! reporters
          end
        end
      end
    end

    # Perform a default invocation to configure reporters immediately if the
    # target test suite does not configure any reporters natively.
    Minitest::Reporters.use!
  rescue LoadError => e
    warn "Failed to load minitest-reporters inside preloader: #{e.message}"
  end
end
