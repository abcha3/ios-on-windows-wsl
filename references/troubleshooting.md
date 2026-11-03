# Troubleshooting index

Start here. Find your error text, follow the pointer.

---

## Build system won't initialise

| Error text | Cause | Go to |
|---|---|---|
| `platform 'com.apple.platform.X' already registered from ...` | two Developer trees in the SDK bundle | `sdk-layout.md` |
| `Could not initialize build system` | same as above | `sdk-layout.md` |
| `failed to load toolchains in .../Xcode.app/.../Toolchains: does not exist` | you moved/removed `Xcode.app` | `sdk-layout.md` |

---

## SDK lifecycle

| Error text | Cause | Go to |
|---|---|---|
| `Darwin SDK is out of date. Rebuilding...` | version check timed out (network) **or** layout changed | `network.md` first, then `sdk-layout.md` |
| `Error: HTTPClientError.deadlineExceeded` | `github.com` unreachable | `network.md` |
| `StreamClosed(... HTTP2ErrorCode<0x8 Cancel>)` | download aborted | `network.md` |
| `[Downloading OpenAppleMacros] 4%` forever | slow link, 69 MB single file | `toolchain.md` |
| `No Swift SDK found matching query 'darwin'` | versioned triple used | `toolchain.md` |

---

## Swift compilation

| Error text | Cause | Go to |
|---|---|---|
| `unable to load standard library for target 'arm64-apple-ios12.0'` | Swift < 6.4.1 (interfaces unparseable) | `toolchain.md` |
| `cannot suppress '~Copyable' on generic parameter` | Swift 6.3 | `toolchain.md` |
| `consecutive statements on a line must be separated by ';'` at `Swift::Comparable` | Swift 6.2 | `toolchain.md` |
| `arm_neon.h: incompatible constant for this __builtin_neon function` | wrong clang headers | `toolchain.md` |
| `invalid conversion between vector type 'bfloat16x8_t'` | same | `toolchain.md` |
| `error while loading shared libraries: libncurses.so.6` | missing runtime dep | `toolchain.md` |
| `libxml2.so.2: no version information available` | harmless warning; filter it | `toolchain.md` |

---

## Linking

| Error text | Cause | Go to |
|---|---|---|
| `Option '-r' is not yet implemented` | ld64.lld limitation | `ld-trampoline.md` |
| `undefined symbol: swift_retain` / `swift_release` | `-r` fell through to a real link | `ld-trampoline.md` |
| `ld64.lld trampoline could not process arguments` | original xtool trampoline rejects SWPM's arg shape | `ld-trampoline.md` |
| `error: '.../Walk.o': No such file or directory` | LinkFileList contains the output itself | `ld-trampoline.md` |
| `unable to open dependencies file (...dependency_info.dat)` | depfile not produced | `ld-trampoline.md` |
| `error reading dependency file ...: missing null terminator` | depfile needs trailing NUL | `ld-trampoline.md` |
| `... missing version record` | depfile must start with a version record | `ld-trampoline.md` |
| `... unknown opcode 0x76` | used text `version 1` (`'v'`=0x76) | `ld-trampoline.md` |
| `... unknown opcode 0xA` | treated `0x10` opcode as a length | `ld-trampoline.md` |
| `... empty operand` | empty field in a record | `ld-trampoline.md` |
| `must specify -platform_version` | relocatable link needs it | `ld-trampoline.md` |
| `error: 'arm64': No such file or directory` | `-arch_only` value parsed as input | `ld-trampoline.md` |
| `error: -static option: must be specified` | `llvm-libtool-darwin` requires it | `ld-trampoline.md` |

---

## Kotlin / Native

| Error text | Cause | Go to |
|---|---|---|
| `Target ios_arm64 is not available for output kind 'FRAMEWORK' on the linux_x64 host` | host check | `kmp-framework.md` |
| `'expect' and 'actual' declarations can be used only in multiplatform projects` | missing flatten | `kmp-framework.md` |
| `expect and corresponding actual are declared in the same module` | `-Xmulti-platform` misused | `kmp-framework.md` |
| `actual has no corresponding 'expect' declaration` | common sources not compiled | `kmp-framework.md` |
| `Error parsing file .../compiler_interface.bc` | iOS bitcode missing on Linux | `kmp-framework.md` |
| `DISubprogramRef DICreateFunctionShared ... Assertion 'false' failed` | `assert(false)` in DebugInfoC.cpp | `kmp-framework.md` |
| `source file or directory not found: OS` | `-Dos.name="Mac OS X"` split by shell | `kmp-framework.md` |
| framework header < 200 lines, own types absent | klib passed as dependency | `kmp-framework.md` |
| `Both 'ios-arm64-simulator' and 'ios-x86_64-simulator' represent two equivalent library definitions` | duplicate simulator slices / stale cache | `kmp-framework.md` |

---

## XCFramework / SwiftPM

