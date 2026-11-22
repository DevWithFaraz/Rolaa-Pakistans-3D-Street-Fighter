class_name InputBuffer
extends RefCounted
## Deterministic 60-tick per-player input ring buffer with relative numpad directions and 3-frame chord leniency.

const BTN_LP := 1 << 0
const BTN_RP := 1 << 1
const BTN_LK := 1 << 2
const BTN_RK := 1 << 3
const BTN_JOSH := 1 << 4
const BTN_GUARD := 1 << 5
const CAPACITY := 60

var history: Array[Dictionary] = []
var current_tick: int = 0
var prev_held: int = 0


func clear() -> void:
	history.clear()
	current_tick = 0
	prev_held = 0


func push_frame(axis_x: float, axis_y: float, facing: float, held_mask: int) -> Dictionary:
	var rel_x := axis_x * (1.0 if facing >= 0.0 else -1.0)
	var dir_x := 0
	if rel_x > 0.35:
		dir_x = 1
	elif rel_x < -0.35:
		dir_x = -1

	var dir_y := 0
	if axis_y > 0.35:
		dir_y = 1
	elif axis_y < -0.35:
		dir_y = -1

	var dir := (dir_y + 1) * 3 + (dir_x + 2)
	var pressed := held_mask & ~prev_held
	var released := prev_held & ~held_mask
	prev_held = held_mask
	current_tick += 1

	var entry := {
		"tick": current_tick,
		"dir": dir,
		"held": held_mask,
		"pressed": pressed,
		"released": released,
	}
	history.append(entry)
	if history.size() > CAPACITY:
		history.pop_front()
	return entry


func recent_chord_mask(window_ticks: int = 3) -> int:
	var mask := 0
	var start := maxi(0, history.size() - maxi(1, window_ticks))
	for i in range(start, history.size()):
		mask |= int(history[i].pressed)
	return mask


func has_motion(sequence: Array[int], max_ticks: int = 15) -> bool:
	if sequence.is_empty() or history.is_empty():
		return false
	var start := maxi(0, history.size() - maxi(1, max_ticks))
	var seq_idx := 0
	for i in range(start, history.size()):
		var d := int(history[i].dir)
		if d == sequence[seq_idx]:
			seq_idx += 1
			if seq_idx >= sequence.size():
				return true
	return false


func has_double_tap(target_dir: int, max_ticks: int = 12) -> bool:
	if history.size() < 3:
		return false
	var last_dir := int(history[history.size() - 1].dir)
	var prev_dir := int(history[history.size() - 2].dir)
	if last_dir != target_dir or prev_dir == target_dir:
		return false
	var seq: Array[int] = [target_dir, 5, target_dir]
	return has_motion(seq, max_ticks)


func format_recent_tokens(max_tokens: int = 8) -> String:
	if history.is_empty():
		return "-"
	var dir_glyphs := {
		1: "↙", 2: "↓", 3: "↘",
		4: "←", 5: "•", 6: "→",
		7: "↖", 8: "↑", 9: "↗",
	}
	var tokens: Array[String] = []
	var prev_dir := -1
	for i in range(history.size()):
		var entry: Dictionary = history[i]
		var d := int(entry.dir)
		var p := int(entry.pressed)
		var btn_parts: Array[String] = []
		if (p & BTN_LP) != 0:
			btn_parts.append("1")
		if (p & BTN_RP) != 0:
			btn_parts.append("2")
		if (p & BTN_LK) != 0:
			btn_parts.append("3")
		if (p & BTN_RK) != 0:
			btn_parts.append("4")
		if (p & BTN_JOSH) != 0:
			btn_parts.append("JOSH")

		if not btn_parts.is_empty():
			var prefix := String(dir_glyphs.get(d, "")) if d != 5 else ""
			tokens.append(prefix + "+".join(btn_parts))
		elif d != 5 and d != prev_dir:
			tokens.append(String(dir_glyphs.get(d, str(d))))
		prev_dir = d

	if tokens.is_empty():
		return "•"
	if tokens.size() > max_tokens:
		tokens = tokens.slice(tokens.size() - max_tokens)
	return " ".join(tokens)


func snapshot() -> Dictionary:
	var copy_hist: Array[Dictionary] = []
	for entry in history:
		copy_hist.append(entry.duplicate())
	return {
		"current_tick": current_tick,
		"prev_held": prev_held,
		"history": copy_hist,
	}


func restore(snap: Dictionary) -> void:
	current_tick = int(snap.get("current_tick", 0))
	prev_held = int(snap.get("prev_held", 0))
	history.clear()
	var saved_hist: Array = snap.get("history", [])
	for entry in saved_hist:
		if entry is Dictionary:
			history.append((entry as Dictionary).duplicate())
