#!/bin/bash

set -eo pipefail

# Install gems in the user directory because the default install directory
# is in a read-only location.
export GEM_HOME=$HOME/.gem
export PATH=$GEM_HOME/bin:$PATH
echo "=== ENVIRONMENT DEBUG ==="
echo "PATH: $PATH"
echo "User ID: $(id)"
echo "Kernel: $(uname -a)"
echo "Glibc version: $(ldd --version | head -n 1)"
echo "DOCKER_API_VERSION: $DOCKER_API_VERSION"
echo "Docker path: $(which docker || echo 'Not found on PATH')"
ls -l /usr/bin/docker || true
ldd /usr/bin/docker || true
ls -la /var/run/docker.sock || true
docker version || true
podman version || true
echo "========================="

cd gas
toys gas kokoro-trigger -v
