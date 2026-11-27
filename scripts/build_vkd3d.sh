#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$ROOT/vkd3d-proton"
BUILD_DIR="$ROOT/build/meson-x64"
OUT_DIR="$ROOT/build"

reconfigure=0
if [ "${1:-}" = "--reconfigure" ]; then
  reconfigure=1
fi

if [ "$reconfigure" -eq 1 ] && [ -d "$BUILD_DIR" ]; then
  rm -rf "$BUILD_DIR"
fi

if [ ! -f "$BUILD_DIR/build.ninja" ]; then
  meson setup --cross-file "$SRC_DIR/build-win64.txt" \
    --buildtype release \
    --prefix "$OUT_DIR" \
    --strip \
    --bindir x64 \
    --libdir x64 \
    "$BUILD_DIR" "$SRC_DIR"
fi

nice -n 19 ionice -c 3 ninja -j4 -C "$BUILD_DIR" install

rm -f "$OUT_DIR/x64/"*.a "$OUT_DIR/x64/"*.dll.a
ls -lh "$OUT_DIR/x64/d3d12.dll" "$OUT_DIR/x64/d3d12core.dll"
