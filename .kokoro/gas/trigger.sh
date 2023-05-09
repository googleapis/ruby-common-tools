#!/bin/bash

set -eo pipefail

# Install gems in the user directory because the default install directory
# is in a read-only location.
export GEM_HOME=$HOME/.gem
export PATH=$GEM_HOME/bin:$PATH

cd gas
rbenv local $RUBY_31_VERSION
gem install --no-document toys:0.14.5
toys gas kokoro-trigger -v
