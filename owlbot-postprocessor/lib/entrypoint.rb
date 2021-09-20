# frozen_string_literal: true

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

require "toys-core"
require "logger"
require_relative "owlbot"

cli = ::Toys::CLI.new base_level: ::Logger::INFO

cli.add_config_block do
  desc "Ruby postprocessor for OwlBot"

  flag :gem_name, "--gem=NAME"

  def run
    if gem_name
      OwlBot.entrypoint gem_name: gem_name, logger: logger
    else
      OwlBot.multi_entrypoint logger: logger
    end
  rescue OwlBot::Error => e
    logger.error e.message
    exit 1
  end
end

exit cli.run ::ARGV
