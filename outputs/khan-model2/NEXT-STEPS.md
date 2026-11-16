# Khan Model 2 — garment and motion review

Latest update (`repair_chaak_and_clearance.py`): Side-slit (`chaak`) webbing and `MmaKick` thigh poke-through have been repaired on `blender/khan-model2-recovery-trial.blend` and `../../game/assets/characters/khan_recovery_trial.glb` (`uv_unchanged: true`, double-sided garment material, cross-leg trouser weights fixed, `0` overlaps across all 13 sampled frames in `inspection/recovery-surface-audit.json`, and verified in Godot 4.7.2 `gl_compatibility` captures under `inspection/recovery-review/`). See `REPAIR-SESSION-2026-09-26.md` for full metrics and details. Remaining unfinished items below (hands/fingers, upper trouser UVs, hair flecks, LOD/triangle budget, and gameplay integration) remain open.

22 September work checkpoint: `TEXTURED-REPAIR-CHECKPOINT.md`. The waist repair improved the captured back view, but front penetration remains. Further contact and cloth tests failed visual validation; none replaced the review launcher.

20 September recovery: Revision 2 was rejected for visual regressions. Use the original textured review below as the recovery baseline. Its original clipping and hand issues still need repair. See `REVISION-2-CHECKPOINT.md` for the rejected experiment and resume constraints.

18 September 2026. Budget: $0. The actual selected character is now rigged and animated in an isolated Godot review scene. This is an asset experiment, not a finished combat character.

## Your next action

Open `../Play Khan Garment Review.cmd`. No more Mixamo downloads or model uploads are needed for this checkpoint.

- **1 / 2:** the two downloaded idles.
- **3:** punch. **4:** MMA kick.
- **C:** compare garment motion enabled/disabled.
- **T:** gentle sideways movement to expose garment inertia.
- **Space:** pause the body animation; the garment can settle.
- **Q / E:** turn the review camera. **Mouse wheel:** zoom.
- **Home:** reset garment motion. **Esc:** close.

First watch idle 2, then the kick from front and side. The review uses the real character, restored sandal geometry, original textures and downloaded motions. It does not change the main combat prototype. The studio camera is not the final gameplay camera.

## Completed since the T-pose checkpoint

All five FBX files are present in `mixamo/downloads/`: T-pose, Idle, Idle2, Punch and MmaKick. Blender inspection found matching body bone names and rest transforms. The four motion clips play in Godot Compatibility on the laptop's Iris Xe GPU.

The first 151,826-triangle reduction visibly damaged the sandals and some clothing folds. The separate 284,676-triangle quality candidate restored the original head, hands and entire footwear region, retaining more clothing detail. Checks of 85,031 protected vertices found zero coordinate displacement. The original roughness/metalness map was restored alongside the original color and normal maps. Body weights were transferred from the Mixamo rig; normalized weights alone do not guarantee good deformation.

Baseline kick inspection confirmed that the original leg weights pull the long tunic into a stretched triangle. The current garment experiment:

- Separates the hanging front and back into two meshes, retaining their original per-face UVs.
- Attaches their upper edges to the body and gives the lower fabric separate garment bones.
- Uses two three-bone chains for coherent front/back movement. Twelve unused guide bones remain from an earlier experiment; the total skeleton has 59 bones, including the 41 Mixamo body bones.
- Uses Godot secondary motion with gravity, damping and thigh/hip collision shapes, blended lightly with the controlled garment pose.
- Adds a pose-dependent lift before secondary motion to help a raised thigh clear the broad panel. This is a controlled animation correction, not full cloth simulation.
- Reconstructs the missing upper trousers. The first overlapping tubes were replaced with geometry joined directly to the original trouser boundaries. The new upper section uses stretched boundary UVs and remains unfinished artwork.

The runtime garment motion is in the Godot scripts. Opening the Blender file alone does not reproduce the Godot gravity simulation. The current three-mesh trial totals 309,860 triangles after the trouser reconstruction; this is a quality/deformation candidate, not a final optimized game mesh. All vertices have normalized skin weights, which is a structural check rather than visual approval.

## Current files

- `blender/khan-model2-garment-trial.blend`: current separate garment experiment, body, skeleton and four actions.
- `../../game/assets/characters/khan_garment_trial.glb`: exported character and clips used by the review scene.
- `../../game/scenes/garment_review.tscn`: isolated engine review.
- `../../game/scripts/garment_review.gd`: review controls, environment, secondary-motion setup and checks.
- `../../game/scripts/kameez_clearance.gd`: pose-dependent panel clearance.
- `blender/khan-model2-rig-review.blend`: preserved pre-garment rig and quality comparisons.
- `blender/khan-model2-working.blend`: preserved original cleanup/reversible reduction.
- `source/`: untouched copies of both original GLBs and their hash manifest.
- `textures/`: unchanged source texture bytes.
- `scripts/`: preparation scripts. These are checkpoint-specific; do not rerun all of them blindly over the current trial.

Both original Downloads GLBs and the preserved source copies still match their recorded SHA-256 hashes. Verification: `inspection/original-verification-garment.json`.

## Evidence and limits

`inspection/runtime/` contains Godot captures and a runtime report for the current enabled garment. `inspection/cloth-disabled/` is the no-motion comparison. The report samples the solver result during the modifier's completion signal, before influence blending, and includes the pose correction; it is not a measurement of pure visible sway. Earlier rest-pose offset reports should not be interpreted as cloth movement. These fixed-step checks exercise import, animation and finite transforms. They do **not** establish sustained 60 fps, collision-free fabric, or completed art quality.

`inspection/baseline-*.png` records the original body-weighted garment problem. `inspection/sewn-trousers.json` records the continuous joins. `inspection/garment-export.json` records export structure. Earlier grid-panel and six-chain experiments are superseded, although their evidence files remain for traceability.

Still unfinished:

- Garment/body intersections at demanding poses, upper attachment and side-slit finish. Lightweight bone collisions do not cover the full cloth surface.
- The reconstructed upper trousers need proper surface detail and final UV work.
- Underarm/shoulder deformation and merged/touching fingers. Mixamo supplied thumb/index chains only; middle/ring/little finger chains are absent. No full hand repair has been claimed.
- Hair texture flecks, final lighting/material tuning and the final triangle budget.
- Gameplay-camera assessment, combat animation timing, hit alignment and sustained performance testing.

Next development step: refine garment clearance/finish and hands, then put the visual character into a separate copy of the existing stage for gameplay-distance checks. Preserve combat state and timing rules. The proxy is roughly 3.5 units tall while this asset is authored around 1.8 m; choose scene scaling deliberately because secondary-motion rigs are sensitive to skeleton scaling.

The two idles, punch and kick are pipeline tests. The intended game retains varied, character-specific attacks.

Implementation references: [Godot SpringBoneSimulator3D](https://docs.godotengine.org/en/stable/classes/class_springbonesimulator3d.html), [SkeletonModifier3D](https://docs.godotengine.org/en/stable/classes/class_skeletonmodifier3d.html), and [capsule collisions](https://docs.godotengine.org/en/stable/classes/class_springbonecollisioncapsule3d.html).
