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
  DEFAULT_RUBIES = ["2.6", "2.7", "3.0", "3.1", "3.2"]

  ##
  # Version of the Gems gem to install
  #
  GEMS_VERSION = "1.2.0"

  ##
  # Version of Rake to install
  #
  RAKE_VERSION = "13.0.6"

  ##
  # Version of Rake-compiler to install
  #
  RAKE_COMPILER_VERSION = "1.2.1"

  ##
  # Version of Rake-compiler-dock to install
  #
  RAKE_COMPILER_DOCK_VERSION = "1.3.0"

  ##
  # RCD images with pinned hashes, for 1.3.0-mri, keyed by platform
  #
  RAKE_COMPILER_DOCK_IMAGE = {
    "aarch64-linux" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:a8eeb523cd8bef165d4b8dcb9e4588274dd0b9c95f11b66631ae0b4207791e36",
    "arm-linux" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:e0d38dfca73d1c100a0e8bdb211d898498ae2d9e0f46cba66bdcd7057647ac94",
    "arm64-darwin" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:e0eb1f9f632fb18d4f244b7297d1a5e7cf60ae58e649ac5b2f8ac6266ea07128",
    "x64-mingw-ucrt" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:29a89cf3864b78d2a8c4668982210cbf1d102395061d9281158a9f329f99099a",
    "x64-mingw32" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:6e968a39510aa16fb7b02f9dbb7eed35045ad751eacc32deec9b7d55603bae09",
    "x86-linux" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:7bc2311ef5ee37ed63a379fa988854770d9392b3120b51c384d6cd3cafd914c8",
    "x86-mingw32" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:4372920da490410bfb0f892be20a2258643408bf265e48bb6cd388694fa7746d",
    "x86_64-darwin" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:8dd11cad778d9fc01c3555a57254016f5db7227309d24f50a192a6db80d4a51c",
    "x86_64-linux" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:31d4d870b2cb209daa154c7b3aa09db3eb75335c208d2b1606c32bd40db16e1e"
  }
end
