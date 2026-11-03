#!/usr/bin/env bash
# ============================================================================
#  sign-and-package.sh
#  ----------------------------------------------------------------------------
#  Sign the built app and package a .ipa.
#
#  Prerequisites (both interactive, cannot be scripted):
#    1. `xtool auth login`            — Apple ID + password / app-specific password
#    2. device registered to the team — done automatically by `xtool dev run`,
#                                       NOT by `xtool dev build --sign`
#
#  If you get:
#    "There are no current IOS devices on this team matching the provided device IDs"
#  run the full flow once to register the device:
#    xtool dev run --udid <UDID> --usb
#
#  Usage: bash sign-and-package.sh [native-dir] [triple]
# ============================================================================
set -uo pipefail

NATIVE="${1:-/root/ios-build}"
TRIPLE="${2:-arm64-apple-ios}"
SWIFT_HOME="${SWIFT_HOME:-/opt/swift641}"
export PATH="$SWIFT_HOME/usr/bin:$PATH"

cd "$NATIVE" || { echo "!! no such dir: $NATIVE" >&2; exit 1; }

echo "== 0. auth =="
xtool auth status 2>&1 | head -4
if ! xtool auth status 2>&1 | grep -q 'Logged in'; then
  echo "  ✗ not logged in. Open an INTERACTIVE console and run:"
  echo "      script -q -e -c 'xtool auth login --mode password' /root/login.log"
  echo "    (do NOT pipe it — without a real TTY the password field receives nothing)"
  exit 1
fi

echo "== 1. build + sign =="
xtool dev build --triple "$TRIPLE" --sign > /root/sign.log 2>&1
CODE=$?
echo "  exit $CODE"
grep -v libxml2 /root/sign.log | tr '\r' '\n' \
  | grep -vE '^\s*$|Downloading|Installing SDKs' | tail -12

if [ $CODE -ne 0 ]; then
  if grep -q 'no current IOS devices' /root/sign.log; then
    echo
    echo "  → device not registered. Run once:"
    echo "      xtool dev run --udid <UDID> --usb"
    echo "    (it registers the device and generates the profile)"
  fi
  exit $CODE
fi

echo "== 2. package .ipa =="
xtool dev build --triple "$TRIPLE" --sign --ipa > /root/ipa.log 2>&1
CODE=$?
echo "  exit $CODE"
grep -iE 'wrote|ipa|error' /root/ipa.log | tail -4

IPA=$(find "$NATIVE" -maxdepth 5 -name '*.ipa' 2>/dev/null | head -1)
if [ -n "$IPA" ]; then
  echo "  ✓ $IPA  ($(du -h "$IPA" | cut -f1))"
  mkdir -p "$(dirname "$NATIVE")/dist" 2>/dev/null || true
  echo
  echo "  install with:"
  echo "    export USBMUXD_SOCKET_ADDRESS=\$(ip route show default | awk '{print \$3}'):27016"
  echo "    ideviceinstaller -u <UDID> install $IPA"
else
  echo "  ✗ no .ipa produced — see /root/ipa.log"
  exit 1
fi
