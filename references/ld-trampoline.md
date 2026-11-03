# ld64.lld has no `-r` — surrogate linker

---

## The problem

SwiftPM merges a library target's objects with a relocatable link:

```
clang -target arm64-apple-ios16.0 -r -isysroot <SDK> -filelist Walk.LinkFileList \
      --ld-path=<toolset>/ld64.lld -o .../Walk.o
```

The only Mach-O linker that runs on Linux is LLVM's `ld64.lld` (shipped with xtool's
toolset). It reports:

```
ld64.lld: warning: Option `-r' is not yet implemented. Stay tuned...
```

then either fails with a cascade of `undefined symbol: swift_retain` (no runtime libs
linked) or leaves the build broken.

---

## Why not just add `-lswiftCore`?

Because `-r` is *relocatable* — it must not resolve symbols at all. `ld64.lld` skipping
`-r` semantics means it tries a real link, which then needs the whole Swift runtime and
fails differently. Not a fixable parameter list; the mode itself is absent.

---

## The fix: substitute an archive step

For the library-target case, `-r` only exists to **merge a set of `.o` files into one
intermediate artifact** which is archived next. An `ar` archive of the same inputs is
equivalent for that purpose.

So replace the toolset trampoline `toolset/bin/ld64.lld` with:

```bash
#!/usr/bin/env bash
# If -r: merge objects with llvm-lib -static (produces a valid ar archive)
# Otherwise: pass through to the real linker
```

`llvm-lib` here is `llvm-libtool-darwin`, which **requires an explicit `-static`**.

### Two subtleties that cost real time

**(a) SwiftPM's `LinkFileList` contains the output file itself.**

When generating `Walk.o`, the list also contains `.../Walk.o`. `llvm-lib` then errors:

```
error: '.../Walk.o': No such file or directory
```

It cannot exist yet — it is the output. Filter it. Note that the output path
(`Products/…/Walk.o`) and the listed path (`Objects-normal/…/Walk.o`) have **different
directories but the same basename**, so compare **basenames**, not full paths.

**(b) `-dependency_info` must be produced, in ld64's binary format.**

SwiftPM parses this file afterwards. Getting it wrong produces a sequence of errors —
each one hides the next:

```
missing null terminator       → file must end with NUL
missing version record        → first record must be the version string
unknown opcode 0x76           → tried text "version 1"; 'v' = 0x76
unknown opcode 0xA            → tried a length prefix; 0x0A was read as an opcode
empty operand                 → an empty field inside a record
```

**Correct layout**, reverse-engineered from a genuine `ld64.lld` output:

```
\x00  "LLD 21.1.6"  \x00  \x10 <path> \x00  \x10 <path> \x00  ...
                         ^            ^
                         opcode      NUL-terminated string
```

- leading NUL opens the record area
- version string, NUL-terminated
- then one record per path: **opcode `0x10`**, then the raw path, then NUL

`0x10` is the **opcode for a path record** — it is *not* a length prefix. That
misreading is what produced `unknown opcode 0xA`.

Python that emits it correctly:

```python
buf = bytearray()
buf.append(0)                       # open record area
buf.extend(b"LLD 21.1.6"); buf.append(0)
for item in deps + ([out] if out else []):
    buf.append(0x10)                # opcode: path record
    buf.extend(item.encode()); buf.append(0)
open(path, "wb").write(bytes(buf))
```

---

## Argument parsing

Expand `-Xlinker` pairs first, then skip every option that takes a value. Missing
even one turns its value into a phantom input file:

```
-mllvm -enable-linkonceodr-outlining   → 'enable-linkonceodr-outlining' treated as an object
-arch_only arm64                       → 'arm64' treated as an object
```

Value-taking set used (`libtool` needs `-arch_only`, `ld` needs `-arch`):

```
-o -filelist -dependency_info -arch -arch_only -object_path_lto
-platform_version -syslibroot -framework -L -l -mllvm -F -u -undefined
-insystem -exact_version -component_version -segaddr -segprot -force_load
-rpath_l -lazy_library -reexport_l -target -arch_multiple -map
```

---

## Also patch `libtool`

Kotlin/Native invokes `libtool` for the static framework. The macOS binary in the Xcode
tree cannot run, so point `toolset/.../usr/bin/libtool` at `llvm-lib`:

```bash
#!/usr/bin/env bash
# llvm-libtool-darwin REQUIRES -static; also drop value-taking flags (-arch etc.)
out=""; objs=()
while [ $# -gt 0 ]; do
  case "$1" in
    -static) ;;
    -o) shift; out="$1" ;;
    -arch_only|-arch|-syslibroot|-D|-U|-framework|-L|-l|-filelist|-isysroot|-objlist) shift ;;
    -*) ;;
    *) objs+=("$1") ;;
  esac
  shift
done
cmd=(<toolset>/llvm-lib -static)
[ -n "$out" ] && cmd+=(-o "$out")
cmd+=("${objs[@]}")
exec "${cmd[@]}"
```

If a smoke test with a **Linux ELF** object fails with `format not supported`, that is
expected — `llvm-libtool-darwin` accepts Mach-O only. Test with a real arm64 Mach-O `.o`.

---

## Fragility warning

**Any `xtool sdk` update overwrites `toolset/bin/ld64.lld`.** After every SDK rebuild:

```bash
grep -c 'LLD 21.1.6' ~/.swiftpm/swift-sdks/darwin.artifactbundle/toolset/bin/ld64.lld
# 0  -> patched version gone, re-run scripts/fix-ld64-trampoline.sh
# >=1 -> still patched
```

Keep the original as `ld64.lld.xtool-orig` before overwriting.
