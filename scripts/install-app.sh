#!/usr/bin/env bash
# ============================================================================
#  install-app.sh   (runs in WSL)
#  ----------------------------------------------------------------------------
#  Install a signed .ipa onto the phone through Apple's driver relay.
#
#  This deliberately does NOT use USB/IP: usbmuxd over USB/IP cannot open the
#  AFC service, so any file copy dies:
#      afcclient ls /     -> Mux error (-8)
#      ideviceinstaller   -> AFC Write error: 30
#  (Note: listing the root also fails, so it is not a "large file" issue.)
#
#  Prereqs, on Windows:
#      winget install --id Apple.AppleMobileDeviceSupport
#      powershell -File relay-setup.ps1      # bridges 0.0.0.0:27016 -> 127.0.0.1:27015
#      powershell -File relay-handoff.ps1    # usbipd unbind + restart Apple service
#
#  Usage: bash install-app.sh <path-to.ipa> [udid] [port]
# ============================================================================
set -uo pipefail

IPA="${1:-}"
UDID="${2:-}"
PORT="${3:-27016}"

[ -n "$IPA" ] && [ -f "$IPA" ] || { echo "usage: $0 <file.ipa> [udid] [port]" >&2; exit 1; }

HOSTIP=$(ip route show default | awk '{print $3}' | head -1)
export USBMUXD_SOCKET_ADDRESS="${HOSTIP}:${PORT}"
echo "== relay: $USBMUXD_SOCKET_ADDRESS =="

echo "== 1. TCP reachability =="
if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$HOSTIP/$PORT" 2>/dev/null; then
  echo "  ✓ port open"
else
  echo "  ✗ cannot reach $HOSTIP:$PORT" >&2
  echo "    on Windows: powershell -File relay-setup.ps1" >&2
  exit 1
fi

echo "== 2. device visible? =="
for i in $(seq 1 12); do
  if idevice_id -l 2>/dev/null | grep -q .; then break; fi
  sleep 2
done
IDS=$(idevice_id -l 2>/dev/null)
if [ -z "$IDS" ]; then
  echo "  ✗ no device. Most likely the iPhone still holds a pending trust dialog." >&2
  echo "    Unlock the phone and tap \"Trust This Computer\", then retry." >&2
  echo "    If no dialog appears: on Windows run relay-handoff.ps1 (usbipd unbind)." >&2
  exit 1
fi
echo "  ✓ $(echo "$IDS" | tr '\n' ' ')"
[ -z "$UDID" ] && UDID=$(echo "$IDS" | head -1)

echo "== 3. pairing =="
idevicepair validate 2>&1 | sed 's/^/  /'
if ! idevicepair validate 2>&1 | grep -q SUCCESS; then
  echo "  attempting pair..."
  idevicepair pair 2>&1 | sed 's/^/  /'
fi

echo "== 4. install (keep the phone unlocked) =="
ideviceinstaller -u "$UDID" install "$IPA" 2>&1 | tail -16

echo "== 5. verify =="
ideviceinstaller -u "$UDID" list 2>&1 | grep -iE 'XTL-|com\.' | head -5 || echo "  (not listed)"

echo
echo "If the app installs but will not open:"
echo "  Settings > General > VPN & Device Management > <your Apple ID> > Trust"
echo "  iOS 16+: Settings > Privacy & Security > Developer Mode (then reboot)"
