#!/usr/bin/env bash
# ============================================================================
#  sdk-layout.sh
#  ----------------------------------------------------------------------------
#  Fix "platform already registered" without breaking the SDK.
#
#  The Darwin SDK bundle contains two complete Developer trees:
#      <bundle>/Developer/                     <- swift-sdk.json points here
#      <bundle>/Xcode.app/Contents/Developer/  <- raw Xcode payload (toolchains)
#  SwiftBuild sees every platform twice and refuses to initialise.
#
#  A symlink does NOT help (dedup is by resolved path string).
#  Hide the Platforms directory in the Xcode.app tree, keeping its Toolchains.
#
#  ⚠ Run this ONLY when `xtool sdk status` reports the SDK as current.
#    If the SDK is considered stale, xtool reinstalls it, which restores the
#    Platforms directory AND overwrites your patched ld64.lld trampoline.
#
#  Usage: bash sdk-layout.sh [--revert]
# ============================================================================
set -uo pipefail

BUNDLE="${BUNDLE:-$HOME/.swiftpm/swift-sdks/darwin.artifactbundle}"
XD="$BUNDLE/Xcode.app/Contents/Developer"
SWIFT_HOME="${SWIFT_HOME:-/opt/swift641}"
export PATH="$SWIFT_HOME/usr/bin:$PATH"

revert() {
  if [ -d "$XD/Platforms.hidden" ] && [ ! -d "$XD/Platforms" ]; then
    mv "$XD/Platforms.hidden" "$XD/Platforms"
    echo "  ✓ Platforms restored (needed for xtool sdk update)"
  else
    echo "  nothing to revert"
  fi
  exit 0
}
[ "${1:-}" = "--revert" ] && revert

echo "== 0. SDK must be current =="
STATUS=$(xtool sdk status 2>&1 | head -6)
echo "$STATUS" | sed 's/^/  /'
if echo "$STATUS" | grep -qi 'not installed'; then
  echo "  ✗ SDK not installed. Run: xtool sdk install <Xcode.xip>" >&2; exit 1
fi

echo "== 1. inventory =="
echo -n "  Developer/Platforms:           "; ls "$BUNDLE/Developer/Platforms" 2>/dev/null | tr '\n' ' '; echo
echo -n "  Xcode.app/.../Platforms:       "; ls "$XD/Platforms" 2>/dev/null | tr '\n' ' '; echo
echo -n "  Xcode.app/.../Toolchains:      "; ls "$XD/Toolchains" 2>/dev/null | tr '\n' ' '; echo

echo "== 2. which tree holds the compiler =="
HAVE_DEV=0; HAVE_XC=0
for p in "$BUNDLE/Developer/Toolchains/XcodeDefault.xctoolchain" \
         "$XD/Toolchains/XcodeDefault.xctoolchain"; do
  if [ -e "$p/usr/bin/swift-frontend" ]; then
    echo "  compiler: $p"; [ "${p%%Xcode.app*}" = "$BUNDLE/" ] && HAVE_DEV=1 || HAVE_XC=1
  fi
done
if [ "$HAVE_XC" -eq 0 ] && [ "$HAVE_DEV" -eq 1 ]; then
  echo "  the top-level Developer tree is self-sufficient; nothing to hide"
else
  echo "  keeping Xcode.app toolchains, hiding its duplicate Platforms"
fi

echo "== 3. hide duplicate Platforms =="
if [ -d "$XD/Platforms" ] && [ ! -d "$XD/Platforms.hidden" ]; then
  mv "$XD/Platforms" "$XD/Platforms.hidden"
  echo "  ✓ moved to Platforms.hidden"
else
  echo "  already hidden / absent"
fi

echo "== 4. re-check SDK freshness (must NOT say out of date) =="
xtool sdk status 2>&1 | head -4 | sed 's/^/  /'

echo "== 5. trampoline still patched? =="
N=$(grep -c 'LLD 21.1.6' "$BUNDLE/toolset/bin/ld64.lld" 2>/dev/null || echo 0)
echo "  marker count: $N"
if [ "$N" -lt 1 ]; then
  echo "  re-applying trampoline"
  bash "$(dirname "$0")/fix-ld-trampoline.sh"
fi

echo
echo "To undo: bash $(basename "$0") --revert"
