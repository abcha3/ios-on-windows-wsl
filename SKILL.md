---
name: ios-on-windows-wsl
description: Build, sign, and install iOS apps on Windows via WSL without a Mac. Covers Kotlin Multiplatform frameworks (XCFramework), Swift 6.4 toolchain, xtool, and getting a real .ipa onto a physical iPhone over USB. Use when the user wants to build or install an iOS app on a Windows machine, asks about "iOS on Windows", "no Mac", "WSL iOS", "install to iPhone from Windows", or hits errors like "Mux error -8", "AFC Write error: 30", "platform already registered", "Darwin SDK is out of date", "-r is not yet implemented", or "libxml2 no version information".
---

# iOS on Windows via WSL (no Mac)

Build → sign → install a real iOS app on a physical iPhone, entirely on Windows.

**Verified end-to-end**: Kotlin Multiplatform + SwiftUI app compiled, signed with a free
Apple ID, and installed onto an iPhone 12 (iOS 27.0.1).

---

## When to use this skill

Use it when the user:
- wants to build/run an iOS app but has **no Mac**
- has a **Kotlin Multiplatform** or **SwiftPM** project targeting iOS
- needs to **install to a physical iPhone** from Windows
- hits any error in the message list of this skill's `description`

Do **not** use it for: Android builds, simulator-only work on macOS, App Store submission.

---

## The one decision that matters most

> **USB/IP (`usbipd`) cannot install apps. Use Apple's own driver instead.**

This is the single most expensive lesson in this skill. `usbipd` + WSL works fine for
`ideviceinfo` (it only uses lockdownd), which makes you think everything is fine. But
the moment anything opens a **new service channel** (AFC — used to copy files/apps),
it dies:

```
afcclient ls /        → Could not connect to lockdownd: Mux error (-8)
ideviceinstaller ...  → Copying to device... AFC Write error: 30   (AFC_E_MUX_ERROR)
```

Note `ls /` fails too — so it is **not** a "big file" problem. Signing and packaging
succeed; only the transfer dies.

**So: build via WSL, but install via Apple Mobile Device Service (TCP 27015).**
Details in `references/relay-install.md`.

---

## Pipeline overview

```
Kotlin (KMP)          Gradle compile klib ──► konanc link ──► Shared.xcframework
                                                                    │
Swift sources ──► swift build / xtool dev build ────────────────────┘
                              │
                        Walk.app (Mach-O arm64)
                              │
                    sign with Apple ID ──► Walk.ipa
                              │
            Apple Mobile Device Service (TCP relay)
                              │
                        iPhone (physical) ✔
```

Two independent tracks. **Build** happens in WSL. **Install** happens through Windows.

---

## Quick start

```bash
# ---------- one-time environment (WSL) ----------
bash scripts/setup-linux-ios-toolchain.sh   # Swift 6.4.1 SDK, konan, ld trampoline
bash scripts/fix-github-hosts.sh            # github.com is often blocked in CN
bash scripts/fix-ld64-trampoline.sh         # ld64.lld has no -r

# ---------- build the KMP framework ----------
bash scripts/build-xcframework.sh

# ---------- build + sign + package IPA ----------
bash scripts/build-native.sh                # copy to /root, build there (9P is too slow)
bash scripts/sign-ipa.sh                    # -> Walk.ipa
```

```powershell
# ---------- install (Windows side) ----------
powershell -File scripts\relay-fix.ps1          # bridge TCP 27016 -> 127.0.0.1:27015
powershell -File scripts\relay-wait-trust.ps1   # hand device back; tap Trust on iPhone
```

```bash
bash scripts/install-relay-27016.sh         # installs the IPA
```

Apple ID login is **interactive** — the agent cannot type the password.
Open a console window running `scripts/login-apple.cmd` and ask the user to fill it in.

---

## The eight hard gates

Each one has bitten us. Read the detail page before improvising.

