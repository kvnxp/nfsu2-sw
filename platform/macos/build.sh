#!/usr/bin/env bash
# Build the NFSU2 (Xbox) recompilation for macOS (Apple Silicon or Intel),
# with the Vulkan renderer on MoltenVK -- the combination that draws a window
# there (platform/macos/build.sh).
#
#   cmake configure + build  ->  $BUILD_DIR/nfsu2_recomp
#
# Needs (Homebrew):
#   brew install cmake pkg-config molten-vk vulkan-loader sdl2 libepoxy \
#                openssl@3 glslang spirv-tools
# (Xcode Command Line Tools: xcode-select --install. libepoxy and pkg-config
# are required even in the Vulkan build: the D3D8 shim links them.)
# Optional, for the movies instead of the slow lifted VP6 decoder:
#   tools/build_ffmpeg_vp6.sh mac   (LGPL, VP6 only)
#
# Usage:
#   platform/macos/build.sh [GAME_DIR]
#
#   GAME_DIR   the extracted disc (a directory with default.xbe): build, then
#              start the game with NFSU2_GAME_DIR=GAME_DIR. Everything.
#   no argument  build only, then print the command to run.
#
# Environment:
#   BUILD_DIR       default <repo>/build
#   JOBS            parallel compile jobs (default: hw.ncpu)
#   NFSU2_GEN_DIR   lifted C from tools/regen.sh (default <repo>/xboxrecomp/gen)
#   ARCH            target architecture: arm64 or x86_64
#                   (default: the machine's own, so Intel Macs build Intel
#                   binaries with their /usr/local Homebrew and Apple
#                   Silicon builds arm64 with /opt/homebrew -- just run it).
#                   Cross-compiling x86_64 on Apple Silicon goes through a
#                   Rosetta Homebrew in /usr/local (installed separately;
#                   the script fails naming it if missing) and passes
#                   -DCMAKE_PREFIX_PATH so CMake finds those bottles.
#   VULKAN          1 (default) Vulkan on MoltenVK. 0 builds the GL renderer,
#                   which has no window path on macOS yet: it would hit the
#                   same Cocoa main-thread rule that used to leave the Vulkan
#                   build with sound and no picture.
#   FFMPEG_DIR      VP6-only FFmpeg (default <repo>/../ffmpeg-vp6-mac)
#
# At run time the disc is $NFSU2_GAME_DIR, else a game/ directory next to
# the executable (default.xbe, NFSUNDER/, B3/), else ./game.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="${BUILD_DIR:-$REPO/build}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"
VK="${VULKAN:-1}"
GEN="${NFSU2_GEN_DIR:-$REPO/xboxrecomp/gen}"
# Native architecture by default (arm64 on Apple Silicon, x86_64 on Intel).
NATIVE="$(uname -m 2>/dev/null)"
case "$NATIVE" in
    arm64|aarch64)   NATIVE=arm64 ;;
    x86_64|amd64)   NATIVE=x86_64 ;;
    *)              NATIVE="" ;;
esac
case "${ARCH:-$NATIVE}" in
    arm64|aarch64)  ARCH=arm64 ;;
    x86_64|amd64)   ARCH=x86_64 ;;
    *)              ARCH="" ;;  # unknown: let the compiler default decide
esac

fail() { echo "error: $*" >&2; exit 1; }

# The brew that owns this build's dependencies. Native builds use the
# machine's own Homebrew; cross-compiling x86_64 on Apple Silicon needs a
# Rosetta Homebrew (conventionally /usr/local, while the native arm64 one
# lives in /opt/homebrew). Stored as an array because the Rosetta one must
# run under arch -x86_64.
BREW=(brew)
if [ "$(uname -s)" = "Darwin" ] && [ -n "$ARCH" ] && [ -n "$NATIVE" ] && [ "$ARCH" != "$NATIVE" ]; then
    if [ "$ARCH" = "x86_64" ]; then
        /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null \
            || fail "cross-compiling for x86_64 needs Rosetta (softwareupdate --install-rosetta)"
        [ -x /usr/local/bin/brew ] \
            || fail "cross-compiling for x86_64 needs an x86_64 Homebrew (install it with: arch -x86_64 /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"), then: brew install cmake pkg-config molten-vk vulkan-loader sdl2 libepoxy openssl@3 glslang spirv-tools"
        BREW=(/usr/bin/arch -x86_64 /usr/local/bin/brew)
        echo "cross-compiling for $ARCH with Rosetta Homebrew (/usr/local)"
    else
        fail "cross-compiling for $ARCH on this $NATIVE machine is not supported"
    fi
