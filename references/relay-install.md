# Installing the relay (Apple driver instead of USB/IP)

The single most important page in this skill.

---

## Why USB/IP fails

`usbipd` can forward the iPhone's USB device into WSL. Basic queries work:

```bash
ideviceinfo            # ✔ works — only uses lockdownd
idevice_id -l          # ✔ works
```

But anything that opens a **new lockdown service channel** fails:

```bash
afcclient ls /             # ✘ Could not connect to lockdownd: Mux error (-8)
ideviceinstaller install   # ✘ AFC Write error: 30  (AFC_E_MUX_ERROR)
```

**Critical diagnostic**: `ls /` also fails. So the cause is *not* "the IPA is too big"
and *not* "slow transfer". `usbmuxd` on top of USB/IP cannot spawn the AFC service at
all. Signing and packaging are fine; only the copy step dies.

`usbmuxd` multiplexes several logical channels over one USB pipe; USB/IP's
virtual-host-controller emulation does not survive that for long-lived streams.

### Conclusion

> **Do not try to install over USB/IP. It is not a tuning problem.**

Use build-over-WSL + install-over-Apple-driver.

---

## Prerequisite on Windows

```powershell
winget install --id Apple.AppleMobileDeviceSupport
```

That installs `Apple Mobile Device Service`, which listens on **`127.0.0.1:27015`**
speaking the usbmuxd protocol — Apple's own driver, no USB/IP involved.

> The Microsoft Store "Apple Devices" app does **not** expose TCP 27015. You need
> `Apple Mobile Device Support` (the classic component; can be installed standalone).

Verify:

```powershell
Get-Service | Where-Object { $_.DisplayName -like '*Apple Mobile*' }
Get-NetTCPConnection -LocalPort 27015 -State Listen
# expect: 127.0.0.1:27015  owning process AppleMobileDeviceService
```

---

## Step 1 — bridge the port (use 27016, NOT 27015)

```powershell
# WRONG — collides with Apple's own 127.0.0.1:27015 binding
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=27015 connectaddress=127.0.0.1 connectport=27015

# RIGHT — bridge on a different port
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=27016 connectaddress=127.0.0.1 connectport=27015

New-NetFirewallRule -DisplayName "iOS relay 27016" -Direction Inbound `
  -Protocol TCP -LocalPort 27016 -Action Allow -Profile Any
```

**Why 27016 matters**: if `portproxy` binds `0.0.0.0:27015`, Windows will not let
Apple's service bind `127.0.0.1:27015`, and the service start hangs with:

```
WARNING: Waiting for service 'Apple Mobile Device Service' to start...
```

repeating until it times out.

---

## Step 2 — hand the device back to Windows

```powershell
usbipd detach --busid <N>     # stop the USB/IP session
usbipd unbind --busid <N>     # release it from usbipd entirely
Restart-Service 'Apple Mobile Device Service'
```

**`unbind` is required.** `detach` alone leaves the device in usbipd's shared set and
Apple's service never enumerates it — you'll see the relay TCP port open but
`idevice_id -l` returns nothing.

Expected end state:

```
2-2  05ac:12a8  Apple Mobile Device USB Composite Device   Not shared
```

---

## Step 3 — point WSL clients at the relay

```bash
HOSTIP=$(ip route show default | awk '{print $3}' | head -1)
export USBMUXD_SOCKET_ADDRESS="$HOSTIP:27016"
```

`libimobiledevice` honours this env var instead of looking for a local `usbmuxd`.

Verify connectivity at the TCP layer first:

```bash
timeout 5 bash -c "cat < /dev/null > /dev/tcp/$HOSTIP/27016" && echo OPEN
```

Then:

```bash
export USBMUXD_SOCKET_ADDRESS="$HOSTIP:27016"
idevice_id -l          # should print the UDID
ideviceinfo | grep ProductVersion
```

---

## Step 4 — install

```bash
export USBMUXD_SOCKET_ADDRESS="$HOSTIP:27016"
ideviceinstaller -u <UDID> install Walk.ipa
```

Successful run looks like:

```
Copying 'Walk.ipa' to device... DONE.
Installing 'XTL-<TEAMID>.<bundle>'
Install: CreatingStagingDirectory (5%)
...
Install: InstallComplete (100%)
Install: Complete
```

Verify:

```bash
ideviceinstaller -u <UDID> list | grep -i <app>
# XTL-<TEAMID>.<bundle>, "0.1.0", "<App name>"
```

---

## Trust prompt

The first time you use this path, iOS shows **"Trust This Computer?"** on the phone.

- The user must tap **Trust** and enter the passcode.
- If you changed transport (USB/IP → relay), iOS treats it as a **new computer** and
  asks again — even if trust was granted before under USB/IP.
- Symptoms of a pending trust dialog:
  ```
  ERROR: Please accept the trust dialog on the screen of device <UDID>, then attempt to pair again.
  Could not connect to lockdownd: Pairing dialog response pending.
  ```

Poll until the device appears rather than failing immediately — the user needs time to
look at the phone:

```bash
for i in $(seq 1 30); do
  idevice_id -l | grep -q "$UDID" && break
  sleep 5
done
```

---

## After install: developer certificate trust

The app installs but will not launch until the certificate is trusted on-device:

**Settings → General → VPN & Device Management → (Developer App) → Trust**

On iOS 16+ also enable **Settings → Privacy & Security → Developer Mode**, then reboot.

---

## Failure → fix

| Symptom | Cause | Fix |
|---|---|---|
| `Mux error (-8)` | still on USB/IP | switch to relay |
| `AFC Write error: 30` | still on USB/IP | switch to relay |
| relay port open but `idevice_id` empty | device still owned by usbipd | `usbipd unbind`, restart Apple service |
| `Waiting for service…` forever | portproxy squatting 27015 | delete it, bridge on 27016 |
| `Pairing dialog response pending` | trust dialog not answered | ask user to tap Trust |
| install works, app won't open | certificate untrusted | Settings → VPN & Device Management |
| `Could not start com.apple.debugserver` | no developer disk image | only affects **debugging**, app still runs |
