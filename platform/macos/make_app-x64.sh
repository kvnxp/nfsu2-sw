#!/usr/bin/env bash
# Package an Intel-Mac .app: x86_64 packaging of platform/macos/make_app.sh.
#
#   platform/macos/make_app-x64.sh [GAME_DIR]
#
# Same arguments as make_app.sh. ARCH flows into the build.sh it invokes
# (unless NO_BUILD=1), and the bundled dylibs are checked against the
# binary's architecture before signing.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ARCH=x86_64
exec "$HERE/make_app.sh" "$@"
