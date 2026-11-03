# Kotlin Multiplatform → XCFramework on Linux

---

## The three traps

### 1. `expect` / `actual` cannot be expressed the way you'd expect

Manual `konanc` invocations fail both obvious ways:

| Attempt | Error |
|---|---|
| pass `commonMain` and `iosMain` together, no flags | `'expect' and 'actual' declarations can be used only in multiplatform projects` |
| same + `-Xmulti-platform` | `'expect' and 'actual' are declared in the same module` |
| pass only `iosMain` + `-Xcommon-sources=<commonMain>` | `actual has no corresponding 'expect'` (common sources never compiled) |

The Gradle KMP plugin does this correctly using fragment/refines configuration, which is
not practical to reproduce by hand.

**Solution — flatten the sources into one module:**

1. copy `commonMain` + `iosMain` into a single temp tree
2. delete every `expect` declaration line from the common sources
3. strip the `actual` keyword from the iOS sources
4. compile that tree as one module

This is semantically equivalent for an iOS slice (which only ever uses the `actual`
implementations), and any call sites in common code still resolve to those same
functions. Works because `expect` declarations are one-liners:

```bash
grep -rlE '^[[:space:]]*(internal )?expect ' "$FLAT" | while read -r f; do
  grep -vE '^[[:space:]]*(internal )?expect ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
grep -rlE '^[[:space:]]*actual ' "$FLAT" | while read -r f; do
  sed -i -E 's/^([[:space:]]*)actual /\1/' "$f"
done
```

Verify before compiling: a non-zero `expect` count means flattening missed something.

### 2. Passing the Gradle-produced klib as input silently drops your API

```bash
konanc -target ios_arm64 -produce framework -l shared/build/classes/kotlin/iosArm64/.../klib/shared
```

This **succeeds**, and the resulting `Shared.framework/Headers/Shared.h` is only ~145
lines — nothing but `KotlinBase`, `KotlinInt`, `KotlinMutableSet` and friends. Your own
types are absent because a `-l` argument is treated as a **dependency**, not the module
being exported.

**Always compile from source.** The header then grows to thousands of lines and contains
your classes (`TrackPoint`, `WalkFacade`, …). Quick sanity check:

```bash
wc -l Shared.framework/Headers/Shared.h    # <200 → wrong; thousands → right
grep -c 'swift_name' Shared.framework/Headers/Shared.h
```

### 3. Host check blocks binary output kinds

```
Target ios_arm64 is not available for output kind 'FRAMEWORK' on the linux_x64 host
```

Also for `STATIC`, `DYNAMIC`, `PROGRAM`. Only `library` (klib) is allowed.

The check reads the JVM's `os.name`, so deceive it:

```bash
konanc -Dos.name="Mac OS X" -Dos.arch=x86_64 ...
```

Do **not** use `-Dos.name="Mac OS X"` (with spaces) inside an unquoted shell string — the
shell splits it and you get `source file not found: OS`. Use an array:

```bash
KOPTS=( -Dos.name="Mac OS X" -Dos.arch=x86_64 )
"$KONANC" "${KOPTS[@]}" ...
```

Once spoofed, the compiler assumes the macOS toolchain and will start downloading a
1.28 GB macOS LLVM — redirect it to the native one:

```properties
llvmHome.macos_x64 = $llvmHome.linux_x64
```

---

## Missing iOS runtime bitcode

The Linux Kotlin/Native distribution has **no** `konan/targets/ios_*/native/*.bc`:

```
Error parsing file .../konan/targets/ios_arm64/native/compiler_interface.bc
```

Copy them from the macOS distribution (only ~287 MB, not the full 1.5 GB):

```bash
curl -L -o kn.tgz \
  https://gh-proxy.com/https://github.com/JetBrains/kotlin/releases/download/v2.4.21/kotlin-native-prebuilt-2.4.21-macos-x86_64.tar.gz
tar xzf kn.tgz -C /root/knmac --wildcards \
  '*/konan/targets/ios_arm64/*' '*/konan/targets/ios_simulator_arm64/*' '*/konan/targets/ios_x64/*'

for t in ios_arm64 ios_simulator_arm64 ios_x64; do
  rm -rf "$KONAN/konan/targets/$t"
  cp -r "/root/knmac/.../konan/targets/$t" "$KONAN/konan/targets/$t"
done
```

---

## The `assert(false)` in DebugInfoC.cpp

`kotlin-native/llvmDebugInfoC/src/main/cpp/DebugInfoC.cpp:96`:

