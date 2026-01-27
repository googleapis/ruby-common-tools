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
    "aarch64-linux-gnu",
    "aarch64-linux-musl",
    "arm64-darwin",
    "x64-mingw-ucrt",
    "x86-linux-gnu",
    "x86-linux-musl",
    "x86-mingw32",
    "x86_64-darwin",
    "x86_64-linux-gnu",
    "x86_64-linux-musl"
  ]

  ##
  # Ruby versions to build if no versions are specified on the command line
  #
  DEFAULT_RUBIES = ["3.1", "3.2", "3.3", "3.4", "4.0"]

  ##
  # Version of the Gems gem to install
  #
  GEMS_VERSION = "1.3.0"

  ##
  # Version of Rake to install
  #
  RAKE_VERSION = "13.3.1"

  ##
  # Version of Rake-compiler to install
  #
  RAKE_COMPILER_VERSION = "1.3.1"

  ##
  # Version of Rake-compiler-dock to install
  #
  RAKE_COMPILER_DOCK_VERSION = "1.11.1"

  ##
  # RCD images with pinned hashes, for 1.11.1-mri, keyed by platform.
  #
  # Any platform that _could_ be requested, should have a corresponding image
  # even if it's a duplicate. e.g. x86_64-linux and x86_64-linux-gnu are
  # synonymous and map to the same image, but both keys need to be present
  # since either could be requested.
  #
  # These MUST be updated when rake-compiler-dock is updated. Find them at:
  # https://github.com/rake-compiler/rake-compiler-dock/pkgs/container/rake-compiler-dock-image
  #
  RAKE_COMPILER_DOCK_IMAGE = {
    "aarch64-linux" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:622413680d8c73a7c3fb5f37f9312aa26ed9b77b6d6d6e9b84e31387bbb9f618",
    "aarch64-linux-gnu" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:622413680d8c73a7c3fb5f37f9312aa26ed9b77b6d6d6e9b84e31387bbb9f618",    
    "aarch64-linux-musl" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:fc4b52173a4683ded5a39424093aca0ec7a3a2793371d0f1e0e3e7d03423cab8",
    "aarch64-mingw-ucrt" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:116ac59f8eaf970384d8a9b8ac06f2369a428be40cbf9ba4d57e13f337ff23e1",
    "arm-linux" => "ghcr.io/rake-compiler/rake-compiler-dock-image@ha256:ea1f972e09a67cb91266f64c1fb073953710dbc68151ce45ba90955588fad860",
    "arm-linux-gnu" => "ghcr.io/rake-compiler/rake-compiler-dock-image@ha256:ea1f972e09a67cb91266f64c1fb073953710dbc68151ce45ba90955588fad860",
    "arm-linux-musl" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:73ef2c62e3cd994928b4566cec6f8c5d4a7e59fda2fb1340df9e780eb82f0b27",
    "arm64-darwin" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:5f087b280675e43271370a95261a0000c79a0bc7456f87c313efbc07ba1b0a76",
    "jruby" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:3a73bfa413e15839f35300fbe31ced121cc30cc84c754d7e345bff2d48f8037e",
    "x64-mingw-ucrt" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:dd80a6d33dfe7019af63b47711aeb9b87c860e71b6dff319149fff3499af86e1",
    "x64-mingw32" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:663206c2dac43e563c7815269e7bb7cdc424a4fe691d0cbfa123332e1f37f1ff",
    "x86-linux" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:b9500afe101f57327690483de0cc40552033a0d54a83e0b6f7f61f8c3dc46003",
    "x86-linux-gnu" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:b9500afe101f57327690483de0cc40552033a0d54a83e0b6f7f61f8c3dc46003",
    "x86-linux-musl" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:6749f76336959623fe3bfe6167eaf3e33ff799dbad6eb07a9ce957523d0905cb",
    "x86-mingw32" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:1663491d3d07c2a06eda34dfe9a97ce4739a162ea137cd9714900f6e7a5192cc",
    "x86_64-darwin" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:e9ec271a0eb24c6910618e85764b5e85c3e9b255225c1a359c8eabbb4a0065e3",
    "x86_64-linux" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:56b7870f3195b5689f1403d35a94aa6ef58205ceb50792d5a06f32a09a070bef",
    "x86_64-linux-gnu" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:56b7870f3195b5689f1403d35a94aa6ef58205ceb50792d5a06f32a09a070bef",
    "x86_64-linux-musl" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:48ebcc90a31acf63baebce3828e95a8565f85a6f0cb1bb861f1947529cfda49e"
  }
end
