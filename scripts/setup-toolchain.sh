#!/usr/bin/env bash
# ============================================================================
#  setup-toolchain.sh
#  ----------------------------------------------------------------------------
#  Prepare a WSL/Linux box to build iOS apps without a Mac.
#
#  Idempotent. Safe to re-run. Every mutation is reversible and backed up.
#
#  Tunables (env):
#    SWIFT_HOME=/opt/swift641     where Swift 6.4.1 lives
#    KONAN_HOME=$HOME/.konan
#    KONAN_VER=2.4.21
#    GITHUB_IP=<ip>               pinned edge IP for github.com
# ============================================================================
set -uo pipefail

SWIFT_HOME="${SWIFT_HOME:-/opt/swift641}"
KONAN_ROOT="${KONAN_HOME:-$HOME/.konan}"
KONAN_VER="${KONAN_VER:-2.4.21}"
KONAN="$KONAN_ROOT/kotlin-native-prebuilt-linux-x86_64-$KONAN_VER"
BUNDLE="$HOME/.swiftpm/swift-sdks/darwin.artifactbundle"
TOOLSET="$BUNDLE/toolset/bin"

ok()   { echo "  ✓ $*"; }
warn() { echo "  ⚠ $*"; }
die()  { echo "  ✗ $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
echo "== 1. Swift toolchain =="
# Why 6.4: Xcode 27 swiftinterface files use Swift::Comparable and ~Copyable
# generic suppression. 6.2/6.3 fail to parse them, and the resulting error
# ("unable to load standard library") misleadingly looks like a missing SDK.
if [ ! -x "$SWIFT_HOME/usr/bin/swift" ]; then
  warn "Swift not found at $SWIFT_HOME — installing 6.4.1"
  URL="https://download.swift.org/swift-6.4.1-release/ubuntu2604/swift-6.4.1-RELEASE/swift-6.4.1-RELEASE-ubuntu26.04.tar.gz"
  curl -fL -m 2400 -o /tmp/swift641.tar.gz "$URL" || die "download failed: $URL"
  sudo rm -rf "$SWIFT_HOME" && sudo mkdir -p "$SWIFT_HOME"
  sudo tar zxf /tmp/swift641.tar.gz -C "$SWIFT_HOME" --strip-components=1 || die "extract failed"
fi
VER=$("$SWIFT_HOME/usr/bin/swift" --version 2>/dev/null | head -1)
ok "$VER"
case "$VER" in
  *"version 6.4"*|*"version 6.5"*|*"version 7"*) ;;
  *) warn "Swift < 6.4 — Xcode 27 interfaces will not parse" ;;
esac

# ---------------------------------------------------------------------------
echo "== 2. Swift runtime deps =="
sudo apt-get install -y -qq binutils-gold unzip zip gnupg2 libc6-dev \
  libcurl4-openssl-dev libpython3-dev libxml2-dev pkg-config zlib1g-dev \
  libz3-dev libncurses6 libtinfo6 2>/dev/null | tail -2
ok "deps installed"
# Ubuntu 26.04 ships libxml2.so.16 while Swift wants .so.2 (warning only)
if [ ! -e /usr/lib/x86_64-linux-gnu/libxml2.so.2 ]; then
  sudo ln -sf /usr/lib/x86_64-linux-gnu/libxml2.so.16 /usr/lib/x86_64-linux-gnu/libxml2.so.2 2>/dev/null && \
    ok "libxml2.so.2 symlink (silences a harmless warning)" || warn "libxml2 symlink skipped"
fi

