#!/bin/bash

set -eo pipefail

# Install gems in the user directory because the default install directory
# is in a read-only location.
export GEM_HOME=$HOME/.gem
export PATH=$GEM_HOME/bin:$PATH

# Force Docker client to use legacy API version 1.39 to match Kokoro host daemon.
export DOCKER_API_VERSION=1.39

cd gas
toys gas kokoro-trigger -v
