class_name CombatV2Validation
extends RefCounted
## Automated Phase P2 Combat Core v2 verification suite (--combat-v2-test).

const InputBufferScript = preload("res://scripts/input_buffer.gd")
const CommandParserScript = preload("res://scripts/command_parser.gd")
const FrameDataToolScript = preload("res://scripts/frame_data_tool.gd")

var g: Node


func _release_all() -> void:
	for player in [1, 2]:
		for suffix in ["left", "right", "jump", "down", "guard", "punch", "kick", "lp", "rp", "lk", "rk", "josh"]:
			Input.action_release("p%d_%s" % [player, suffix])


func _setup(distance: float = 1.6) -> void:
	_release_all()
	g.dummy_guard = false
	g.dummy_mode = "stand"
	g.testing = true
	g.reset()
	await g._tick(4)
	g.fighters[0].neutral_guard_enabled = false
	g.fighters[1].neutral_guard_enabled = false
	g.fighters[0].position.x = -distance * 0.5
	g.fighters[1].position.x = distance * 0.5
	await g._tick(4)


func _tap(action: String, hold_ticks: int = 2) -> void:
	Input.action_press(action)
	await g._tick(hold_ticks)
	Input.action_release(action)


func _check(ok: bool, msg: String) -> void:
	g._check(ok, msg)


