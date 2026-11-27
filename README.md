# Victory Proton & vkd3d-proton Runtime (`victory-cachyos-radv-runtime`)

Custom Wine (`ntdll.so`, `winevulkan`) and `vkd3d-proton` (`d3d12.dll`, `d3d12core.dll`) patches and isolated Proton A/B harnesses tailored for running the [`CaullenOmdahl/Victory`](https://github.com/CaullenOmdahl/Victory) Xbox Series X -> Windows/DX12 recompiler on **CachyOS Linux + Mesa RADV** (**AMD Ryzen 9 5900X + Radeon RX 6800 16 GB ReBAR**).

## Source Forks
- **Wine (`cachyos-11.0-20261015-native` base):** [`CaullenOmdahl/wine-cachyos-victory-radv`](https://github.com/CaullenOmdahl/wine-cachyos-victory-radv) (`branch: victory-radv-rx6800`)
- **`vkd3d-proton` (`3.2.0` `71cae09` base):** [`CaullenOmdahl/vkd3d-proton-victory-radv`](https://github.com/CaullenOmdahl/vkd3d-proton-victory-radv) (`branch: victory-radv-rx6800`)
- **Minimal Patch Exports:** [`patches/wine-cachyos/`](patches/wine-cachyos/) and [`patches/vkd3d-proton/`](patches/vkd3d-proton/)

## Build & A/B Usage
- **Build custom `vkd3d-proton` DLLs (`d3d12.dll`, `d3d12core.dll`):** `./scripts/build_vkd3d.sh` (throttled `nice -n 19 ionice -c 3 ninja -j4`, stages into `./build/x64/` and isolated `proton-custom`).
- **Build custom Wine `ntdll.so`:** `./scripts/build_ntdll.sh` (throttled `nice -n 19 ionice -c 3 make -j4`, outputs `./build/x64/ntdll.so`).
- **Serialized A/B Harness:** `flock /tmp/victory_gpu.lock ./scripts/run_runtime_ab.sh --mode stock|custom --exe <snapshot.exe> --wait 90 --log <logfile>` (uses isolated `STEAM_COMPAT_DATA_PATH` and `VKD3D_SHADER_CACHE_PATH`).

## Measured Runtime Uplift Log (Settled `[0 0]`, Warm Cache, Zero Faults)

| Loop | Subsystem & Change | Victory Target & Flags | Stock (`proton-patched` + `30b0eb9`) | Custom (`proton-custom` + `71cae091b`) | Key Deltas (`prep` / `copies` / `watches`) | Status |
|---|---|---|---|---|---|---|
| **R2** | `vkd3d-proton` baseline (`71cae091b`) | `victory-r2-snapshot.exe` (Loop 120) | `3.7 fps` (`269.0 ms/f`) | `3.8 fps` (`264.0 ms/f`) | Parity baseline (`~130–134 ms` GPU, `0` faults) | Baseline |
| **R3–R6** | `VKD3D_CONFIG` matrix + `vkQueueSubmit2` / barrier coalescing (`-36%` barriers) | `victory-r2-snapshot.exe` (Loop 120) | `3.8–3.9 fps` | `3.8 fps` (`261.4–262.6 ms/f`) | `0` FPS gain (`124.5 ms` sync `vkWaitSemaphores` GPU-bound) | Reverted cleanly |
| **R7–R9** | Wine `ntdll.so`: `vm_tree_state` rwlock + `vm_prot` + AVX2 `get_vprot_range_size` + TEB deferred signals | `victory-r2-snapshot.exe` (Loop 120, `--wait 90` clean) | `3.8–3.9 fps` (`254.2–262.5 ms/f`) | **`4.0–4.1 fps` (`243.5–250.9 ms/f`)** (`+7.9%` FPS) | `prep` `92.6–98.0 -> 83.5–86.0 ms`, `copies -27%`, `watches -28%` | Kept (`fcc7914`) |
| **R10–R11** | Wine `ntdll.so`: `ThreadTimes` `getrusage(RUSAGE_THREAD)` fast path + `set_vprot` no-op `mprotect` elision | `victory-s4-snapshot.exe` (`b9b431d`, `S1–S4`, `--wait 90` clean) | `3.8–4.0 fps` (`252.1–260.4 ms/f`) | **`4.1–4.2 fps` (`237.5–245.9 ms/f`)** | `prep` `89.7–91.3 -> 78.5–81.1 ms`, `copies` `236–244 -> 159–168 ms`, `watches -35%` | Kept (`fcc7914`) |
| **R12–R13** | Wine `ntdll.so`: 128-way 2 MiB `vm_prot_stripes` + lockless `PAGEMAP_SCAN` dispatch | `victory-s8p1-snapshot.exe` (`622e793`, `S1–S6`, `--wait 90` clean) | `4.0 fps` (`247.5 ms/f`) | **`4.2–4.3 fps` (`230.0–236.6 ms/f`)** (`+7.5%` FPS) | `prot lock` `59–69 -> 8.8–10.9 ms` (`>6x`), `prep -10%`, `copies -34%`, `watches -31%` | Kept (`fcc7914`) |
| **R14** | `vkd3d-proton`: `VK_KHR_map_memory2` + `VK_EXT_map_memory_placed` wiring + full-stack `VICTORY_CCD=1` | `victory-s10-snapshot.exe` (`c9e6bd0`, `S1–S6` + `CCD`, `--wait 90` clean) | `4.6–5.0 fps` (`200.0–216.7 ms/f`) | **`5.0–5.3 fps` (`188.9–200.0 ms/f`)** (`188.9 ms` final) | `prep` `77.4–84.3 -> 67.3–72.0 ms` (`-12%`), `copies -33%`, `watches -38%` | Kept (`029eec9`) |
| **R15** | Wine `winevulkan` / `win32u`: unblocked `VK_EXT_map_memory_placed` (`memoryMapPlaced=1`, `memoryUnmapReserve=1`) natively | `victory-s10-snapshot.exe` (`c9e6bd0`, `S1–S6` + `CCD`, `--wait 90` clean) | `4.6–5.0 fps` (`200.0–216.7 ms/f`) | **`4.9–5.3 fps` (`188.9–203.3 ms/f`)** | `prep` `67.8–74.1 ms`, `copies` `148.9–176.9 ms`, `watches` down to `338.35 ms`, `0` faults | Kept (`e38c477`) |
| **R16** | Wine `ntdll.so`: `vm_tree_seq` seqlock `AV` fast path + TEB 4-slot `vm_mru` cache + lockless WW check + `class 7` `RegionType` | `victory-s10-snapshot.exe` (`c9e6bd0`, `S1–S6` + `CCD`, `--wait 90` clean) | `4.6–5.0 fps` (`200.0–216.7 ms/f`) | **`4.8–5.4 fps` (`186.1–210.0 ms/f`)** (**`5.4 fps / 186.1 ms` peak**) | `prep` `65.2–74.6 ms`, **`copies` `118.9–131.9 ms` (`-42%`)**, `watches` `363–523 ms`, `0` faults | Kept (`0be2db5`) |
| **R17** | Wine `ntdll.so`: lockless `fill_basic_memory_info` MRU fast path + `NtGetWriteWatch` `rgns[32]` (`768 B`) stack shrink | `victory-s10-snapshot.exe` (`c9e6bd0`, `S1–S6` + `CCD`, `--wait 90` clean) | `4.6–5.0 fps` (`200.0–216.7 ms/f`) | **`4.8–5.4 fps` (`183.5–210.1 ms/f`)** (**`5.4 fps / 183.5 ms` peak**; **`5.5 fps / 183.3 ms`** stats) | `prep` `67.0–73.4 ms`, `watches` **`372.0–466.7 ms`** (tighter variance), `multi=0`, `0` faults | Kept (`ntdll-victory-r17.patch`) |
