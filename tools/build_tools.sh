#!/usr/bin/env bash
# Cross-compile static aarch64 userspace tools: iw, aireplay-ng, airodump-ng, iwpriv, deauth.
set -euo pipefail
CC=aarch64-linux-gnu-gcc
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

# deauth (no deps)
$CC -static -O2 -o deauth deauth.c

# libnl (static) — needed by iw + aircrack osdep
[ -d nlstage ] || { curl -L -o nl.tgz https://github.com/thom311/libnl/releases/download/libnl3_7_0/libnl-3.7.0.tar.gz
  tar xzf nl.tgz && cd libnl-3.7.0
  ./configure --host=aarch64-linux-gnu CC=$CC --enable-static --disable-shared --disable-cli --prefix="$HERE/nlstage"
  make -j"$(nproc)" && make install && cd "$HERE"; }

# iw (static)
[ -f iw ] || { curl -L -o iw.tgz https://mirrors.edge.kernel.org/pub/software/network/iw/iw-5.19.tar.gz
  tar xzf iw.tgz && cd iw-5.19
  PKG_CONFIG_LIBDIR="$HERE/nlstage/lib/pkgconfig" make CC=$CC \
    CFLAGS="-O2 -I$HERE/nlstage/include/libnl3 -DCONFIG_LIBNL30" LDFLAGS="-static" -j"$(nproc)" iw
  cp iw "$HERE/iw"; cd "$HERE"; }

# OpenSSL libcrypto (static) — for aircrack-ng
[ -d osslstage ] || { curl -L -o ossl.tgz https://github.com/openssl/openssl/releases/download/OpenSSL_1_1_1w/openssl-1.1.1w.tar.gz
  tar xzf ossl.tgz && cd openssl-1.1.1w
  ./Configure linux-aarch64 no-shared no-dso no-engine no-tests \
    --cross-compile-prefix=aarch64-linux-gnu- --prefix="$HERE/osslstage"
  make -j"$(nproc)" build_libs && make install_dev && cd "$HERE"; }

# aircrack-ng (aireplay-ng + airodump-ng, fully static)
[ -f aireplay-ng ] || { curl -L -o ac.tgz https://github.com/aircrack-ng/aircrack-ng/archive/refs/tags/1.7.tar.gz
  tar xzf ac.tgz && cd aircrack-ng-1.7 && NOCONFIGURE=1 ./autogen.sh
  PKG_CONFIG_LIBDIR="$HERE/osslstage/lib/pkgconfig:$HERE/nlstage/lib/pkgconfig" \
    ./configure --host=aarch64-linux-gnu CC=$CC --with-experimental --disable-shared --without-sqlite3 \
    CPPFLAGS="-I$HERE/osslstage/include -I$HERE/nlstage/include/libnl3" CFLAGS="-O2"
  make aireplay-ng airodump-ng LDFLAGS="-all-static -no-pie -L$HERE/osslstage/lib -L$HERE/nlstage/lib"
  cp aireplay-ng airodump-ng "$HERE/"; cd "$HERE"; }

# iwpriv (wireless-tools) — for QCA setMonChan experiments
[ -f iwpriv ] || { curl -L -o wt.tgz https://hewlettpackard.github.io/wireless-tools/wireless_tools.30.pre9.tar.gz
  tar xzf wt.tgz && cd wireless_tools.30 && cp wireless.22.h wireless.h
  $CC -O2 -I. -c iwlib.c -o iwlib.o && $CC -O2 -I. -c iwpriv.c -o iwpriv.o
  $CC -static -O2 -o iwpriv iwpriv.o iwlib.o -lm && cp iwpriv "$HERE/"; cd "$HERE"; }

file iw aireplay-ng airodump-ng iwpriv deauth | sed 's/:.*ELF/: ELF/'
echo "[✓] tools built (static aarch64)"
