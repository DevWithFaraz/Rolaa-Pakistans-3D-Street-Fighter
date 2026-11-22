class_name AsimDemo
extends RefCounted
## Single-button (F7 / --asim-demo) scripted combat showcase exercising all of Asim Jani's moves, combos, locomotion, and reactions.

const InputBufferScript = preload("res://scripts/input_buffer.gd")

var active: bool = false
var chapter_idx: int = 0
var chapter_tick: int = 0
var banner_text: String = ""
var _chapters: Array[Dictionary] = []


func start(proof: Node) -> void:
	_build_chapters()
	active = true
	chapter_idx = 0
	chapter_tick = 0
	proof.paused = false
	proof.demo = false
	proof.wins[0] = 0
	proof.wins[1] = 0
	proof.round_number = 1
	proof._start_round()
	_apply_chapter_setup(proof, _chapters[0])


func stop(proof: Node, announce: String = "") -> void:
	if not active:
		return
	active = false
	chapter_idx = 0
	chapter_tick = 0
	banner_text = ""
	proof.reset()
	proof.round_state = "fight"
	proof.round_ticks = 0
	if not announce.is_empty():
		proof.event_text = announce
		proof.event_ticks = 90


func current_banner() -> String:
	if not active or _chapters.is_empty():
		return ""
	return "ASIM DEMO [%d/%d]  ·  %s" % [chapter_idx + 1, _chapters.size(), banner_text]


func step_frame(proof: Node) -> Dictionary:
	var out := {
		"axes": [0.0, 0.0],
		"jumps": [false, false],
		"ups": [false, false],
		"downs": [false, false],
		"guards": [false, false],
		"masks": [0, 0],
	}
	if not active or _chapters.is_empty():
		return out

	if chapter_tick == 0:
		_apply_chapter_setup(proof, _chapters[chapter_idx])

	var ch: Dictionary = _chapters[chapter_idx]
	banner_text = String(ch.title)
	proof.round_time_ticks = proof.ROUND_DURATION

	for ev in ch.events:
		var t0 := int(ev[0])
		var t1 := int(ev[1])
		if chapter_tick >= t0 and chapter_tick <= t1:
			var slot := int(ev[2])
			var kind := String(ev[3])
			var val = ev[4]
			match kind:
				"axis":
					out.axes[slot] = float(val)
				"fwd":
					# Relative forward toward opponent (Asim on right = -1, Khan on left = +1)
					out.axes[slot] = proof.fighters[slot].facing * float(val)
				"back":
					out.axes[slot] = -proof.fighters[slot].facing * float(val)
				"down":
					out.downs[slot] = bool(val)
				"up":
					out.ups[slot] = bool(val)
				"jump":
					out.jumps[slot] = bool(val) and chapter_tick == t0
					out.ups[slot] = bool(val)
				"guard":
					out.guards[slot] = bool(val)
					out.masks[slot] = int(out.masks[slot]) | InputBufferScript.BTN_GUARD
				"btn":
					out.masks[slot] = int(out.masks[slot]) | int(val)

	chapter_tick += 1
	if chapter_tick >= int(ch.duration):
		chapter_idx += 1
		chapter_tick = 0
		if chapter_idx >= _chapters.size():
			stop(proof, "ASIM DEMO COMPLETE! LIVE FIGHT READY")

	return out


