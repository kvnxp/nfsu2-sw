#!/usr/bin/env bash
# Package the macOS build into a double-clickable NFSU2.app
# (platform/macos/make_app.sh).
#
#   build/nfsu2_recomp  ->  $APP/Contents/MacOS/nfsu2_recomp + bundled dylibs
#                           + the disc copied to Contents/Resources/game
#
# The bundle carries its own copies of every Homebrew dylib the binary links
# (vulkan-loader, MoltenVK, SDL2-compat + SDL3 it dlopens, epoxy, glslang,
# SPIRV-Tools, libcrypto), rewritten to @rpath, so it runs with no Homebrew
# installed. A launcher script (CFBundleExecutable) sets the MoltenVK ICD,
# finds the disc and starts in a writable state directory (the renderer
# caches and xbox_kernel.log go to the working directory, which is / for a
# Finder launch).
#
# Usage:
#   platform/macos/make_app.sh [GAME_DIR]
#
#   Builds the binary (platform/macos/build.sh) and packages it together with
#   the disc: GAME_DIR -- the extracted disc (default.xbe) -- is COPIED into
#   the bundle as Contents/Resources/game, so the .app carries everything
#   and grows by the disc's size (~2.5 GB). Default GAME_DIR: the build/game
#   symlink target when it is a disc. Saves land in the bundled copy
#   (Contents/Resources/game/UDATA); a re-run keeps that copy as long as
#   GAME_DIR still points at the same disc, RECOPY=1 starts fresh.
#   no argument  package without a disc (an already bundled copy is kept);
#                at run time the launcher still honours $NFSU2_GAME_DIR and
#                a game/ folder next to the .app.
#
# Environment:
#   BUILD_DIR   default <repo>/build   (build.sh writes nfsu2_recomp there)
#   APP         output bundle (default $BUILD_DIR/NFSU2.app)
#   RECOPY=1    with GAME_DIR: discard the previous bundle copy, copy again
#   NO_BUILD=1  package the binary as it is, skip platform/macos/build.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="${BUILD_DIR:-$REPO/build}"
BIN="$BUILD/nfsu2_recomp"
APP="${APP:-$BUILD/NFSU2.app}"
HPREFIX="${HOMEBREW_PREFIX:-$(brew --prefix 2>/dev/null || echo /opt/homebrew)}"

fail() { echo "error: $*" >&2; exit 1; }

# The disc: argument, else whatever build/game points at.
GAME="${1:-}"
if [ -z "$GAME" ] && [ -f "$BUILD/game/default.xbe" ]; then
    GAME="$(cd "$BUILD/game" && pwd -P)"
fi
if [ -n "$GAME" ]; then
    [ -f "$GAME/default.xbe" ] || fail "$GAME has no default.xbe"
    GAME="$(cd "$GAME" && pwd -P)"
fi

# One command from a clean tree: compile, then package what we built.
if [ -z "${NO_BUILD:-}" ]; then
    echo "building (platform/macos/build.sh, NO_BUILD=1 to skip)"
    "$REPO/platform/macos/build.sh"
fi
[ -x "$BIN" ] || fail "no $BIN after the build"

