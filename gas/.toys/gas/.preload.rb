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

##
# Common settings for Gas tools
#
module Gas
  ##
  # Platforms to build if no platforms are specified on the command line
  #
  DEFAULT_PLATFORMS = [
    "aarch64-linux",
    "arm64-darwin",
    "x64-mingw-ucrt",
    "x64-mingw32",
    "x86-linux",
    "x86-mingw32",
    "x86_64-darwin",
    "x86_64-linux"
  ]

  ##
  # Ruby versions to build if no versions are specified on the command line
  #
  DEFAULT_RUBIES = ["3.0", "3.1", "3.2", "3.3", "3.4"]

  ##
  # Version of the Gems gem to install
  #
  GEMS_VERSION = "1.3.0"

  ##
  # Version of Rake to install
  #
  RAKE_VERSION = "13.2.1"

  ##
  # Version of Rake-compiler to install
  #
  RAKE_COMPILER_VERSION = "1.2.9"

  ##
  # Version of Rake-compiler-dock to install
  #
  RAKE_COMPILER_DOCK_VERSION = "1.8.0"

  ##
  # RCD images with pinned hashes, for 1.8.0-mri, keyed by platform.
  # These MUST be updated when rake-compiler-dock is updated. Find them at:
  # https://github.com/rake-compiler/rake-compiler-dock/pkgs/container/rake-compiler-dock-image
  #
  RAKE_COMPILER_DOCK_IMAGE = {
    "aarch64-linux" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:434ec9a0ab986c1e8021e56fb5d92169b68f50a8479ab57bb7c78288ab5c1bd6",
    "arm-linux" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:421ab2dfa84a3d6253116cdacabc9a7692f7d588dd50ff42c0d7fd71f458921e",
    "arm64-darwin" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:0f816ad0b08b0826fe64a43750e3e56663d8a697f753e98292994aa988fc9ccc",
    "x64-mingw-ucrt" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:71c07d2a3d946110ccee8a612ad1950c1809161b35d68e337037f82ebb58879a",
    "x64-mingw32" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:1fabf2a37c13610cc6fa3311c319a352c17683f03e0a25921122d5cb8f6dce03",
    "x86-linux" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:23d6452730ae98eca32c39cbdcaa08204a877bd86958c192b9824b0bac251160",
    "x86-mingw32" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:550a7cf8685b8844c024b3395b2642facd1679a0796afc3ec7120512b27c8afd",
    "x86_64-darwin" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:c5af54f9f41da6d55f1b8f802923469d870cc9d28918086eaa8a79a18ba2337c",
    "x86_64-linux" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:c2b005647d54a5a04502b584bc036886c876f6f2384fb6e7bf21f5616fbae853"
  }
end