fi

# Homebrew's .pc files (epoxy, sdl2) are outside pkg-config's default path on
# Apple Silicon, and a clean environment then fails to find epoxy. Before the
# checks below, so that "pkg-config --exists epoxy" sees them too.
if [ "$(uname -s)" = "Darwin" ]; then
    HPREFIX="${HOMEBREW_PREFIX:-$("${BREW[@]}" --prefix 2>/dev/null || echo /opt/homebrew)}"
    export PKG_CONFIG_PATH="$HPREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
fi

usage() {
    echo "usage: ${0##*/} [GAME_DIR]"
    echo "  GAME_DIR    the extracted disc (a directory with default.xbe):"
    echo "              build, then start the game with NFSU2_GAME_DIR pointing at it"
    echo "  no argument build only, then print how to run"
    exit "${1:-0}"
}
case "${1:-}" in
    -h|--help) usage 0 ;;
    -*) echo "error: unknown option $1" >&2; usage 1 ;;
esac
GAME="${1:-}"
if [ -n "$GAME" ]; then
    [ -f "$GAME/default.xbe" ] || fail "$GAME has no default.xbe (point at the extracted disc)"
fi

command -v cmake >/dev/null || fail "cmake not found (brew install cmake)"
command -v pkg-config >/dev/null || fail "pkg-config not found (brew install pkg-config)"
pkg-config --exists epoxy || fail "epoxy not found (brew install libepoxy)"
[ -f "$GEN/recomp_funcs.h" ] || fail "no generated code in $GEN (run tools/regen.sh, or set NFSU2_GEN_DIR)"

VK_ARGS=(-DNFSU2_VULKAN=ON)
if [ "$VK" != "1" ]; then
    echo "warning: the GL renderer has no window path on macOS -- you will get" >&2
    echo "         sound and no picture. Set VULKAN=1 (the default)." >&2
    VK_ARGS=(-DNFSU2_VULKAN=OFF)
fi

FFMPEG_DIR="${FFMPEG_DIR:-$REPO/../ffmpeg-vp6-mac}"
FF_ARGS=(-DNFSU2_FFMPEG_DIR=)
if [ -f "$FFMPEG_DIR/lib/libavcodec.a" ]; then
    FF_ARGS=(-DNFSU2_FFMPEG_DIR="$FFMPEG_DIR")
else
    echo "warning: no FFmpeg in $FFMPEG_DIR -- movies use the lifted VP6 decoder" >&2
    echo "         (tools/build_ffmpeg_vp6.sh mac)" >&2
fi

ARCH_ARGS=()
if [ -n "$ARCH" ]; then
    ARCH_ARGS=(-DCMAKE_OSX_ARCHITECTURES="$ARCH")
    echo "target architecture: $ARCH"
fi
# In cross mode, point CMake at the foreign prefix first so find_package
# (Vulkan, etc.) resolves the matching-arch libraries, not the native ones
# CMake would otherwise prefer from its built-in search paths.
if [ -n "$ARCH" ] && [ -n "$NATIVE" ] && [ "$ARCH" != "$NATIVE" ]; then
    ARCH_ARGS+=(-DCMAKE_PREFIX_PATH="$HPREFIX")
fi

