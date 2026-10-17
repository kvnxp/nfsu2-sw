#!/usr/bin/env bash
# Regenerate the lifted C from the XBE: disasm -> func_id -> abi -> recomp.
#
#   tools/regen.sh
#
# Environment:
#   XBOXRECOMP_DIR  toolkit            (default: the vendored xboxrecomp/)
#   NFSU2_XBE       default.xbe        (default: <repo>/game/default.xbe when
#                   a game/ directory exists, else /root/nfsu2x/game/default.xbe)
#   NFSU2_GEN_DIR   output directory   (default: <repo>/xboxrecomp/gen; the
#                   legacy default /root/nfsu2x/gen applies only when the XBE
#                   resolved to the legacy path)
#   LIFT_ONLY=1     skip disasm/func_id/abi (enough after editing
#                   recomp_manual.c; seeds need the full run)
#
# Seeds (config/seed_functions.json) are entry points the static pass cannot
# see -- thread start routines and indirect-call targets found at runtime.
# Grow them with:  python3 -m tools.seed_from_log run.log default.xbe \
#                    --functions tools/disasm/output/functions.json \
#                    --seeds <this repo>/config/seed_functions.json
# and review every addition: a seed inside a function splits it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TK="${XBOXRECOMP_DIR:-$HERE/xboxrecomp}"
LEGACY_XBE="/root/nfsu2x/game/default.xbe"
if [ -n "${NFSU2_XBE:-}" ]; then
    XBE="$NFSU2_XBE"
elif [ -f "$HERE/game/default.xbe" ]; then
    XBE="$HERE/game/default.xbe"
    echo "XBE: $XBE (from <repo>/game)"
else
    XBE="$LEGACY_XBE"
fi
if [ -n "${NFSU2_GEN_DIR:-}" ]; then
    GEN="$NFSU2_GEN_DIR"
elif [ "$XBE" = "$LEGACY_XBE" ]; then
    GEN="/root/nfsu2x/gen"
else
    GEN="$HERE/xboxrecomp/gen"
fi

cd "$TK"
if [ "${LIFT_ONLY:-0}" != "1" ]; then
    python3 -m tools.disasm "$XBE" --seed-functions "$HERE/config/seed_functions.json"
    python3 -m tools.func_id "$XBE"
    python3 -m tools.abi_analysis "$XBE"
fi
mkdir -p "$GEN"
# recomp_types.h is written only when absent, so a stale copy would hide
# register-model changes in the toolkit. Nothing here edits it by hand.
rm -f "$GEN/recomp_types.h"
python3 -m tools.recomp "$XBE" --game-name "NFS Underground 2" --all --split 250 \
    --gen-dir "$GEN" --exclude-manual "$HERE/src/recomp_manual.c" \
    --mmio-sections DSOUND,XPP
