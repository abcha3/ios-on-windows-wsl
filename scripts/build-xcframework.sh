#!/usr/bin/env bash
# ============================================================================
#  build-xcframework.sh
#  ----------------------------------------------------------------------------
#  Produce <Name>.xcframework from a Kotlin Multiplatform module, on Linux.
#
#  Usage:
#    bash build-xcframework.sh [project-dir] [--name Shared] [--bundle com.x.y]
#
#  Defaults assume a standard KMP layout:
#    <project>/shared/src/commonMain/kotlin
#    <project>/shared/src/iosMain/kotlin
#    <project>/shared/build/XCFrameworks/release   (output)
#
#  Env:
#    GRADLE_BIN            gradle executable
#    GRADLE_USER_HOME      dependency cache (needed to locate kotlinx klibs)
#    KONAN_VER             2.4.21 by default
#    FW_NAME / BUNDLE_ID   framework name / bundle id
#    SHIM                  /root/assert_shim.so
# ============================================================================
set -uo pipefail

PROJ="$(cd "${1:-$(pwd)}" && pwd)"
FW_NAME="${FW_NAME:-Shared}"
BUNDLE_ID="${BUNDLE_ID:-com.example.app}"
GRADLE_BIN="${GRADLE_BIN:-gradle}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$HOME/.gradle}"
KONAN="$HOME/.konan/kotlin-native-prebuilt-linux-x86_64-${KONAN_VER:-2.4.21}"
SHIM="${SHIM:-/root/assert_shim.so}"
WORK="${WORK:-/tmp/xcf-build}"
OUT="$PROJ/shared/build/XCFrameworks/release"

[ -x "$KONAN/bin/konanc" ] || { echo "!! konanc not found: $KONAN" >&2; exit 1; }
[ -f "$SHIM" ] || { echo "!! missing $SHIM — run setup-toolchain.sh" >&2; exit 1; }

# Gradle target name -> konanc target -> xcframework slice id
TARGETS=(
  "iosArm64:ios_arm64:ios-arm64"
  "iosSimulatorArm64:ios_simulator_arm64:ios-arm64-simulator"
)

echo "== 1. compile klibs via Gradle =="
# klibs are only used to (a) validate the module compiles and (b) locate the
# kotlinx dependency klibs. The framework itself is compiled from SOURCE,
# because passing a klib with -l makes it a dependency and drops your API
# from the generated header (~145 lines instead of thousands).
( cd "$PROJ" && "$GRADLE_BIN" :shared:compileKotlinIosArm64 \
    :shared:compileKotlinIosSimulatorArm64 --no-daemon --console=plain -q ) \
  || { echo "!! Gradle compile failed" >&2; exit 1; }
echo "  ✓ klibs compiled"

find_dep_klibs() {   # find_dep_klibs <artifact-suffix>  e.g. iosarm64
  local suffix="$1" json core
  json=$(find "$GRADLE_USER_HOME/caches/modules-2/files-2.1/org.jetbrains.kotlinx/kotlinx-serialization-json-$suffix" -name '*.klib' 2>/dev/null | head -1)
  core=$(find "$GRADLE_USER_HOME/caches/modules-2/files-2.1/org.jetbrains.kotlinx/kotlinx-serialization-core-$suffix" -name '*.klib' 2>/dev/null | head -1)
  [ -n "$json" ] && [ -n "$core" ] || return 1
  printf '%s\n%s\n' "$json" "$core"
}

echo "== 2. flatten sources (common + ios into one module) =="
# Kotlin/Native cannot pair expect/actual across two hand-invoked compilations:
#   both dirs together -> "declared in the same module"
#   only ios + -Xcommon-sources -> common never compiled
# Flattening is equivalent for an iOS slice, which only uses the actuals.
rm -rf "$WORK"; mkdir -p "$WORK"
FLAT="$WORK/flat-src"
mkdir -p "$FLAT"
cp -r "$PROJ/shared/src/commonMain/kotlin/." "$FLAT/" 2>/dev/null || { echo "!! no commonMain" >&2; exit 1; }
cp -r "$PROJ/shared/src/iosMain/kotlin/."  "$FLAT/" 2>/dev/null || { echo "!! no iosMain"  >&2; exit 1; }

grep -rlE '^[[:space:]]*(internal )?expect ' "$FLAT" 2>/dev/null | while read -r f; do
  grep -vE '^[[:space:]]*(internal )?expect ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
