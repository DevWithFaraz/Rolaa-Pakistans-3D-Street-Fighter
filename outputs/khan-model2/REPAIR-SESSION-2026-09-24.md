# Tunic repair session — 24 September 2026

The user accepted the textured seam trial's waist. That accepted baseline and both original GLBs remain preserved. This session uses separate trial files. No launcher or main game scene has been changed.

## Inspection and rejected trial

Blender MCP connects to Blender 4.5.14; the older add-on still supports scene/code/screenshot operations. The baseline was opened after confirming the default scene had no unsaved edits.

The old height-based garment extraction includes inner return surfaces below approximately 0.68 m. Treating these as visible fabric creates excessive clearance demands. A collider selection based only on height also includes hands. Restricting colliders to pelvis/leg weights corrected that selection error.

`smooth_surface_clearance.py` produced `khan-model2-surface-fit-trial.blend` and `khan_surface_fit_trial.glb`. Its original mesh coordinates and UVs are unchanged; it uses 128 added control bones with per-clip baked offsets. Godot exercised all four clips and captured front/back/side samples under `inspection/surface-fit`. This trial is **rejected as a finished garment**: it reduces penetration but flares/stretches the hem too far during attacks. Finite bone transforms are only a numerical check, not visual acceptance.

## Current experiment

`draped_surface_trial.py` starts afresh from `khan-model2-textured-seam-trial.blend`. It uses two separate low-resolution control panels with gravity, length constraints, and bone-following pelvis/leg capsules, then bakes control motion into the four existing animations. The original textured surface follows those controls. This is an offline animation bake, not general runtime cloth.

The first constrained test improved idle silhouettes but retained attack penetration. Inspection identified two additional problems: the previously reconstructed upper trousers extend knee-ring folds to the waist, and point-only collisions let spans of fabric pass through thighs. The current script refits only the artificial upper trouser extension, removes accidentally captured hidden inner return faces, interpolates the existing UVs through local fabric subdivision, initializes controls outside posed legs, and checks contacts along control edges.

Outputs `khan-model2-draped-trial.blend`, `khan_draped_trial.glb`, and `draped_review.tscn` are **internal trials pending visual acceptance**. Earlier captures under `inspection/draped` and `inspection/draped-refit` do not represent the final test until the latest bake is imported and captured again.

Hands/fists have not been changed in this session. Full gameplay integration and performance validation remain pending.

## Final checkpoint before user credit limit

The latest bake completed and was imported and exercised in Godot. Evidence is in `inspection/draped-contact/`: all four complete clips were sampled at 30 fps (253/61/34/50 frame checks), with front/back/side captures at roughly eight intervals. Bone transforms remained finite. This does not certify mesh collision clearance or performance.

Visual result: idle and some punch poses improve, but the high kick still has severe folding, intersections, and an incorrect settled/loop-end shape. **Do not promote this candidate, create a recommended launcher for it, or call the tunic repaired.** No existing launcher was modified. The accepted waist version remains `khan-model2-textured-seam-trial.blend` / `Play Khan Textured Seam Test.cmd`.

The current draped trial has 239 bones; it refits 5,039 artificial upper-trouser vertices. UVs are interpolated through the local subdivision and preserved through subsequent rigging; the report's `uv_unchanged` compares before/after rigging, not against the original topology. Maximum control-edge stretch was approximately 1.13 in idle, 1.18 in punch, and 1.29 in kick. Better control-point metrics did not eliminate visual mesh defects.

Next: inspect/repair the actual garment surface and its binding to the control panels; investigate contact between the rendered surface and shalwar, plus panel self-intersection and loop recovery. Avoid another broad outward-offset approach. Capsule contact and edge-length constraints alone have proved insufficient. Keep source materials and accepted waist join. Hands remain a later task.

User reported 9%, then 5% credit remaining; work stopped after checkpointing. No background bake remains running.
