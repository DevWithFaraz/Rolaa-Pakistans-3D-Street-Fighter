class_name FrameDataTool
extends RefCounted
## Validates MoveData kits and exports CSV + Markdown frame-data tables for Khan & Asim.

const CharacterDefScript = preload("res://scripts/character_def.gd")
const MoveDataScript = preload("res://scripts/move_data.gd")
const VALID_HIT_LEVELS := ["high", "mid", "low", "throw", "unblockable"]
const VALID_TRACKING := ["linear", "homing"]


static func validate_and_export(out_dir: String = "") -> Dictionary:
	var errors: Array[String] = []
	var rows: Array[Dictionary] = []
	var counts: Dictionary = {}

	for char_id in ["khan", "asim"]:
		var def = CharacterDefScript.load_or_default(char_id)
		var move_ids: Array = def.moves.keys()
		move_ids.sort()
		counts[char_id] = move_ids.size()
		if move_ids.size() < 12:
			errors.append("%s has only %d moves (need >= 12)" % [char_id, move_ids.size()])

		for move_id_var in move_ids:
			var move_id := String(move_id_var)
			var md = def.get_move(move_id)
			if md == null:
				errors.append("%s.%s is null" % [char_id, move_id])
				continue
			if md.startup_ticks <= 0:
				errors.append("%s.%s startup_ticks <= 0" % [char_id, move_id])
			if md.active_ticks <= 0:
				errors.append("%s.%s active_ticks <= 0" % [char_id, move_id])
			if md.recovery_ticks <= 0:
				errors.append("%s.%s recovery_ticks <= 0" % [char_id, move_id])
			if md.reach <= 0.0:
				errors.append("%s.%s reach <= 0" % [char_id, move_id])
			if not (md.hit_level in VALID_HIT_LEVELS):
				errors.append("%s.%s invalid hit_level: %s" % [char_id, move_id, md.hit_level])
			if not (md.tracking in VALID_TRACKING):
				errors.append("%s.%s invalid tracking: %s" % [char_id, move_id, md.tracking])
			if md.animation_clip.is_empty():
				errors.append("%s.%s animation_clip empty" % [char_id, move_id])

			var props: Array[String] = []
			if md.launcher:
				props.append("launcher")
			if md.knockdown:
				props.append("knockdown")
			if md.wall_splat:
				props.append("wall_splat")
			if md.armour_hits > 0:
				props.append("armour:%d" % md.armour_hits)
			if md.chip_damage > 0:
				props.append("chip:%d" % md.chip_damage)
			if not md.cancel_routes.is_empty():
				props.append("cancels:" + ",".join(PackedStringArray(md.cancel_routes.values())))

			rows.append({
				"character": def.display_name,
				"move_id": md.id,
				"display_name": md.display_name,
				"clip": String(md.animation_clip),
				"hit_level": md.hit_level,
				"tracking": md.tracking,
				"startup": md.startup_ticks,
				"active": md.active_ticks,
				"recovery": md.recovery_ticks,
				"total": md.total_ticks(),
				"damage": md.damage,
				"on_hit": md.on_hit_advantage(),
				"on_block": md.on_block_advantage(),
				"properties": ";".join(props) if not props.is_empty() else "-",
			})

	if not out_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(out_dir)
		var csv_lines: Array[String] = [
			"character,move_id,display_name,clip,hit_level,tracking,startup,active,recovery,total,damage,on_hit,on_block,properties"
		]
		var md_lines: Array[String] = [
			"# Rolaa — Frame Data Table",
			"",
			"| Character | Move ID | Display Name | Clip | Level | Tracking | Startup | Active | Recovery | Total | Dmg | On Hit | On Block | Properties |",
			"|---|---|---|---|---|---|---|---|---|---|---|---|---|---|",
		]
		for r in rows:
			csv_lines.append("%s,%s,%s,%s,%s,%s,%d,%d,%d,%d,%d,%+d,%+d,%s" % [
				r.character, r.move_id, r.display_name, r.clip, r.hit_level, r.tracking,
				r.startup, r.active, r.recovery, r.total, r.damage, r.on_hit, r.on_block, r.properties
			])
			md_lines.append("| %s | `%s` | %s | `%s` | %s | %s | i%d | %df | %df | %df | %d | %+d | %+d | %s |" % [
				r.character, r.move_id, r.display_name, r.clip, r.hit_level, r.tracking,
				r.startup, r.active, r.recovery, r.total, r.damage, r.on_hit, r.on_block, r.properties
			])
		var csv_file := FileAccess.open(out_dir.path_join("frame-data.csv"), FileAccess.WRITE)
		if csv_file != null:
			csv_file.store_string("\n".join(csv_lines) + "\n")
		var md_file := FileAccess.open(out_dir.path_join("frame-data.md"), FileAccess.WRITE)
		if md_file != null:
			md_file.store_string("\n".join(md_lines) + "\n")

	return {
		"errors": errors,
		"counts": counts,
		"row_count": rows.size(),
	}


static func save_default_resources() -> void:
	for char_id in ["khan", "asim"]:
		var def = CharacterDefScript.create_khan_default() if char_id == "khan" else CharacterDefScript.create_asim_default()
		var base_dir := "res://characters/%s" % char_id
		var moves_dir := base_dir.path_join("moves")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(moves_dir))
		for move_key in def.moves:
			var move_id := String(move_key)
			var md = def.get_move(move_id)
			var move_path := moves_dir.path_join(move_id + ".tres")
			ResourceSaver.save(md, move_path)
			def.moves[move_id] = ResourceLoader.load(move_path)
		ResourceSaver.save(def, base_dir.path_join("CharacterDef.tres"))
