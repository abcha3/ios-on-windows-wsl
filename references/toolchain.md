# Toolchain: Swift 6.4.1 + Darwin SDK

---

## Why Swift must be ≥ 6.4.1

Xcode 27.x ships `Swift.swiftinterface` files using syntax introduced in **Swift 6.4**:

| Version | Result |
|---|---|
| 6.2 | `error: consecutive statements on a line must be separated by ';'` at `Swift::Comparable` |
| 6.3 | parses `Swift::` but fails `Self.Element : ~Copyable` → `cannot suppress '~Copyable' on generic parameter` |
| **6.4.1** | ✔ works |

### The misleading symptom

```
error: unable to load standard library for target 'arm64-apple-ios12.0'
```

This makes it look like the SDK is incomplete. It is not. Inspecting:

```bash
ls .../iPhoneOS.sdk/usr/lib/swift/Swift.swiftmodule/
# arm64e-apple-ios.swiftinterface
# arm64e.x1-apple-ios.swiftinterface
```

Only `arm64e` interfaces appear — there is no `arm64` one. **That is normal for this SDK.**
The real failure is the compiler being too old to parse those interfaces.

Do not go hunting for a "missing arm64 SDK" — upgrade the compiler.

---

## Installing Swift 6.4.1 on Ubuntu 26.04

```bash
curl -L -o /tmp/swift.tar.gz \
  https://download.swift.org/swift-6.4.1-release/ubuntu2604/swift-6.4.1-RELEASE/swift-6.4.1-RELEASE-ubuntu26.04.tar.gz

sudo mkdir -p /opt/swift641 && sudo tar zxf /tmp/swift.tar.gz -C /opt/swift641 --strip-components=1
export PATH=/opt/swift641/usr/bin:$PATH
swift --version     # Swift version 6.4.1
```

**URL pitfall**: the path segment is `swift-6.4.1-release` — not `swift-6.4-release`
(404). Verify the exact tag from the official index rather than guessing:

```bash
curl -s https://www.swift.org/api/v1/install/releases.json | \
  python3 -c "import json,sys; [print(r['name'], r.get('tag')) for r in json.load(sys.stdin) if r['name'].startswith('6.4')]"
# 6.4.1 swift-6.4.1-RELEASE
```

### Runtime dependencies (Ubuntu 26.04)

```bash
sudo apt-get install -y binutils-gold unzip zip gnupg2 libc6-dev \
  libcurl4-openssl-dev libpython3-dev libxml2-dev pkg-config zlib1g-dev libz3-dev
sudo apt-get install -y libncurses6 libtinfo6 libstdc++-15-dev
```

If `swift` fails with:

```
error while loading shared libraries: libncurses.so.6: cannot open shared object file
```

install `libncurses6` (Ubuntu 26.04 keeps the `.so.6` names but splits packages).

### libxml2 version mismatch (harmless)

```
/lib/x86_64-linux-gnu/libxml2.so.2: no version information available
(required by .../libFoundationXML.so)
```

Ubuntu 26.04 has `libxml2.so.16`; Swift links against `.so.2`. A symlink silences the
build but the warning persists (no version symbols):

```bash
sudo ln -sf /usr/lib/x86_64-linux-gnu/libxml2.so.16 /usr/lib/x86_64-linux-gnu/libxml2.so.2
```

It is a **warning only**. Filter it from logs (`grep -v libxml2`) or it will bury real
errors.

---

## Darwin SDK from `Xcode.xip`

```bash
xtool sdk install /path/to/Xcode_27.1.xip
```

### Copy the .xip to a native path first

Reading a 2 GB file from `/mnt/e` takes **hours**; copying it takes 17 s and the
subsequent extraction is minutes:

```bash
cp /mnt/e/Hi/XCode/Xcode_27.1.xip /root/Xcode.xip   # 17 s vs hours
xtool sdk install /root/Xcode.xip
```

### Verifying the .xip before spending an hour on it

An Apple `.xip` is a xar archive. Check the declared data extent:

```python
import struct, zlib, re, os
f = open(p,'rb'); assert f.read(4)==b'xar!'
hsize, ver, toc_c, toc_u, ck = struct.unpack('>HHQQI', f.read(24))
toc = zlib.decompress(f.read(toc_c))
for d in re.findall(rb'<data>(.*?)</data>', toc, re.S):
    off = int(re.search(rb'<offset>(.*?)</offset>', d).group(1))
    ln  = int(re.search(rb'<length>(.*?)</length>', d).group(1))
    print(os.path.getsize(p) >= off + ln)   # True → complete
```

### `xtool sdk install --slim` is slower here

`slim` re-extracts; the default mode was faster and produced a working SDK. Prefer the
default unless disk space is critical.

### "Downloading OpenAppleMacros" crawls

On a slow link this single component dominates (69 MB at ~100 KB/s). It is fetched from
GitHub Releases; simply let it run, or pre-download:

```
https://github.com/xtool-org/OpenAppleMacros/releases/download/v1.4.1/OpenAppleMacrosServer-x86_64.tar.gz
```

(That archive contains the *downloader*, not the server — the slow part is the server
itself, so pre-downloading does not help much. Budget ~15 min.)

---

## Swift SDK configuration sanity

```bash
cat ~/.swiftpm/swift-sdks/darwin.artifactbundle/swift-sdk.json | head -40
```

It must reference `Developer/Platforms/...` paths. If it points at
`Xcode.app/Contents/Developer/...`, the bundle layout was altered — see
`references/sdk-layout.md`.

---

## Build triple

```bash
swift build --swift-sdk darwin --triple arm64-apple-ios-simulator    # ✔
swift build --swift-sdk darwin --triple arm64-apple-ios16.0-simulator # ✘
```

```
error: No Swift SDK found matching query `darwin`, target triple
       `arm64-apple-ios16.0-simulator`
```

**Use unversioned triples.** The SDK's `supportedTriples` list contains
`arm64-apple-ios`, `arm64-apple-ios-simulator`, etc. — deployment target comes from
`Package.swift`, not the triple.

---

## clang header mismatch

When compiling Swift for iOS, the compiler may pick up the **Xcode** copy of
`clang/include/arm_neon.h`, which does not match Swift 6.4.1's builtins:

```
arm_neon.h:1919:24: error: incompatible constant for this __builtin_neon function
arm_neon.h:41261:11: error: invalid conversion between vector type 'bfloat16x8_t' ...
```

Point the Xcode-tree path at Swift's own headers:

```bash
XCI=<bundle>/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/clang/include
SCI=$(ls -d /opt/swift641/usr/lib/clang/*/include | head -1)
mv "$XCI" "$XCI.xcode-orig" && ln -s "$SCI" "$XCI"
```

Apply to **every** Developer tree in the bundle (both `Developer/` and
`Xcode.app/Contents/Developer/`) so it holds regardless of which one is active.