```cpp
if (isTransparentStepping != 0) {
#ifdef __APPLE__
    spFlags |= llvm::DISubprogram::SPFlagIsTransparentStepping;
#else
    assert(false);          // ← the Linux-built .so takes this branch
#endif
}
```

The decision is made at **build time** of the native library, so no compiler flag avoids
it. When linking an Apple target it aborts immediately:

```
java: ... DebugInfoC.cpp:96: DISubprogramRef DICreateFunctionShared(...): Assertion `false' failed.
```

Bypass with a preload shim that turns the abort into a log line:

```c
/* assert_shim.c */
#include <stdio.h>
void __assert_fail(const char *a, const char *f, unsigned int l, const char *fn) {
    fprintf(stderr, "[assert-shim] ignored: %s (%s:%u %s)\n", a, f, l, fn);
}
```

```bash
clang -shared -fPIC -O2 -o /root/assert_shim.so /root/assert_shim.c
LD_PRELOAD=/root/assert_shim.so konanc ...
```

Cost: you lose the "transparent stepping" debugger feature only. Linking is unaffected.

---

## Full command shape

```bash
K="$HOME/.konan/kotlin-native-prebuilt-linux-x86_64-2.4.21"
LD_PRELOAD=/root/assert_shim.so "$K/bin/konanc" \
  -Dos.name="Mac OS X" -Dos.arch=x86_64 \
  -target ios_arm64 -produce framework \
  -Xstatic-framework \
  -Xbinary=bundleId=<your.bundle.id> \
  -Xexpect-actual-classes \
  -o "$OUT/Shared" \
  -l <kotlinx-serialization-json-iosarm64.klib> \
  -l <kotlinx-serialization-core-iosarm64.klib> \
  <flattened source dir>
```

Dependency klibs live under
`$GRADLE_USER_HOME/caches/modules-2/files-2.1/org.jetbrains.kotlinx/<artifact>/<ver>/…`.

---

## Assembling the XCFramework

Structure:

```
Shared.xcframework/
├── Info.plist
├── ios-arm64/{Shared.framework}
└── ios-arm64-simulator/{Shared.framework}
```

`Info.plist` needs, per slice: `LibraryIdentifier`, `LibraryPath`,
`SupportedArchitectures`, `SupportedPlatform`, and `SupportedPlatformVariant`
(`simulator` for the simulator slice).

### No `x86_64` simulator slice

An XCFramework allows exactly one library definition per *platform + variant*. Supporting
both arm64 and x86_64 simulators requires one **fat** static library — that needs
`llvm-lipo`, which is absent from the xtool toolset.

Consequence: Intel Mac simulators are unsupported. Device (arm64) and Apple-Silicon
simulators are fine. Document this rather than silently shipping a broken slice.

### Empty-slice error

```
Failed to load XCFramework ...: Both 'ios-arm64-simulator' and 'ios-x86_64-simulator'
represent two equivalent library definitions.
```

Either merge them with `llvm-lipo`, or ship only the arm64 simulator slice.
Also: SwiftPM caches the slice description — after editing the XCFramework delete
`.build` or you'll keep seeing the stale error.

---

## Interop issues that only appear on compile

When Swift first compiles against the framework, expect these (all mechanical):

| Symptom | Cause | Fix |
|---|---|---|
| `cannot convert 'KotlinDouble' to 'Double'` | Kotlin primitives box at the boundary | `.doubleValue` / `.floatValue` |
| `'init()' is unavailable` | class has Kotlin default args → no zero-arg init exported | add `fun defaultXxx(): X = X()` to the facade |
| `value of type X has no member 'newId'` | ObjC renames `new*` | call `doNewId(...)` |
| `have 'sessionId:', expected 'sessionId_:'` | trailing-underscore disambiguation | match the exported label exactly |
| `'Saved' is not a member of 'FinishResult'` | sealed subclasses are flattened | `RecordingSession.FinishResultSaved` |
| `reference to member 'SAFE' cannot be resolved` | Kotlin enum exports as a **class** with static properties | compare `e.name == "SAFE"` |
| `expected ',' separator` | Chinese full-width quotes `“…”` inside a Swift string | use `「」` |
| `WritableKeyPath` comparison fails | Kotlin data class is an immutable ObjC class | pass an explicit enum, not a keypath |

**The generated `Shared.h` is the authoritative signature reference.** Read it instead of
guessing — it is far faster than compile-fail loops.
