# Asim Jani (`asim-model1`) — Pre-Mixamo Ready & Next Steps

## Completed So Far
1. **Preserved Source:** Copied `C:\Users\IT\Downloads\Asim Jani 3D model.glb` untouched to `source/asim-model1-original.glb` (`19,539,000` bytes, SHA256 `8DF55B59...`), recorded in `source/manifest.json`, and losslessly unpacked `EXT_meshopt_compression` + `KHR_mesh_quantization` via `@gltf-transform` + `meshoptimizer` to `source/asim-model1-uncompressed.glb`.
2. **Blender Working Prep (`scripts/prepare_working.py` -> `blender/asim-model1-working.blend`):**
   - Rotated `-90 deg` around `Z` so Asim faces `-Y` with `+Z` up and feet grounded at `z = 0.0`.
   - Scaled uniformly to `1.8000 m` height (`1.3622 x 0.3803 x 1.8000 m`), applied transforms.
   - Exact-position weld (`dist = 1e-6`), preserving `UVMap`: `1,004,813 -> 978,896` vertices, `1,957,791` triangles kept (`boundary_edges: 51,501 -> 2`).
   - Extracted raw `4096x4096` maps (`textures/raw_4k/`) and generated crisp `2048x2048` PBR maps (`Asim_Working_basecolor.jpg`, `Asim_Working_rm.jpg`, re-normalized `Asim_Working_normal.jpg`).
3. **Targeted Optimization Trial (`scripts/build_optimization_trial.py` -> `blender/asim-model1-optimization-trial.blend`):**
   - Weighted `Decimate Collapse` (`ratio = 0.07764`) preserving head/cap/face (`27,599` tris), 5-fingered hands (`16,631` tris), medals/belt/sash/joints/tunic (`68,926` tris), footwear (`16,055` tris), and clean leg rings (`22,758` tris) totaling **`152,001` triangles** (`92.24%` reduction), clearing stale custom split normals and enabling smooth shading (`trial-face.png`, `trial-hand-left-smooth.png`, `trial-hand-right.png`, `trial-feet.png`).
4. **Forearm Pronation & Mixamo Mesh-Only FBX (`scripts/fix_arm_pronation.py` + `scripts/export_mixamo_fbx.py` -> `mixamo/Asim_Model1_Rigging_Trial.fbx`):**
   - Pronated left & right forearms/hands (`±90°` across elbow-to-cuff, `9,941` vertices moved) so palms face down/inward (`-Z` / `∓X`) and thumbs point forward (`-Y`) to match Mixamo's expected A-pose bind orientation (`inspection/pronated-hand-left.png`, `inspection/pronated-hand-right.png`, `inspection/pronated-front-ortho.png`).
   - Generated annotated marker guide: `inspection/mixamo-marker-guide.png`.
   - Exported rig-free, animation-free FBX (`6,611,628` bytes, `152,001` tris, `76,001` verts, `1.318722 x 0.380307 x 1.799966 m`) with embedded `2048x2048` `basecolor` + `normal` maps and standard Mixamo FBX axes (`axis_forward='-Z'`, `axis_up='Y'` -> `UpAxis: 1`, `FrontAxis: 2`, `CoordAxisSign: 1`, matching `Khan_Model2_Rigging_Trial.fbx`).
   - Verified via clean Blender 4.5.14 LTS CLI round-trip (`inspection/fbx-roundtrip.json`, `passed: true`, `rotation_euler: [-0.0, 0.0, 0.0]`, `head_y_range: [-0.1785, 0.1412]`).

---

## Your Manual Step: Mixamo Auto-Rig & Downloads
1. Upload the refreshed file:
   `C:\Users\IT\Documents\Codex\2026-09-14\it-s-time-to-get-serious\outputs\asim-model1\mixamo\Asim_Model1_Rigging_Trial.fbx`
2. Place Auto-Rigger markers following **`inspection/mixamo-marker-guide.png`** (`Use Symmetry` ON):
   - **Chin**: right on the underside of the chin (above the red collar)
   - **Wrists**: right at the sleeve cuff / palm crease
   - **Elbows**: mid sleeve bend
   - **Knees**: center of kneecap
   - **Groin**: place **inside the coat** around true hip/crotch height (`z ≈ 0.87 m`, just above the coat bottom edge) — **not** down at the coat hem (`z ≈ 0.79 m`)
   - Choose **`Standard Skeleton (65 bones)`** so Mixamo rigs all 5 fingers.
   - *(Expect minor coat hem/sash flexing in Mixamo's raw browser preview; as long as arms, hands, torso, and legs bend cleanly at joints, coat/badge weights will be locked cleanly in Blender next.)*
3. Download into `C:\Users\IT\Documents\Codex\2026-09-14\it-s-time-to-get-serious\outputs\asim-model1\mixamo\downloads\`:
   - `Asim_Model1_Rigged_TPose.fbx` (**FBX Binary, With Skin, T-Pose**)
   - Core combat clips matching Khan (**FBX Binary, Without Skin, 30 fps, Keyframe Reduction: None**):
     - `Asim_Model1_Idle.fbx`
     - `Asim_Model1_Idle2.fbx`
     - `Asim_Model1_Punch.fbx`
     - `Asim_Model1_MmaKick.fbx`
   - *(Optional bonus if you want full state coverage right away: Walk Forward, Walk Backward, Jump, Block/Guard, Hit Reaction, Knockdown/KO.)*

---

## After Downloads Arrive (Next Automated Steps)
1. Inspect imported `TPose.fbx` (`65`-bone rig check) + verify rest pose compatibility across all downloaded animation `.fbx` files (`rest_matrix_max_difference == 0.0`).
2. Transfer Mixamo skin weights cleanly onto a sharp game-budget mesh (`~250K–300K` tris, restoring `Asim_Working_rm.jpg` metallic/roughness map + high-detail face/cap/hands/medals/footwear).
3. Paint/lock rigid weights on **officer cap -> `Head`**, **belt/medals/sash -> `Spine1`/`Spine2`/`Hips`**, check **shoulder boards** & **short tunic hem** clearance during `Punch` and `MmaKick`.
4. Pack actions & export `game/assets/characters/asim_model1.glb` -> run `Godot --headless --import` -> verify in isolated `gl_compatibility` inspection scene before mounting P2 onto the stage!