func _apply_chapter_setup(proof: Node, ch: Dictionary) -> void:
	proof.round_state = "fight"
	proof.round_ticks = 0
	proof.hitstop_ticks = 0
	proof.pending_attacks[0] = ""
	proof.pending_attacks[1] = ""
	proof.pending_ticks[0] = 0
	proof.pending_ticks[1] = 0
	proof.active_throw.clear()
	proof.rock_proj.clear()
	proof.bullet_proj.clear()
	proof.feedback.clear()

	var center_x := float(ch.get("center_x", 0.0))
	var dist := float(ch.get("dist", 1.7))
	proof.dummy_mode = String(ch.get("dummy_mode", "stand"))
	proof.dummy_guard = (proof.dummy_mode == "always_guard")

	for i in range(2):
		var f = proof.fighters[i]
		f.reset_combat()
		f.neutral_guard_enabled = false
		f.health = int(ch.get("khan_hp", 100)) if i == 0 else int(ch.get("asim_hp", 100))
		f.josh_meter = int(ch.get("asim_josh", 0)) if i == 1 else int(ch.get("khan_josh", 0))
		f.junoon_active = bool(ch.get("asim_junoon", false)) if i == 1 else false
		f.position = Vector3(center_x - dist * 0.5 if i == 0 else center_x + dist * 0.5, 0.025, 0.0)
		f.velocity = Vector3.ZERO
		f.facing = 1.0 if i == 0 else -1.0
		proof._prev_junoon[i] = f.junoon_active
		proof._prev_attack_kind[i] = ""
		proof._prev_states[i] = "idle"
	banner_text = String(ch.title)


func _tap_btn(t: int, slot: int, btn: int, hold: int = 2) -> Array:
	return [t, t + hold - 1, slot, "btn", btn]


func _double_tap(t: int, slot: int, dir_kind: String) -> Array[Array]:
	return [
		[t, t + 1, slot, dir_kind, 1.0],
		# t+2..t+3 neutral
		[t + 4, t + 6, slot, dir_kind, 1.0],
	]


