extends Control

const WHITE = Color("f5ebd5")
const GOLD = Color("e3b566")
const DARK = Color("152e35")
const MUTED = Color("a9bfbb")
const PANEL = Color(0.06, 0.13, 0.16, 0.94)
var proof: Node
var show_help := true
var show_debug := false
var font: Font
var speedlines_tex: Texture2D
var badge_junoon_tex: Texture2D
var badge_jalwa_tex: Texture2D
var _prewarm_frames := 0
var _cached_subtitle := ""
var _cached_panel_w := 315.0
var _prev_sig: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = ThemeDB.fallback_font
	if ResourceLoader.exists("res://assets/vfx/jalwa_speedlines.png"):
		speedlines_tex = load("res://assets/vfx/jalwa_speedlines.png") as Texture2D
	if ResourceLoader.exists("res://assets/vfx/badge_junoon.png"):
		badge_junoon_tex = load("res://assets/vfx/badge_junoon.png") as Texture2D
	if ResourceLoader.exists("res://assets/vfx/badge_jalwa.png"):
		badge_jalwa_tex = load("res://assets/vfx/badge_jalwa.png") as Texture2D
	if DisplayServer.get_name() == "headless":
		_prewarm_frames = 2

func _build_hud_sig() -> Array:
	if proof == null or proof.fighters.size() < 2:
		return []
	var f0 = proof.fighters[0]
	var f1 = proof.fighters[1]
	var sft := int(proof.feedback.get("super_flash_ticks")) if proof.feedback != null else 0
	var secs := maxi(0, int(ceilf(float(proof.round_time_ticks) / 60.0)))
	return [
		size, show_help, show_debug, proof.demo, proof.paused,
		proof.asim_demo.active if proof.get("asim_demo") != null else false,
		proof.asim_demo.current_banner() if proof.get("asim_demo") != null else "",
		proof.round_state, proof.round_number, int(proof.wins[0]), int(proof.wins[1]),
		proof.result_text, proof.event_ticks > 0, proof.event_text,
		proof.dummy_mode, proof.dummy_guard, secs, sft,
		f0.health, f0.josh_meter, f0.junoon_active, f0.state, f0.attack_kind, f0.combo_hits, f0.combo_damage,
		f1.health, f1.josh_meter, f1.junoon_active, f1.state, f1.attack_kind, f1.combo_hits, f1.combo_damage,
	]

func _process(_delta: float) -> void:
	if show_debug:
		_prev_sig.clear()
		queue_redraw()
		return
	if _prewarm_frames < 2:
		queue_redraw()
		return
	var sig := _build_hud_sig()
	if sig != _prev_sig:
		_prev_sig = sig
		queue_redraw()

func _draw() -> void:
	if proof == null or font == null or proof.fighters.size() < 2:
		return
	var factor = minf(size.x / 1280.0, size.y / 720.0)
	var offset = (size - Vector2(1280, 720) * factor) * 0.5
	draw_set_transform(offset, 0.0, Vector2.ONE * factor)
	if _prewarm_frames < 2 and DisplayServer.get_name() != "headless":
		_prewarm_frames += 1
		# Upload HUD VFX textures to GPU on frame 0-1 under the opaque scoreboard panel.
		for tex in [speedlines_tex, badge_junoon_tex, badge_jalwa_tex]:
			if tex != null:
				draw_texture_rect(tex, Rect2(0, 0, 1, 1), false, Color(1.0, 1.0, 1.0, 0.01))
	if speedlines_tex != null and proof.feedback != null and int(proof.feedback.get("super_flash_ticks")) > 0:
		var flash_a := clampf(float(proof.feedback.get("super_flash_ticks")) / 20.0, 0.0, 0.88)
		draw_texture_rect(speedlines_tex, Rect2(0, 0, 1280, 720), false, Color(1.0, 0.92, 0.65, flash_a))
	if show_debug:
		_draw_world_boxes(offset, factor)
	_draw_scoreboard()
	_draw_combo_counters()
	_draw_stage_label()
	if show_help:
		_draw_controls()
	else:
		draw_rect(Rect2(24, 674, 252, 25), PANEL)
		_text("H  controls   /   Esc  pause   /   R  restart", Vector2(34, 692), 11, MUTED)
	if show_debug:
		_draw_diagnostics()
	if proof.demo:
		_centered("CAMERA TOUR  /  F2 TO RETURN TO THE FIGHT", 569, 14, GOLD)
	elif proof.get("asim_demo") != null and proof.asim_demo.active:
		draw_rect(Rect2(240, 560, 800, 42), PANEL)
		draw_rect(Rect2(240, 560, 800, 2), GOLD)
		_centered(proof.asim_demo.current_banner() + "   (F7 STOP)", 586, 15, GOLD)
		if proof.event_ticks > 0 and not proof.event_text.is_empty():
			var ev_c = GOLD if "BLOCK" in proof.event_text else WHITE
			draw_rect(Rect2(500, 130, 280, 33), PANEL)
			_centered(proof.event_text, 152, 16, ev_c)
	elif proof.round_state == "ready":
		_banner("ROUND %d" % proof.round_number, "READY", "First to two round wins", GOLD)
	elif proof.round_state == "round_over":
		_banner("ROUND COMPLETE", proof.result_text, "Enter  next round     /     R  restart match", GOLD)
	elif proof.round_state == "match_over":
		_banner("MATCH COMPLETE", proof.result_text, "Enter  rematch     /     R  restart match", GOLD)
	elif proof.event_ticks > 0 and not proof.event_text.is_empty():
		var event_color = GOLD if "BLOCK" in proof.event_text else WHITE
		if proof.event_text == "FIGHT":
			_centered("FIGHT", 286, 44, GOLD)
		else:
			draw_rect(Rect2(529, 130, 222, 33), PANEL)
			_centered(proof.event_text, 152, 17, event_color)
	if proof.paused:
		draw_rect(Rect2(0, 108, 1280, 508), Color(0.04, 0.09, 0.11, 0.65))
		_banner("MATCH PAUSED", "PAUSED", "Esc  resume     /     R  restart match", WHITE)

