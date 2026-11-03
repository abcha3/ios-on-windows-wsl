#!/usr/bin/env bash
# ============================================================================
#  fix-ld-trampoline.sh
#  ----------------------------------------------------------------------------
#  ld64.lld (the only Mach-O linker that runs on Linux) does not implement -r,
#  but SwiftPM uses `clang -r` for library targets. Substitute an archive step.
#
#  Three things must be right; each was found the hard way:
#    1. -r  -> llvm-lib -static      (valid ar archive of the same objects)
#    2. skip the output file if SwiftPM listed it among the inputs
#       (output is under Products/, listed path under Objects-normal/ —
#        same basename, different directories, so compare basenames)
#    3. emit dependency_info in ld64's binary format:
#           \0 "LLD 21.1.6" \0   then per path:  \x10 <path> \0
#       \x10 is an OPCODE (path record), not a length prefix.
#       Wrong guesses produce, in order: missing null terminator /
#       missing version record / unknown opcode 0x76 / unknown opcode 0xA.
#
#  RE-RUN THIS AFTER ANY `xtool sdk` UPDATE — the update overwrites the file.
#  Check: grep -c 'LLD 21.1.6' .../toolset/bin/ld64.lld   (>=1 means patched)
# ============================================================================
set -uo pipefail

BUNDLE="${BUNDLE:-$HOME/.swiftpm/swift-sdks/darwin.artifactbundle}"
TOOLSET="$BUNDLE/toolset/bin"
T="$TOOLSET/ld64.lld"

[ -d "$BUNDLE" ] || { echo "!! Darwin SDK bundle not found: $BUNDLE" >&2; exit 1; }
[ -f "$T" ] || { echo "!! $T missing" >&2; exit 1; }

# keep a pristine copy once
if [ ! -f "$T.xtool-orig" ] && ! grep -q 'ios-wsl trampoline' "$T" 2>/dev/null; then
  cp "$T" "$T.xtool-orig"
fi

command -v python3 >/dev/null 2>&1 || { echo "!! python3 required" >&2; exit 1; }

python3 - "$T" "$TOOLSET" <<'PY'
import sys
target, toolset = sys.argv[1], sys.argv[2]
body = r'''#!/usr/bin/env bash
# ld64.lld trampoline (ios-wsl)
#
#   -r   -> llvm-lib -static  (merge objects into an ar archive)
#   else -> the real ld64.lld
#
# Why: ld64.lld does not implement -r ("Option `-r' is not yet implemented").
# For SwiftPM library targets -r only means "merge .o files into one
# intermediate artifact", so an archive of the same inputs is equivalent.
set -u

TS_BIN=TOOLSET_DIR
LLD="$TS_BIN/orig/ld64.lld"

# expand -Xlinker <arg> pairs into plain args
raw=("$@"); args=()
i=0; n=${#raw[@]}
while [ $i -lt $n ]; do
  if [ "${raw[$i]}" = "-Xlinker" ] && [ $((i+1)) -lt $n ]; then
    args+=("${raw[$((i+1))]}"); i=$((i+2))
  else
    args+=("${raw[$i]}"); i=$((i+1))
  fi
done

# every option that consumes the next argument
TAKE_VALUE="-o -filelist -dependency_info -arch -arch_only -object_path_lto \
-platform_version -syslibroot -framework -L -l -mllvm -F -u -undefined \
-insystem -exact_version -component_version -segaddr -segprot -force_load \
-rpath_l -lazy_library -reexport_l -target -arch_multiple -map"

out=""; filelist=""; depinfo=""
objs=(); reloc=0
i=0; n=${#args[@]}
while [ $i -lt $n ]; do
  a="${args[$i]}"
  if [ "$a" = "-r" ]; then reloc=1; i=$((i+1)); continue; fi
  skip=0
  for f in $TAKE_VALUE; do [ "$a" = "$f" ] && skip=1 && break; done
  if [ $skip -eq 1 ]; then
    v="${args[$((i+1))]:-}"
    case "$a" in
      -o) out="$v" ;;
      -filelist) filelist="$v" ;;
      -dependency_info) depinfo="$v" ;;
    esac
    i=$((i+2)); continue
  fi
  case "$a" in -*) ;; *) objs+=("$a") ;; esac
  i=$((i+1))
done

if [ "$reloc" -eq 1 ]; then
  out_base=""
  [ -n "$out" ] && out_base="$(basename "$out")"

  inputs=()
  if [ -n "$filelist" ] && [ -f "$filelist" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      # skip the output itself (SwiftPM lists it among the inputs)
      [ -n "$out_base" ] && [ "$(basename "$line")" = "$out_base" ] && continue
      inputs+=("$line")
    done < "$filelist"
  else
    for o in ${objs[@]+"${objs[@]}"}; do
      [ -n "$out_base" ] && [ "$(basename "$o")" = "$out_base" ] && continue
      inputs+=("$o")
    done
  fi

  if [ ${#inputs[@]} -eq 0 ]; then
    echo "ld64.lld trampoline: -r with no inputs (out=$out filelist=$filelist)" >&2
    exit 1
  fi

  cmd=("$TS_BIN/llvm-lib" -static)
  [ -n "$out" ] && cmd+=(-o "$out")
  cmd+=("${inputs[@]}")
  "${cmd[@]}" || exit $?

  # dependency_info: NUL + version + NUL, then (opcode 0x10 + path + NUL)*
  if [ -n "$depinfo" ]; then
    mkdir -p "$(dirname "$depinfo")"
    python3 - "$depinfo" "$out" "${inputs[@]}" <<'PYDEP'
import sys
path, out, deps = sys.argv[1], sys.argv[2], sys.argv[3:]
buf = bytearray()
buf.append(0)                      # open record area
buf.extend(b"LLD 21.1.6"); buf.append(0)
for item in deps + ([out] if out else []):
    buf.append(0x10)               # opcode: path record (NOT a length)
    buf.extend(item.encode()); buf.append(0)
open(path, "wb").write(bytes(buf))
PYDEP
  fi
  exit 0
fi

exec "$LLD" "${args[@]}"
'''
open(target, 'w').write(body.replace('TOOLSET_DIR', toolset))
PY

chmod +x "$T"

# libtool also needs substituting: the macOS binary cannot run on Linux,
# and llvm-libtool-darwin REQUIRES an explicit -static.
LT_RUNNER="$BUNDLE/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/libtool"
if [ -d "$(dirname "$LT_RUNNER")" ]; then
  [ -f "$LT_RUNNER" ] && [ ! -f "$LT_RUNNER.apple-orig" ] && mv "$LT_RUNNER" "$LT_RUNNER.apple-orig"
  cat > "$LT_RUNNER" <<EOF
#!/usr/bin/env bash
# libtool -> llvm-libtool-darwin. It requires -static; drop value-taking flags.
out=""; objs=()
while [ \$# -gt 0 ]; do
  case "\$1" in
    -static) ;;
    -o) shift; out="\$1" ;;
    -arch_only|-arch|-syslibroot|-D|-U|-framework|-L|-l|-filelist|-isysroot|-objlist) shift ;;
    -*) ;;
    *) objs+=("\$1") ;;
  esac
  shift
done
cmd=("$TOOLSET/llvm-lib" -static)
[ -n "\$out" ] && cmd+=(-o "\$out")
cmd+=("\${objs[@]}")
exec "\${cmd[@]}"
EOF
  chmod +x "$LT_RUNNER"
fi

echo "  ✓ trampoline patched: $T"
grep -c 'LLD 21.1.6' "$T" 2>/dev/null | sed 's/^/    marker count: /'
