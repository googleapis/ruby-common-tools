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
require "toys/standard_mixins/exec"
require "logger"
require_relative "owlbot"
require_relative "owlbot_releases"

cli = ::Toys::CLI.new base_level: ::Logger::INFO

cli.add_config_block do # rubocop:disable Metrics/BlockLength
  desc "Ruby postprocessor for OwlBot"

  flag :gem_name, "--gem=NAME"
  flag :all_gems
  flag :owlbot_tasks, "--[no-]owlbot-tasks", default: true
  flag :release_tasks, "--[no-]release-tasks", default: true

  def run
    handle_owlbot_tasks if owlbot_tasks
    handle_release_tasks if release_tasks
  end

  def handle_owlbot_tasks
    if gem_name
      OwlBot.entrypoint gem_name: gem_name, logger: logger
    else
      OwlBot.multi_entrypoint logger: logger
    end
  rescue OwlBot::Error => e
    logger.error e.message
    exit 1
  end

  def handle_release_tasks
    exec_service = self[Toys::StandardMixins::Exec::KEY]
    releases = OwlBotReleases.new logger: logger, exec_service: exec_service
    if gem_name
      releases.single_gem gem_name
    elsif all_gems
      releases.all_gems
    else
      releases.changed_gems
    end
  end
end

exit cli.run ::ARGV
