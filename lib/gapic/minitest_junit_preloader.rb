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
      class SpongeReporter < Minitest::Reporters::JUnitReporter
        private

        def filename_for _suite
          File.join @reports_path, "sponge_log.xml"
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
              FileUtils.mkdir_p "tmp/reports"
              reporters << SpongeReporter.new("tmp/reports", false, { single_file: true })
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