func run(game: Node) -> void:
	g = game
	await _setup(1.6)

	# 1. Character Move Kits, Asim Clips & FrameDataTool
	var khan_def = g.fighters[0].get("character_def")
	var asim_def = g.fighters[1].get("character_def")
	_check(khan_def != null and khan_def.moves.size() >= 13, "Khan CharacterDef loads >= 13 Combat v2 moves")
	_check(asim_def != null and asim_def.moves.size() >= 13, "Asim CharacterDef loads >= 13 Combat v2 moves")

	var fd_report: Dictionary = FrameDataToolScript.validate_and_export(g.capture_dir)
	_check(fd_report.errors.is_empty() and int(fd_report.row_count) >= 26, "FrameDataTool validates all moves and exports CSV/MD")

	# Verify Asim's unique clips (Headbutt, RoundhouseKick, QuadPunch) bind cleanly in FighterView
	await _setup(1.8)
	Input.action_press("p2_left")
	Input.action_press("p2_rp")
	await g._tick(3)
	Input.action_release("p2_left")
	Input.action_release("p2_rp")
	_check(g.fighters[1].attack_kind == "command_heavy" and g.fighters[1].current_anim_state == "clip_headbutt" and g.fighters[1].has_finite_bones(), "Asim f+2 triggers Headbutt clip with finite bones")
	await g._tick(42)

	await _setup(1.8)
	Input.action_press("p2_right")
	Input.action_press("p2_rk")
	await g._tick(3)
	Input.action_release("p2_right")
	Input.action_release("p2_rk")
	_check(g.fighters[1].attack_kind == "power_kick" and g.fighters[1].current_anim_state == "clip_roundhousekick" and g.fighters[1].has_finite_bones(), "Asim b+4 triggers RoundhouseKick clip with finite bones")
	await g._tick(46)

	await _setup(1.8)
	Input.action_press("p2_lp")
	Input.action_press("p2_rp")
	await g._tick(3)
	Input.action_release("p2_lp")
	Input.action_release("p2_rp")
	_check(g.fighters[1].attack_kind == "signature" and g.fighters[1].current_anim_state == "clip_quadpunch" and g.fighters[1].has_finite_bones(), "Asim 1+2 triggers QuadPunch clip with finite bones")
	await g._tick(60)

	# 2. InputBuffer & CommandParser Unit + Kara-Chord Tests
	var buf = InputBufferScript.new()
	for _k in range(75):
		buf.push_frame(0.0, 0.0, 1.0, 0)
	_check(buf.history.size() == 60, "InputBuffer enforces 60-tick ring capacity")

	buf.clear()
	buf.push_frame(0.0, 0.0, 1.0, InputBufferScript.BTN_LP)
	buf.push_frame(0.0, 0.0, 1.0, 0)
	buf.push_frame(0.0, 0.0, 1.0, InputBufferScript.BTN_LK)
	_check(CommandParserScript.resolve_command(buf, false) == "throw_front", "CommandParser resolves 3-frame staggered LP+LK chord as throw_front")

	var buf_snap: Dictionary = buf.snapshot()
	var buf2 = InputBufferScript.new()
	buf2.restore(buf_snap)
	_check(buf2.history.size() == buf.history.size() and buf2.current_tick == buf.current_tick, "InputBuffer snapshot/restore preserves state")

	buf.clear()
	buf.push_frame(0.0, -1.0, 1.0, 0)
	buf.push_frame(1.0, -1.0, 1.0, 0)
	buf.push_frame(1.0, 0.0, 1.0, InputBufferScript.BTN_LP)
	_check(CommandParserScript.resolve_command(buf, false) == "signature", "CommandParser resolves QCF (2,3,6)+LP motion as signature")

	await _setup(1.5)
	Input.action_press("p1_lp")
	await g._tick(1)
	_check(g.fighters[0].state == "attack" and g.fighters[0].attack_kind == "punch", "Kara window starts LP on tick 1 with zero delay")
	Input.action_press("p1_lk")
	await g._tick(1)
	_release_all()
	_check(g.fighters[0].attack_kind == "throw_front", "Staggered LK within 2 ticks kara-upgrades LP into throw_front")

	# 3. Tekken Auto-Guard, Crouch Guard & High/Mid/Low Hit Levels
	await _setup(1.6)
	g.fighters[1].neutral_guard_enabled = true
	await _tap("p1_lp")
	await g._tick(10)
	_check(g.fighters[1].health == 100 and g.fighters[1].state == "blockstun", "Tekken neutral auto-guard blocks High LP")
	await g._tick(25)

	await _tap("p1_rk")
	await g._tick(16)
	_check(g.fighters[1].health == 100 and g.fighters[1].state == "blockstun", "Tekken neutral auto-guard blocks Mid RK")
	await g._tick(30)

	await _tap("p1_lk")
	await g._tick(14)
	_check(g.fighters[1].health == 89 and g.fighters[1].state == "hitstun", "Low LK breaks standing Tekken auto-guard")
	await g._tick(30)

	# Hold-back guard without neutral auto-guard
	await _setup(1.6)
	Input.action_press("p2_right")
	await g._tick(2)
	await _tap("p1_lp")
	await g._tick(10)
	Input.action_release("p2_right")
	_check(g.fighters[1].health == 100 and g.fighters[1].state == "blockstun", "Holding back blocks High LP")
	await g._tick(25)

	# Crouch-guard: ducks High, blocks Low, hit by Mid
	await _setup(1.6)
	Input.action_press("p2_down")
	Input.action_press("p2_right")
	await g._tick(3)
	await _tap("p1_lp")
	await g._tick(14)
	_check(g.fighters[1].health == 100 and g.fighters[1].state == "crouch_guard", "High LP whiffs cleanly over crouching defender")
	await g._tick(20)

	g.fighters[0].position.x = g.fighters[1].position.x - 1.35
	await _tap("p1_lk")
	await g._tick(14)
	_check(g.fighters[1].health == 100 and g.fighters[1].state == "blockstun", "Crouch-guard blocks Low LK")
	await g._tick(26)

	g.fighters[0].position.x = g.fighters[1].position.x - 1.35
	await _tap("p1_rk")
	await g._tick(16)
	_release_all()
	_check(g.fighters[1].health == 83 and g.fighters[1].state == "hitstun", "Mid RK hits through crouch-guard")

	# 4. Dashes & Sidestep-Lite (Linear Evasion vs Homing)
	await _setup(3.0)
	await _tap("p1_right", 2)
	await g._tick(2)
	Input.action_press("p1_right")
	await g._tick(2)
	Input.action_release("p1_right")
	_check(g.fighters[0].state == "dash_forward", "Double-tap forward triggers dash_forward")
	await g._tick(28)

	await _tap("p1_left", 2)
	await g._tick(2)
	Input.action_press("p1_left")
	await g._tick(2)
	Input.action_release("p1_left")
	_check(g.fighters[0].state == "backdash", "Double-tap back triggers backdash")
	await g._tick(26)

	await _setup(1.6)
	await _tap("p2_down", 2)
	await g._tick(2)
	Input.action_press("p2_down")
	await g._tick(2)
	Input.action_release("p2_down")
	_check(g.fighters[1].state == "sidestep", "Double-tap down triggers foreground sidestep-lite")
	await _tap("p1_lp")
	await g._tick(8)
	_check(g.fighters[1].health == 100, "Sidestep-lite evades linear High LP")
	await g._tick(22)

	await _setup(1.6)
	await _tap("p2_down", 2)
	await g._tick(2)
	Input.action_press("p2_down")
	await g._tick(2)
	Input.action_release("p2_down")
	Input.action_press("p1_right")
	Input.action_press("p1_rp")
	await g._tick(2)
	Input.action_release("p1_right")
	Input.action_release("p1_rp")
	await g._tick(16)
	_check(g.fighters[1].health == 80, "Homing f+2 catches sidestepping defender")

	await _setup(2.0)
	await _tap("p1_jump", 2)
	await g._tick(2)
	Input.action_press("p1_jump")
	await g._tick(2)
	Input.action_release("p1_jump")
	_check(g.fighters[0].state == "sidestep" and g.fighters[0].sidestep_dir < 0.0, "Double-tap up cancels early jump into background sidestep-lite")

	# 5. Counter-Hit ("COUNTER — ULTA PAD GAYA!")
	await _setup(1.5)
	Input.action_press("p2_rk")
	await g._tick(2)
	Input.action_release("p2_rk")
	await _tap("p1_lp")
	await g._tick(8)
	_check(g.fighters[1].health == 88 and "COUNTER" in g.event_text, "Counter-hit deals 1.2x bonus damage and triggers Ulta Pad Gaya callout")

	# 6. Target Combo String Cancel (1 -> 2 -> 4)
	await _setup(1.15)
	await _tap("p1_lp", 2)
	await g._tick(5)
	await _tap("p1_rp", 2)
	await g._tick(18)
	await _tap("p1_rk", 2)
	await g._tick(35)
	_check(g.fighters[1].combo_hits == 3 and g.fighters[1].health < 70, "String cancel 1->2->4 chains into 3-hit combo")

	# 7. Launcher, Juggle & Damage Scaling
	await _setup(1.3)
	Input.action_press("p1_down")
	Input.action_press("p1_right")
	Input.action_press("p1_rp")
	await g._tick(2)
	_release_all()
	await g._tick(30)
	_check(g.fighters[1].state == "juggle" and g.fighters[1].position.y > 0.35 and g.fighters[1].health == 85, "df+2 Launcher pops defender into juggle state")
	_check(g.fighters[0].current_anim_state == "clip_flipkick" and g.fighters[0].position.x < g.fighters[1].position.x and (g.fighters[1].position.x - g.fighters[0].position.x) >= 1.0, "FlipKick (df+2) connects without clipping or passing through defender")
	Input.action_press("p1_right")
	await g._tick(38)
	Input.action_release("p1_right")
	await _tap("p1_lp", 2)
	await g._tick(12)
	_check(g.fighters[1].combo_hits == 2 and g.fighters[1].health == 77, "Juggle follow-up applies 80% damage scaling (10 -> 8)")
	await g._tick(65)
	_check(g.fighters[1].state in ["knockdown", "wakeup_stand", "idle"], "Juggled defender transitions to grounded knockdown")

	# 8. Knockdown & Quick-Rise
	await _setup(1.6)
	Input.action_press("p1_down")
	Input.action_press("p1_lk")
	await g._tick(2)
	_release_all()
	await g._tick(22)
	_check(g.fighters[1].state == "knockdown" and g.fighters[1].health == 84, "d+3 low sweep knocks defender down")
	await _tap("p1_lp", 2)
	await g._tick(10)
	_check(g.fighters[1].health == 84, "Grounded knocked-down defender is invulnerable to standing LP")
	Input.action_press("p2_lk")
	Input.action_press("p2_rk")
	await g._tick(2)
	_release_all()
	_check(g.fighters[1].state == "wakeup_quick", "3+4 input triggers wakeup_quick")

	# 9. Front Throw & Chhuraao Throw Break
	await _setup(1.25)
	Input.action_press("p1_lp")
	Input.action_press("p1_lk")
	await g._tick(2)
	_release_all()
	await g._tick(11)
	_check(not g.active_throw.is_empty(), "1+3 at close range initiates throw tech window")
	await g._tick(16)
	_check(g.fighters[1].health == 78 and g.fighters[1].state == "knockdown" and "PAKAD" in g.event_text, "Unteched throw deals 22 dmg and knocks down")

	await _setup(1.25)
	Input.action_press("p1_lp")
	Input.action_press("p1_lk")
	await g._tick(2)
	_release_all()
	await g._tick(11)
	await _tap("p2_lp", 2)
	await g._tick(4)
	_check(g.fighters[1].health == 100 and "CHHURAAO" in g.event_text, "Pressing LP in 14-tick window breaks throw (Chhuraao)")

	# 10. Wall Splat
	await _setup(1.8)
	g.fighters[0].position.x = 12.1
	g.fighters[1].position.x = 13.75
	await g._tick(2)
	Input.action_press("p1_left")
	Input.action_press("p1_rk")
	await g._tick(2)
	_release_all()
	await g._tick(18)
	_check(g.fighters[1].state == "wall_splat" and "WALL SPLAT" in g.event_text, "Wall-splat move near boundary triggers wall_splat state")

	# 11. Josh Meter, Junoon Comeback & Jalwa Super
	await _setup(1.5)
	g.fighters[0].health = 35
	await _tap("p2_lp", 2)
	await g._tick(10)
	_check(g.fighters[0].health == 25 and g.fighters[0].junoon_active and g.fighters[0].junoon_used, "Dropping to <=25 HP triggers Junoon comeback state once")
	await g._tick(25)

	await _setup(1.6)
	g.fighters[0].josh_meter = 100
	await _tap("p1_josh", 2)
	await g._tick(14)
	_check(g.fighters[1].health == 66 and g.fighters[0].josh_meter == 0, "Full Josh super_jalwa deals 34 damage and spends 100 meter")

	await _setup(1.6)
	g.fighters[0].josh_meter = 100
	Input.action_press("p2_guard")
	await g._tick(2)
	await _tap("p1_josh", 2)
	await g._tick(14)
	_release_all()
	_check(g.fighters[1].health == 92 and g.fighters[1].state == "blockstun", "Guarded super_jalwa deals 8 chip damage")

	# 12. Pooled Hit Sparks (Zero Runtime Allocations)
	var pre_count := int(g.feedback.get_total_child_mesh_count())
	for _s in range(10):
		g.feedback.impact(Vector3(0, 1.5, 0.48), false, "punch", true)
	var post_count := int(g.feedback.get_total_child_mesh_count())
	_check(pre_count == 48 and post_count == pre_count, "CombatFeedback reuses fixed 48-spark pool with zero runtime MeshInstance3D allocations")

	# 13. Phase P3 Khan Distinct Animations, Crouch Walk, WalkBack, Guard, Jump & Mid-Range 3D Rock Throw
	await _setup(2.5)
	g.fighters[0].neutral_guard_enabled = true
	Input.action_press("p1_down")
	await g._tick(4)
	_check(g.fighters[0].current_anim_state == "st_crouch" and g.fighters[0].has_finite_bones(), "Khan plays real CrouchIdle animation with finite bones")
	var crouch_start_x: float = g.fighters[0].position.x
	Input.action_press("p1_right")
	await g._tick(16)
	Input.action_release("p1_right")
	var crouch_fwd_x: float = g.fighters[0].position.x
	_check(crouch_fwd_x > crouch_start_x + 0.25 and g.fighters[0].state == "crouch" and g.fighters[0].current_anim_state == "st_crouch_walk" and g.fighters[0].has_finite_bones(), "Crouch forward walk advances along road with CrouchWalk clip even under neutral guard")
	Input.action_press("p1_left")
	await g._tick(16)
	_release_all()
	_check(g.fighters[0].position.x < crouch_fwd_x - 0.25 and g.fighters[0].state == "crouch_guard" and g.fighters[0].current_anim_state == "st_crouch_walk_back" and g.fighters[0].has_finite_bones(), "Crouch backward walk moves back while keeping crouch_guard and CrouchWalkBack clip")
	await g._tick(3)

	await _setup(2.2)
	var walk_start_x: float = g.fighters[0].position.x
	Input.action_press("p1_left")
	await g._tick(12)
	_check(g.fighters[0].current_anim_state == "walk_back" and g.fighters[0].position.x < walk_start_x - 0.35 and g.fighters[0].has_finite_bones(), "Standing backward walk plays WalkBack slot and moves backward")
	Input.action_release("p1_left")
	await g._tick(4)

	Input.action_press("p1_guard")
	await g._tick(4)
	_check(g.fighters[0].state == "guard" and g.fighters[0].current_anim_state == "guard" and khan_def.get_clip("guard") == &"Idle2" and g.fighters[0].has_finite_bones(), "Khan guard uses Idle2 (Bouncing Fight Idle) stance cleanly")
	Input.action_release("p1_guard")
	await g._tick(3)

	await _tap("p1_jump", 2)
	await g._tick(16)
	_check(g.fighters[0].position.y > 0.8 and g.fighters[0].current_anim_state == "st_jump" and g.fighters[0].has_finite_bones(), "Khan jump seeks st_jump Jump clip cleanly while airborne")
	await g._tick(35)

	await _setup(3.6)
	Input.action_press("p1_lp")
	Input.action_press("p1_lk")
	await g._tick(2)
	_release_all()
	_check(g.fighters[0].state == "attack" and g.fighters[0].attack_kind == "rock_throw" and g.fighters[0].current_anim_state == "clip_throwrock", "Khan mid-range 1+3 routes to dedicated rock_throw (ThrowRock)")
	await g._tick(14)
	var hand_rock = g.fighters[0].get("_hand_rock")
	_check(hand_rock != null and hand_rock.visible and g.rock_proj.is_empty(), "Khan bends down to pick up visible HandRockProp before throwing")
	await g._tick(32)
	_check(not g.rock_proj.is_empty(), "Khan mid-range 1+3 launches 3D cliff_rock projectile")
	await g._tick(18)
	_check(g.fighters[1].health == 82 and g.fighters[1].current_anim_state == "st_hit_head" and g.fighters[1].has_finite_bones() and "PATTHAR" in g.event_text, "3D rock projectile strikes opponent head (18 dmg) and triggers HitHead reaction")

	await _setup(1.6)
	g.fighters[0].josh_meter = 100
	await _tap("p1_josh", 2)
	await g._tick(6)
	_check(g.fighters[0].current_anim_state == "clip_jalwasuper" and g.feedback.super_flash_ticks > 0 and g.fighters[0].has_finite_bones(), "Khan super_jalwa triggers JalwaSuper clip and speedlines burst VFX")
	await g._tick(20)

	# 14. Phase P3 Part 2: Taunt (3+4), BlockHit & Asim Distinct Motifect Library
	await _setup(2.0)
	Input.action_press("p1_lk")
	Input.action_press("p1_rk")
	await g._tick(3)
	_release_all()
	_check(g.fighters[0].state == "taunt" and g.fighters[0].current_anim_state == "st_taunt" and "ABSOLUTELY NOT!" in g.event_text and g.fighters[0].has_finite_bones(), "Khan standing 3+4 triggers Standing Taunt Battlecry and ABSOLUTELY NOT! callout")

	await _setup(2.0)
	Input.action_press("p2_lk")
	Input.action_press("p2_rk")
	await g._tick(3)
	_release_all()
	_check(g.fighters[1].state == "taunt" and g.fighters[1].current_anim_state == "st_taunt" and "SALUTE!" in g.event_text and g.fighters[1].has_finite_bones(), "Asim standing 3+4 triggers military salute taunt and SALUTE! callout")

	await _setup(1.4)
	Input.action_press("p1_guard")
	await g._tick(2)
	await _tap("p2_lp", 2)
	await g._tick(7)
	_release_all()
	_check(g.fighters[0].state == "blockstun" and g.fighters[0].current_anim_state == "st_block_hit" and g.fighters[0].has_finite_bones(), "Khan blocking triggers BlockHit clip cleanly")

	await _setup(1.4)
	Input.action_press("p2_guard")
	await g._tick(2)
	await _tap("p1_lp", 2)
	await g._tick(7)
	_release_all()
	_check(g.fighters[1].state == "blockstun" and g.fighters[1].current_anim_state == "st_block_hit" and g.fighters[1].has_finite_bones(), "Asim blocking triggers BlockHit clip cleanly")

	# Asim distinct attacks & locomotion
	await _setup(1.8)
	await _tap("p2_lp", 2)
	await g._tick(2)
	_check(g.fighters[1].attack_kind == "punch" and g.fighters[1].current_anim_state == "punch" and asim_def.get_move("punch").animation_clip == &"JabLeft" and g.fighters[1].has_finite_bones(), "Asim 1 uses JabLeft clip cleanly")
	await g._tick(26)

	await _setup(1.8)
	await _tap("p2_rp", 2)
	await g._tick(3)
	_check(g.fighters[1].attack_kind == "heavy_punch" and g.fighters[1].current_anim_state == "clip_crossright" and g.fighters[1].has_finite_bones(), "Asim 2 uses CrossRight clip")
	await g._tick(45)

	await _setup(1.8)
	await _tap("p2_lk", 2)
	await g._tick(3)
	_check(g.fighters[1].attack_kind == "quick_kick" and g.fighters[1].current_anim_state == "clip_frontkick" and g.fighters[1].has_finite_bones(), "Asim 3 uses FrontKick clip")
	await g._tick(35)

	await _setup(1.8)
	Input.action_press("p2_down")
	Input.action_press("p2_lk")
	await g._tick(2)
	_release_all()
	await g._tick(3)
	_check(g.fighters[1].attack_kind == "low_sweep" and g.fighters[1].current_anim_state == "clip_sweepkick" and g.fighters[1].has_finite_bones(), "Asim d+3 uses SweepKick clip")
	await g._tick(56)

	await _setup(1.8)
	Input.action_press("p2_down")
	Input.action_press("p2_left")
	Input.action_press("p2_rp")
	await g._tick(2)
	_release_all()
	await g._tick(3)
	_check(g.fighters[1].attack_kind == "launcher" and g.fighters[1].current_anim_state == "clip_uppercutright" and g.fighters[1].has_finite_bones(), "Asim df+2 uses UppercutRight clip")
	await g._tick(56)

	await _setup(1.3)
	Input.action_press("p2_lp")
	Input.action_press("p2_lk")
	await g._tick(2)
	_release_all()
	await g._tick(2)
	_check(g.fighters[1].attack_kind == "throw_front" and g.fighters[1].current_anim_state == "clip_grabthrow" and g.fighters[1].has_finite_bones(), "Asim 1+3 uses GrabThrow clip")
	await g._tick(45)

	await _setup(1.8)
	g.fighters[1].josh_meter = 100
	await _tap("p2_josh", 2)
	await g._tick(4)
	_check(g.fighters[1].attack_kind == "super_jalwa" and g.fighters[1].current_anim_state == "clip_combopunchkick" and g.fighters[1].has_finite_bones(), "Asim super_jalwa uses ComboPunchKick clip")
	await g._tick(48)

	await _setup(2.4)
	Input.action_press("p2_right")
	await g._tick(8)
	_check(g.fighters[1].current_anim_state == "walk_back" and g.fighters[1].has_finite_bones(), "Asim walking backward plays WalkBack clip")
	Input.action_release("p2_right")
	await g._tick(2)
	Input.action_press("p2_down")
	Input.action_press("p2_left")
	await g._tick(8)
	_check(g.fighters[1].current_anim_state == "st_crouch_walk" and g.fighters[1].has_finite_bones(), "Asim crouch walk forward plays CrouchWalk clip")
	_release_all()
	await g._tick(3)
	await _tap("p2_right", 2)
	await g._tick(2)
	Input.action_press("p2_right")
	await g._tick(2)
	Input.action_release("p2_right")
	_check(g.fighters[1].state == "backdash" and g.fighters[1].current_anim_state == "st_backdash" and g.fighters[1].has_finite_bones(), "Asim backdash plays Step Backward clip (same as Khan)")
	await g._tick(28)
	var k_walk: Animation = g.fighters[0].anim_player.get_animation(khan_def.get_clip("walk"))
	var a_walk: Animation = g.fighters[1].anim_player.get_animation(asim_def.get_clip("walk"))
	var k_bd: Animation = g.fighters[0].anim_player.get_animation(khan_def.get_clip("backdash"))
	var a_bd: Animation = g.fighters[1].anim_player.get_animation(asim_def.get_clip("backdash"))
	_check(k_walk != null and a_walk != null and is_equal_approx(k_walk.length, a_walk.length), "Asim Walk clip matches Khan Walking.fbx duration")
	_check(k_bd != null and a_bd != null and is_equal_approx(k_bd.length, a_bd.length), "Asim Backdash clip matches Khan Step Backward.fbx duration")
	await _tap("p2_down", 2)
	await g._tick(2)
	Input.action_press("p2_down")
	await g._tick(2)
	Input.action_release("p2_down")
	_check(g.fighters[1].state == "sidestep" and g.fighters[1].current_anim_state == "st_sidestep" and g.fighters[1].has_finite_bones(), "Asim sidestep plays dodge_left clip")
	await g._tick(24)

	# 15. Slow stand <-> crouch transition & single-button Asim Demo (F7)
	await _setup(2.2)
	Input.action_press("p1_down")
	Input.action_press("p2_down")
	await g._tick(2)
	var k_xfade_down: float = g.fighters[0]._state_trans.xfade_time
	var a_xfade_down: float = g.fighters[1]._state_trans.xfade_time
	_check(k_xfade_down >= 0.25 and a_xfade_down >= 0.25, "Stand-to-crouch slows transition xfade for both Khan and Asim")
	await g._tick(18)
	Input.action_release("p1_down")
	Input.action_release("p2_down")
	await g._tick(2)
	_check(g.fighters[0]._state_trans.xfade_time >= 0.25 and g.fighters[1]._state_trans.xfade_time >= 0.25, "Crouch-to-stand slows transition xfade for both Khan and Asim")
	await g._tick(18)
	await _tap("p1_lp", 2)
	await g._tick(2)
	_check(is_equal_approx(g.fighters[0]._state_trans.xfade_time, khan_def.xfade_time), "Attacks restore fast xfade_time immediately")
	await g._tick(24)

	g.toggle_asim_demo(1)
	_check(g.asim_demo.active and not g.asim_demo.current_banner().is_empty(), "Asim single-button demo starts cleanly with HUD banner")
	g.toggle_asim_demo(0)
	_check(not g.asim_demo.active, "Asim demo stops cleanly back to live fight on second toggle")

	g.toggle_asim_demo(1)
	var saw_walk := false
	var saw_backdash := false
	var saw_taunt := false
	var saw_pistol := false
	var saw_combo3 := false
	var saw_juggle := false
	var saw_wall_splat := false
	var saw_super := false
	var all_finite := true
	for _step in range(2450):
		await g._tick(1)
		if g.fighters[1].current_anim_state == "walk":
			saw_walk = true
		if g.fighters[1].current_anim_state == "st_backdash":
			saw_backdash = true
		if g.fighters[1].state == "taunt":
			saw_taunt = true
		if g.fighters[1].state == "attack" and g.fighters[1].attack_kind == "pistol_shoot":
			saw_pistol = true
		if g.fighters[0].combo_hits >= 3:
			saw_combo3 = true
		if g.fighters[0].state == "juggle":
			saw_juggle = true
		if g.fighters[0].state == "wall_splat":
			saw_wall_splat = true
		if g.fighters[1].state == "attack" and g.fighters[1].attack_kind == "super_jalwa":
			saw_super = true
		if not g.fighters[0].has_finite_bones() or not g.fighters[1].has_finite_bones():
			all_finite = false
		if not g.asim_demo.active:
			break
	_check(not g.asim_demo.active and "COMPLETE" in g.event_text, "Asim full moves demo completes all chapters cleanly")
	_check(all_finite and saw_walk and saw_backdash and saw_taunt and saw_pistol, "Asim demo exercises Walk, Backdash, Salute Taunt, and Pistol Shot cleanly")
	_check(saw_combo3 and saw_juggle and saw_wall_splat and saw_super, "Asim demo lands 3-hit combo, juggle, wall splat, and Commander Jalwa super")

	# 16. Round-start entries (Khan Entry (1).fbx walk-in / Asim Crouch To Stand.fbx) & KO victory dances
	_release_all()
	g.testing = false
	g.reset()
	await g._tick(4)
	var k_skel: Skeleton3D = g.fighters[0].skeleton
	var k_hip_idx: int = k_skel.find_bone("mixamorig_Hips")
	if k_hip_idx < 0:
		k_hip_idx = maxi(0, k_skel.find_bone("mixamorig:Hips"))
	var k_entry_start_x: float = k_skel.to_global(k_skel.get_bone_global_pose(k_hip_idx).origin).x
	_check(g.round_state == "ready" and g.fighters[0].current_anim_state == "st_entry" and g.fighters[1].current_anim_state == "st_entry" and g.fighters[0].has_finite_bones() and g.fighters[1].has_finite_bones(), "Round start plays Khan Entry and Asim Crouch To Stand entries cleanly")
	await g._tick(180)
	var k_entry_end_x: float = k_skel.to_global(k_skel.get_bone_global_pose(k_hip_idx).origin).x
	_check(k_entry_start_x < -4.5 and absf(k_entry_end_x - g.fighters[0].position.x) < 0.25, "Khan walks in from afar during Entry and arrives at fighting position on FIGHT")
	_check(g.round_state == "fight" and g.fighters[0].current_anim_state == "idle" and g.fighters[1].current_anim_state == "idle", "Round entries finish cleanly into Idle at FIGHT")
	g.testing = true

	await _setup(1.5)
	g.fighters[1].health = 10
	await _tap("p1_lp", 2)
	await g._tick(28)
	_check(g.round_state == "round_over" and g.fighters[1].state == "ko" and g.fighters[0].state != "victory", "Khan waits for opponent KO falling animation before celebrating")
	await g._tick(90)
	_check(g.fighters[0].state == "victory" and g.fighters[0].current_anim_state == "st_victory" and g.fighters[0].has_finite_bones(), "Khan celebrates KO victory with Rumba Dancing after fall completes")

	await _setup(1.5)
	g.fighters[0].health = 10
	await _tap("p2_lp", 2)
	await g._tick(28)
	_check(g.round_state == "round_over" and g.fighters[0].state == "ko" and g.fighters[1].state != "victory", "Asim waits for opponent KO falling animation before celebrating")
	await g._tick(90)
	_check(g.fighters[1].state == "victory" and g.fighters[1].current_anim_state == "st_victory" and g.fighters[1].has_finite_bones(), "Asim celebrates KO victory with Silly Dancing after fall completes")

	# 17. Jump-over side switch triggers Running Turn 180
	await _setup(2.0)
	Input.action_press("p1_right")
	await _tap("p1_jump", 2)
	var saw_def_turn := false
	var saw_jump_turn := false
	var turn_finite := true
	for _jt in range(60):
		await g._tick(1)
		if g.fighters[1].turn_ticks > 0 and g.fighters[1].current_anim_state == "st_turn_180":
			saw_def_turn = true
		if g.fighters[0].turn_ticks > 0 and g.fighters[0].current_anim_state == "st_turn_180":
			saw_jump_turn = true
		if not g.fighters[0].has_finite_bones() or not g.fighters[1].has_finite_bones():
			turn_finite = false
		if _jt == 36:
			Input.action_release("p1_right")
	_release_all()
	_check(saw_def_turn and saw_jump_turn and turn_finite and g.fighters[0].facing < 0.0 and g.fighters[1].facing > 0.0, "Jumping over opponent triggers Running Turn 180 on both fighters with finite bones")
	await g._tick(10)
	_check(g.fighters[0].turn_ticks == 0 and g.fighters[1].turn_ticks == 0 and g.fighters[0].current_anim_state == "idle", "Both fighters finish Running Turn 180 cleanly into Idle facing each other")

	# 18. Asim M1911 Mid-Range Pistol Shot (pistol_shoot / ShootPistol + flying 3D bullet)
	await _setup(3.8)
	Input.action_press("p2_lp")
	Input.action_press("p2_lk")
	await g._tick(2)
	_release_all()
	var hand_pistol = g.fighters[1].get("_hand_pistol")
	_check(g.fighters[1].state == "attack" and g.fighters[1].attack_kind == "pistol_shoot" and g.fighters[1].current_anim_state == "clip_shootpistol" and hand_pistol != null and hand_pistol.visible and g.fighters[1].has_finite_bones(), "Asim mid-range 1+3 routes to pistol_shoot (ShootPistol) with visible M1911 prop")
	await g._tick(18)
	_check(not g.bullet_proj.is_empty() and g.feedback.flying_bullet != null and g.feedback.flying_bullet.visible, "Asim pistol_shoot spawns flying 3D .45 ACP bullet projectile at barrel muzzle")
	await g._tick(14)
	_check(g.fighters[0].health == 84 and g.fighters[0].current_anim_state == "st_hit_body" and "PISTOL" in g.event_text and g.bullet_proj.is_empty() and g.fighters[0].has_finite_bones(), "3D bullet strikes standing opponent (16 dmg), triggers HitBody, and clears projectile")

	await _setup(3.6)
	Input.action_press("p1_down")
	await g._tick(4)
	Input.action_press("p2_lp")
	Input.action_press("p2_lk")
	await g._tick(2)
	Input.action_release("p2_lp")
	Input.action_release("p2_lk")
	await g._tick(26)
	_check(g.fighters[0].health == 100 and not g.bullet_proj.is_empty(), "High pistol bullet passes cleanly above crouching opponent mid-flight")
	await g._tick(38)
	_release_all()
	_check(g.fighters[0].health == 100 and g.bullet_proj.is_empty(), "Crouching opponent ducks cleanly under high pistol bullet")

	await _setup(3.6)
	Input.action_press("p1_guard")
	await g._tick(2)
	Input.action_press("p2_lp")
	Input.action_press("p2_lk")
	await g._tick(2)
	Input.action_release("p2_lp")
	Input.action_release("p2_lk")
	await g._tick(32)
	_release_all()
	_check(g.fighters[0].health == 97 and "BLOCKED SHOT!" in g.event_text and g.bullet_proj.is_empty(), "Standing guard blocks pistol bullet for 3 chip damage and BLOCKED SHOT! callout")

	if not g.capture_dir.is_empty() and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(g.capture_dir)
		await _setup(6.4)
		Input.action_press("p2_lp")
		Input.action_press("p2_lk")
		await g._tick(2)
		_release_all()
		for _f in range(24):
			if g.fighters[1].state == "attack" and g.fighters[1].attack_kind == "pistol_shoot" and g.fighters[1].attack_tick >= 18:
				break
			await g._tick(1)
		await g._save_capture("p3-asim-pistol-fire")
		await g._tick(3)
		await g._save_capture("p3-asim-pistol-flight")
		for _h in range(20):
			if g.fighters[0].health < 100:
				break
			await g._tick(1)
		await g._tick(4)
		await g._save_capture("p3-asim-pistol-hit")

	# 19. Full-Junoon Fire Aura & Reworked JalwaSuper Lightning/Slash/Crater Finisher VFX
	await _setup(3.4)
	g.fighters[0].josh_meter = 100
	g.fighters[1].josh_meter = 100
	await g._tick(6)
	var k_body_mat: ShaderMaterial = g.fighters[0].get("_body_fire_overlay_mat") as ShaderMaterial
	var a_body_mat: ShaderMaterial = g.fighters[1].get("_body_fire_overlay_mat") as ShaderMaterial
	var k_shroud: MeshInstance3D = g.fighters[0].get("_fire_shroud_outer") as MeshInstance3D
	var a_shroud: MeshInstance3D = g.fighters[1].get("_fire_shroud_outer") as MeshInstance3D
	_check(
		g.fighters[0].is_full_junoon_aura()
		and g.fighters[1].is_full_junoon_aura()
		and g.fighters[0].get("_junoon_flames").emitting
		and g.fighters[1].get("_junoon_flames").emitting
		and k_shroud != null and k_shroud.visible
		and a_shroud != null and a_shroud.visible
		and k_body_mat != null and float(k_body_mat.get_shader_parameter("intensity")) > 0.5
		and a_body_mat != null and float(a_body_mat.get_shader_parameter("intensity")) > 0.5,
		"Full Josh/Junoon bar (100) covers both fighters in full-body fire aura, shrouds, and flames"
	)
	if not g.capture_dir.is_empty() and DisplayServer.get_name() != "headless":
		await g._tick(10)
		await g._save_capture("p3-full-junoon-fire-aura")
	g.fighters[0].josh_meter = 0
	g.fighters[1].josh_meter = 0
	await g._tick(4)
	_check(not g.fighters[0].is_full_junoon_aura() and not k_shroud.visible and float(k_body_mat.get_shader_parameter("intensity")) <= 0.01, "Fire aura clears cleanly when Josh meter drops below 100")

	await _setup(2.2)
	g.fighters[0].josh_meter = 100
	await _tap("p1_josh", 2)
	await g._tick(3)
	var startup_bolt_vis: bool = not g.feedback.lightning_sky_bolts.is_empty() and g.feedback.lightning_sky_bolts[0].visible
	_check(
		g.fighters[0].current_anim_state == "clip_jalwasuper"
		and g.feedback.super_flash_ticks > 0
		and startup_bolt_vis
		and float(g.feedback.sky_dim_factor) > 0.2
		and g.fighters[0].has_finite_bones(),
		"Reworked JalwaSuper triggers sky lightning summon, storm dimming, and finite bones"
	)
	if not g.capture_dir.is_empty() and DisplayServer.get_name() != "headless":
		await g._save_capture("p3-jalwa-super-startup")
	for _jf in range(18):
		if g.fighters[1].health < 100:
			break
		await g._tick(1)
	_check(
		g.fighters[1].health == 66
		and float(g.feedback.finisher_age) < 0.45
		and g.feedback.ground_crack != null and g.feedback.ground_crack.visible
		and g.feedback.slash_wave != null and g.feedback.slash_wave.visible
		and g.feedback.lightning_sky_bolts.size() >= 3 and g.feedback.lightning_sky_bolts[1].visible
		and int(g.feedback.get_total_child_mesh_count()) == 48
		and g.fighters[0].has_finite_bones() and g.fighters[1].has_finite_bones(),
		"JalwaSuper finisher strikes with twin 3D lightning bolts, 3D slash wave, crater crack, and fixed 48-spark pool"
	)
	if not g.capture_dir.is_empty() and DisplayServer.get_name() != "headless":
		await g._save_capture("p3-jalwa-super-finisher")

	# 20. Hit Knockdown (SweepFall) -> Stand Up (WakeupStand) vs KO (KnockdownDeath)
	_check(
		khan_def.get_clip("knockdown") == &"SweepFall"
		and khan_def.get_clip("ko") == &"KnockdownDeath"
		and khan_def.get_clip("wakeup") == &"WakeupStand"
		and asim_def.get_clip("knockdown") == &"SweepFall"
		and asim_def.get_clip("ko") == &"KnockdownDeath"
		and asim_def.get_clip("wakeup") == &"WakeupStand",
		"Khan & Asim map hit knockdown to SweepFall, stand-up to WakeupStand, and KO to KnockdownDeath"
	)
	await _setup(1.8)
	Input.action_press("p1_down")
	await g._tick(2)
	await _tap("p1_lk", 2)
	_release_all()
	await g._tick(28)
	_check(g.fighters[1].state == "knockdown" and g.fighters[1].current_anim_state == "st_knockdown" and g.fighters[1].has_finite_bones(), "Hit knockdown plays SweepFall clip cleanly with finite bones")
	await g._tick(20)
	if not g.capture_dir.is_empty() and DisplayServer.get_name() != "headless":
		await g._save_capture("p3-sweep-fall")
	await g._tick(58)
	_check(g.fighters[1].state == "wakeup_stand" and g.fighters[1].current_anim_state == "st_wakeup" and g.fighters[1].has_finite_bones(), "Auto-wakeup from SweepFall plays Stand Up clip (st_wakeup) cleanly")
	await g._tick(32)
	if not g.capture_dir.is_empty() and DisplayServer.get_name() != "headless":
		await g._save_capture("p3-stand-up")
	await g._tick(48)
	_check(g.fighters[1].state == "idle" and g.fighters[1].current_anim_state == "idle" and g.fighters[1].has_finite_bones(), "Fighter returns smoothly to Idle after Stand Up completes")

	await _setup(1.6)
	g.fighters[1].health = 8
	await _tap("p1_lp", 2)
	await g._tick(16)
	_check(g.fighters[1].state == "ko" and g.fighters[1].current_anim_state == "st_ko" and g.fighters[1].has_finite_bones(), "Lethal KO continues to play KnockdownDeath clip (st_ko) unchanged")

	# 21. Aerial Attacks (JumpPunch & JumpKick)
	var k_air_p = khan_def.get_move("air_punch")
	var k_air_k = khan_def.get_move("air_kick")
	var a_air_p = asim_def.get_move("air_punch")
	var a_air_k = asim_def.get_move("air_kick")
	_check(
		k_air_p != null and k_air_p.animation_clip == &"JumpPunch"
		and k_air_k != null and k_air_k.animation_clip == &"JumpKick"
		and a_air_p != null and a_air_p.animation_clip == &"JumpPunch"
		and a_air_k != null and a_air_k.animation_clip == &"JumpKick",
		"Khan & Asim CharacterDef map air_punch -> JumpPunch and air_kick -> JumpKick"
	)

	await _setup(2.4)
	Input.action_press("p1_right")
	await g._tick(1)
	await _tap("p1_jump", 2)
	await g._tick(10)
	Input.action_release("p1_right")
	await _tap("p1_lp", 2)
	await g._tick(5)
	_check(
		not g.fighters[0].is_on_floor()
		and g.fighters[0].state == "attack"
		and g.fighters[0].attack_kind == "air_punch"
		and g.fighters[0].current_anim_state == "clip_jumppunch"
		and g.fighters[0].has_finite_bones(),
		"Khan mid-air punch triggers JumpPunch clip cleanly with finite bones"
	)
	if not g.capture_dir.is_empty() and DisplayServer.get_name() != "headless":
		await g._tick(2)
		await g._save_capture("p3-air-punch")
	await g._tick(14)
	_check(g.fighters[1].health == 87, "Jumping Flying Knee Punch connects as mid overhead on standing opponent (13 dmg)")
	await g._tick(28)
	_check(g.fighters[0].is_on_floor() and g.fighters[0].state == "idle" and not g.fighters[0].air_attack_used, "Landing from JumpPunch resets air_attack_used and returns cleanly to Idle")

	await _setup(2.5)
	Input.action_press("p2_left")
	await g._tick(1)
	await _tap("p2_jump", 2)
	await g._tick(9)
	Input.action_release("p2_left")
	await _tap("p2_rk", 2)
	await g._tick(7)
	_check(
		not g.fighters[1].is_on_floor()
		and g.fighters[1].state == "attack"
		and g.fighters[1].attack_kind == "air_kick"
		and g.fighters[1].current_anim_state == "clip_jumpkick"
		and g.fighters[1].has_finite_bones(),
		"Asim mid-air kick triggers Drop Kick (JumpKick) clip cleanly with finite bones"
	)
	if not g.capture_dir.is_empty() and DisplayServer.get_name() != "headless":
		await g._tick(2)
		await g._save_capture("p3-air-kick")
	await g._tick(16)
	_check(g.fighters[0].health == 84 and g.fighters[0].state == "knockdown", "Jumping Drop Kick connects cleanly and knocks standing opponent down (16 dmg)")
	await g._tick(30)
	_check(g.fighters[1].is_on_floor() and not g.fighters[1].air_attack_used, "Landing from Drop Kick resets air_attack_used cleanly")

	await _setup(2.2)
	Input.action_press("p2_down")
	Input.action_press("p1_right")
	await g._tick(2)
	await _tap("p1_jump", 2)
	await g._tick(10)
	Input.action_release("p1_right")
	await _tap("p1_lp", 2)
	await g._tick(22)
	_release_all()
	_check(g.fighters[1].health == 87, "Mid-level JumpPunch hits crouching opponent cleanly (cannot be ducked)")

	var report := {
		"passed": g.checks,
		"failed": g.failures,
		"frame_data": fd_report,
		"spark_pool_size": pre_count,
		"renderer": RenderingServer.get_current_rendering_method(),
		"engine": Engine.get_version_info().string,
	}
	if not g.capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(g.capture_dir)
		var file := FileAccess.open(g.capture_dir.path_join("combat-v2-validation.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "  "))

	print("COMBAT_V2_VALIDATION " + JSON.stringify(report))
	g.get_tree().quit(0 if g.failures.is_empty() else 1)