func _build_chapters() -> void:
	if not _chapters.is_empty():
		return
	var LP := InputBufferScript.BTN_LP
	var RP := InputBufferScript.BTN_RP
	var LK := InputBufferScript.BTN_LK
	var RK := InputBufferScript.BTN_RK
	var JOSH := InputBufferScript.BTN_JOSH

	# 1. Forward walk (same as Khan) & backward walk
	_chapters.append({
		"title": "WALK FORWARD (SAME AS KHAN) & WALK BACK",
		"dist": 4.2, "duration": 96,
		"events": [
			[4, 42, 1, "fwd", 1.0],
			[48, 86, 1, "back", 1.0],
		],
	})

	# 2. Slow stand -> crouch -> crouch walk -> crouch walk back -> slow crouch -> stand
	_chapters.append({
		"title": "SLOW STAND <-> CROUCH & CROUCH WALK",
		"dist": 3.4, "duration": 144,
		"events": [
			[10, 108, 1, "down", true],
			[34, 62, 1, "fwd", 1.0],
			[68, 96, 1, "back", 1.0],
			# 109..143 stands slowly back up via CROUCH_TRANSITION_XFADE
		],
	})

	# 3. Dash forward, Backdash (same as Khan Step Backward), Sidestep & Jump
	var ev3: Array = []
	ev3.append_array(_double_tap(6, 1, "fwd"))
	ev3.append_array(_double_tap(34, 1, "back"))
	ev3.append([66, 67, 1, "down", true])
	ev3.append([70, 72, 1, "down", true])
	ev3.append([96, 98, 1, "jump", true])
	_chapters.append({
		"title": "DASH FORWARD, BACKDASH (SAME AS KHAN), SIDESTEP & JUMP",
		"dist": 3.2, "duration": 150,
		"events": ev3,
	})

	# 4. Guard stance & BlockHit + Khan hits Asim (Head & Body reactions)
	_chapters.append({
		"title": "GUARD (IDLE2), BLOCKHIT & HIT REACTIONS (HEAD/BODY)",
		"dist": 1.65, "duration": 136,
		"events": [
			[4, 42, 1, "guard", true],
			_tap_btn(12, 0, LP),
			_tap_btn(50, 0, LP),
			[84, 96, 0, "down", true],
			_tap_btn(85, 0, LP),
		],
	})

	# 5. Salute Taunt (3+4)
	_chapters.append({
		"title": "MILITARY SALUTE TAUNT (3+4)",
		"dist": 2.4, "duration": 106,
		"events": [
			_tap_btn(8, 1, LK | RK),
		],
	})

	# 6. Left Jab (1) & Twin Jab (1,1)
	_chapters.append({
		"title": "LEFT JAB (1 -> JABLEFT) & TWIN JAB (1,1 -> JABCROSS)",
		"dist": 1.65, "duration": 96,
		"events": [
			_tap_btn(6, 1, LP),
			_tap_btn(42, 1, LP),
			_tap_btn(52, 1, LP),
		],
	})

	# 7. Right Cross (2) & 3-Hit Target Combo (1 -> 2 -> 4)
	_chapters.append({
		"title": "RIGHT CROSS (2) & 3-HIT COMBO (1 -> 2 -> 4)",
		"dist": 1.35, "duration": 124,
		"events": [
			_tap_btn(6, 1, RP),
			_tap_btn(56, 1, LP),
			_tap_btn(63, 1, RP),
			_tap_btn(83, 1, RK),
		],
	})

	# 8. Front Boot (3) & Heavy Kick (4)
	_chapters.append({
		"title": "FRONT BOOT (3 LOW) & HEAVY KICK (4 MID)",
		"dist": 1.85, "duration": 96,
		"events": [
			_tap_btn(6, 1, LK),
			_tap_btn(46, 1, RK),
		],
	})

	# 9. Body Blow (d+1) & Boot Sweep (d+3) -> WakeupStand (Stand Up)
	_chapters.append({
		"title": "BODY BLOW (D+1), BOOT SWEEP (D+3) & GET-UP WAKEUP",
		"dist": 1.65, "duration": 225,
		"events": [
			[6, 12, 1, "down", true],
			_tap_btn(7, 1, LP),
			[40, 48, 1, "down", true],
			_tap_btn(41, 1, LK),
		],
	})

	# 10. Commander Uppercut (df+2) -> Air Juggle Combo (df+2 -> 1 -> 2 -> 4)
	_chapters.append({
		"title": "COMMANDER UPPERCUT (DF+2) + AIR JUGGLE COMBO!",
		"dist": 1.35, "duration": 152,
		"events": [
			[6, 14, 1, "down", true],
			[6, 14, 1, "fwd", 1.0],
			_tap_btn(8, 1, RP),
			[38, 68, 1, "fwd", 1.0],
			_tap_btn(69, 1, LP),
			_tap_btn(76, 1, RP),
			_tap_btn(96, 1, RK),
		],
	})

	# 11. Iron Headbutt (f+2 Homing Wall-Splat) & Commander Roundhouse (b+4)
	_chapters.append({
		"title": "IRON HEADBUTT (F+2 WALL SPLAT!) & ROUNDHOUSE (B+4)",
		"dist": 1.70, "center_x": -12.65, "duration": 134,
		"events": [
			[6, 12, 1, "fwd", 1.0],
			_tap_btn(7, 1, RP),
			[74, 80, 1, "back", 1.0],
			_tap_btn(75, 1, RK),
		],
	})

	# 12. Salute & Strike Signature (1+2) & Military Throw (1+3)
	_chapters.append({
		"title": "SALUTE & STRIKE (1+2) & MILITARY THROW (1+3)",
		"dist": 1.50, "duration": 140,
		"events": [
			_tap_btn(6, 1, LP | RP),
			[68, 80, 1, "fwd", 1.0],
			_tap_btn(84, 1, LP | LK),
		],
	})

	# 13. M1911 Pistol Shot (1+3 at mid-range)
	_chapters.append({
		"title": "M1911 PISTOL SHOT (1+3 MID-RANGE) - BULLET HIT!",
		"dist": 3.8, "duration": 96,
		"events": [
			_tap_btn(8, 1, LP | LK),
		],
	})

	# 14. Full Junoon + Commander Jalwa Super (Josh)
	_chapters.append({
		"title": "JUNOON + COMMANDER JALWA SUPER (O / COMBOPUNCHKICK)",
		"dist": 2.1, "duration": 120, "asim_josh": 100, "asim_junoon": true,
		"events": [
			_tap_btn(10, 1, JOSH),
		],
	})
