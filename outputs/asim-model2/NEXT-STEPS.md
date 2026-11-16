# Asim Jani (`asim-model2`) — Pre-Mixamo Ready & Next Steps

## Completed So Far
1. **Preserved Source & Extracted Textures (`source/`, `textures/`):**
   - Archived `C:\Users\IT\Downloads\military officer 3d model.glb` untouched to `source/asim-model2-original.glb` (`19,988,784` bytes, SHA256 `4560457875D854CF1531EB8B6BEDC117291D6922F1CEC7821F9689D85A6502EB`), decoded `KHR_mesh_quantization` + `EXT_meshopt_compression` to `source/asim-model2-uncompressed.glb` (`source/manifest.json`), extracted raw `4096x4096` maps (`textures/raw_4k/`), and generated `2048x2048` PBR maps (`Asim2_Working_basecolor.jpg`, `Asim2_Working_rm.jpg`, re-normalized `Asim2_Working_normal.jpg`).
2. **Blender Working Prep (`scripts/prepare_working.py` -> `blender/asim-model2-working.blend`):**
   - Rotated `-90 deg` around `Z` so the character faces `-Y` with `+Z` up and boots grounded at `Z = 0.0`, scaled uniformly to `1.8000 m` height (`0.735718 x 0.379423 x 1.800000 m`).
   - Exact-position weld (`dist = 1e-6`), preserving `UVMap`: `984,618 -> 954,801` vertices, `1,909,608` triangles (`boundary_edges: 0`, `nonmanifold_edges: 0` in `inspection/working-preparation.json`).
3. **Armpit Release, 36° A-Pose & Targeted Decimation (`scripts/build_optimization_trial.py` -> `blender/asim-model2-optimization-trial.blend`):**
   - Released the upper-sleeve/rib bridge cleanly via medial bisect (`z = 1.130..1.285 m`), separate torso/arm caps with planar micro-UVs, inward torso tucking to avoid protruding rib lips, and smooth `36.0°` symmetric A-pose abduction per arm (`max_armpit_edge_growth_m: 0.0101 m`, `0` edges stretched `> 3 cm`).
   - Kept natural inward palms & forward thumbs (no extra pronation needed).
   - Applied weighted `Decimate Collapse` (`CollapsePriority` `0.16..0.68`, `ratio = 0.078968`): `1,924,824 -> 152,000` triangles (`76,009` vertices, `92.1%` reduction, `1.373572 x 0.379354 x 1.800014 m`), preserving `head_cap` (`28,560`), `torso_tunic` (`65,837`), `legs` (`21,530`), `footwear` (`20,625`), `arms_hands_abducted` (`13,813`), and `shoulders_upper_sleeves_other` (`1,635`).
   - Inspected `inspection/trial-front-ortho.png`, `inspection/trial-armpit-hand.png`, and annotated `inspection/mixamo-marker-guide.png` (`inspection/optimization-trial.json`).
4. **Mixamo Mesh-Only FBX & Round-Trip Verification (`scripts/export_mixamo_fbx.py` -> `mixamo/Asim_Model2_Rigging_Trial.fbx`):**
   - Exported rig-free, animation-free FBX (`6,446,636` bytes / `6.15 MB`, `embed_textures: true`, `bake_anim: false`, `axis_forward='-Z'`, `axis_up='Y'`, `object_types: ["MESH"]`) recorded in `inspection/mixamo-export.json` — matching `Khan_Model2_Rigging_Trial.fbx` standard Mixamo FBX axes (`UpAxis: 1`, `UpAxisSign: 1`, `FrontAxis: 2`, `FrontAxisSign: 1`, `CoordAxis: 0`, `CoordAxisSign: 1`).
   - Verified via clean `--factory-startup` Blender 4.5.14 LTS CLI round-trip (`inspection/fbx-roundtrip.json`): `passed: true`, `meshes: 1`, `armatures: 0`, `rotation_euler: [0, 0, 0]`, `triangles: 152,000`, `vertices: 76,009`, `dimensions_m: [1.373572, 0.379354, 1.800014]`, `uv_layers: ["UVMap"]`, `Asim2_Working_Material`, and packed `2048x2048` `Asim2_Working_basecolor` + `Asim2_Working_normal` textures intact.

---

## Your Manual Step: Mixamo Auto-Rig & Downloads
1. Upload:
   `C:\Users\IT\Documents\Codex\2026-09-14\it-s-time-to-get-serious\outputs\asim-model2\mixamo\Asim_Model2_Rigging_Trial.fbx`
2. Place Auto-Rigger markers following **`inspection/mixamo-marker-guide.png`** (`Use Symmetry` ON):
   - **Chin**: underside center of chin (`z ≈ 1.509 m`, above the red collar)
   - **Wrists**: sleeve cuff / wrist crease (`z ≈ 0.971 m`)
   - **Elbows**: mid-sleeve bend (`z ≈ 1.195 m`)
   - **Knees**: center of kneecaps (`z ≈ 0.475 m`)
   - **Groin**: place **inside the lower tunic midline** at the true anatomical pelvic hinge (`z ≈ 0.86 m`, well above the bottom coat hem — **not** down at the coat skirt edge)
   - Choose **`Standard Skeleton (65 bones)`** so Mixamo rigs all 5 fingers on both hands.
3. Download into `C:\Users\IT\Documents\Codex\2026-09-14\it-s-time-to-get-serious\outputs\asim-model2\mixamo\downloads\`:
   - `Asim_Model2_Rigged_TPose.fbx` (**FBX Binary, With Skin, T-Pose**)
   - Combat clips matching Khan (**FBX Binary, Without Skin, 30 fps, Keyframe Reduction: None**):
     - `Asim_Model2_Idle.fbx`
     - `Asim_Model2_Idle2.fbx`
     - `Asim_Model2_Punch.fbx`
     - `Asim_Model2_MmaKick.fbx`

---

## After Downloads Arrive (Post-Mixamo Steps)
1. Validate rest-pose alignment across `Asim_Model2_Rigged_TPose.fbx` and all downloaded animation `.fbx` clips (`rest_matrix_max_difference == 0.0`, `65`-bone Mixamo hierarchy).
2. Transfer/normalize weights back onto restored high-detail geometry + re-hook all three `2048x2048` PBR maps (`Asim2_Working_basecolor`, `Asim2_Working_rm`, `Asim2_Working_normal`).
3. Lock rigid weights on the cap/medals/belt/sash/epaulettes and verify silhouette + bone finite checks inside an isolated Godot `gl_compatibility` review scene before mounting onto the playable stage.
