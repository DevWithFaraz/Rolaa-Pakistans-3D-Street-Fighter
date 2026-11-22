# Pakistani Fighter — Living Game Design Document

Version 0.1, revision 6 · 18 September 2026 · Pre-production and prototype

This is the initial working design, not a frozen specification. **Confirmed** means agreed by the user; **Proposed** means a concrete starting point to review or playtest; **Experiment** means a choice awaiting evidence. Update this document after each meaningful test. Unresolved choices are not silently treated as approvals.

## 1. Game vision

**Confirmed:** A desktop 2.5D fighting game featuring recognizable, stylized Pakistani public-figure characters, expressive performance, local settings, and a humorous tone. Fighters and the playable ground are 3D; movement stays on a fighting plane.

The first roster is **Khan Sahab** and **Asim Jani**, using the user's supplied reference sheets. The user has accepted their fairly natural proportions and stylized realism. Do not automatically enlarge heads or redesign costumes to match the earlier caricature discussion.

The supplied gameplay-camera mockup establishes a Lahore street composition, a decorated bus, spectators, warm daylight, and truck-art-inspired HUD. It is a visual reference, not evidence of achievable real-time performance or verified architectural accuracy.

### Design priorities

- Responsive, readable combat that remains enjoyable after the initial recognition and humor.
- Recognizable faces, contrasting costumes, characteristic posture and expressive entrances.
- Cohesive Pakistani street atmosphere and interface design.
- A small, finished match on the user's hardware before expanding the roster.

## 2. Confirmed foundations and current evidence

- Engine choice: Godot Standard with GDScript and Compatibility rendering.
- Asset authoring: Blender, assisted through MCP and scripts; reusable assets and animation are welcome.
- First showcase scope: two fighters and one stage.
- Camera: horizontal tracking/panning is required. Orbiting and other perspective changes remain undecided. A permanently fixed gameplay camera is not an accepted constraint.
- Audio: separate ambience, crowd reactions, combat effects and announcements/dialogue are accepted; they should remain independent of background video.
- Development hardware: Intel i5-1135G7, 16 GB RAM, Intel Iris Xe integrated graphics.
- Initial performance objective: 60 fps at 1280 × 720. This is a target, not a benchmark result.
- Character references: `Khan Sahab.png` and `Asim jani.png` supplied by the user.
- Composition reference: `gameplay-camera mockup.png` supplied by the user.
- Godot project: `game/project.godot`; running integration tests confirm Godot 4.7.2 and `gl_compatibility` rendering.
- Blender MCP: verified with Blender 4.5.14 LTS and matching protocol 7. On 17 September, inspected the chosen Khan Model 2 and prepared a separate working scene/file. Original GLBs and a Blender inspection master are preserved under `khan-model2/`.
- Character asset decision: user selected `C:\Users\IT\Downloads\2.glb` as Khan's base, with `1.glb` retained as an alternative. Budget is **$0**. Improve the selected asset; further generator shopping is not the current task.
- Godot, Blender MCP and the Mixamo download/import pipeline have been exercised. The selected character and four motion clips play in an isolated Godot Compatibility review scene. Final garment deformation and sustained performance remain unverified.

## 3. First playable match — proposed rules

Proposed defaults are intentionally small and editable:

- Local versus, with a practice dummy for solo testing; a full computer opponent is a later decision.
- Select either fighter, start a round, fight, resolve the result, restart or rematch.
- Start with 100 health, a 99-second round timer and first-to-two round wins. Timeout awards the round to the higher remaining health; equal health or simultaneous knockout produces a drawn round that is replayed.
- Move toward/away, jump, crouch, hold away to guard, and use light attack, heavy attack and kick. Confirm exact keyboard/controller bindings before implementation.
- Prototype attacks cover a quick standing strike, a slower punishable strike, and a low kick. Standing guard blocks high/mid strikes; crouching guard blocks lows and mids; high strikes can miss a crouching opponent. No airborne guard in the initial proposal.
- Add one short combo and one signature move per character only after the basic exchanges work.
- Pause and rematch controls; health, timer and round markers displayed as actual UI.
- Provisional differentiation: Khan Sahab explores a mobile pressure style; Asim Jani explores a counter-oriented style. These are fictional gameplay roles, not assertions about real people. Begin with shared placeholder mechanics before differentiating.

Early controls should be remappable. Prefer gamepads for local versus; test any shared-keyboard setup for simultaneous-key limitations.

### Combat implementation boundary

Use explicit states such as idle, moving, jumping, attacking, guarding, hit reaction and knockout. Each attack specifies startup, active and recovery ticks, damage, reach, knockback and allowed transitions. Start with a fixed 60 Hz combat update. Visual animation and background playback must not determine damage or timing.

Use authored attack regions and vulnerable regions with an in-game debugging display. A fist's rendered appearance alone does not determine a hit. Stop movement at stage boundaries and prevent unintended fighter overlap. Provide repeatable tests for block direction, side switching, one hit per intended strike, damage, pause and round reset.

