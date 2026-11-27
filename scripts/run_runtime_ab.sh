#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE=""
EXE=""
LOG=""
INWORLD_WAIT=45
REFRESH_PREFIX=0

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)
      MODE="${2:?missing --mode value}"
      shift 2
      ;;
    --exe)
      EXE="${2:?missing --exe value}"
      shift 2
      ;;
    --log)
      LOG="${2:?missing --log value}"
      shift 2
      ;;
    --wait)
      INWORLD_WAIT="${2:?missing --wait value}"
      shift 2
      ;;
    --refresh-prefix)
      REFRESH_PREFIX=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$MODE" ] || [ -z "$EXE" ] || [ -z "$LOG" ]; then
  echo "Usage: $0 --mode stock|custom --exe <path> --log <path> [--wait 45] [--refresh-prefix]" >&2
  exit 1
fi

if [ ! -f "$EXE" ]; then
  echo "Executable not found: $EXE" >&2
  exit 1
fi

# Strict GPU collision guard: never launch while any victory.exe is running
if python3 -c '
import os, subprocess, sys
out = subprocess.check_output(["ps", "-eo", "pid=,ppid=,comm=,args="], text=True)
self_pids = {str(os.getpid()), str(os.getppid())}
hits = []
for line in out.splitlines():
    parts = line.strip().split(None, 3)
    if len(parts) < 4:
        continue
    pid, ppid, comm, args = parts
    if pid in self_pids or comm in ("bash", "sh", "zsh", "dash", "ps", "python3", "flock"):
        continue
    if "run_victory_loop.py" in args or "run_runtime_ab.sh" in args:
        continue
    if "victory.exe" in args.lower() or "victory.exe" in comm.lower():
        hits.append(line.strip())
if hits:
    print("\n".join(hits))
    sys.exit(0)
sys.exit(1)
'; then
  echo "ABORT: victory.exe is already running" >&2
  exit 2
fi

BASE_VP="$HOME/.local/share/victory-proton"
case "$MODE" in
  stock)
    PROTON_DIR="$BASE_VP/proton-patched"
    COMPAT_DIR="$HOME/.local/share/victory-proton-stock"
    ;;
  custom)
    PROTON_DIR="$BASE_VP/proton-custom"
    COMPAT_DIR="$HOME/.local/share/victory-proton-custom"
    ;;
  *)
    echo "Invalid --mode '$MODE' (expected stock or custom)" >&2
    exit 1
    ;;
esac

if [ "$REFRESH_PREFIX" -eq 1 ] || [ ! -d "$COMPAT_DIR/pfx" ]; then
  echo "Initializing isolated compat dir ($MODE): $COMPAT_DIR"
  rm -rf "$COMPAT_DIR"
  mkdir -p "$COMPAT_DIR/vkd3d-cache"
  cp -a --reflink=auto "$BASE_VP/pfx" "$COMPAT_DIR/pfx"
  for meta in config_info tracked_files upscaler_files version; do
    if [ -e "$BASE_VP/$meta" ]; then
      cp -a --reflink=auto "$BASE_VP/$meta" "$COMPAT_DIR/$meta"
    fi
  done
  if [ "$MODE" = "stock" ] && [ -d "$BASE_VP/vkd3d-cache" ]; then
    cp -a --reflink=auto "$BASE_VP/vkd3d-cache/." "$COMPAT_DIR/vkd3d-cache/"
  fi
fi

mkdir -p "$COMPAT_DIR/vkd3d-cache"

# runinprefix skips Proton's system32 DLL sync; ensure exact target DLLs in system32
SYS32="$COMPAT_DIR/pfx/drive_c/windows/system32"
if [ "$MODE" = "custom" ]; then
  cp -f "$ROOT/build/x64/d3d12.dll" "$ROOT/build/x64/d3d12core.dll" "$SYS32/"
else
  cp -fL \
    "$BASE_VP/pfx/drive_c/windows/system32/d3d12.dll" \
    "$BASE_VP/pfx/drive_c/windows/system32/d3d12core.dll" \
    "$SYS32/"
fi

KEYS_FILE="/tmp/runtime_keys.txt"
: > "$KEYS_FILE"
: > "$LOG"

export STEAM_COMPAT_DATA_PATH="$COMPAT_DIR"
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$COMPAT_DIR"
export SteamAppId=0
export WINEDLLOVERRIDES="d3d12,d3d12core,dxgi,d3dcompiler_47=n"
export VKD3D_SHADER_CACHE_PATH="${VKD3D_SHADER_CACHE_PATH:-$COMPAT_DIR/vkd3d-cache}"
mkdir -p "$VKD3D_SHADER_CACHE_PATH"
export VKD3D_DEBUG="${VKD3D_DEBUG:-info}"
export VICTORY_KEYS_FILE='Z:\tmp\runtime_keys.txt'
if [ -f /tmp/victory_shader_base.exe ] && [ -z "${VICTORY_SHADER_BUILD_OF:-}" ]; then
  export VICTORY_SHADER_BUILD_OF='Z:\tmp\victory_shader_base.exe'
fi

TITLE_EXE='Z:\home\caullen\Downloads\GTA6\GTA6.Xbox.v1.0.2.1-CYBERLEEK\game_scarlett_master.exe'

setsid "$PROTON_DIR/proton" runinprefix "$EXE" run --execute "$TITLE_EXE" >"$LOG" 2>&1 &
PID=$!

