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

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = ThemeDB.fallback_font

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if proof == null or font == null or proof.fighters.size() < 2:
		return
	var factor = minf(size.x / 1280.0, size.y / 720.0)
	var offset = (size - Vector2(1280, 720) * factor) * 0.5
	draw_set_transform(offset, 0.0, Vector2.ONE * factor)
	_draw_scoreboard()
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
	_right("%d / 100" % proof.fighters[0].health, 538, 92, 11, WHITE)
	_text("%d / 100" % proof.fighters[1].health, Vector2(742, 92), 11, WHITE)
	draw_rect(Rect2(590, 10, 100, 69), Color("284148"))
	draw_rect(Rect2(590, 10, 100, 69), GOLD, false, 1.5)
	var seconds = maxi(0, int(ceilf(float(proof.round_time_ticks) / 60.0)))
	_centered("%02d" % seconds, 60, 43, GOLD if seconds <= 10 else WHITE)
	_centered("ROUND %d" % proof.round_number, 96, 11, GOLD)
	_diamond(Vector2(572, 44), 5, GOLD)
	_diamond(Vector2(708, 44), 5, GOLD)

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
			return str(fighter.attack_kind).to_upper()
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
	var subtitle := "P0  ·  RIGGED FIGHTERS  ·  KHAN SAHAB VS ASIM JANI" if rigged else "BUILD 02  ·  COMBAT PROOF  ·  PROTOTYPE CHARACTERS"
	var panel_w := maxf(315.0, font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 28.0)
	draw_rect(Rect2(24, 122, panel_w, 53), PANEL)
	_text("LAHORE  /  MALL ROAD", Vector2(36, 143), 12, GOLD)
	_text(subtitle, Vector2(36, 163), 10, MUTED)
	if proof.dummy_guard and not proof.demo:
		draw_rect(Rect2(966, 122, 290, 33), PANEL)
		_text("P2 AUTO-GUARD ON  /  T TO TOGGLE", Vector2(978, 144), 12, GOLD)

func _draw_controls() -> void:
	draw_rect(Rect2(24, 612, 1232, 87), PANEL)
	draw_rect(Rect2(24, 612, 1232, 2), Color("476166"))
	_text("P1", Vector2(42, 642), 14, GOLD)
	_text("A / D move   W jump   F punch   G kick   S block", Vector2(75, 642), 14, WHITE)
	_text("P2", Vector2(42, 676), 14, GOLD)
	_text("← / → move   ↑ jump   J punch   K kick   ↓ block", Vector2(75, 676), 14, WHITE)
	draw_line(Vector2(590, 627), Vector2(590, 686), Color("476166"), 1)
	_text("T  P2 auto-guard     R  restart match     Enter  next / rematch", Vector2(610, 642), 13, WHITE)
	_text("F2  tour    H  help    F3  diagnostics    Esc  pause    M  mute", Vector2(610, 676), 13, MUTED)

func _draw_diagnostics() -> void:
	draw_rect(Rect2(896, 179, 360, 155), PANEL)
	var renderer_name := RenderingServer.get_current_rendering_method().to_upper()
	var preset_name: String = str(proof.get("quality_preset")).to_upper()
	_text("RENDER / %s  (%s)" % [renderer_name, preset_name], Vector2(912, 202), 11, GOLD)
	_text("%d FPS  ·  %.1f ms process" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000], Vector2(912, 226), 13, WHITE)
	_text("Draw %d  ·  Tris/Prim %d" % [int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))], Vector2(912, 250), 12, WHITE)
	_text("Camera X  %+.2f  |  Shadows %s (F4)" % [proof.camera.position.x, "ON" if proof.sun.shadow_enabled else "OFF"], Vector2(912, 274), 11, WHITE)
	_text("F5 preset   |   P1 %s / P2 %s" % [proof.fighters[0].state, proof.fighters[1].state], Vector2(912, 298), 11, MUTED)

func _banner(eyebrow: String, title: String, subtitle: String, accent: Color) -> void:
	draw_rect(Rect2(190, 260, 900, 152), Color(0.06, 0.13, 0.16, 0.95))
	draw_rect(Rect2(190, 260, 900, 2), accent)
	_centered(eyebrow, 291, 12, accent)
	_centered(title, 346, 34, WHITE)
	_centered(subtitle, 384, 14, MUTED)

func _text(value: String, at: Vector2, font_size: int, color: Color) -> void:
	draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _centered(value: String, y: float, font_size: int, color: Color) -> void:
	draw_string(font, Vector2(0, y), value, HORIZONTAL_ALIGNMENT_CENTER, 1280, font_size, color)

func _right(value: String, right: float, y: float, font_size: int, color: Color) -> void:
	var width = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(value, Vector2(right - width, y), font_size, color)

func _diamond(at: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([at + Vector2(0, -radius), at + Vector2(radius, 0), at + Vector2(0, radius), at + Vector2(-radius, 0)]), color)