Online play remains **undecided**. Keep game state separate from presentation now, but do not claim rollback support or deterministic networking. Confirm online ambitions before substantial combat architecture investment; a future online mode requires its own work and verification.

## 4. Stage design — camera-led hybrid-stage experiment

**Confirmed:** horizontal camera tracking/panning is necessary. **Open:** zoom range, orbiting and cinematic perspective changes. **Experiment:** whether generated video or video-derived animation can supply some background activity. The stage method must satisfy the camera requirement rather than requiring the user to abandon it.

### Proposed construction

Recommended starting point: a compact 3D road, curb, barriers and nearby props; simple building facades and a bus with sufficient depth for the intended camera views; a small number of low-detail animated crowd figures; and distant skyline/detail on image cards where flatness is not conspicuous. Test video-derived crowd cards as an alternative to some 3D spectators. Preserve the existing user mockup as the composition reference.

The ground has actual collision and receives fighter shadows. Start with inexpensive materials and simple contact shadows if needed. Nearby objects visible from changing angles need geometry that supports those views. Far-away details can tolerate more approximation. A shallow set supports a defined camera range, not unlimited exploration.

A wide video remains an option for distant scenery. It must have enough coverage for both ends of the bounded arena. Its left and right edges do not need to tile unless repeated spatially. Temporal looping is a separate requirement. Scrolling one flat image/video is panorama scrolling; distinct layers at different depths or scroll speeds produce parallax.

Any backdrop must exclude fighters, HUD and baked foreground fighter shadows. Generate from a cleaned plate. Nearby moving pedestrians and objects that cross the fighting area require suitable geometry or separately managed layers. A curb or barrier can help conceal a visual transition.

Match horizon, perspective, ground level, sun direction, color and exposure between the source plate, road and fighters. Keep background lighting stable. Spectators in a recording cannot react to the actual fight, so prefer general cheering and reserve event-specific reactions for audio or later real-time elements.

### Camera behavior and asset coverage

- Prototype lateral tracking along the arena, tentatively following the fighters' midpoint with smoothing and stage-edge clamps. Exact camera distance, lens and tracking limits remain proposed until tested.
- Keep both fighters visible through maximum separation and jump height. Evaluate whether tracking alone suffices or a limited distance/zoom adjustment is wanted; do not assume zoom is approved.
- Test framing at both stage ends, not only the center. Every visible angle needs adequate geometry, backdrop coverage and appropriate lighting.
- A wide card supports bounded lateral tracking. Its baked contents do not reveal new sides or correct internal depth parallax as the camera translates. Put cards farther away and use real geometry for nearby details.
- Small zooms or rotations are not universally impossible, but reveal different weaknesses depending on projection, layering and scene depth. Decide the intended camera envelope before final asset production.
- If cinematic orbiting is selected, assess a limited authored arc with real nearby geometry, a dedicated cinematic set, or a separately framed backdrop. A full 360-degree arena is a distinct scope decision.
- Preserve 16:9 with letterboxing as needed. The existing project uses stretch/aspect `expand`; evaluate changing that during implementation rather than allowing the backdrop to distort or reveal uncovered edges. No setting has been changed yet.
- Evaluate impact shake with the full composition and enough overscan to avoid exposed borders.
- Do not plan foreground occlusion by people or vehicles embedded in the backdrop; that requires separate layers/masks or geometry.

### Generated animation options to compare

- **Wide background video:** simplest authored motion, limited baked perspective and CPU decoding cost. Use only where its depth limitations fit the camera.
- **Video-derived sprite animation:** generate one cheering person or small group against a clean background, remove the background, trim a loop and export selected transparent frames. Place on a 3D card, with occlusion determined by its position. Frame count, resolution, texture memory, edge quality and transparent overdraw must be budgeted. These cards remain flat; rotation toward the camera does not create a correct side view.
- **Low-detail 3D crowd:** use a few reusable humanoids and animation clips, vary clothing, position and animation phase. More authoring, but a better fit for nearby spectators and possible cinematic angles. Measure actual rig/animation cost rather than assuming it is too expensive.
- **Simple procedural motion:** lightweight foliage movement, flags or particles can add life without a full-scene movie; evaluate their cost and readability on Compatibility rendering.

