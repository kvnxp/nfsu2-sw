#!/usr/bin/env bash
# Build for Intel Macs: x86_64 build of platform/macos/build.sh.
#
#   platform/macos/build-x64.sh [GAME_DIR]
#
# Same arguments as build.sh. On an Intel Mac this is identical to running
# build.sh (native architecture); on Apple Silicon it cross-compiles, which
# needs x86_64 Homebrew bottles (a stock single-arch Homebrew only carries
# the host arch, so prefer a native build on each machine).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ARCH=x86_64
exec "$HERE/build.sh" "$@"