| # | Gate | Symptom if wrong | Detail |
|---|---|---|---|
| 1 | **Swift must be ≥ 6.4.1** | `unable to load standard library for target 'arm64-apple-ios12.0'`, or `Swift::Comparable` parse errors | `references/toolchain.md` |
| 2 | **KMP expect/actual must be flattened** | `expect and corresponding actual are declared in the same module`, or `actual has no corresponding expect` | `references/kmp-framework.md` |
| 3 | **Headers must come from source compile** | framework header only ~145 lines, your own types missing | `references/kmp-framework.md` |
| 4 | **ld64.lld has no `-r`** | `Option '-r' is not yet implemented` | `references/ld-trampoline.md` |
| 5 | **Duplicate platform registration** | `platform 'com.apple.platform.iphoneos' already registered` | `references/sdk-layout.md` |
| 6 | **`/mnt/*` (9P) is too slow to compile** | processes stuck in `p9_client_rpc`, no `.o` after 10+ min | `references/build-native.md` |
| 7 | **`github.com` blocked → SDK "out of date"** | `HTTPClientError.deadlineExceeded` then `Darwin SDK is out of date. Rebuilding...` | `references/network.md` |
| 8 | **USB/IP can't do AFC** | `Mux error (-8)` / `AFC Write error: 30` | `references/relay-install.md` |

---

## Non-negotiable rules

1. **Never `rm -rf .build` before an incremental retry.** The `-r` merge step is
   expensive and only succeeds once the depfile exists. Clearing it restarts the
   whole failure cycle.
2. **Never modify the SDK bundle's directory layout while `xtool` thinks the SDK
   is stale.** `xtool sdk status` must say `installed` and *not* prompt a rebuild —
   otherwise it re-downloads and **overwrites your patched `ld64.lld` trampoline**.
3. **Re-apply `fix-ld64-trampoline.sh` after any SDK rebuild.** Check with:
   `grep -c 'LLD 21.1.6' ~/.swiftpm/swift-sdks/darwin.artifactbundle/toolset/bin/ld64.lld`
   (should be ≥ 1).
4. **`portproxy` must NOT listen on 27015.** It collides with Apple's own binding and
   makes the service fail to start (endless *Waiting for service…*). Bridge on **27016**.
5. **`usbipd unbind`, not just `detach`.** Only after unbind does Windows fully own the
   device, and only then does Apple's service enumerate it.
6. **Keep the iPhone unlocked** during install. A locked device aborts AFC mid-copy.
7. **Free Apple ID = 7-day certificate.** Say this to the user; offer the paid-account
   alternative if they want 90 days.

---

## Verification checklist

Run these after a successful install:

```bash
# device present?
idevice_id -l                                  # expect the UDID

# app installed?
ideviceinstaller -u <UDID> list | grep -i <app>
```

Expect something like:

```
XTL-<TEAMID>.<bundle.id>, "0.1.0", "<App display name>"
```

The `XTL-` prefix is normal — xtool prefixes the bundle id for free-account signing.

---

## What this skill does NOT cover

- **App Store submission** (needs Apple Developer Program + a Mac for some steps)
- **iOS Simulator** (requires macOS)
- **Background-execution validation** — e.g. "does GPS recording survive 8h locked" —
  that can only be verified by physically walking with the phone. Do not claim it works
  because the build succeeded.

---

## File map

```
SKILL.md                          this file
references/toolchain.md           Swift 6.4.1 install, why 6.2/6.3 fail
references/kmp-framework.md       XCFramework from Kotlin: flatten, compile, assemble
references/ld-trampoline.md       replacing `-r`, dependency_info binary format
references/sdk-layout.md          duplicate platforms, when it's safe to hide them
references/build-native.md        9P slowness, build on ext4
references/network.md             github.com blocking, SDK version check
references/relay-install.md       ★ Apple driver relay instead of USB/IP
references/troubleshooting.md     error string → cause → fix (start here when stuck)
scripts/                          runnable, generalized versions of every step
```

When something fails, **start with `references/troubleshooting.md`** — it maps raw
error text to the gate above.