func _draw_scoreboard() -> void:
	draw_rect(Rect2(0, 0, 1280, 108), PANEL)
	draw_rect(Rect2(0, 106, 1280, 2), GOLD)
	_text("PLAYER 1", Vector2(32, 17), 10, GOLD)
	_text(proof.fighters[0].get_display_name(), Vector2(32, 39), 21, WHITE)
	_right("PLAYER 2", 1248, 17, 10, GOLD)
	_right(proof.fighters[1].get_display_name(), 1248, 39, 21, WHITE)
	_health_bar(Rect2(32, 49, 506, 23), float(proof.fighters[0].health), false)
	_health_bar(Rect2(742, 49, 506, 23), float(proof.fighters[1].health), true)
	for i in range(2):
		for mark in range(2):
			var x = 42.0 + mark * 21.0 if i == 0 else 1238.0 - mark * 21.0
			var won: bool = mark < int(proof.wins[i])
			_diamond(Vector2(x, 88), 6, GOLD if won else Color("476166"))
			if not won:
				_diamond(Vector2(x, 88), 3, DARK)
	_text(_fighter_status(0), Vector2(86, 92), 11, MUTED)
	_right(_fighter_status(1), 1194, 92, 11, MUTED)
	_josh_bar(Rect2(230, 80, 210, 11), int(proof.fighters[0].josh_meter), bool(proof.fighters[0].junoon_active), false)
	_josh_bar(Rect2(840, 80, 210, 11), int(proof.fighters[1].josh_meter), bool(proof.fighters[1].junoon_active), true)
	_text("JOSH", Vector2(192, 90), 10, GOLD if int(proof.fighters[0].josh_meter) >= 100 or bool(proof.fighters[0].junoon_active) else MUTED)
	_right("JOSH", 1088, 90, 10, GOLD if int(proof.fighters[1].josh_meter) >= 100 or bool(proof.fighters[1].junoon_active) else MUTED)
	_right("%d / 100" % proof.fighters[0].health, 538, 92, 11, WHITE)
	_text("%d / 100" % proof.fighters[1].health, Vector2(742, 92), 11, WHITE)
	draw_rect(Rect2(590, 10, 100, 69), Color("284148"))
	draw_rect(Rect2(590, 10, 100, 69), GOLD, false, 1.5)
	var seconds = maxi(0, int(ceilf(float(proof.round_time_ticks) / 60.0)))
	_centered("%02d" % seconds, 60, 43, GOLD if seconds <= 10 else WHITE)
	_centered("ROUND %d" % proof.round_number, 96, 11, GOLD)
	_diamond(Vector2(572, 44), 5, GOLD)
	_diamond(Vector2(708, 44), 5, GOLD)

