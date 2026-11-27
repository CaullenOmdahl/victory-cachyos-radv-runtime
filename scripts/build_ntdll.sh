#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$ROOT/wine-cachyos"
BUILD_DIR="$ROOT/build/wine-unix"
OUT_SO="$ROOT/build/x64/ntdll.so"
CUSTOM_DIR="/home/caullen/.local/share/victory-proton/proton-custom/files"
STOCK_DIR="/home/caullen/.local/share/victory-proton/proton-patched/files"
CUSTOM_NTDLL="$CUSTOM_DIR/lib/wine/x86_64-unix/ntdll.so"
STOCK_NTDLL="$STOCK_DIR/lib/wine/x86_64-unix/ntdll.so"

if [ "${1:-}" = "--restore" ]; then
  rm -f "$CUSTOM_NTDLL"
  ln -s "$STOCK_NTDLL" "$CUSTOM_NTDLL"
  ls -la "$CUSTOM_NTDLL"
  exit 0
fi

nice -n 19 ionice -c 3 make -C "$BUILD_DIR" -j4 dlls/ntdll/ntdll.so
mkdir -p "$(dirname "$OUT_SO")"
cp -f "$BUILD_DIR/dlls/ntdll/ntdll.so" "$OUT_SO"
strip --strip-unneeded "$OUT_SO"

# Replace symlinks on wine loader executables inside proton-custom so /proc/self/exe
# resolves inside proton-custom rather than proton-patched. Never modify proton-patched.
for rel in \
  bin/wine \
  bin/wineserver \
  lib/wine/x86_64-unix/wine \
  lib/wine/x86_64-unix/wine-preloader \
  lib/wine/x86_64-unix/wine64 \
  lib/wine/x86_64-unix/wine64-preloader \
  lib/wine/i386-unix/wine64 \
  lib/wine/i386-unix/wine64-preloader; do
  if [ -L "$CUSTOM_DIR/$rel" ]; then
    tmp="$(mktemp "$CUSTOM_DIR/${rel}.tmp.XXXXXX")"
    cp -L "$STOCK_DIR/$rel" "$tmp"
    chmod 0755 "$tmp"
    mv -f "$tmp" "$CUSTOM_DIR/$rel"
  fi
done

# Copy ntdll.so as a real file (NOT a symlink) so loader.c's realpath_dirname(ntdll.so)
# resolves inside proton-custom/files/lib/wine/x86_64-unix alongside wine/wine-preloader.
tmp_so="$(mktemp "${CUSTOM_NTDLL}.tmp.XXXXXX")"
cp -f "$OUT_SO" "$tmp_so"
chmod 0755 "$tmp_so"
mv -f "$tmp_so" "$CUSTOM_NTDLL"
ls -lh "$OUT_SO" "$CUSTOM_NTDLL"
