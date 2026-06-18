#!/usr/bin/env bash
# Build cfg80211.ko + mac80211.ko + rtl8xxxu.ko for a stock Android GKI kernel.
# Pin these three to YOUR device (uname -r / /proc/version):
set -euo pipefail

GKI_BUILD=13729987                                       # ci.android.com kernel build number (the -abNNNN in uname -r)
KCOMMON_SHA=6f2f96be86b93de6ed58a2c46b456fb49734c382      # kernel/common commit (android13-5.15)
SCMVERSION='-android13-8-00021-g6f2f96be86b9-ab13729987'  # makes vermagic match exactly
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
J=${J:-$(nproc)}

echo "[*] Downloading upstream LLVM 14 (matches AOSP clang r450784e ABI: CFI/LTO/SCS)…"
mkdir -p "$ROOT/toolchain"
[ -d "$ROOT/toolchain/llvm14" ] || {
  curl -L -o /tmp/llvm14.tar.xz \
    https://github.com/llvm/llvm-project/releases/download/llvmorg-14.0.0/clang+llvm-14.0.0-x86_64-linux-gnu-ubuntu-18.04.tar.xz
  tar -C "$ROOT/toolchain" -xf /tmp/llvm14.tar.xz
  mv "$ROOT/toolchain"/clang+llvm-14.0.0-* "$ROOT/toolchain/llvm14"
}
export PATH="$ROOT/toolchain/llvm14/bin:$PATH"

echo "[*] Fetching GKI vmlinux.symvers + device config…"
mkdir -p "$ROOT/gki"
curl -L -o "$ROOT/gki/vmlinux.symvers" \
  "https://ci.android.com/builds/submitted/$GKI_BUILD/kernel_aarch64/latest/raw/vmlinux.symvers"
# device_config: adb shell su -c 'zcat /proc/config.gz' > device_config   (commit-free; user-supplied)

echo "[*] Fetching ACK kernel/common @ $KCOMMON_SHA…"
[ -d "$ROOT/kernel" ] || {
  curl -L -o /tmp/k.tar.gz "https://android.googlesource.com/kernel/common/+archive/$KCOMMON_SHA.tar.gz"
  mkdir -p "$ROOT/kernel" && tar -C "$ROOT/kernel" -xzf /tmp/k.tar.gz
}

cd "$ROOT/kernel"
printf '%s' "$SCMVERSION" > .scmversion
cp "$ROOT/device_config" .config
./scripts/config --file .config -e WLAN -m CFG80211 -e CFG80211_WEXT -m MAC80211 \
  -e MAC80211_RC_MINSTREL -e WLAN_VENDOR_REALTEK -m RTL8XXXU -e RTL8XXXU_UNTESTED \
  -d TRIM_UNUSED_KSYMS -d UNUSED_KSYMS_WHITELIST -d MODULE_SIG -d MODULE_SIG_ALL -d MODULE_SIG_PROTECT
make ARCH=arm64 LLVM=1 LLVM_IAS=1 olddefconfig
make ARCH=arm64 LLVM=1 LLVM_IAS=1 -j"$J" modules_prepare
cp "$ROOT/gki/vmlinux.symvers" vmlinux.symvers

make ARCH=arm64 LLVM=1 LLVM_IAS=1 -j"$J" M=net/wireless modules
make ARCH=arm64 LLVM=1 LLVM_IAS=1 -j"$J" M=net/mac80211 \
  KBUILD_EXTRA_SYMBOLS="$PWD/net/wireless/Module.symvers" modules

echo "[*] Building rtl8xxxu (6.6 backported to 5.15, embedded firmware) from $ROOT/driver…"
make ARCH=arm64 LLVM=1 LLVM_IAS=1 -j"$J" M="$ROOT/driver" \
  KBUILD_EXTRA_SYMBOLS="$PWD/net/wireless/Module.symvers $PWD/net/mac80211/Module.symvers" modules

llvm-strip --strip-debug "$ROOT/kernel/net/wireless/cfg80211.ko" -o "$ROOT/cfg80211.ko"
llvm-strip --strip-debug "$ROOT/kernel/net/mac80211/mac80211.ko" -o "$ROOT/mac80211.ko"
llvm-strip --strip-debug "$ROOT/driver/rtl8xxxu.ko" -o "$ROOT/rtl8xxxu.ko"
echo "[✓] Built: cfg80211.ko mac80211.ko rtl8xxxu.ko  (verify: modinfo -F vermagic *.ko)"
