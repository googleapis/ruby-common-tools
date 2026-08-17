#!/bin/bash

set -eo pipefail

# Install gems in the user directory because the default install directory
# is in a read-only location.
export GEM_HOME=$HOME/.gem
export PATH=$GEM_HOME/bin:$PATH

echo "=== ENVIRONMENT DEBUG ==="
echo "PATH: $PATH"
echo "User ID: $(id)"
echo "Kernel: $(uname -r)"
echo "Glibc version: $(ldd --version | head -n 1)"
echo "DOCKER_API_VERSION: $DOCKER_API_VERSION"
if which docker > /dev/null 2>&1; then
  echo "Docker path: $(which docker)"
  ls -l $(which docker)
  docker version || true
else
  echo "Docker binary not found in PATH"
fi

cd gas
toys gas kokoro-trigger -v