Godot provides AnimatedSprite3D for animated image frames in 3D. Its performance documentation discusses practical geometry and transparency costs. Sources: [AnimatedSprite3D](https://docs.godotengine.org/en/stable/classes/class_animatedsprite3d.html), [3D optimization](https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html).

Do not adopt NeRF/Gaussian splatting as the initial stage shortcut. Standard reconstruction needs consistent multi-view evidence; an AI-generated clip may not provide it. A radiance-field/splat representation is not automatically an editable mesh, animation rig or collision surface, and it does not guarantee unseen viewpoints or low-end Godot performance. Source: [original 3D Gaussian Splatting project](https://repo-sam.inria.fr/fungraph/3d-gaussian-splatting/).

A 360-degree panorama can support looking around from its capture center, but does not supply nearby-object parallax when the camera moves sideways. Keep this option for distant surroundings if needed, rather than treating it as a fully navigable arena.

### Video technical route and evidence

Godot's built-in video path uses Ogg Theora, normally `.ogv`, with CPU decoding. An MP4 generation therefore requires transcoding or an additional decoder extension. The first trial should use 720p, 24 or 30 fps video, independent of 60 Hz combat. VideoStreamPlayer supports looping and exposing video frames as textures. These facts establish feasibility, not acceptable performance on this laptop. Sources: [video guide](https://docs.godotengine.org/en/stable/tutorials/animation/playing_videos.html), [VideoStreamPlayer](https://docs.godotengine.org/en/stable/classes/class_videostreamplayer.html).

### Generation brief for a later distant-video test

The source clip's camera should remain locked even though the game's camera will track. This keeps the recorded motion separate from the game's controlled camera movement. Prepare sufficient horizontal coverage for the chosen in-game camera range.

> Fixed tripod camera, locked lens and composition, warm Lahore street background for a side-view fighting game. Spectators remain behind a roadside barrier, with restrained varied cheering, small hand gestures and gentle leaf movement. Preserve buildings, bus decoration, faces, signage and daylight consistently. Leave the foreground fighting area empty. No fighters, interface, camera movement, zoom, scene cuts, moving shadows across the fighting area, or objects entering the foreground. Aim for a natural approximately ten-second loop with compatible opening and closing motion.

This prompt does not guarantee a seamless result. Inspect repeated playback for a visible cut, shape drift, exposure changes and repetitive gestures. Matching endpoint pictures alone does not ensure matching motion. Avoid reversing the whole clip to make a loop; crowds and vehicles can visibly move backward. A crossfade is optional but must not produce distracting doubled people.

### Test and decision

First prove camera tracking with two placeholder fighters and simple 3D blocks marking the bus, curb and buildings. Then compare distant still/video and a small crowd-card/3D-crowd sample under the same camera path. Test an exported Windows build on the laptop for at least three minutes, including both arena ends, repeated loop boundaries, movement, jumps, attacks and pause/resume. Record typical frame time, p95/p99 frame time, spikes at loop boundaries, CPU/GPU load where available and memory. Target the 16.7 ms frame budget associated with 60 fps; investigate consistent misses and visible stutters.

Adopt video only if it passes both visual and performance checks. If it fails, use the still backdrop with a few localized animated elements, simplify/re-encode the clip, or separately evaluate another decoder. A simple still scene is the baseline, not a guarantee that video will be faster than 3D.

## 5. Character and animation pipeline

1. Preserve original reference sheets. Prepare consistent isolated neutral-pose views for any generation tool.
2. Use the selected Khan Model 2 as the first base. Check face/profile consistency and joint geometry before multiplying assets.
3. Clean geometry, UVs and materials in Blender; these determine appearance and deformation quality.
4. Reuse or auto-generate a humanoid skeleton and adjust skinning as needed. Test idle, punch, kick and hit reaction before elaborate animation.
5. Bring in a small set of suitable existing motion clips, adapt timing and poses, and keep the source assets and usage records.
6. Export a `.glb` into Godot and verify scale, orientation, materials, animation and reimport behavior.

Khan Sahab needs special tests for the long tunic, loose trousers, sandals and hair silhouette. **Confirmed garment behavior:** the hanging front and back of the kameez should move independently with gravity and restrained sway, rather than stretch with the legs. Current experiment separates the lower garment into two panels with dedicated bones and runtime secondary motion. The top stays attached to the body. This is a lightweight approximation; collision clearance and finished garment geometry still need validation. Asim Jani needs tests for shoulder movement, jacket deformation and accessory attachment. Small uniform details can use textures where appropriate. Avoid fragile moving accessories during the first combat proof.

Body rigging does not automatically provide a facial rig. Begin with a few expressions and expand only after the body pipeline works. Confirm a visually acceptable character at gameplay distance before investing in close-up detail.

## 6. Sound — accepted layered approach

The user proposed ElevenLabs. Its sound-effects tools support generating effects and ambience; evaluate a small sample when needed. No purchase, generation or service connection is authorized by this document alone. Source: [ElevenLabs sound-effects documentation](https://elevenlabs.io/docs/overview/capabilities/sound-effects).

The user agrees to keep audio independent of the video:

- A continuous street ambience bed at a restrained volume.
- Several crowd-reaction clips triggered with variation and cooldowns.
- Footsteps, movement whooshes, impacts, guard sounds and clothing motion.
- UI sounds and round/KO announcements; music can be assessed separately.

Use separate Master, Ambience, Combat, Voice and Music buses. Essential fight feedback should remain audible over ambience. Export sound assets and play them locally; the game should not need live AI requests. Prefer original fictional dialogue and performance. Confirm any specific voice approach separately.

## 7. Milestones and exit criteria

### A. Setup verification — partly complete

Complete: project configuration inspected; Blender MCP verified and used for the chosen character; a source-project scene runs in Godot Compatibility on Intel Iris Xe. Character-only Blender-to-FBX-to-Blender validation passed. The actual rigged Khan model and four motion clips now import and play in an isolated Godot review scene. A standalone Windows export and sustained game performance checks remain pending.

### B. Stage and camera proof

**Implemented, first iteration:** the source project now contains a collidable 3D road, simple Lahore-inspired street geometry, two costume-colored movement proxies, jumping, pause/reset, and a horizontally tracking camera. F2 runs an automatic camera tour. Rendered integration checks cover grounding, arena ends, jump framing, spacing, pause and reset; evidence is in `stage-proof/validation.json` and its adjacent captures. This is not final artwork or a sustained performance benchmark. The temporary spacing tether is an experiment, not a confirmed combat rule. User review of camera feel is next; cinematic camera scope remains open.

Two placeholders stand convincingly on the road while the camera tracks horizontally. Prove coverage, grounding and acceptable perspective across the full intended camera range. Then compare a small sample of background/crowd techniques. Exit: decide the stage construction from measured behavior and visual inspection; resolve intended cinematic camera freedom before final environment assets.

### C. Combat proof

**Implemented, first iteration (build 02):** local two-player punch/kick/held guard, frame-based attack windows, one contact per attack, hit/block reactions, knockback, health bars, short impact freezes, procedural impact sounds, ready countdown, knockout, round score and rematch. Player 2 automatic guard supports solo testing. Prototype tuning is 100 health, 60 simulation seconds per round and first to two wins; these are adjustable implementation choices, not final competitive rules. Punch/kick damage is 10/17, with different range and recovery. Equal-health timeouts and double KOs draw without a round win. See `combat-proof/README.md` and `combat-proof/combat-validation.json` for controls, limitations and verification. Awaiting user playtest; final characters, skeletal animation and measured performance remain separate work.

Implement the smallest proposed attack/guard loop using placeholders, followed by health, round end, pause and rematch. Exit: repeated matches complete reliably, attacks read clearly, and input feels responsive.

### D. One finished character proof

**Active asset task:** user selected Model 2 after reviewing both downloaded models in Blender. Preserve and improve it within the $0 budget. Source has 474,548 triangles and no skeleton. A reversible reduction candidate has 151,826 triangles, with head and hands protected; a coordinate check found no movement of those protected vertices. Original 2K texture bytes are preserved. Character-only FBX reimport verified scale, UVs, triangle count and embedded color/normal textures. Roughness/metalness stays in the Blender master for restoration after Mixamo. This is a conservative rigging trial, not final runtime optimization or proof of animation quality.

**18 September update:** Mixamo rigging succeeded and the user supplied a rigged T-pose. The 41-bone rig has thumb/index finger chains only. Matched Blender comparisons confirmed the first reduction damaged footwear and clothing detail. A 284,676-triangle quality candidate restores all original footwear-region geometry, retains more clothing detail and uses transferred body weights plus the original PBR material. The new file is `khan-model2/blender/khan-model2-rig-review.blend`. Finger geometry/articulation, underarm stretching and tunic deformation still require repair. This higher-detail candidate is not the final runtime mesh.

**Current checkpoint:** both idles, punch and MMA kick have been downloaded, inspected in Blender, and imported into the Godot garment review scene. The files share the same body skeleton. Baseline kick inspection confirmed that the original leg weights drag the tunic. A separate working file, `khan-model2/blender/khan-model2-garment-trial.blend`, tests independent front/back panels, gravity/sway, thigh collision shapes and reconstructed upper trousers. This is an art/deformation experiment, not a finished character. Main combat still uses its proxies; gameplay-camera integration, attack timing alignment and sustained performance remain pending. See `khan-model2/NEXT-STEPS.md` for the handoff. Existing references remain in `character-pipeline/references/`.

Take one reference through model, rig, an idle, one punch and one high knee/kick, then engine import. These three motions test the asset pipeline; the intended game retains varied, character-specific attacks. Exit: recognizable appearance, tolerable clothing deformation and successful reimport at measured performance. Add a hit reaction after the initial three tests pass.

### E. Two-character showcase

Add the second character, limited distinct moves, stage dressing, audio, HUD and original humorous performance. Exit: a Windows build supports a complete local match and rematch on the target laptop, with working controls and acceptable frame pacing.

Stages B and D can inform each other; do not finish the whole roster before proving the pipeline. No duration or cost estimate is committed until these tests expose the actual workload.

## 8. Open decisions and change policy

Resolve next: final tracking limits and lens, whether zoom or orbiting/cinematic angles are wanted, final control scheme, proposed round rules and online ambitions. Khan Sahab is the first character and the current asset budget is $0. Horizontal tracking is required. Video and animated cards remain experimental. Full arcade AI, broad roster, story mode, advanced cloth and online infrastructure are outside the proposed first showcase scope, pending user decisions. Cinematic camera scope is explicitly undecided.

For each meaningful experiment, record: question, setup, result, decision and next action. Promote a proposal to confirmed only after user agreement; promote a technical experiment to the implementation plan only after its result supports it. Keep a short deferred-feature list so new ideas are preserved without continually enlarging the first milestone.

### Initial decision log

- 16 Sep 2026: natural proportions/stylized realism accepted by the user.
- 16 Sep 2026: tool setup reported complete; Blender scene listing independently verified without edits.
- 16 Sep 2026: looping video backdrop and generated sound proposed by the user; performance, loop quality and integration are untested.
- 16 Sep 2026: GDD v0.1 drafted to combine a stable initial scope with experimental implementation decisions.
- 16 Sep 2026, revision 1: horizontal panning confirmed as necessary; supersedes the proposed fixed-camera constraint. Orbiting and perspective changes remain open. Recommended experiment changes to a compact 3D set with optional distant cards/video and a camera-coverage test.
- 16 Sep 2026, revision 1: separate layered ambience, crowd, combat and voice audio accepted by the user.
- 16 Sep 2026, revision 2: user authorized starting implementation. Built the first stage/camera movement proof in the existing Godot project. Horizontal tracking works with a compact 3D set; no video technique or final camera lens has been approved by this implementation alone.
- 16 Sep 2026: user playtested and confirmed horizontal tracking, left/right movement and jumping. This confirms functionality, not final camera tuning or artwork approval.
- 17 Sep 2026, revision 3: resumed authorized combat implementation after the interrupted session. Build 02 provides a complete local round/match/rematch loop with placeholder fighters. Combat parameters and simple synthesized sound cues are provisional; ElevenLabs assets have not been generated.
- 17 Sep 2026, revision 4: user chose downloaded Model 2 for Khan and a $0 budget. Preserved both originals, inspected geometry/materials, prepared a separate Blender working copy and a 151,826-triangle Mixamo trial. Export/reimport passed; rigging, deformation and game-performance tests remain pending. The user confirmed the prototype attacks work and wants to advance the actual character pipeline.
- 18 Sep 2026, revision 5: user supplied the rigged T-pose and rejected visible footwear/clothing degradation. Confirmed that degradation in matched views, restored protected footwear geometry and increased retained clothing detail in a separate rigged review candidate. T-pose inspection passed file/weight-coverage checks but exposed remaining underarm and finger limitations. Motion downloads are next; no final art or game-performance approval is implied.
- 18 Sep 2026, revision 6: user supplied two idles, punch and MMA kick, and requested independent hanging front/back tunic motion. All four motions are imported. The first garment implementation is available in an isolated Godot review scene; collision and garment finish require further refinement. Motion-library expansion remains deferred until this asset pipeline is usable.
- 15 Nov 2026: full-game scope, requirements and architecture drafted in `pakistani-fighter-scope-v1.0.md` (release tiers, Tekken-style combat/animation/camera/audio/story design, NFRs, performance budget, phased roadmap). All items there are Recommended/Open until the user answers its §15 decisions; the P0 rigged-fighter refactor remains the immediate next step.
- 15 Nov 2026: user confirmed parody + original-cast roster mix (keep current pair for now; decide on Asim Jani before public release), Tekken-style four-limb buttons, Tekken auto-guard (neutral/back guards, down-back crouch guard), comedy-rich tone, Urdu + English voices, and an intended public release. Sidestep scope remains open.
- 15 Nov 2026: user chose sidestep-lite (Option B) for R1, kept Khan Sahab + Asim Jani as the R1 roster, chose open-source AI voices for Urdu/English lines, and approved the Compatibility vs Forward+ renderer spike (best image within the laptop's budget wins). Title shortlist added to scope §3.1; title still open.
- 15 Nov 2026: title confirmed as ROLA (رولا), tagline "Ab Baat Laaton Se Hogi"; announcer callouts, system names (Josh/Jalwa/Junoon/Saaf Safaya) and cheeky UI copy approved. Khan base model confirmed as khan_recovery_trial.glb (latest repaired build). Stage 2 (Karachi Sea View or Islamabad with Faisal Mosque backdrop) deferred until Mall Road and the two-character game are complete.
- 15 Nov 2026: updated project title/spelling to **Rolaa** with 4-word game-defining tagline **"Pakistan's 3D Street Fighter"** in `game/project.godot` and `outputs/rolaa-scope-v1.0.md` (renamed from `pakistani-fighter-scope-v1.0.md`). Placed story-mode framing ("Rolaa Live!"), online play deferral, and R2 original cast priority into Open / Deferred scope for later.
- 16 Nov 2026: **P0 complete.** Added `MoveData` (`game/scripts/move_data.gd`) and `CharacterDef` (`game/scripts/character_def.gd`) resources with `.tres` data under `game/characters/{khan,asim}/`, refactored `khan_stage_fighter.gd` into generic `FighterView` (`game/scripts/fighter_view.gd`), promoted rigged `khan_recovery_trial.glb` (P1) vs `asim_model1.glb` (P2) to the default `stage_proof.tscn` scene and `Play Combat Prototype.cmd`, verified `--khan-stage-test` (48/48), `--self-test` (17/17), and `--combat-test` (29/29) in headless and rendered `gl_compatibility` modes, and initialized Git + GitHub Actions headless CI (`.github/workflows/ci.yml`).
- 16 Nov 2026: **P1 complete.** Built Low/Med/High `GraphicsPresets` (`game/scripts/graphics_presets.gd`), `--perf-bench` (`game/scripts/perf_benchmark.gd`), and `--determinism-test` (`game/scripts/determinism_check.gd`) with `snapshot_match()`/`restore_match()` and fixed-tick `_poll_just_pressed()` + grounded gravity fix; decimated both rigged fighters via `tools/blender/decimate_rigged_fighter.py` (`khan_recovery_trial.glb` 292,869 → 65,877 tris / 6.07 MB keeping 2,608/2,608 `chaak` panel verts; `asim_model1.glb` 284,999 → 61,999 tris / 6.94 MB); measured `gl_compatibility` (298.9 fps Low, 87.0 fps Med, 64.0 fps High) vs `forward_plus` D3D12 (68.6 fps Med, 16.2 fps High w/ SSAO) on Intel Iris Xe and locked `gl_compatibility` + ~60k tri LOD0 in `docs/adr/0001-renderer-and-lod-budget.md`; verified 1-tick input latency and 180-tick replay determinism (9/9 `--determinism-test` checks passing) and added `--determinism-test` to CI.
- 17 Nov 2026: **P2 complete.** Implemented Tekken 4-limb controls (`LP/RP/LK/RK` + `Josh`), 60-tick `InputBuffer` (`game/scripts/input_buffer.gd`), and `CommandParser` (`game/scripts/command_parser.gd`) with 3-frame kara-chord upgrade (preserving 1-tick normal latency), command motions (`66`, `44`, `22`, `88`, `236`), and directional normals; added `high`/`mid`/`low`/`throw` hit levels, Tekken neutral/back/crouch guard, dashes, sidestep-lite (`linear` vs `homing`), counter-hits (`COUNTER — ULTA PAD GAYA!`), target-combo cancels (`1,2,4` & `1,1,2`), launchers/juggles with damage scaling (`100%→80%→70%→60%…`), knockdown/wake-up options (`wakeup_quick`/`wakeup_roll`/`wakeup_stand`), throws + 14-tick `Chhuraao` break, wall splats, and `Josh` meter / `Junoon` comeback / `Jalwa` super; authored 13 `MoveData` `.tres` moves per fighter under `game/characters/{khan,asim}/moves/`, updated `FighterView` to bind arbitrary `MoveData` clips dynamically (wiring Asim's `Headbutt`, `RoundhouseKick`, and `QuadPunch`), built `FrameDataTool` (`game/scripts/frame_data_tool.gd`), upgraded the HUD + `F3` hitbox/frame/input overlay (`game/scripts/proof_hud.gd`), pooled 48 hit-spark nodes in `combat_feedback.gd` (reaching **93.9 fps** avg at 720p Medium on Iris Xe), added `--combat-v2-test` (`game/scripts/combat_v2_validation.gd`, **41/41** checks passing) to CI, and verified all existing suites (`--self-test` 17/17, `--combat-test` 29/29, `--khan-stage-test` 39/39 headless, `--determinism-test` 9/9).
- 17 Nov 2026: **Phase P3 Part 1 (incl. Part 1b) complete.** Built retargeted Mixamo animation GLBs via `tools/blender/build_p3_character_anims.py` (`outputs/p3-animations/build-report.json`, 0 NaN keyframes): Khan Sahab (`game/assets/characters/khan_recovery_trial.glb`, 65,877 tris, 239 skin joints incl. kameez drape bones, 12.18 MB) now has **28 clips** (added `WalkBack` from `Step Backward.fbx`, `Jump` from `Jumping.fbx`, `CrouchWalkBack` reversed from `Crouched Walking.fbx`; rebuilt `Idle2` guard from `Bouncing Fight Idle.fbx`; locked horizontal hip XY drift via `lock_xy=True`, `max_locked_hips_xy_drift_m: 0.0`, across 22 attack/locomotion/reaction clips so `FlipKick`/`SignatureKick` never ghost through Asim), and Asim Jani (`game/assets/characters/asim_model1.glb`, 61,999 tris, 65 skin joints, 7.40 MB) has **14 clips** (added `Jump` + `lock_xy=True` on `CrouchIdle`, `Jump`, `HitHead`, `HitBody`); authoritative **27-row** move→clip table (`14` Khan incl. `rock_throw`, `13` Asim) exported to `outputs/p3-animations/frame-data.md` (`heavy_punch` 42f, `low_sweep` 55f, `launcher` `FlipKick` 55f, `signature` `SignatureKick` 58f, close `throw_front` grab 35f, Khan ranged `rock_throw` 80f), and crouch walk (`CrouchWalk` + `CrouchWalkBack`) now moves along the road even with `neutral_guard_enabled=true`. Added Khan's ranged **"Patthar Throw" (`1+3`)** with realistic rock shatter using `game/assets/props/cliff_rock.glb` (946 tris) and `game/assets/props/cliff_rock_shards.glb` (1,044 tris: 6 jagged PBR-textured stone chunks `Shard_0..Shard_5` via `tools/blender/build_rock_prop.py`) plus `game/assets/vfx/dust_puff.png`: at range (`dist > 1.70` or crouching/airborne), Khan bends to pick up the rock with road dust (`HandRockProp` visible ticks `11..43`) and launches a head-height 3D projectile at tick `44` (18 dmg, sharp `HitHead` snap-back, 12 ground-bouncing jagged shards + soft dust plumes in `combat_feedback.gd`, `"PATTHAR HEAD HIT!"`; crouch ducks, sidestep evades, standing guard blocks for 3 chip), while close-range `1+3` remains the 35f grab throw (22 dmg, LP tech). Added **Junoon/Jalwa VFX** (`tools/vfx/generate_vfx_assets.py` → 7 textures under `game/assets/vfx/{junoon_aura_ring,junoon_flame_particle,hit_spark_burst,jalwa_speedlines,dust_puff,badge_junoon,badge_jalwa}.png`): 3D golden ground aura ring, rising flame particles, gold body glow, activation shockwave + light pillar burst, `JUNOON!`/`JALWA` HUD badges, fullscreen speedlines + camera FOV zoom during `super_jalwa`, `F6` debug shortcut for full Josh + Junoon, and hidden-until-active particle prewarm (`visible = false`, `billboard_keep_scale = true`). Verified headless suites (`--self-test` 17/17, `--combat-test` 29/29, `--khan-stage-test` 39/39, `--determinism-test` 9/9, `--combat-v2-test` **53/53** in `outputs/p3-animations/combat-v2-validation.json`); rendered 720p Medium benchmark (`gl_compatibility` on Iris Xe, `outputs/p3-animations/perf-bench-720p-medium.json`) measured **130.4 avg fps** (`avg 7.67 ms`, `p50 6.51 ms`, `p95 19.96 ms`, `p99 22.32 ms`, `max 26.89 ms`; Run 1 **137.2 avg fps** / `p99 22.65 ms`; zero stray prewarm particles), recovering from a 58.5 fps / 687.91 ms max first-use GL Compatibility hitch via 2-frame sub-pixel prewarm for P3 props/VFX, constant `emission_enabled = true` + flash cache (`fighter_view.gd`), active-only spark/shard guards (`combat_feedback.gd`), and load-time HUD texture upload + dirty-checked redraws (`proof_hud.gd`). Documented with captures (`p3-jump.png`, `p3-guard.png`, `p3-walk-back.png`, `p3-crouch-walk.png`, `p3-flipkick.png`, `p3-rock-pickup.png`, `p3-rock-throw-hithead.png`, `stage-p3-bench.png`, etc.) in `outputs/p3-animations/README.md`; standing backward walk (`Step Backward`), `Jump`, and `Bouncing Fight Idle` are now done, while still-needed downloads for Part 2 are dedicated Mixamo `Crouch Walk Backward` (currently reversed from `Crouched Walking.fbx`), `Kip Up` / quick-rise wake-up, dedicated `Blocking` impact reaction, air attack, and Asim's unique kit (left jab, low kick, launcher uppercut/rising kick, military shoulder throw, Asim Jalwa super finisher, taunt/victory pose).
- 20 Nov 2026: **Phase P3 Part 2 complete.** Extended `tools/blender/build_p3_character_anims.py` with `BVH_TO_MIXAMO` 22-bone world-space Mixamo T-pose delta retargeting (`global_scale=0.01`, `lock_xy=True`, `0` NaN keyframes, `max_locked_hips_xy_drift_m: 0.0`): **Khan Sahab** (`game/assets/characters/khan_recovery_trial.glb`, 65,877 tris, 239 skin joints, 12.97 MB) now has **30 clips** (added `Taunt` from `Standing Taunt Battlecry.fbx` [86f], `BlockHit` from `BVH/block_mid.bvh` [55f], and replaced `WakeupStand` with `BVH/get_up.bvh` [132f]); **Asim Jani** (`game/assets/characters/asim_model1.glb`, 61,999 tris, 65 skin joints, 8.53 MB) expanded from 14 to **31 clips** (`Idle2`, `WalkBack`, `CrouchWalk`, `CrouchWalkBack`, `DashForward`, `Backdash` [`dodge_back`], `Sidestep` [`dodge_left`], `JabLeft`, `JabCross`, `CrossRight`, `BodyPunch`, `FrontKick`, `SweepKick`, `UppercutRight`, `GrabThrow`, `ComboPunchKick`, `BlockHit`, `WakeupStand`, `Taunt` [`salute_military.bvh`]). Regenerated `.tres` kits via `FrameDataTool.save_default_resources()` (`outputs/p3-animations/frame-data.md`: Asim `punch`→`JabLeft`, `light_combo`→`JabCross`, `heavy_punch`→`CrossRight`, `crouch_jab`→`BodyPunch`, `quick_kick`→`FrontKick`, `low_sweep`→`SweepKick`, `launcher`→`UppercutRight`, `throw_front`→`GrabThrow`, `super_jalwa`→`ComboPunchKick`). Wired standing `3+4` `taunt` (`J+K` P1 / `Num1+Num2` P2, 96 ticks) with `"ABSOLUTELY NOT!"` (Khan) / `"SALUTE!"` (Asim) HUD callouts, `CharacterDef.voice_bank["taunt"]` + `CombatFeedback.play_voice_path()` voice hooks (`res://assets/audio/khan_taunt_absolutely_not.ogg` and `asim_taunt_salute.ogg`), `blockstun`→`BlockHit` seek, and `wakeup`→`WakeupStand` (`get_up`) seek in `fighter_view.gd`, `proxy_fighter.gd`, `combat_feedback.gd`, `stage_proof.gd`, and `proof_hud.gd`. All 5 headless suites passed (`--self-test` **17/17**, `--combat-test` **29/29**, `--khan-stage-test` **39/39**, `--determinism-test` **9/9**, `--combat-v2-test` **68/68**, `failed: []`), 720p Medium `--perf-bench` measured **137.5 avg fps** (`avg 7.27 ms`, `p99 22.65 ms`, `134` avg draw calls, `197,777` avg primitives, `147.0 MB` VRAM, `meets_60fps_avg: true`, `meets_p99_20ms: false`), and all 7 Part 2 renders passed visual inspection (`p3-khan-taunt.png`, `p3-asim-salute-taunt.png`, `p3-asim-jab-and-block.png`, `p3-asim-sweep.png`, `p3-asim-uppercut.png`, `p3-wakeup-getup.png`, `stage-p3-bench.png`). Deferred to next pass per user direction: Khan's reworked `JalwaSuper` clip, lightning/super finisher VFX, full-Junoon fire aura covering character, and recorded `.ogg` voice files.
- 22 Nov 2026: **Phase P3 complete (Part 3 & Closeout) + 60 fps live VSync / shadow fix.** Completed the remaining P3 deliverables in `tools/blender/build_p3_character_anims.py`, `build_pistol_props.py`, and `build_super_vfx_assets.py` (**Khan** `36` clips / `14.47 MB`, **Asim** `38` clips / `9.08 MB`, `0` NaN keyframes, `0.0 m` locked XY drift): added round `Entry` (Khan walks in from afar from `Entry (1).fbx`, Asim `Crouch To Stand`), post-KO `VictoryCelebrate` (`Rumba Dancing` / `Silly Dancing`, waiting for `KO_FALL_TICKS = 108`), `Turn180` (`Running Turn 180`), Asim `M1911 Pistol Shot` (`m1911_pistol.glb` 12,080 tris + `bullet_45acp.glb` 736 tris + muzzle flash + ejecting shell casing), reworked `JalwaSuper` with storm dimming, twin 3D lightning bolts (`lightning_bolts.glb`), 3D `SlashWave` (`slash_arc.glb`), crater crack decal, rune circle, and full-body Junoon fire aura (`junoon_body_fire.gdshader` + volumetric shrouds/flames/embers), separated `SweepFall` (`KNOCKDOWN_TICKS = 76`) + `Stand Up.fbx` (`WAKEUP_STAND_TICKS = 72`) hit knockdowns from `KnockdownDeath` KOs, and added mid-air `air_punch` (`Flying Knee Punch Combo.fbx`, `i7/6f/14f`, `13` dmg) and `air_kick` (`Drop Kick.fbx`, `i9/7f/16f`, `16` dmg knockdown) with `lock_z=True` and touchdown cancels. Regenerated all `.tres` resources on disk via `--save-resources` (`16` Khan moves + `16` Asim moves = `32` rows in `outputs/p3-animations/frame-data.md`). Restored non-Junoon primitive/draw-call cost and eliminated live-play 30 fps lag via dynamic `material_overlay` attachment in `fighter_view.gd`, `SHADOW_PARALLEL_2_SPLITS` (`32.0 m` Medium) in `stage_proof.gd`/`graphics_presets.gd`, cached `_apply_super_environment()`, and `window/vsync/vsync_mode=0` + `Engine.max_fps = 60` (Intel Iris Xe OpenGL `VSYNC_ENABLED` previously halved live play to 30 fps) — verified **90.3 avg fps** uncapped (`11.07 ms` avg, `p50 8.16 ms`, `133,387` avg primitives, `109` avg draw calls, `200.8 MB` VRAM in `outputs/p3-animations/perf-bench-720p-medium.json`) and locked **60.0 fps** live, alongside all 5 headless suites (`--self-test` **17/17**, `--combat-test` **29/29**, `--khan-stage-test` **39/39**, `--determinism-test` **9/9**, `--combat-v2-test` **110/110** headless / **120/120** rendered, `failed: []`, `err_len=0`). **Next phase: P4 — Stage 1 Final (Lahore Mall Road).**