cleanup() {
  kill -- -"$PID" 2>/dev/null || true
  sleep 1
  kill -9 -- -"$PID" 2>/dev/null || true
  WINEPREFIX="$COMPAT_DIR/pfx" "$PROTON_DIR/files/bin/wineserver" -k 2>/dev/null || true
}
trap cleanup EXIT

START=$(date +%s)
SENT_ENTER=0
SENT_AT=0
IN_WORLD_AT=0
GPU_SAMPLES=""

while kill -0 "$PID" 2>/dev/null; do
  NOW=$(date +%s)
  ELAPSED=$((NOW - START))
  if (( ELAPSED > 420 )); then
    echo "TIMEOUT_420S"
    break
  fi

  if (( SENT_ENTER == 0 )); then
    if (( ELAPSED >= 30 )) || grep -qE "\[[89][0-9]{4} [23][0-9]{4}\]" "$LOG" 2>/dev/null; then
      echo "Sending Enter #1 at ${ELAPSED}s"
      echo "Enter" >> "$KEYS_FILE"
      SENT_ENTER=1
      SENT_AT=$NOW
    fi
  elif (( SENT_ENTER == 1 )) && (( NOW - SENT_AT >= 12 )); then
    LAST_LINE=$(tr '\r' '\n' < "$LOG" | grep "fps," | tail -n 1 || true)
    if ! echo "$LAST_LINE" | grep -qE "([89][0-9]{2}|[1-9][0-9]{3}) draws/frame"; then
      echo "Sending Enter #2 at ${ELAPSED}s (last: $LAST_LINE)"
      echo "Enter" >> "$KEYS_FILE"
      SENT_ENTER=2
    fi
  fi

  if (( SENT_ENTER >= 1 && IN_WORLD_AT == 0 )); then
    INW=$(python3 -c '
import re, sys
t = open(sys.argv[1], errors="replace").read().replace("\r", "")
t = re.sub(r"\x1b\[[0-9;]*m", "", t)
lines = [l for l in t.splitlines() if "fps," in l]
if len(lines) >= 2:
    parsed = []
    for l in lines[-2:]:
        m = re.search(r"\[(\d+)\s+(\d+)\]\s+([\d.]+)\s+fps,\s+([\d.]+)\s+ms/frame.*?\b(\d+)\s+draws/frame", l)
        if m:
            parsed.append((int(m.group(1)), float(m.group(3)), int(m.group(5))))
    if len(parsed) == 2 and all(b0 < 5000 and fps >= 0.5 and draws >= 1000 for b0, fps, draws in parsed):
        print(1); sys.exit(0)
print(0)
' "$LOG" 2>/dev/null || echo 0)
    if [[ "$INW" == "1" ]]; then
      IN_WORLD_AT=$NOW
      echo "Detected in-world at ${ELAPSED}s"
    fi
  fi

  if (( IN_WORLD_AT > 0 )); then
    BUSY=$(cat /sys/class/drm/card1/device/gpu_busy_percent 2>/dev/null || echo "?")
    GPU_SAMPLES="$GPU_SAMPLES $BUSY"
    if (( NOW - IN_WORLD_AT >= INWORLD_WAIT )); then
      echo "Finished ${INWORLD_WAIT}s in-world window at ${ELAPSED}s"
      break
    fi
  fi

  sleep 2
done

echo "EXIT_CHECK ELAPSED=$(( $(date +%s) - START ))"
echo "GPU_BUSY_SAMPLES:$GPU_SAMPLES"
echo "--- VKD3D VERSION ---"
echo "ENV VKD3D_CONFIG='${VKD3D_CONFIG:-}' RADV_PERFTEST='${RADV_PERFTEST:-}' VKD3D_SHADER_CACHE_PATH='$VKD3D_SHADER_CACHE_PATH'"
grep -iE 'vkd3d-proton - applicationVersion|vkd3d-proton - build|VKD3D_CONFIG=|VK_EXT_descriptor_heap|vkd3d_memory_info_upload_hvv|Rejecting pipeline library' "$LOG" | head -n 15 || true
echo "--- METRICS ---"
python3 -c '
import re, sys
t = open(sys.argv[1], errors="replace").read().replace("\r", "")
t = re.sub(r"\x1b\[[0-9;]*m", "", t)
lines = t.splitlines()
fps_lines = [l for l in lines if "fps," in l]
inworld = []
for l in fps_lines:
    m = re.search(r"\[(\d+)\s+(\d+)\]\s+([\d.]+)\s+fps,\s+([\d.]+)\s+ms/frame.*?\b(\d+)\s+draws/frame", l)
    if m and int(m.group(1)) < 5000 and int(m.group(5)) >= 1000:
        inworld.append((float(m.group(3)), float(m.group(4))))
if inworld:
    print(f"INWORLD_SUMMARY: intervals={len(inworld)} avg_fps={sum(f for f,_ in inworld)/len(inworld):.2f} ({min(f for f,_ in inworld):.1f}..{max(f for f,_ in inworld):.1f}) avg_ms={sum(ms for _,ms in inworld)/len(inworld):.1f} ({min(ms for _,ms in inworld):.1f}..{max(ms for _,ms in inworld):.1f})")
for l in lines:
    if any(k in l for k in ["fps,", "GPU time", "copied from", "sparse writes", "device removed", "GPUVM", "fault", "FAULT", "a key was asked", "victory::memory", "slow host submission", "queue waited", "title memory used in place", "dropped "]):
        print(l[:260])
' "$LOG" | tail -n 120
