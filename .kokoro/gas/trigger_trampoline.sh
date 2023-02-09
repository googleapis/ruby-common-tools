#!/usr/bin/env bash

export TRAMPOLINE_WORKSPACE="$(dirname $(dirname $(dirname $(realpath "$0"))))"
echo Set TRAMPOLINE_WORKSPACE=$TRAMPOLINE_WORKSPACE
source "$TRAMPOLINE_WORKSPACE/.kokoro/trampoline_v2.sh"
