# SDK layout: duplicate platform registration

---

## Symptom

Any build after a clean `.build` fails at **build-system initialisation**, before
compiling anything:

```
error: SessionFailedError(error: Could not initialize build system, diagnostics: [
  ... message: "platform 'com.apple.platform.macosx' already registered from
      <bundle>/Xcode.app/Contents/Developer/Platforms/MacOSX.platform",
  ... message: "platform 'com.apple.platform.iphoneos' already registered from
      <bundle>/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform",
  ... ])
```

Note it fires for **every** platform (macOS, iOS, simulator, tvOS, watchOS, DriverKit) —
whichever pair it sees twice.

---

## Cause

The Darwin SDK bundle xtool produces contains **two complete Developer trees**:

```
<bundle>/Developer/                      ← swift-sdk.json points here (SDKs, platforms)
<bundle>/Xcode.app/Contents/Developer/   ← the raw Xcode payload (toolchains)
```

Both are real copies (≈3.0 GB and ≈3.8 GB), not symlinks. SwiftBuild scans for platforms
and finds each one twice → refuses to initialise.

A **symlink does not help** (`Developer -> Xcode.app/Contents/Developer`): the registry
deduplicates by resolved path string and still reports duplicates.

---

## Fix: hide the redundant copy

```bash
XD=<bundle>/Xcode.app/Contents/Developer
mv "$XD/Platforms" "$XD/Platforms.hidden"
```

Keep `Toolchains` in place — the real compiler lives there and xtool needs it:

```
Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain   ← keep
Xcode.app/Contents/Developer/Platforms                            ← hide
Developer/Platforms                                               ← keep (this one is used)
```

Verify:

```bash
ls <bundle>/Developer/Platforms                 # MacOSX iPhoneOS iPhoneSimulator
ls <bundle>/Xcode.app/Contents/Developer/Platforms   # does not exist / empty
ls <bundle>/Xcode.app/Contents/Developer/Toolchains  # XcodeDefault.xctoolchain
```

Only hide it when the top-level `Developer` tree actually has the platforms you need
(`MacOSX`, `iPhoneOS`, `iPhoneSimulator`). If it doesn't, hide the *other* one instead.

---

## ⚠️ Ordering constraint — this is what makes it fragile

Doing this while xtool considers the SDK stale breaks everything:

```
Darwin SDK is out of date. Rebuilding...
```

It then tries to re-download / re-install, which:

1. needs network (often fails: `HTTPClientError.deadlineExceeded`),
2. **overwrites `toolset/bin/ld64.lld`**, silently reverting your `-r` trampoline,
3. reinstalls the `Platforms` directory you just hid.

### Required sequence

```bash
# 1) SDK must be current and healthy FIRST
xtool sdk status          # expect: "Darwin SDK is installed" + a version line
# if it says out of date -> let it finish updating (needs working network)

# 2) THEN hide the duplicate platforms
mv "$XD/Platforms" "$XD/Platforms.hidden"

# 3) re-check: must NOT say out of date
xtool sdk status

# 4) re-apply the trampoline (step 2 may have clobbered it in an earlier round)
grep -c 'LLD 21.1.6' <bundle>/toolset/bin/ld64.lld    # want >= 1
bash scripts/fix-ld64-trampoline.sh
```

---

## Reverting

```bash
[ -d "$XD/Platforms.hidden" ] && mv "$XD/Platforms.hidden" "$XD/Platforms"
```

Revert whenever you need `xtool sdk update` / `xtool sdk install` to succeed — it will
complain about the missing platforms otherwise.

---

## Diagnosing which tree is "authoritative"

```bash
# which tree actually has the compiler?
for p in <bundle>/Developer/Toolchains/XcodeDefault.xctoolchain \
         <bundle>/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain; do
  [ -e "$p/usr/bin/swift-frontend" ] && echo "has compiler: $p" || echo "shell only : $p"
done
```

Typical result: only the `Xcode.app` one has the compiler; `Developer/` is a slim view
containing platforms and SDKs only. Hence: keep both, but expose platforms from exactly
one of them.

---

## Related: "out of date" caused by network, not by layout

If you see:

```
Error: HTTPClientError.deadlineExceeded
Darwin SDK is out of date. Rebuilding...
```

before ever touching the layout, the trigger is the **version check timing out**, not a
layout problem. Fix network first: `references/network.md`.
