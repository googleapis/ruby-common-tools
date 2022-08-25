# frozen_string_literal: true

# Copyright 2022 Google LLC
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

desc "Installs python packages used by release scripts."

flag :update_hashes do
  desc "Regenerate releases-requirements.txt file with the latest hashes"
end

include :exec, e: true
include :fileutils

def run
  if update_hashes
    do_update_hashes
  else
    do_install
  end
end

def do_update_hashes
  requirements_dir = find_data "requirements", type: :directory
  unless File.writable? requirements_dir
    logger.fatal "Cannot write the requirements directory. " \
                 "You must update hashes from the original ruby-common-tools repo."
    exit 1
  end
  require "tmpdir"
  Dir.mktmpdir do |dir|
    exec ["python", "-m", "venv", "reqs"], chdir: dir
    venv_dir = File.join dir, "reqs"
    exec <<~SCRIPT, chdir: requirements_dir
      source #{venv_dir}/bin/activate
      echo '####'
      echo '####' python -m pip install --require-hashes -r pip-tools-requirements.txt
      echo '####'
      python -m pip install --require-hashes -r pip-tools-requirements.txt
      echo '####'
      echo '####' pip-compile releases-requirements.in --generate-hashes
      echo '####'
      rm releases-requirements.txt
      pip-compile releases-requirements.in --generate-hashes
    SCRIPT
  end
end

def do_install
  releases_requirements = find_data "requirements/releases-requirements.txt", type: :file
  exec ["python", "-m", "pip", "install", "--no-deps", "--require-hashes", "-r", releases_requirements]
end
