# Combat prototype — build 02

17 September 2026. Open the existing Godot project and press **F5**, or double-click **Play Combat Prototype.cmd** in the parent outputs folder. Close an older running game window first; it will not receive these script changes automatically. This launcher runs the source project with installed Godot, not a standalone exported game.

## Try a fight

1. Wait for READY to become FIGHT. Move Khan toward Asim with **D** until they are within reach.
2. Tap **F** for a punch or **G** for a kick. Punches deal 10 damage; kicks reach farther, deal 17, and recover more slowly. Holding an attack does not repeatedly trigger it.
3. Press **T** to enable Asim's automatic guard, then attack again. Blue flashes/sparks and BLOCK indicate a successful guard, which prevents all damage. Press T again to disable it.
4. Keep attacking and closing distance after knockback to earn a knockout. **Enter** starts the next round. First to two round wins wins the match; **Enter** then starts a rematch.

## Controls

- Player 1: **A/D** move, **W** jump, **F** punch, **G** kick, hold **S** to block.
- Player 2: **Left/Right** move, **Up** jump, **J** punch, **K** kick, hold **Down** to block.
- **T:** toggle player 2 automatic guard for solo testing. This is not an AI opponent.
- **Enter:** next round or rematch after a result.
- **R:** restart the entire match, including the score.
- **Esc:** pause/resume. **H:** show/hide controls. **M:** mute/unmute placeholder sound effects.
- **F2:** camera tour. Entering or leaving the tour restarts the match; the tour disables combat and pauses the round clock.
- **F3:** diagnostics. **F4:** toggle shadows.
- Controllers 1/2: left stick/D-pad movement, bottom face button jump, left face button punch, top face button kick, right shoulder guard. Keyboard controls manage rounds and menus. Controller hardware has not been tested.

## Current rules

100 health, 60-second simulation clock, first to two round wins. At timeout the higher remaining health wins; equal health and double knockouts are draws, with no win awarded. Enter proceeds to another round. R restores both fighters and clears the score. The auto-guard and mute preferences persist across rematches.

Attacks have startup, a short active contact window, and recovery. Punch: 6 startup ticks, 3 active, 14 recovery. Kick: 12 startup, 4 active, 22 recovery. Combat runs at 60 physics ticks per second. There is a short freeze on contact for impact emphasis; the clock also pauses during this freeze. Hits interrupt attacks, cause a brief stun, and push the opponent away. Simultaneous contacts can trade. Each attack connects at most once.

Blocking is a held button and stops movement. It works on the ground while facing the opponent. There is no chip damage, crouching, high/low distinction, aerial attack, throw, special move or combo-cancel system in this proof. A short attack-input buffer accepts late presses near the end of recovery; it does not cancel an ongoing move. Both characters currently use identical combat data for testing.

The existing movement plane, camera bounds and temporary maximum-spacing tether remain. Jumping and horizontal camera tracking continue to work. Character poses are procedural placeholders, and the environment remains a blockout. New sound effects are simple locally synthesized placeholders, not ElevenLabs assets. Final character likenesses, real skeletal animation, crowd/media backgrounds, voice, online play and standalone export remain later work.

## Validation and evidence

`combat-validation.json` records the running-scene integration tests and screenshot saves. Tests cover startup, one hit per attack, damage, knockback, recovery, blocking/blockstun, range, simultaneous trades, swapped sides, automatic guard, ground-only attacks, pause, KO, score retention, match completion, rematch, double KO, timeouts and camera-tour isolation. These use actual input actions and physics ticks. Adjacent screenshots show punch, block, kick, round result, match result and the neutral scene.

The original stage/movement regression checks were also rerun. These checks are not a sustained performance benchmark or proof of a stable 60 fps. Rendering uses Godot Compatibility on the laptop's Intel Iris Xe. The restricted tool runtime reports shader-cache/root-certificate access warnings; no game script error is expected.

To rerun the rendered combat test from the project root in PowerShell:

```powershell
& 'C:\Program Files\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe' --path './game' -- --combat-test "--capture-dir=$((Resolve-Path './outputs/combat-proof').Path)"
```

To run the stage regression, replace the arguments after `--` with `--self-test`. Add `--headless` before `--path` for logic-only execution without screenshots.

## Next review

Play several rounds. Review whether the punch feels responsive, the kick's extra reach is useful, blocking is clear, and knockback requires a reasonable amount of repositioning. Camera framing and combat numbers remain adjustable. This establishes the first concrete idle/walk/jump/punch/kick/guard/hit/KO animation requirements for the later model-and-rig trial.
