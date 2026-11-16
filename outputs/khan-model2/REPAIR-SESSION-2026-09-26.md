# Tunic repair checkpoint — 26 September 2026 (Updated with Chaak & Clearance Repair)

## Result

The side-slit (`chaak`) webbing repair and panel-separated thigh-clearance bake (`scripts/repair_chaak_and_clearance.py`) resolves the protruding side-slit triangular flap, floating ribbon edges, and `MmaKick` thigh poke-through while retaining 100% of the original PBR textures/UVs (`uv_unchanged: true`) and the accepted waist seam (`z = 1.035`).

**Key fixes implemented:**
- **Side-slit (`chaak`) geometry cleanup (`clean_chaak_and_subdivide`):** Removed the scanned inward side-slit pocket wall, recessed trouser triangles, and 6 disconnected under-hem/crotch return islands; symmetrically bisected both the Front (`y = -0.055 -> -0.040`) and Back (`y = +0.035 -> +0.020`) `chaak` boundaries; pruned dangling boundary ear triangles; subdivided long panel edges; and triangulated N-gons, yielding two clean single sheets (`front_faces: 1973`, `front_vertices: 1154`; `back_faces: 2522`, `back_vertices: 1455`) with zero shared vertices below the waist seam.
- **Separate Front/Back control cage (`build_rest_grid`, `map_vertex_to_cage`, `HALF_FRONT = HALF_BACK = 0.42*pi`):** Explicitly mapped vertices by topological panel membership instead of `co.y <= 0` so boundary vertices never bridge across the side slit (`max_control_edge_stretch`: `Idle` 1.1080, `Idle2` 1.1078, `Punch` 1.1833, `MmaKick` 1.3760).
- **Double-sided material export:** Disabled backface culling (`use_backface_culling = False`) on `Khan_Working_Material.001` so the interior sides of the single-sheet `chaak` panels render solidly during punches and kicks instead of culling to thin edge ribbons.
- **Cross-leg trouser weight de-bleed & groin clearance (`refit_upper_trousers`, `get_tapered_capsules`):** Removed opposite-leg skin weight bleeding (`LeftUpLeg`/`RightUpLeg`, `LeftLeg`/`RightLeg`) on trouser vertices, extended radial upper-trouser refitting down to `z = 0.43` (`14,617` vertices refitted), and added pelvis-to-mid-thigh groin bridge capsules plus back-panel collision bias.

## Verification

- **Overlap audit (`scripts/audit_recovery_surface.py` -> `inspection/recovery-surface-audit.json`):** `0` overlapping garment/trouser face pairs across all 13 sampled frames (`Idle2` frames 1, 30, 60; `Punch` frames 1, 12, 24, 32; `MmaKick` frames 1, 10, 18, 26, 36, 49).
- **Godot 4.7.2 `gl_compatibility` multi-angle capture (`inspection/recovery-review/`):** Re-imported `game/assets/characters/khan_recovery_trial.glb` and rendered `res://scenes/recovery_review.tscn` across all 4 clips (`Idle`: 253 frames, `Idle2`: 61 frames, `Punch`: 34 frames, `MmaKick`: 50 frames; `bone_count: 239`, `finite_bone_transforms: true`). Visual inspection of front, side, and back PNGs (`Idle`, `Idle2`, `Punch`, `MmaKick`) confirms clean `chaak` separation, no protruding side triangle (`Screenshot 2026-09-26 013650.png` / `014017.png`), no detached ribbon strips, no front-panel puncture (`MmaKick_side_024.png`), and smooth recovery.

## Saved work

- `scripts/repair_chaak_and_clearance.py`: reproducible chaak cleanup, cross-leg trouser de-bleed, 18x10 separated drape bake, and double-sided GLB export run from `blender/khan-model2-textured-seam-trial.blend`.
- `blender/khan-model2-recovery-trial.blend` and `game/assets/characters/khan_recovery_trial.glb`: updated four-clip asset (`inspection/recovery-trial-build.json`).
- `game/scenes/recovery_review.tscn`: isolated internal review (`visual_acceptance` flag in `runtime-check.json` remains harness-default `false`).
- Preserved untouched baseline: `blender/khan-model2-textured-seam-trial.blend` and `source/` GLBs.

## Remaining scope (unchanged from milestone plan)

Hands/fingers (`middle/ring/little` chains absent in Mixamo), upper trouser texture/UV polish, hair flecks, triangle-budget optimization, and gameplay-camera combat integration remain separate next-stage tasks.
