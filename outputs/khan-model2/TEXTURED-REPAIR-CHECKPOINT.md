# Textured kameez repair — 22 September 2026

## User-facing state

The original textured review remains the only user-facing baseline. Its clipping and hand defects are unresolved. No launcher was changed to point to the trials below. Revision 2 remains rejected.

## Saved seam repair

`blender/khan-model2-textured-seam-trial.blend` and `../../game/assets/characters/khan_textured_seam_trial.glb` preserve the original material and UV map. The lower sections were re-extracted to the body's exact 1.035 m cut plane, joined, and 79 coincident waist vertices welded. Six boundary edges remain at that height, so this is not a claim of globally watertight topology. The reconstructed upper trousers were narrowed conservatively.

Godot captures under `inspection/seam-back/` show that the previous broad back-waist gaps are absent in the captured Idle2 pose. `inspection/seam-front/` still shows thigh penetration in Idle2 and Punch. The four clips were exercised for 100 frames each from each view. This is limited pose evidence, not a full animation or collision certification. No new user review was offered.

## Rejected diagnostic experiments

- `scripts/bake_garment_contacts.py` produced `blender/khan-model2-contact-trial.blend` and `khan_contact_trial.glb`. Ray-projected pose corrections imported and animated but visibly distort and tear the garment silhouette in `inspection/contact-front/`. Reject this output. The report's `finite_poses` is not a valid quality result: the old test samples only the disabled spring modifier, not morph-deformed vertices.
- `scripts/native_cloth_idle_test.py` tested a native Blender cloth modifier on an extracted original-UV surface with an armature lead-in and simplified body collider. It is NOT a usable cloth bake. Its cloth bounds expand to metres beyond the body even during settling. Do not export/promote it as an improvement. The saved static snapshot and native trial blend are diagnosis only.
- Extracted surface inspection: initially 2,472 vertices, 2,524 faces, 1,710 boundary edges, 16 non-manifold edges, 63 edges shorter than 0.1 mm and 35 faces below 1e-8 square metres. Coincident welding and degenerate cleanup reduced it to 2,361 vertices, 2,516 faces and 1,501 boundary edges; 16 non-manifold edges remain. Cleanup did not stabilize the simulation. These observations establish mesh problems, but do not isolate the sole cause of instability; collision initialization, pinning and rest-pose transforms still require controlled checks.

## Next work, without repeating failed methods

1. Start from the preserved textured seam trial, not contact shapes or Revision 2.
2. Inspect connected components, boundary loops, and initial cloth/body intersections in the rest pose. Separate collider-only, pin-only, and self-collision tests before recombining them. Stop early on invalid bounds.
3. Repair or locally retopologize the hanging surface while transferring its existing texture detail. Do not use a plain replacement material. Establish an intact, fitted neutral pose before motion.
4. Validate standing and both complete idle loops from front/back/sides before punch/kick. Preserve hands while garment work proceeds; original hand defects remain.
5. Only offer a new launcher after a visibly improved candidate passes those checks. Runtime success, finite control positions, and preserved UV layer names alone are not acceptance.

Blender MCP was unavailable because Blender was not running. The work used the installed Blender 4.5.14 command-line executable on copies of the saved files. No source GLB or baseline review asset was replaced.
