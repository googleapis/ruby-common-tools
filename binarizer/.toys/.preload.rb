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
# Common settings for binarizer tools
#
module Binarizer
  DEFAULT_PLATFORMS = [
    "x86_64-linux", "x86-linux", "x86_64-darwin", "arm64-darwin",
    "x86-mingw32", "x64-mingw32", "x64-mingw-ucrt"
  ]
  DEFAULT_RUBIES = ["2.6", "2.7", "3.0", "3.1", "3.2"]

  GEMS_VERSION = "1.2.0"
  RAKE_VERSION = "13.0.6"
  RAKE_COMPILER_VERSION = "1.2.1"
  RAKE_COMPILER_DOCK_VERSION = "1.3.0"
end