func _josh_bar(rect: Rect2, meter: int, junoon: bool, reverse: bool) -> void:
	draw_rect(rect, Color("243b42"))
	var inner := Rect2(rect.position + Vector2(2, 2), rect.size - Vector2(4, 4))
	var frac := clampf(float(meter) / 100.0, 0.0, 1.0)
	if frac > 0.0:
		var filled := inner
		filled.size.x *= frac
		if reverse:
			filled.position.x += inner.size.x - filled.size.x
		var col := Color("f0a33c") if (meter >= 100 or junoon) else Color("5fb8d4")
		draw_rect(filled, col)
	if junoon:
		var badge_rect := Rect2(742, 23, 98, 24) if reverse else Rect2(440, 23, 98, 24)
		var tex := badge_jalwa_tex if meter >= 100 else badge_junoon_tex
		if tex != null:
			draw_texture_rect(tex, badge_rect, false)
		if reverse:
			_text("JUNOON!", Vector2(758, 39), 11, Color("ffe28a"))
		else:
			_right("JUNOON!", 526, 39, 11, Color("ffe28a"))

func _draw_combo_counters() -> void:
	var p1_combo := int(proof.fighters[1].combo_hits)
	if p1_combo >= 2:
		draw_rect(Rect2(24, 185, 168, 48), PANEL)
		_text("%d HIT COMBO" % p1_combo, Vector2(36, 208), 16, GOLD)
		_text("%d DMG" % int(proof.fighters[1].combo_damage), Vector2(36, 226), 11, WHITE)
	var p2_combo := int(proof.fighters[0].combo_hits)
	if p2_combo >= 2:
		draw_rect(Rect2(1088, 185, 168, 48), PANEL)
		_right("%d HIT COMBO" % p2_combo, 1244, 208, 16, GOLD)
		_right("%d DMG" % int(proof.fighters[0].combo_damage), 1244, 226, 11, WHITE)

func _health_bar(rect: Rect2, health: float, reverse: bool) -> void:
	draw_rect(rect, Color("476166"))
	var inner = Rect2(rect.position + Vector2(3, 3), rect.size - Vector2(6, 6))
	draw_rect(inner, Color("3d262b"))
	var fraction = clampf(health / 100.0, 0.0, 1.0)
	var filled = inner
	filled.size.x *= fraction
	if reverse:
		filled.position.x += inner.size.x - filled.size.x
	if fraction > 0.0:
		var color = Color("6fc7a4") if fraction > 0.3 else Color("e98968")
		draw_rect(filled, color)
		draw_rect(Rect2(filled.position, Vector2(filled.size.x, 3)), color.lightened(0.22))

func _fighter_status(index: int) -> String:
	var fighter = proof.fighters[index]
	var status: String = str(fighter.state)
	match status:
		"attack", "attacking":
			return str(fighter.attack_kind).replace("_", " ").to_upper()
		"hitstun", "hit_stun":
			return "HIT"
		"blockstun", "block_stun":
			return "BLOCKED"
		"ko":
			return "KNOCKOUT"
		"idle", "move", "walk", "neutral":
			return "READY" if proof.round_state == "ready" else ""
	return status.replace("_", " ").to_upper()

func _draw_stage_label() -> void:
	var rigged: bool = proof.fighters[0].get("character_def") != null
	var subtitle := "P3 ANIMATIONS & VFX  ·  KHAN SAHAB VS ASIM JANI" if rigged else "P3 COMBAT V2  ·  PROTOTYPE FIGHTERS"
	if subtitle != _cached_subtitle:
		_cached_subtitle = subtitle
		_cached_panel_w = maxf(315.0, font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 28.0)
	var panel_w := _cached_panel_w
	draw_rect(Rect2(24, 122, panel_w, 53), PANEL)
	_text("LAHORE  /  MALL ROAD", Vector2(36, 143), 12, GOLD)
	_text(subtitle, Vector2(36, 163), 10, MUTED)
	if not proof.demo:
		var mode_str := String(proof.get("dummy_mode")).replace("_", " ").to_upper()
		if proof.dummy_guard and mode_str == "STAND":
			mode_str = "GUARD ON"
		draw_rect(Rect2(966, 122, 290, 33), PANEL)
		_text("T DUMMY: %s" % mode_str, Vector2(978, 144), 12, GOLD)

func _draw_controls() -> void:
	draw_rect(Rect2(24, 612, 1232, 87), PANEL)
	draw_rect(Rect2(24, 612, 1232, 2), Color("476166"))
	_text("P1", Vector2(42, 642), 14, GOLD)
	_text("WASD move/step  Space jump  U/I/J/K 1-4  O Josh/Jalwa  J+K 3+4 Taunt  [ Shoot/Rock", Vector2(72, 642), 12, WHITE)
	_text("P2", Vector2(42, 676), 14, GOLD)
	_text("Arrows move/crouch  Num 4/5/1/2 1-4  Num6 Josh  Num1+2 Taunt  1+3 Pistol  V/Num0 guard", Vector2(72, 676), 12, WHITE)
	draw_line(Vector2(640, 627), Vector2(640, 686), Color("476166"), 1)
	_text("T dummy   F6 full Josh/Junoon   F7 Asim demo   R restart", Vector2(658, 642), 13, WHITE)
	_text("F2 tour   H help   F3 hitboxes   F5 preset   Enter rematch   Esc pause", Vector2(658, 676), 13, MUTED)

