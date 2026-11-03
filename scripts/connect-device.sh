#!/usr/bin/env bash
# ============================================================================
#  connect-device.sh   (WSL side, USB/IP path)
#  ----------------------------------------------------------------------------
#  Prepare the USB/IP path AND report whether it is usable.
#
#  ⚠ READ FIRST
#  USB/IP lets you query the device and build, but it CANNOT install apps:
#  usbmuxd cannot open the AFC service, so every file copy fails
#  ("Mux error (-8)" / "AFC Write error: 30"). For installing, use the Apple
#  driver relay instead: scripts/relay-setup.ps1 + relay-handoff.ps1 in Windows,
#  then scripts/install-app.sh.
#
#  This script is still useful for:
#    - ideviceinfo (reading device properties)
#    - confirming the device is paired before switching to the relay
#
#  Order matters: load vhci -> wait for the device -> then start usbmuxd.
#  Starting usbmuxd first yields "0 devices detected".
# ============================================================================
set -uo pipefail

echo "== 1. vhci-hcd =="
lsmod | grep -q vhci_hcd || sudo modprobe vhci-hcd
lsmod | grep -E 'vhci_hcd|usbip_core' | sed 's/^/  /'

echo "== 2. wait for the Apple USB device =="
found=0
for i in $(seq 1 20); do
  for d in /sys/bus/usb/devices/*/; do
    [ -f "$d/idVendor" ] || continue
    if [ "$(cat "$d/idVendor" 2>/dev/null)" = "05ac" ]; then
      echo "  ✓ Apple device: 05ac:$(cat "$d/idProduct" 2>/dev/null) $(cat "$d/product" 2>/dev/null)"
      found=1; break 2
    fi
  done
  sleep 1
done
if [ "$found" -eq 0 ]; then
  echo "  ✗ no Apple device in the kernel" >&2
  echo "    on Windows: usbipd bind --busid <N> ; usbipd attach --wsl --busid <N>" >&2
  echo "    a resident WSL session must be running for attach to work" >&2
  exit 1
fi

echo "== 3. usbmuxd (systemd, so it survives this script) =="
# Starting it with `&` means SIGHUP kills it when this script exits, and the
# very next command reports "Unable to retrieve device list!".
if systemctl list-unit-files 2>/dev/null | grep -q '^usbmuxd.service'; then
  sudo systemctl restart usbmuxd
  echo "  systemd: $(systemctl is-active usbmuxd)"
else
  sudo pkill -x usbmuxd 2>/dev/null; sleep 1
  sudo setsid /usr/sbin/usbmuxd -f </dev/null >/tmp/usbmuxd.log 2>&1 &
  echo "  started with setsid (detached)"
fi
sleep 3

echo "== 4. device =="
for i in $(seq 1 10); do
  idevice_id -l 2>/dev/null | grep -q . && break
  sleep 2
done
UDID=$(idevice_id -l 2>/dev/null | head -1)
if [ -z "$UDID" ]; then
  echo "  ✗ no device. A pending trust dialog blocks enumeration." >&2
  echo "    Unlock the iPhone and tap \"Trust This Computer\"." >&2
  exit 1
fi
echo "  ✓ $UDID"

echo "== 5. pairing =="
idevicepair validate 2>&1 | sed 's/^/  /'

echo "== 6. device info =="
ideviceinfo 2>&1 | grep -E 'DeviceName|ProductVersion|ProductType' | sed 's/^/  /'

echo
echo "NOTE: USB/IP cannot install apps (AFC unsupported)."
echo "      For installing use the relay: scripts/relay-setup.ps1 + relay-handoff.ps1."
