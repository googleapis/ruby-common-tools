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

tool "dev" do
  include :exec, e: true

  flag :tag, "--tag=NAME"

  def run
    ::Dir.chdir context_directory
    version = ::Time.now.utc.strftime "%Y-%m-%d-%H%M%S"
    image_url = "gcr.io/cloud-devrel-public-resources/owlbot-ruby"
    logger.info "Dev build: #{image_url}:#{version} ..."
    exec [
      "gcloud", "builds", "submit",
      "--project=cloud-devrel-public-resources",
      "--tag=#{image_url}:#{version}",
      context_directory
    ]
    if tag
      logger.info "Tagging as #{image_url}:#{tag} ..."
      exec [
        "gcloud", "container", "images", "add-tag",
        "--project=cloud-devrel-public-resources",
        "#{image_url}:#{version}",
        "#{image_url}:#{tag}",
        "--quiet"
      ]
    end
    logger.info "... Done"
  end
end

tool "prod" do
  include :exec, e: true

  required_arg :version

  def run
    ::Dir.chdir ::File.dirname context_directory
    logger.info "Prod build: gcr.io/cloud-devrel-public-resources/owlbot-ruby:v#{version} ..."
    exec [
      "gcloud", "builds", "submit",
      "--project=cloud-devrel-public-resources",
      "--config=owlbot-preprocessor/cloudbuild.yaml",
      "--substitutions=TAG_NAME=owlbot-preprocessor/v#{version}",
      "."
    ]
    logger.info "... Done"
  end
end