func _world_rect_to_canvas(box: Rect2, offset: Vector2, factor: float) -> Rect2:
	if not box.has_area() or proof.camera == null:
		return Rect2()
	var p1 := Vector3(box.position.x, box.position.y, 0.0)
	var p2 := Vector3(box.end.x, box.end.y, 0.0)
	if proof.camera.is_position_behind(p1) or proof.camera.is_position_behind(p2):
		return Rect2()
	var s1: Vector2 = (proof.camera.unproject_position(p1) - offset) / maxf(0.001, factor)
	var s2: Vector2 = (proof.camera.unproject_position(p2) - offset) / maxf(0.001, factor)
	var min_pt := Vector2(minf(s1.x, s2.x), minf(s1.y, s2.y))
	var max_pt := Vector2(maxf(s1.x, s2.x), maxf(s1.y, s2.y))
	return Rect2(min_pt, max_pt - min_pt)

func _draw_world_boxes(offset: Vector2, factor: float) -> void:
	for f in proof.fighters:
		var hurt_2d := _world_rect_to_canvas(f.get_hurt_box(), offset, factor)
		if hurt_2d.has_area():
			draw_rect(hurt_2d, Color(0.28, 0.85, 0.65, 0.16))
			draw_rect(hurt_2d, Color("48d9a6"), false, 2.0)
		var hit_2d := _world_rect_to_canvas(f.get_attack_box(), offset, factor)
		if hit_2d.has_area():
			draw_rect(hit_2d, Color(0.95, 0.30, 0.22, 0.24))
			draw_rect(hit_2d, Color("ff5a36"), false, 2.5)

func _draw_diagnostics() -> void:
	draw_rect(Rect2(836, 165, 420, 212), PANEL)
	var renderer_name := RenderingServer.get_current_rendering_method().to_upper()
	var preset_name: String = str(proof.get("quality_preset")).to_upper()
	_text("RENDER / %s  (%s)" % [renderer_name, preset_name], Vector2(852, 188), 11, GOLD)
	_text("%d FPS  ·  %.1f ms  ·  Draw %d  ·  Prim %d" % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
	], Vector2(852, 210), 11, WHITE)
	_text("Cam (%.2f, %.2f)  |  Shadows %s (F4)  |  F5 Preset" % [
		proof.camera.position.x, proof.camera.position.z, "ON" if proof.sun.shadow_enabled else "OFF"
	], Vector2(852, 232), 11, MUTED)
	for i in range(2):
		var f = proof.fighters[i]
		var y: int = 262 + i * 54
		var adv: int = int(f.last_frame_advantage)
		var adv_str: String = ("%+df" % adv) if adv != 0 else "0f"
		var mv: String = ("%s@%d" % [f.attack_kind, f.attack_tick]) if str(f.state) == "attack" else "-"
		_text("P%d  %s  (%s)  adv %s  Josh %d" % [i + 1, f.state, mv, adv_str, f.josh_meter], Vector2(852, y), 11, GOLD if i == 0 else WHITE)
		_text("IN: " + str(f.input_buffer.format_recent_tokens(9)), Vector2(852, y + 19), 11, MUTED)

func _banner(eyebrow: String, title: String, subtitle: String, accent: Color) -> void:
	draw_rect(Rect2(360, 114, 560, 102), Color(0.06, 0.13, 0.16, 0.90))
	draw_rect(Rect2(360, 114, 560, 2), accent)
	_centered(eyebrow, 136, 11, accent)
	_centered(title, 174, 26, WHITE)
	_centered(subtitle, 202, 13, MUTED)

func _text(value: String, at: Vector2, font_size: int, color: Color) -> void:
	draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _centered(value: String, y: float, font_size: int, color: Color) -> void:
	draw_string(font, Vector2(0, y), value, HORIZONTAL_ALIGNMENT_CENTER, 1280, font_size, color)

func _right(value: String, right: float, y: float, font_size: int, color: Color) -> void:
	var width = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(value, Vector2(right - width, y), font_size, color)

func _diamond(at: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -radius), at + Vector2(radius, 0), at + Vector2(0, radius), at + Vector2(-radius, 0)]), color)
