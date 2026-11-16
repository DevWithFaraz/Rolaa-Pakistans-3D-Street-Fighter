# ADR-0001: Default Renderer & Character LOD0 Triangle Budget

- **Status:** Accepted
- **Date:** 2026-11-16
- **Phase:** P1 — Tech Spikes (`outputs/rolaa-scope-v1.0.md` §5.2, §5.3, §11, §14)
- **Target Baseline Hardware:** Intel Core i5-1135G7 / Intel(R) Iris(R) Xe Graphics (OpenGL 3.3.0 / D3D12 12_0), 1280×720, Godot 4.7.2-stable

---

## 1. Context

Two blockers prevented sustained 60 fps performance in P0:
1. **High-poly character assets:** `khan_recovery_trial.glb` (~293k–310k source tris, 16.74 MB) and `asim_model1.glb` (285k source tris, 16.89 MB) totaled ~578k fighter triangles before stage geometry and directional shadow passes, exceeding the 400k scene triangle budget (`rolaa-scope-v1.0.md` §11.1). Running the 2-fighter benchmark pre-decimation yielded only **28.6 fps** (`35.01 ms` avg, `50.92 ms` p99).
2. **Renderer choice (`gl_compatibility` vs `forward_plus`):** `forward_plus` (D3D12) unlocks AgX tonemapping, volumetric/exponential fog, and SSAO, whereas `gl_compatibility` has lower GPU/VRAM overhead on integrated Iris Xe GPUs.

---

## 2. Character High-to-Low Decimation (`tools/blender/decimate_rigged_fighter.py`)

We built a reusable Blender 4.5 CLI decimation script (`tools/blender/decimate_rigged_fighter.py`) that applies weighted `DECIMATE` (`COLLAPSE`, `delimit={'UV', 'MATERIAL'}`) in rest pose above the `ARMATURE` modifier, preserves UVs and 2K PBR textures, normalizes `BONE_DEFORM` skin weights, and exports clean single-mesh GLBs with all NLA clips intact:
- **Khan (`khan_recovery_trial.glb`):** `292,869 → 65,877` triangles (`77.51%` reduction), `16.74 MB → 6.07 MB`, `0` unweighted vertices, **2,608 / 2,608** repaired `chaak` drape panel vertices 100% preserved, all 4 clips intact (`Idle`, `Idle2`, `Punch`, `MmaKick`).
- **Asim (`asim_model1.glb`):** `284,999 → 61,999` triangles (`78.25%` reduction), `16.89 MB → 6.94 MB`, `0` unweighted vertices, face/cap/5-finger hands/medals/boots protected, all 8 clips intact (`Idle`, `Idle2`, `Punch`, `MmaKick`, `Walk`, `QuadPunch`, `RoundhouseKick`, `Headbutt`).
- **Validation:** Re-imported into Godot and verified **48/48 checks passed** in rendered `--khan-stage-test` (`gl_compatibility`) with finite bone transforms and zero `chaak`/trouser poke-through.

---

## 3. Performance Benchmark Results (1280×720, Intel Iris Xe Graphics)

All post-decimation measurements ran 30 warm-up frames + 240 active combat frames via `game/scripts/perf_benchmark.gd` (`--perf-bench`).

### Uncapped Renderer Comparison (`--disable-vsync`)

| Configuration | Avg FPS | Avg Frame (ms) | p50 (ms) | p95 (ms) | p99 (ms) | Max (ms) | Draw Calls | Avg Prims | VRAM (MB) | RAM (MB) | 60 fps Avg |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Pre-decimation (`gl_compatibility` Medium, VSync ON) | 28.6 | 35.01 | 33.39 | 37.15 | 50.92 | 343.49 | 129 | 274,654 | 135.6 | 76.0 | No |
| `gl_compatibility` Low (no shadows/MSAA/glow) | **298.9** | **3.35** | **2.57** | **6.34** | **16.28** | 28.06 | 82 | 66,774 | 93.6 | 75.8 | **Yes** |
| `gl_compatibility` Medium (shadows + 2x MSAA + glow) | **87.0** | **11.49** | **8.06** | 35.09 | 38.62 | 45.23 | 132 | 197,288 | 116.0 | 76.0 | **Yes** |
| `gl_compatibility` High (shadows + 4x MSAA + glow + fog + ACES) | **64.0** | **15.62** | **11.12** | 43.04 | 54.32 | 71.40 | 140 | 199,711 | 130.0 | 76.0 | **Yes** |
| `forward_plus` D3D12 Medium (shadows + 2x MSAA + glow + fog + AgX) | **68.6** | **14.58** | **12.52** | 24.73 | 30.42 | 34.29 | 131 | 196,505 | 343.8 | 96.4 | **Yes** |
| `forward_plus` D3D12 High (+ SSAO, 4x MSAA) | 16.2 | 61.75 | 60.57 | 84.71 | 96.04 | 98.19 | 137 | 199,780 | 391.8 | 95.6 | **No** |

*(Note: When `VSync` is enabled, cold-start shader/material allocations in un-pooled hit sparks push individual frames over 16.67 ms and snap VSync down to 20–30 fps quantums; under D3D12 `forward_plus`, first-frame PSO compilation produced an `11,863 ms` startup hitch in `bench-post-forward-medium.json`.)*

---

## 4. Decision

1. **Keep `gl_compatibility` as the default renderer** in `game/project.godot`. At 1280×720 Medium on Intel Iris Xe it sustains **87.0 fps** (`11.49 ms` avg, `8.06 ms` median) with **116.0 MB VRAM** (1/3 the VRAM of `forward_plus`) and no D3D12 cold-start shader compilation hitches.
2. **Ship Low / Medium / High presets (`game/scripts/graphics_presets.gd`, `F5` cycle):**
   - **Low** gives **298.9 fps** (`3.35 ms` avg, `16.28 ms` p99) for lower-spec integrated GPUs.
   - **Medium** is the default laptop target (**87.0 fps** avg).
   - **High** delivers **64.0 fps** avg on `gl_compatibility`.
3. **Keep `forward_plus` (D3D12) as an optional higher-tier renderer only without SSAO (`Medium` = 68.6 fps avg):** SSAO at 720p drops Intel Iris Xe to **16.2 fps** (`61.75 ms` avg) and is excluded from integrated-GPU presets.
4. **Lock LOD0 character triangle budget at 40k–70k triangles per fighter** (~62k–66k measured; combined 127,876 tris leaves >270k tris headroom for Mall Road stage geometry, props, and 3D crowd).
5. **Next optimization ticket (P2/P5):** Pool hit-spark meshes/materials in `VFXDirector` (`combat_feedback.gd` currently allocates `StandardMaterial3D.new()` + `SphereMesh.new()` per hit) and optimize directional shadow split count so `Medium` `p99` also drops under `20 ms` with VSync enabled.

---

## 5. Input Latency & Determinism Verification (`--determinism-test`)

Verified on `stage_proof.tscn` via `game/scripts/determinism_check.gd`:
- **Input-to-state latency (NFR-3 ≤ 3 frames):** `1 tick` (`16.7 ms`) measured across `p1_punch`, `p2_kick`, `p1_guard`, and `p1_jump`, with kick hitbox activating on exact startup tick `12`.
- **Fixed-tick determinism (NFR-4):** 180-tick two-player fight sequence produces bit-identical final snapshots and identical per-tick state digests across repeated runs and after mid-match snapshot save/restore at tick `75`.
