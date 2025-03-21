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
    "x64-mingw32",
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
  DEFAULT_RUBIES = ["3.1", "3.2", "3.3", "3.4"]

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
  RAKE_COMPILER_DOCK_VERSION = "1.9.1"

  ##
  # RCD images with pinned hashes, for 1.9.1-mri, keyed by platform.
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
    "aarch64-linux" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:69c2a064731d037f94f587cdfc4b37ec426874d7c8a5c207b6b3b921649aa1ac",
    "aarch64-linux-gnu" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:69c2a064731d037f94f587cdfc4b37ec426874d7c8a5c207b6b3b921649aa1ac",
    "aarch64-linux-musl" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:8a42843df1b4515b73baf14740fc09665e6777e107a4a5df8cc101e090364d5d",
    "arm-linux" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:e84dd09e113e7caf86b7efc94f2b56333f95bcb3cfb853fe003c8f9026874a25",
    "arm-linux-gnu" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:e84dd09e113e7caf86b7efc94f2b56333f95bcb3cfb853fe003c8f9026874a25",
    "arm-linux-musl" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:c71a3ef81655461705f2faf8f92271f13eb04dc85e191f669fd47e66880f3fdc",
    "arm64-darwin" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:263789090e83ea52d59adbfcb333238a75944707e77cc891b80b848721956a5f",
    "x64-mingw-ucrt" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:93d31a629f80afb1c04c46a711444fe850623204788d615d1164233f514f55f6",
    "x64-mingw32" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:bdd23784091050f8bbffc729a3c8739d4cd60e95d24bf49e6b0b6ef22d752f32",
    "x86-linux" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:b0d45d75a5caa83108ee871bc62efa4be1455ccc551b88f9bf1034bd14fb9092",
    "x86-linux-gnu" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:b0d45d75a5caa83108ee871bc62efa4be1455ccc551b88f9bf1034bd14fb9092",
    "x86-linux-musl" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:a1965e5b4a5e62fee9cd5e888496c12755ab6b9ecb20a5476e19e57a47961999",
    "x86-mingw32" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:02482994cd88c078b9ab5fc68b57d71270024c8a162d52a55a6a2d0ba9e6758d",
    "x86_64-darwin" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:a8798226c8b05d9d9e9777858d626316a07940d2f2847e17e6c96bd38c7f809c",
    "x86_64-linux" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:e25669c5d40fb48b5b6447050e47e40d9c0e00796e11dcc58e65253162cc2d1d",
    "x86_64-linux-gnu" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:e25669c5d40fb48b5b6447050e47e40d9c0e00796e11dcc58e65253162cc2d1d",
    "x86_64-linux-musl" => "ghcr.io/rake-compiler/rake-compiler-dock-image@sha256:c6f5a2d3bef675af799fecd0c7f01dc49aa5b04b71607eca39c6e23a2e457496"
  }
end
