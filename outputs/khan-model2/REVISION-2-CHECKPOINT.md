# Khan cloth and hands — 20 September checkpoint

REJECTED by the user on 20 September: lost garment texture continuity, visible waist join, resting lift/folding and misaligned curled fingers. Do not present this version as an improvement. The Revision 2 launcher now redirects to the preserved original textured review. The failed Blender and GLB assets remain available for diagnosis only.

Recovery baseline: `blender/khan-model2-garment-trial.blend`, engine asset `../../game/assets/characters/khan_garment_trial.glb`, and `../Play Khan Garment Review.cmd`. This baseline still has the earlier clipping and hand defects; restoring it is not completion of those repairs.

The next candidate must preserve original garment textures and continuity. Validate neutral front/back/side views before dynamics, then inspect each hand and its fist independently. Do not offer a candidate that fails those visual checks. If changing topology, retain or properly transfer the existing UVs/material detail; a plain replacement material is not acceptable.

## Saved work

- Blender: `blender/khan-model2-cloth-hands-v2.blend`.
- Engine asset (relative to this directory): `../../game/assets/characters/khan_cloth_hands_v2.glb`.
- Isolated Godot scene: `res://scenes/garment_review_v2.tscn`.
- Original GLBs and the first garment review remain preserved. The main fighting scene and existing review launcher were not replaced.

The working hands have narrow geometric separations and 24 additional finger bones. Original thumb weights were blended continuously into the new finger weights to avoid a hard boundary. Both hands still need close-up inspection, rounding at the finger webs, and a more convincing closed-fist pose; this is not a finished hand asset.

The two experimental hanging panels now have regular surfaces (1,221 vertices each). Their attachment weights are restricted to torso bones. An initial radial sampling trial picked up nearby arm geometry and produced arm-driven shirt stretching; the sampling radius and attachment weights were corrected. The lower panels currently use a plain provisional cream material, so their finish does not yet match the original textured upper garment.

## Actual validation

The revised GLB imported into Godot and ran the four clips for 100 frames each at a fixed simulation step. The run exited successfully with finite cloth-control positions. This is a short regression check, not a complete animation sweep, collision proof, or performance benchmark.

Evidence: `inspection/v2-runtime/Idle.png`, `Idle2.png`, `Punch.png`, `MmaKick.png`, and `runtime-check.json`. Latest run is 20 September around 22:59 local time.

Visual review still FAILS the requested cloth finish: the back lifts too far, the waist transition is visible, the shalwar intersects the fabric, and the kick produces unacceptable folded/intersecting surfaces. Finite solver positions do not establish that the rendered mesh stays outside the body. Do not promote this revision as collision-free or production-ready.

## Resume here

1. Inspect the saved revision and latest runtime captures before modifying it.
2. Correct the waist attachment and the relationship between rendered cloth and its collision surface. The current solver uses only two 5-by-6 point grids and capsule proxies; it does not resolve every rendered triangle or self-collision.
3. Inspect the reconstructed upper shalwar separately; its stretched detail and silhouette are also unfinished.
4. Finish both finger webs, thumb transitions and a closed fist, then inspect idle and punch from both sides.
5. Export and test full clips, transitions, back views and motion before offering a replacement review.

Relevant scripts: `scripts/regular_fabric_v2.py`, `scripts/separate_fingers_v2.py`, `scripts/rig_fingers_v2.py`, `scripts/blend_thumb_weights_v2.py`; game scripts `kameez_fabric_grid.gd` and `garment_review_v2.gd`. Do not rerun the one-time finger creation scripts on an already modified mesh/rig.
