#!/usr/bin/env bash
# ============================================================================
#  build-native.sh
#  ----------------------------------------------------------------------------
#  Build the iOS app on a NATIVE Linux path instead of /mnt/*.
#
#  WSL reaches Windows drives over 9P. A Swift build touches tens of thousands
#  of small files; on /mnt/e the build processes wedge in p9_client_rpc
#  (uninterruptible sleep) and produce no .o for 10+ minutes. The same build on
#  ext4 finishes in under a minute.
#
#  Edits stay on Windows; only the build happens natively.
#
#  Usage: bash build-native.sh [src-ios-dir]
#  Env:   NATIVE=/root/ios-build   TRIPLE=arm64-apple-ios
# ============================================================================
set -uo pipefail

SRC="${1:-/mnt/e/projects/YourApp/ios}"
NATIVE="${NATIVE:-/root/ios-build}"
TRIPLE="${TRIPLE:-arm64-apple-ios}"
SWIFT_HOME="${SWIFT_HOME:-/opt/swift641}"
export PATH="$SWIFT_HOME/usr/bin:$PATH"

[ -d "$SRC" ] || { echo "!! source dir not found: $SRC" >&2; exit 1; }

echo "== 0. stop stale builds =="
# Do NOT use `pkill -f "$SRC"` �?this script's own command line contains that
# path, so it would kill itself. Match on the tool instead.
pkill -f 'xtool dev build' 2>/dev/null
pkill -f 'swift-frontend -frontend' 2>/dev/null
sleep 2
echo "  remaining: $(pgrep -fc 'swift-frontend -frontend' 2>/dev/null || echo 0)"

echo "== 1. ensure trampoline is patched =="
BUNDLE="$HOME/.swiftpm/swift-sdks/darwin.artifactbundle"
if ! grep -q 'LLD 21.1.6' "$BUNDLE/toolset/bin/ld64.lld" 2>/dev/null; then
  echo "  patched version missing �?re-applying"
  bash "$(dirname "$0")/fix-ld-trampoline.sh"
fi
echo "  ok"

echo "== 2. sync sources to native path =="
mkdir -p "$NATIVE"
rsync -a --delete --exclude '.build' --exclude '.bsp' --exclude 'xtool/.xtool-tmp' \
  "$SRC/" "$NATIVE/" 2>/dev/null || cp -a "$SRC/." "$NATIVE/"
echo "  $NATIVE ($(du -sh "$NATIVE" 2>/dev/null | cut -f1))"

XCF=$(find "$NATIVE/shared/build/XCFrameworks" -maxdepth 3 -name '*.xcframework' 2>/dev/null | head -1)
[ -n "$XCF" ] || { echo "!! no XCFramework under $NATIVE/shared/build �?run build-xcframework.sh first" >&2; exit 1; }
echo "  framework: $(basename "$XCF")"

echo "== 3. build (incremental �?do NOT wipe .build) =="
# Wiping .build repeats the expensive -r merge and can re-trigger failures.
cd "$NATIVE"
if [ -d .build ] && [ -n "${REBUILD:-}" ]; then rm -rf .build .bsp; fi
START=$(date +%s)
xtool dev build --triple "$TRIPLE" "$@" > /root/xtool-build.log 2>&1
CODE=$?
echo "  exit $CODE, $(( $(date +%s) - START ))s"

if [ $CODE -ne 0 ]; then
  echo "  --- filtered output ---"
  sed -E 's/\x1b\[[0-9;]*m//g' /root/xtool-build.log | tr '\r' '\n' \
    | grep -vE 'Downloading |Installing SDKs|^\s*$' | tail -25
  exit $CODE
fi

grep -E 'Build complete|Wrote to' /root/xtool-build.log | tail -3

echo "== 4. artifact =="
APP=$(find "$NATIVE" -maxdepth 4 -name '*.app' 2>/dev/null | head -1)
if [ -n "$APP" ]; then
  echo "  $APP"
  file "$APP"/* 2>/dev/null | grep Mach-O
  mkdir -p "$SRC/dist" && rm -rf "$SRC/dist/$(basename "$APP")" && cp -a "$APP" "$SRC/dist/"
  echo "  copied to $SRC/dist/"
fi