grep -rlE '^[[:space:]]*actual ' "$FLAT" 2>/dev/null | while read -r f; do
  sed -i -E 's/^([[:space:]]*)actual /\1/' "$f"
done
remaining=$(grep -rcE '^[[:space:]]*(internal )?expect ' "$FLAT" 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')
echo "  ✓ flattened (remaining expect: $remaining)"

echo "== 3. link framework per slice =="
KOPTS=( -Dos.name="Mac OS X" -Dos.arch=x86_64 )
for spec in "${TARGETS[@]}"; do
  IFS=':' read -r gradleName konanTarget sliceId <<< "$spec"
  case "$gradleName" in
    iosArm64)          ser=iosarm64 ;;
    iosSimulatorArm64) ser=iossimulatorarm64 ;;
    iosX64)            ser=iosx64 ;;
  esac
  mapfile -t DEP < <(find_dep_klibs "$ser" || true)

  SLICE="$WORK/$sliceId"; mkdir -p "$SLICE"
  echo "  -> $sliceId ($konanTarget)"
  LD_PRELOAD="$SHIM" "$KONAN/bin/konanc" "${KOPTS[@]}" \
    -target "$konanTarget" -produce framework \
    -Xstatic-framework \
    -Xbinary=bundleId="$BUNDLE_ID" \
    -Xexpect-actual-classes \
    -o "$SLICE/$FW_NAME" \
    ${DEP[0]:+-l "${DEP[0]}"} ${DEP[1]:+-l "${DEP[1]}"} \
    "$FLAT" > "$SLICE/link.log" 2>&1 \
    || { echo "!! $sliceId failed; tail of log:" >&2; grep -vE '^\s+at |assert-shim' "$SLICE/link.log" | tail -20 >&2; exit 1; }

  HF="$SLICE/$FW_NAME.framework/Headers/$FW_NAME.h"
  if [ -f "$HF" ]; then
    LINES=$(wc -l < "$HF")
    echo "     header $LINES lines"
    [ "$LINES" -lt 200 ] && echo "     ⚠ suspiciously small — did you pass a klib instead of sources?"
  fi
done

echo "== 4. assemble XCFramework =="
XCF="$OUT/$FW_NAME.xcframework"
rm -rf "$XCF"; mkdir -p "$XCF"
for spec in "${TARGETS[@]}"; do
  IFS=':' read -r _ _ sliceId <<< "$spec"
  mkdir -p "$XCF/$sliceId"
  cp -r "$WORK/$sliceId/$FW_NAME.framework" "$XCF/$sliceId/"
done

{
  cat <<'PH'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AvailableLibraries</key>
    <array>
PH
  for spec in "${TARGETS[@]}"; do
    IFS=':' read -r _ _ sliceId <<< "$spec"
    case "$sliceId" in
      ios-arm64)           arch=arm64;  variant="" ;;
      ios-arm64-simulator) arch=arm64;  variant="            <key>SupportedPlatformVariant</key>
            <string>simulator</string>
" ;;
      ios-x86_64-simulator) arch=x86_64; variant="            <key>SupportedPlatformVariant</key>
            <string>simulator</string>
" ;;
    esac
    cat <<SL

        <dict>
            <key>LibraryIdentifier</key>
            <string>$sliceId</string>
            <key>LibraryPath</key>
            <string>$FW_NAME.framework</string>
            <key>SupportedArchitectures</key>
            <array>
                <string>$arch</string>
            </array>
            <key>SupportedPlatform</key>
            <string>ios</string>
$variant        </dict>
SL
  done
  cat <<'PT'
    </array>
    <key>CFBundlePackageType</key>
    <string>XFWK</string>
    <key>XCFrameworkFormatVersion</key>
    <string>1.0</string>
</dict>
</plist>
PT
} > "$XCF/Info.plist"

echo "  ✓ $XCF"
echo
echo "NOTE: no x86_64 simulator slice — an XCFramework allows one library per"
echo "      platform+variant; merging arm64+x86_64 simulator needs llvm-lipo,"
echo "      which the xtool toolset does not ship. Intel Mac simulators are"
echo "      therefore unsupported; device and Apple-Silicon simulators are fine."
echo
echo "If SwiftPM previously loaded a different slice set: rm -rf <project>/.build"