is_brew_dep() {
    case "$1" in
        "$HPREFIX"/*|/usr/local/*) return 0 ;;
        *) return 1 ;;
    esac
}

# LC_LOAD_DYLIB entries only: for dylibs otool -L lists the LC_ID_DYLIB first
# (still the Homebrew path after copying) -- it is not a dependency and must
# not be copied, rewritten or counted as "still linked".
deps() {
    local f="$1" id d
    id="$(otool -D "$f" 2>/dev/null | sed -n 2p)"
    otool -L "$f" | tail -n +2 | awk '{print $1}' | while IFS= read -r d; do
        if [ -n "$id" ] && [ "$d" = "$id" ]; then
            continue
        fi
        printf '%s\n' "$d"
    done
}

echo "packaging $BIN -> $APP"

MACOS="$APP/Contents/MacOS"
FW="$APP/Contents/Frameworks"
RES="$APP/Contents/Resources"
GAME_DST="$RES/game"

# The disc inside the bundle: the launcher exports NFSU2_GAME_DIR pointing at
# it, so the .app carries everything. It must live in Contents/Resources --
# Contents/MacOS is reserved for code and codesign refuses data there. The
# copy is ~2.5 GB: move it out of the way instead of letting rm -rf eat it,
# and put it back below when the source disc has not changed (saves in UDATA
# stay with it). Older layouts left it in Contents/MacOS/game; adopt that too.
GAME_KEEP=""
if [ -z "${RECOPY:-}" ]; then
    for cand in "$GAME_DST" "$MACOS/game"; do
        if [ -d "$cand" ] && [ ! -L "$cand" ] && [ -f "$cand/default.xbe" ]; then
            GAME_KEEP="$BUILD/.nfsu2_app_game"
            rm -rf "$GAME_KEEP"
            mv "$cand" "$GAME_KEEP"
            break
        fi
    done
fi

rm -rf "$APP"
mkdir -p "$MACOS" "$FW" "$RES/vulkan/icd.d"

cp -f "$BIN" "$MACOS/nfsu2_recomp"

if [ -n "$GAME_KEEP" ]; then
    if [ -z "$GAME" ] || [ "$(cat "$GAME_KEEP/.nfsu2_source" 2>/dev/null)" = "$GAME" ]; then
        mkdir -p "$RES"
        mv "$GAME_KEEP" "$GAME_DST"
        echo "game: keeping the bundled copy ($GAME_DST)"
    else
        rm -rf "$GAME_KEEP"
    fi
fi
if [ -n "$GAME" ] && [ ! -e "$GAME_DST" ]; then
    echo "game: copying the disc into the bundle (~2.5 GB)..."
    mkdir -p "$GAME_DST"
    ditto "$GAME" "$GAME_DST"
    printf '%s\n' "$GAME" > "$GAME_DST/.nfsu2_source"
    echo "game: done -- $(du -sh "$GAME_DST" | awk '{print $1}') in $GAME_DST"
fi

# SDL2-compat dlopens SDL3 at run time (@loader_path/libSDL3.dylib first) and
# the loader dlopens MoltenVK through the ICD json -- neither is an LC_LOAD,
# so add them by hand. SDL3 keeps its real name only as libSDL3.dylib (the
# candidate sdl2-compat asks for).
cp -f "$HPREFIX/opt/sdl3/lib/libSDL3.0.dylib" "$FW/libSDL3.dylib"
cp -f "$HPREFIX/opt/molten-vk/lib/libMoltenVK.dylib" "$FW/libMoltenVK.dylib"

# Copy every Homebrew dylib reachable from the binary (glslang -> SPIRV-Tools
# is one hop). Two passes over the growing set are enough; the guard makes
# repeats free.
for _pass in 1 2 3; do
    copied=0
    for f in "$MACOS/nfsu2_recomp" "$FW"/*.dylib; do
        while IFS= read -r dep; do
            is_brew_dep "$dep" || continue
            base="$(basename "$dep")"
            [ -e "$FW/$base" ] && continue
            [ -f "$dep" ] || fail "missing dependency $dep"
            cp -f "$dep" "$FW/$base"
            copied=1
        done < <(deps "$f")
    done
    [ "$copied" = 1 ] || break
done

# Point every Homebrew dependency at @rpath (the copies in Frameworks) and
# give each image a runpath that finds them: the binary looks next to itself,
# the dylibs next to each other (@loader_path -- SPIRV-Tools-opt asks for
# @rpath/libSPIRV-Tools.dylib).
rewrite() {
    local f="$1" dep base
    while IFS= read -r dep; do
        is_brew_dep "$dep" || continue
        base="$(basename "$dep")"
        [ -e "$FW/$base" ] || continue
        install_name_tool -change "$dep" "@rpath/$base" "$f"
    done < <(deps "$f")
}
add_rpath() {
    otool -l "$1" | grep -q "path $2 " || install_name_tool -add_rpath "$2" "$1"
}
# CMake links with -L$HPREFIX/lib and records /opt/homebrew/lib as an rpath;
# it sorts before the bundle's own runpaths, so dyld would resolve @rpath
# against Homebrew first. Drop it (and any other absolute Homebrew runpath).
del_homebrew_rpaths() {
    local f="$1" p
    while IFS= read -r p; do
        install_name_tool -delete_rpath "$p" "$f"
    done < <(otool -l "$f" | grep -A2 LC_RPATH | awk '$1 == "path" {print $2}' |
             grep "^$HPREFIX\|^/usr/local" || true)
}
for f in "$MACOS/nfsu2_recomp" "$FW"/*.dylib; do
    rewrite "$f"
    del_homebrew_rpaths "$f"
    add_rpath "$f" "@loader_path"
done
add_rpath "$MACOS/nfsu2_recomp" "@executable_path/../Frameworks"

# MoltenVK ICD, self-contained: library_path is relative to this json.
cat > "$RES/vulkan/icd.d/MoltenVK_icd.json" <<'EOF'
{
    "file_format_version" : "1.0.0",
    "ICD": {
        "library_path": "../../../Frameworks/libMoltenVK.dylib",
        "api_version" : "1.4.0",
        "is_portability_driver" : true
    }
}
EOF

# Launcher: ICD env, disc lookup (env > bundled copy > game beside the .app
# > baked path), then a writable cwd for the caches and the kernel log.
# Keeps the terminal's stdout when there is one; Finder gets run.log.
sed "s|@BAKED_GAME@|${GAME//|/}|g" > "$MACOS/nfsu2" <<'EOF'
#!/bin/sh
# NFSU2.app launcher (platform/macos/make_app.sh)
DIR="$(cd "$(dirname "$0")" && pwd)"
VK_ICD="$DIR/../Resources/vulkan/icd.d/MoltenVK_icd.json"
VK_DRIVER_FILES="$VK_ICD" VK_ICD_FILENAMES="$VK_ICD" export VK_DRIVER_FILES VK_ICD_FILENAMES

if [ -z "${NFSU2_GAME_DIR:-}" ]; then
    for d in "$DIR/../Resources/game" "$DIR/game" "$DIR/../../../game" "@BAKED_GAME@"; do
        if [ -n "$d" ] && [ -f "$d/default.xbe" ]; then
            NFSU2_GAME_DIR="$d"
            break
        fi
    done
    export NFSU2_GAME_DIR
fi

STATE="$HOME/Library/Application Support/NFSU2"
mkdir -p "$STATE" 2>/dev/null || STATE="${TMPDIR:-/tmp}"
cd "$STATE" || exit 1
if [ ! -t 1 ]; then
    exec >>"$STATE/run.log" 2>&1
fi
exec "$DIR/nfsu2_recomp" "$@"
EOF
chmod +x "$MACOS/nfsu2"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>nfsu2</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>recomp.nfsu2</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>NFS Underground 2</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.5</string>
	<key>CFBundleVersion</key>
	<string>0.5</string>
	<key>LSMinimumSystemVersion</key>
	<string>11.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
EOF

# Icon: the 256px Switch icon, upscaled into a full iconset.
SRC_ICON="$REPO/assets/icon.jpg"
if [ -f "$SRC_ICON" ]; then
    SET="$RES/AppIcon.iconset"
    mkdir -p "$SET"
    for spec in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x \
                128:128x128 256:128x128@2x 256:256x256 512:256x256@2x \
                512:512x512 1024:512x512@2x; do
        px="${spec%%:*}"
        name="${spec#*:}"
        sips -s format png -z "$px" "$px" "$SRC_ICON" \
            --out "$SET/icon_$name.png" >/dev/null
    done
    iconutil -c icns "$SET" -o "$RES/AppIcon.icns"
    rm -rf "$SET"
fi

# Ad-hoc signature: arm64 refuses unsigned code, and install_name_tool broke
# whatever the linker and Homebrew had signed.
for f in "$FW"/*.dylib "$MACOS/nfsu2_recomp"; do
    codesign --force --sign - "$f" >/dev/null
done
codesign --force --sign - "$APP" >/dev/null

# Nothing may still point at Homebrew: load commands or runpaths.
left="$(for f in "$MACOS/nfsu2_recomp" "$FW"/*.dylib; do
            deps "$f"
            otool -l "$f" | grep -A2 LC_RPATH | awk '$1 == "path" {print $2}'
        done | grep "^$HPREFIX\|^/usr/local" || true)"
[ -z "$left" ] || fail "still linked to Homebrew:
$left"

echo
echo "built $APP"
if [ -f "$GAME_DST/default.xbe" ]; then
    echo "game:  bundled at Contents/Resources/game ($(du -sh "$GAME_DST" | awk '{print $1}'))"
elif [ -n "$GAME" ]; then
    echo "game:  $GAME"
else
    echo "game:  none in the bundle (put a game/ folder next to the .app or set NFSU2_GAME_DIR)"
fi
echo "run:   open \"$APP\""
