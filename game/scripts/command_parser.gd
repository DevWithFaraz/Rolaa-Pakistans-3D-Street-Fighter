class_name CommandParser
extends RefCounted
## Deterministic fighting-game command & movement gesture parser over a 60-tick InputBuffer.

const InputBufferScript = preload("res://scripts/input_buffer.gd")


static func resolve_command(buf: RefCounted, can_super: bool = false) -> String:
	if buf == null or buf.history.is_empty():
		return ""
	var f: Dictionary = buf.history[buf.history.size() - 1]
	var pressed := int(f.pressed)
	if pressed == 0:
		return ""

	var chord: int = int(buf.recent_chord_mask(3))

	# 1. Super ("Jalwa Attack"): Josh button or all 4 limb buttons when meter is full / Junoon ready.
	if can_super and ((pressed & InputBufferScript.BTN_JOSH) != 0 or (chord & 15) == 15):
		return "super_jalwa"

	# 2. Josh burst (or non-super Josh press)
	if (pressed & InputBufferScript.BTN_JOSH) != 0 and not can_super:
		return "josh_burst"

	# 3. Throws: LP+LK (1+3) or RP+RK (2+4)
	if (chord & (InputBufferScript.BTN_LP | InputBufferScript.BTN_LK)) == (InputBufferScript.BTN_LP | InputBufferScript.BTN_LK) \
		or (chord & (InputBufferScript.BTN_RP | InputBufferScript.BTN_RK)) == (InputBufferScript.BTN_RP | InputBufferScript.BTN_RK):
		return "throw_front"

	# 4. Signature move: LP+RP (1+2) or QCF (2,3,6 or 2,6) + Punch
	var qcf: bool = bool(buf.has_motion([2, 3, 6] as Array[int], 15)) or bool(buf.has_motion([2, 6] as Array[int], 12))
	if (chord & (InputBufferScript.BTN_LP | InputBufferScript.BTN_RP)) == (InputBufferScript.BTN_LP | InputBufferScript.BTN_RP) \
		or (qcf and (pressed & (InputBufferScript.BTN_LP | InputBufferScript.BTN_RP)) != 0):
		return "signature"

	# 5. Taunt / Quick-rise: LK+RK (3+4)
	if (chord & (InputBufferScript.BTN_LK | InputBufferScript.BTN_RK)) == (InputBufferScript.BTN_LK | InputBufferScript.BTN_RK):
		return "taunt"

	# 6. Directional command normals
	var dir := int(f.dir)
	if (dir == 3 and (pressed & InputBufferScript.BTN_RP) != 0) or (dir == 9 and (pressed & InputBufferScript.BTN_RK) != 0):
		return "launcher"
	if dir == 6 and (pressed & InputBufferScript.BTN_RP) != 0:
		return "command_heavy"
	if dir == 4 and (pressed & InputBufferScript.BTN_RK) != 0:
		return "power_kick"
	if dir in [1, 2, 3] and (pressed & InputBufferScript.BTN_LP) != 0:
		return "crouch_jab"
	if dir in [1, 2, 3] and (pressed & (InputBufferScript.BTN_LK | InputBufferScript.BTN_RK)) != 0:
		return "low_sweep"

	# 7. Standing normals (deterministic priority tie-break: RK > RP > LK > LP)
	if (pressed & InputBufferScript.BTN_RK) != 0:
		return "kick"
	if (pressed & InputBufferScript.BTN_RP) != 0:
		return "heavy_punch"
	if (pressed & InputBufferScript.BTN_LK) != 0:
		return "quick_kick"
	if (pressed & InputBufferScript.BTN_LP) != 0:
		return "punch"

	return ""


static func resolve_movement_gesture(buf: RefCounted) -> String:
	if buf == null or buf.history.is_empty():
		return ""
	if buf.has_double_tap(6, 12):
		return "dash_forward"
	if buf.has_double_tap(4, 12):
		return "backdash"
	if buf.has_double_tap(2, 12):
		return "sidestep_fg"
	if buf.has_double_tap(8, 10):
		return "sidestep_bg"
	return ""