# ---------------------------------------------------------------------------
echo "== 3. github.com reachability =="
# xtool checks the SDK version on every build. A timed-out check is treated as
# "SDK out of date", triggering a reinstall that overwrites the ld trampoline.
CODE=$(curl -s -m 10 -o /dev/null -w '%{http_code}' https://github.com 2>/dev/null)
if [ "$CODE" = "200" ]; then
  ok "github.com reachable"
else
  warn "github.com not reachable (HTTP $CODE) — probing edge IPs"
  CHOSEN=""
  for ip in "${GITHUB_IP:-}" 20.27.177.113 140.82.114.3 140.82.112.3 140.82.113.3; do
    [ -z "$ip" ] && continue
    c=$(curl -s -m 6 --resolve "github.com:443:$ip" -o /dev/null -w '%{http_code}' https://github.com 2>/dev/null)
    if [ "$c" = "200" ]; then CHOSEN="$ip"; break; fi
  done
  if [ -n "$CHOSEN" ]; then
    [ -f /etc/hosts.before-github-fix ] || sudo cp /etc/hosts /etc/hosts.before-github-fix
    sudo sed -i '/ios-wsl: github/d' /etc/hosts
    echo "$CHOSEN github.com # ios-wsl: github reachability fix" | sudo tee -a /etc/hosts >/dev/null
    ok "pinned github.com -> $CHOSEN"
  else
    warn "no reachable edge IP; set GITHUB_IP=... and re-run"
  fi
fi

# ---------------------------------------------------------------------------
echo "== 4. Kotlin/Native =="
if [ ! -d "$KONAN" ]; then
  die "Kotlin/Native not found at $KONAN (install it or set KONAN_VER)"
fi
ok "konan: $KONAN"

# iOS runtime bitcode is absent from the Linux distribution.
if [ ! -f "$KONAN/konan/targets/ios_arm64/native/compiler_interface.bc" ]; then
  warn "iOS bitcode missing — need the macOS distribution"
  MAC_KONAN="${MAC_KONAN:-/root/knmac/kotlin-native-prebuilt-macos-x86_64-$KONAN_VER}"
  if [ ! -d "$MAC_KONAN/konan/targets/ios_arm64" ]; then
    warn "fetching macOS konan (~287 MB) via mirror"
    mkdir -p /root/knmac
    curl -fL -m 3000 -o /root/knmac/kn.tgz \
      "https://gh-proxy.com/https://github.com/JetBrains/kotlin/releases/download/v$KONAN_VER/kotlin-native-prebuilt-$KONAN_VER-macos-x86_64.tar.gz" \
      || die "could not download macOS konan"
    tar xzf /root/knmac/kn.tgz -C /root/knmac --wildcards \
      '*/konan/targets/ios_arm64/*' '*/konan/targets/ios_simulator_arm64/*' '*/konan/targets/ios_x64/*' 2>/dev/null
  fi
  for t in ios_arm64 ios_simulator_arm64 ios_x64; do
    if [ -d "$MAC_KONAN/konan/targets/$t" ]; then
      rm -rf "$KONAN/konan/targets/$t"
      cp -r "$MAC_KONAN/konan/targets/$t" "$KONAN/konan/targets/$t"
    fi
  done
  ok "iOS bitcode copied"
else
  ok "iOS bitcode present"
fi

# ---------------------------------------------------------------------------
echo "== 5. konan.properties overrides =="
# (a) spoofed host would fetch a 1.28 GB macOS LLVM; reuse the native one
# (b) point iOS linking at the xtool toolset + the real iOS SDK
P="$KONAN/konan/konan.properties"
[ -f "$P.orig-backup" ] || cp "$P" "$P.orig-backup"
cp "$P.orig-backup" "$P"
sed -i 's|^llvmHome\.macos_x64 = .*|llvmHome.macos_x64 = $llvmHome.linux_x64|' "$P"
cat >> "$P" <<EOF

# ---- ios-wsl overrides (scripts/setup-toolchain.sh) ----
linker.ios_arm64=$TOOLSET/ld64.lld
linker.ios_arm64-linux_x64=$TOOLSET/ld64.lld
linker.ios_simulator_arm64=$TOOLSET/ld64.lld
linker.ios_x64=$TOOLSET/ld64.lld
targetSysRoot.ios_arm64=$BUNDLE/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk
targetSysRoot.ios_simulator_arm64=$BUNDLE/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk
targetSysRoot.ios_x64=$BUNDLE/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk
EOF
ok "konan.properties written (backup: $P.orig-backup)"

# ---------------------------------------------------------------------------
echo "== 6. assert shim =="
# DebugInfoC.cpp does assert(false) on non-Apple hosts for an Apple-only
# debug feature. It is a build-time #ifdef, so no flag avoids it.
cat > /root/assert_shim.c <<'EOF'
#include <stdio.h>
void __assert_fail(const char *a, const char *f, unsigned int l, const char *fn) {
    fprintf(stderr, "[assert-shim] ignored: %s (%s:%u %s)\n", a, f, l, fn);
}
EOF
"$SWIFT_HOME/usr/bin/clang" -shared -fPIC -O2 -o /root/assert_shim.so /root/assert_shim.c \
  && ok "/root/assert_shim.so" || warn "shim build failed"

# ---------------------------------------------------------------------------
echo "== 7. clang headers =="
# Xcode's arm_neon.h does not match Swift 6.4.1 builtins:
#   "incompatible constant for this __builtin_neon function"
SCI=$(ls -d "$SWIFT_HOME"/usr/lib/clang/*/include 2>/dev/null | head -1)
for tree in "$BUNDLE/Developer" "$BUNDLE/Xcode.app/Contents/Developer"; do
  XCI="$tree/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/clang/include"
  if [ -n "$SCI" ] && [ -d "$XCI" ] && [ ! -L "$XCI" ]; then
    mv "$XCI" "$XCI.xcode-orig" && ln -s "$SCI" "$XCI"
    ok "clang include -> swift ($(basename "$tree"))"
  fi
done

# ---------------------------------------------------------------------------
echo "== 8. ld trampoline (-r unsupported) =="
bash "$(dirname "$0")/fix-ld-trampoline.sh"

echo
echo "== done =="
echo "  swift : $("$SWIFT_HOME/usr/bin/swift" --version 2>/dev/null | head -1)"
echo "  konan : $KONAN"
echo "  build : export LD_PRELOAD=/root/assert_shim.so"
echo "  next  : bash $(dirname "$0")/build-xcframework.sh"
