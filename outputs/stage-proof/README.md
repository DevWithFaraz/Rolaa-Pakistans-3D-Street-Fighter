# Stage and camera proof — build 01

**Historical milestone:** the live project is now build 02, with combat. See `../combat-proof/README.md` for current controls and behavior. The captures here preserve the original stage proof.

Open the existing **Pakistani Fighter Prototype** project in Godot and press **F5**, or double-click `Play Stage Proof.cmd` in the parent outputs folder. This runs the source project using the installed Godot; it is not a standalone exported game.

## Controls

- Khan proxy: **A / D** to move; **W** to jump.
- Asim proxy: **Left / Right arrows** to move; **Up arrow** to jump.
- **F2:** automatic camera tour. Press again to return to manual control.
- **R:** reset positions and exit the tour.
- **Esc:** pause/resume.
- **H:** show/hide help. **F3:** diagnostics. **F4:** toggle shadows.
- Two controllers are mapped to left stick/D-pad and the bottom face button. Controller hardware has not been tested.

## What this build establishes

Two costume-colored placeholders stand and jump on a collidable 3D road. The camera follows their midpoint horizontally, stopping before the arena edges. Buildings, a decorated bus, a tea stall, trees and barriers provide depth cues during tracking. Repeated shapes use grouped mesh instances. The renderer remains Compatibility.

This is an early movement and camera study. Character likenesses, production models, attacks, health, rounds, crowd animation, video and sound have not been added. Current walking poses are procedural placeholders. The street is a Lahore-inspired blockout, not an accurate reconstruction.

## Temporary gameplay rules

Fighters stay on one plane, with stage limits at X ±14 and camera limits at X ±9. A temporary maximum separation of 10 units keeps them visible. This acts as a spacing tether and can move the other fighter; it is not a finalized combat or pushing rule. Grounded fighters maintain minimum separation. Jumping can allow side switching. Camera lens and smoothing are starting values for playtesting. Orbiting and cinematic cameras remain undecided.

## Validation

`validation.json` records the actual integration result. The rendered test runs on the laptop's Intel Iris Xe through OpenGL Compatibility and exercises spawn grounding, both stage boundaries, camera framing, fixed camera angle during tracking, jumping/landing, pause, maximum spacing, the fighting plane and reset. Four screenshots capture center, left edge, right edge and jumping.

The test is not a sustained performance benchmark or proof of a 60-fps target. The runtime reported local shader-cache and root-certificate access errors inside the restricted tool environment; these did not prevent the scene rendering or the integration test completing.

To rerun from the project root in PowerShell:

```powershell
& 'C:\Program Files\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe' --path './game' -- --self-test "--capture-dir=$((Resolve-Path './outputs/stage-proof').Path)"
```

## Review next

Try the F2 tour, move both fighters toward each end, and jump. Judge camera height, fighter size and tracking speed before detailed art production. Next implementation steps are a minimal attack/guard/health loop and a separate first-character model/animation import trial. Background and crowd techniques still require comparison and measured performance checks.
