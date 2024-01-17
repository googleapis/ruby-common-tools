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
  DEFAULT_RUBIES = ["2.6", "2.7", "3.0", "3.1", "3.2", "3.3"]

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
  RAKE_COMPILER_VERSION = "1.2.5"

  ##
  # Version of Rake-compiler-dock to install
  #
  RAKE_COMPILER_DOCK_VERSION = "1.4.0"

  ##
  # RCD images with pinned hashes, for 1.4.0-mri, keyed by platform
  #
  RAKE_COMPILER_DOCK_IMAGE = {
    "aarch64-linux" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:37a993592c084198923e9574cbbde1673cfa167cd106bd14364997f1f9981cac",
    "arm-linux" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:afd8feda44731292fd16b816187d04d0def636546756d1e6b3887ce86d5d52b1",
    "arm64-darwin" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:16bb1a0746215557f5577e4cd289e10cec593d74b5a3033c9bb2ab4bc3c6662f",
    "x64-mingw-ucrt" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:beeb644d381f71490e34d40f9697ff3c25fca0db4917565e058a2b39a5815bc3",
    "x64-mingw32" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:9e9454d45a0568f5842fa8933e9905882635951864a07bc986133d5b732b51f0",
    "x86-linux" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:4167d00276c0ddb0eb4eb2a0fc2a882a9983c8fb5f1979297e77ed28d4b2e924",
    "x86-mingw32" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:1b2852da28c272a817b733ba1d6576e3b588b90a50f6159fd1b5c85a13ec48ff",
    "x86_64-darwin" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:ba8e38140f69ae8febe01f8b168782ec1f15cd2e59dd61719fd1176404138062",
    "x86_64-linux" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:8fc4fe7a195a970e0437033f2147eb191b2ed5eea50f0aeaf8e317fdb1f3ff14"
  }
end