# A build dir that previously built another arch holds stale .o files the
# linker would then mix in ("symbol(s) not found for architecture X"):
# detect the switch and force a clean reconfigure (only CMake's own state
# is removed, never sources). Prefer a separate BUILD_DIR per arch.
if [ -n "$ARCH" ] && [ -n "$BUILD" ] && [ "$BUILD" != "/" ] && [ -f "$BUILD/CMakeCache.txt" ]; then
    cached="$(grep '^CMAKE_OSX_ARCHITECTURES:' "$BUILD/CMakeCache.txt" 2>/dev/null | cut -d= -f2-)"
    if [ -n "$cached" ] && [ "$cached" != "$ARCH" ]; then
        echo "architecture changed ($cached -> $ARCH): clearing CMake cache for a clean rebuild"
        rm -rf "$BUILD/CMakeCache.txt" "$BUILD/CMakeFiles"
    fi
fi

# Cross-compiling needs matching-arch bottles for every Homebrew dep; a
# stock single-arch Homebrew cannot provide them. Fail fast naming the
# culprits instead of dying later with a cryptic linker error.
if [ -n "$ARCH" ] && [ -n "$NATIVE" ] && [ "$ARCH" != "$NATIVE" ]; then
    bad=""
    for lib in \
        "$HPREFIX/opt/vulkan-loader/lib/libvulkan.1.dylib" \
        "$HPREFIX/opt/sdl3/lib/libSDL3.0.dylib" \
        "$HPREFIX/opt/sdl2-compat/lib/libSDL2-2.0.0.dylib" \
        "$HPREFIX/opt/libepoxy/lib/libepoxy.0.dylib" \
        "$HPREFIX/opt/openssl@3/lib/libcrypto.3.dylib" \
        "$HPREFIX/opt/glslang/lib/libglslang.16.dylib" \
        "$HPREFIX/opt/spirv-tools/lib/libSPIRV-Tools.dylib" \
        "$HPREFIX/lib/libMoltenVK.dylib" \
        "$FFMPEG_DIR/lib/libavcodec.a" \
        "$FFMPEG_DIR/lib/libavformat.a" \
        "$FFMPEG_DIR/lib/libavutil.a" \
        "$FFMPEG_DIR/lib/libswscale.a"; do
        [ -e "$lib" ] || continue
        case " $(lipo -archs "$lib" 2>/dev/null) " in
            *" $ARCH "*) ;;
            *) bad="$bad
  $lib" ;;
        esac
    done
    if [ -n "$bad" ]; then
        fail "cannot target $ARCH: these libraries lack that slice:$bad
       install matching-arch bottles for them (for x86_64-on-arm64: a Rosetta Homebrew in /usr/local with the same formulae)"
    fi
    echo "cross-compiling for $ARCH (Homebrew deps checked)"
fi

cmake -S "$REPO" -B "$BUILD" -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DNFSU2_GEN_DIR="$GEN" "${ARCH_ARGS[@]}" "${VK_ARGS[@]}" "${FF_ARGS[@]}"
cmake --build "$BUILD" -j"$JOBS"

echo
echo "built $BUILD/nfsu2_recomp"

if [ -n "$GAME" ]; then
    echo "starting it with NFSU2_GAME_DIR=$GAME"
    NFSU2_GAME_DIR="$GAME" exec "$BUILD/nfsu2_recomp"
fi

# Build only: say how to run it, with the disc it would find on its own
# (the same lookup the binary does: $NFSU2_GAME_DIR, game/ next to it,
# then ./game in the working directory).
found=""
for d in "$BUILD/game" "$PWD/game"; do
    if [ -f "$d/default.xbe" ]; then found="$d"; break; fi
done
if [ -n "${NFSU2_GAME_DIR:-}" ]; then
    echo "run:  NFSU2_GAME_DIR=$NFSU2_GAME_DIR $BUILD/nfsu2_recomp"
elif [ -n "$found" ]; then
    echo "run:  $BUILD/nfsu2_recomp     (it picks up $found)"
else
    echo "run:  ${0##*/} /path/to/game   (builds and starts)"
    echo "      or put the extracted disc in a game/ directory next to the binary"
fi
