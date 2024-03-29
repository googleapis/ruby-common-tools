# Copyright 2023 Google LLC
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

require_relative "generator"

def create_data_into_file filename, data_type, data_pattern, data_size
  data_size = data_size.to_i
  generator = Generator.new data_type, data_pattern, data_size
  File.write filename, generator.generate
end

create_data_into_file ARGV.shift, ARGV.shift, ARGV.shift, ARGV.shift