| Error text | Cause | Go to |
|---|---|---|
| `Failed to load XCFramework ... equivalent library definitions` | two slices for one platform+variant | `kmp-framework.md` |
| `No library products were found in the package` | product declared `.static`/`.executable` | see note below |
| `cannot convert 'KotlinDouble' to 'Double'` | boxing at the KMP boundary | `kmp-framework.md` |
| `'init()' is unavailable` | Kotlin default args → no zero-arg init | `kmp-framework.md` |
| `expected 'sessionId_:'` | trailing-underscore disambiguation | `kmp-framework.md` |
| `reference to member 'SAFE' cannot be resolved` | Kotlin enum exports as class | `kmp-framework.md` |
| `expected ',' separator` in a Text literal | full-width Chinese quotes | `kmp-framework.md` |

> **`.library` type**: `xtool dev build` requires a plain library product. Declaring
> `type: .static` or `.executable` yields `No library products were found`. Keep it as
> `.library(name:targets:)` with no type.

---

## Performance

| Symptom | Cause | Go to |
|---|---|---|
| build hangs, `ps` shows `D` in `p9_client_rpc` | compiling on `/mnt/*` | `build-native.md` |
| `.build` tiny, zero `.o` after 10 min | same | `build-native.md` |
| `cp` of the `.xip` takes hours | 9P streamed read | `toolchain.md` |
| script dies instantly with no output | `pkill -f` matched itself | `build-native.md` |

---

## Device / install

| Error text | Cause | Go to |
|---|---|---|
| `Could not connect to lockdownd: Mux error (-8)` | on USB/IP; AFC unsupported | `relay-install.md` |
| `AFC Write error: 30` | same | `relay-install.md` |
| `wrote only 0 of 1048576` | same | `relay-install.md` |
| relay port open but `idevice_id -l` empty | device still owned by usbipd | `relay-install.md` |
| `Waiting for service ... to start` forever | portproxy squatting 27015 | `relay-install.md` |
| `Please accept the trust dialog ...` | trust prompt unanswered | `relay-install.md` |
| `Pairing dialog response pending` | same | `relay-install.md` |
| `Unable to retrieve device list!` | `usbmuxd` not running (or killed by SIGHUP) | note below |
| `There are no current IOS devices on this team matching the provided device IDs` | device not registered to the team | note below |
| `requires logging in with 'xtool auth'` | not authenticated | note below |
| `Enter the correct password for this Apple Account. (-22406)` | wrong password / needs app-specific password | note below |
| `Could not start com.apple.debugserver` | no developer disk image | harmless for running, only blocks debugging |
| `LockdownClient.Error.muxError` | USB/IP instability | `relay-install.md` |

### `usbmuxd` killed right after a script exits

Starting it as `usbmuxd -f &` inside a script means **SIGHUP on script exit** kills it, so
the very next command reports `Unable to retrieve device list!`.

Use systemd, or detach it:

```bash
sudo systemctl restart usbmuxd              # preferred
sudo setsid /usr/sbin/usbmuxd -f </dev/null >/tmp/usbmuxd.log 2>&1 &   # fallback
```

### Device not registered to the team

Free accounts must register the device before a provisioning profile can be generated.
Run the **full** flow rather than `build --sign` alone:

```bash
xtool dev run --udid <UDID> --usb
```

`dev run` performs device registration (`Preparing device` → `Provisioning`) automatically.
`dev build --sign` does not, and fails with the 409 above.

### Apple ID login is interactive

`xtool auth login` prompts for the Apple ID and password and **cannot be scripted safely**.
Open a real console and have the user type it. Two gotchas:

1. **Do not pipe it** (`| tee`). Without a real TTY the password field receives no input —
   the symptom is "Apple ID types fine, password won't accept anything". Use `script` to
   allocate a pty *and* keep a log:
   ```bash
   script -q -e -c 'xtool auth login --mode password' /root/login.log
   ```
2. `-22406` usually means either a typo (password is invisible) or that the account needs
   an **app-specific password** (from appleid.apple.com → Sign-In and Security).

`xtool auth status` must show `Logged in` with a Team ID before signing.

---

## Order of operations when starting from scratch

Because several gates interact, follow this order — each step assumes the previous held:

```
1. network            github.com reachable            network.md
2. toolchain          swift 6.4.1 works               toolchain.md
3. sdk current        xtool sdk status = installed    toolchain.md
4. sdk layout         duplicates hidden (only now)    sdk-layout.md
5. trampoline         patched, -r substituted         ld-trampoline.md
6. native build dir   copy off /mnt/*                 build-native.md
7. kmp framework      header has your types           kmp-framework.md
8. app build+sign     Build complete + .ipa           SKILL.md
9. relay install      Apple driver, port 27016        relay-install.md
```

Skipping ahead (e.g. hiding platforms before the SDK is current) is what produces the
"out of date → rebuild → trampoline reverted" death spiral.
