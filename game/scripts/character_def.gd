class_name CharacterDef
extends Resource
## Data-driven character definition separating identity, rig asset, clips, and moves from FighterView.

@export var id: String = ""
@export var display_name: String = ""
@export var archetype: String = ""
@export_file("*.glb", "*.tscn") var model_path: String = ""
@export var model_scene: PackedScene
@export var model_scale: float = 1.95
@export var model_yaw_rad: float = PI * 0.5
@export var xfade_time: float = 0.06
@export var walk_speed: float = 4.8
@export var jump_speed: float = 8.0
@export var max_health: int = 100
@export var clip_map: Dictionary = {
	"idle": &"Idle",
	"guard": &"Idle2",
	"walk": &"Walk",
	"punch": &"Punch",
	"kick": &"MmaKick",
}
@export var loop_clips: PackedStringArray = PackedStringArray(["Idle", "Idle2", "Walk"])
@export var moves: Dictionary = {}
@export var voice_bank: Dictionary = {}


func instantiate_model() -> Node3D:
	if model_scene != null:
		return model_scene.instantiate() as Node3D
	if not model_path.is_empty():
		var loaded := load(model_path)
		if loaded is PackedScene:
			return (loaded as PackedScene).instantiate() as Node3D
	return null


func get_clip(state_key: String) -> StringName:
	return StringName(clip_map.get(state_key, &""))


func get_move(move_id: String) -> MoveData:
	return moves.get(move_id, null) as MoveData


static func _make_move(
	move_id: String,
	p_display_name: String,
	p_clip: StringName,
	p_startup: int,
	p_active: int,
	p_recovery: int,
	p_damage: int,
	p_reach: float,
	p_low: float,
	p_height: float,
	p_knockback: float,
	p_hitstun: int,
	p_blockstun: int,
	p_hitstop: int,
	p_clip_start: float,
	p_contact_start: float,
	p_contact_end: float,
	p_clip_end: float
) -> MoveData:
	var md := MoveData.new()
	md.id = move_id
	md.display_name = p_display_name
	md.animation_clip = p_clip
	md.startup_ticks = p_startup
	md.active_ticks = p_active
	md.recovery_ticks = p_recovery
	md.damage = p_damage
	md.reach = p_reach
	md.box_low = p_low
	md.box_height = p_height
	md.knockback = p_knockback
	md.hitstun_ticks = p_hitstun
	md.blockstun_ticks = p_blockstun
	md.hitstop_ticks = p_hitstop
	md.clip_start_sec = p_clip_start
	md.contact_start_sec = p_contact_start
	md.contact_end_sec = p_contact_end
	md.clip_end_sec = p_clip_end
	return md


static func _make_move_v2(cfg: Dictionary) -> MoveData:
	var md := MoveData.new()
	md.id = String(cfg.get("id", "punch"))
	md.display_name = String(cfg.get("display_name", "Punch"))
	md.animation_clip = StringName(cfg.get("clip", &"Punch"))
	md.startup_ticks = int(cfg.get("startup", 6))
	md.active_ticks = int(cfg.get("active", 3))
	md.recovery_ticks = int(cfg.get("recovery", 14))
	md.damage = int(cfg.get("damage", 10))
	md.reach = float(cfg.get("reach", 1.8))
	md.box_low = float(cfg.get("low", 1.95))
	md.box_height = float(cfg.get("height", 0.8))
	md.knockback = float(cfg.get("knockback", 4.5))
	md.hitstun_ticks = int(cfg.get("hitstun", 18))
	md.blockstun_ticks = int(cfg.get("blockstun", 12))
	md.hitstop_ticks = int(cfg.get("hitstop", 5))
	md.hit_level = String(cfg.get("hit_level", "mid"))
	md.tracking = String(cfg.get("tracking", "linear"))
	md.launcher = bool(cfg.get("launcher", false))
	md.launch_velocity = cfg.get("launch_velocity", Vector2(2.2, 8.8))
	md.knockdown = bool(cfg.get("knockdown", false))
	md.wall_splat = bool(cfg.get("wall_splat", false))
	md.armour_hits = int(cfg.get("armour_hits", 0))
	md.chip_damage = int(cfg.get("chip_damage", 0))
	md.advance_speed = float(cfg.get("advance_speed", 0.0))
	md.cancel_routes = cfg.get("cancel_routes", {}).duplicate()
	md.josh_cost = int(cfg.get("josh_cost", 0))
	md.clip_start_sec = float(cfg.get("clip_start", 0.08))
	md.contact_start_sec = float(cfg.get("contact_start", 0.56))
	md.contact_end_sec = float(cfg.get("contact_end", 0.64))
	md.clip_end_sec = float(cfg.get("clip_end", 1.05))
	return md


static func _build_shared_moves(is_asim: bool) -> Dictionary:
	var p_s := 0.14 if is_asim else 0.05
	var p_c1 := 0.38 if is_asim else 0.36
	var p_c2 := 0.48 if is_asim else 0.44
	var p_e := 0.88 if is_asim else 0.95

	var lc_s := 0.55 if is_asim else 0.08
	var lc_c1 := 0.85 if is_asim else 0.56
	var lc_c2 := 1.15 if is_asim else 0.64
	var lc_e := 1.55 if is_asim else 1.05

	var cp_s := 0.32 if is_asim else 0.50
	var cp_c1 := 0.72 if is_asim else 1.06
	var cp_c2 := 0.86 if is_asim else 1.18
	var cp_e := 1.35 if is_asim else 1.50

	var rhk_s := 0.45 if is_asim else 0.06
	var rhk_c1 := 0.85 if is_asim else 0.62
	var rhk_c2 := 0.98 if is_asim else 0.72
	var rhk_e := 1.40 if is_asim else 1.08

	var lk_s := 0.72 if is_asim else 0.06
	var lk_c1 := 1.18 if is_asim else 0.62
	var lk_c2 := 1.32 if is_asim else 0.72
	var lk_e := 1.80 if is_asim else 1.55

	var k_s := 0.06 if is_asim else 0.05
	var k_c1 := 0.88 if is_asim else 0.66
	var k_c2 := 0.98 if is_asim else 0.76
	var k_e := 2.18 if is_asim else 1.61

	var sw_s := 0.70 if is_asim else 0.75
	var sw_c1 := 1.18 if is_asim else 1.32
	var sw_c2 := 1.36 if is_asim else 1.48
	var sw_e := 1.95 if is_asim else 2.00

	var fl_s := 0.55 if is_asim else 0.42
	var fl_c1 := 1.00 if is_asim else 0.90
	var fl_c2 := 1.18 if is_asim else 1.15
	var fl_e := 1.75 if is_asim else 1.72

	var hb_s := 0.08 if is_asim else 0.08
	var hb_c1 := 0.72 if is_asim else 0.88
	var hb_c2 := 0.85 if is_asim else 1.05
	var hb_e := 1.90 if is_asim else 2.10

	var rh_s := 0.08 if is_asim else 0.10
	var rh_c1 := 0.95 if is_asim else 1.00
	var rh_c2 := 1.10 if is_asim else 1.14
	var rh_e := 2.20 if is_asim else 2.40

	var qp_s := 0.06 if is_asim else 0.40
	var qp_c1 := 0.75 if is_asim else 2.72
	var qp_c2 := 1.05 if is_asim else 2.92
	var qp_e := 2.05 if is_asim else 3.65

	var sk_s := qp_s if is_asim else 1.15
	var sk_c1 := qp_c1 if is_asim else 1.82
	var sk_c2 := qp_c2 if is_asim else 2.12
	var sk_e := qp_e if is_asim else 2.70

	var moves := {
		"punch": _make_move_v2({
			"id": "punch", "display_name": "Left Jab (1)", "clip": &"JabLeft" if is_asim else &"Punch",
			"startup": 6, "active": 3, "recovery": 14, "damage": 10,
			"reach": 1.8, "low": 1.95, "height": 0.8, "knockback": 4.5,
			"hitstun": 18, "blockstun": 12, "hitstop": 5, "hit_level": "high",
			"cancel_routes": {"rp": "heavy_punch", "lp": "light_combo"},
			"clip_start": p_s, "contact_start": p_c1, "contact_end": p_c2, "clip_end": p_e,
		}),
		"light_combo": _make_move_v2({
			"id": "light_combo", "display_name": "Twin Jab (1,1)", "clip": &"JabCross" if is_asim else &"LightCombo",
			"startup": 5, "active": 3, "recovery": 14, "damage": 8,
			"reach": 1.85, "low": 1.95, "height": 0.8, "knockback": 4.0,
			"hitstun": 18, "blockstun": 12, "hitstop": 5, "hit_level": "high",
			"cancel_routes": {"rp": "heavy_punch"},
			"clip_start": lc_s, "contact_start": lc_c1, "contact_end": lc_c2, "clip_end": lc_e,
		}),
		"heavy_punch": _make_move_v2({
			"id": "heavy_punch", "display_name": "Right Cross (2)", "clip": &"CrossRight" if is_asim else &"CrossPunch",
			"startup": 13, "active": 4, "recovery": 25, "damage": 14,
			"reach": 1.95, "low": 1.75, "height": 0.9, "knockback": 4.2,
			"hitstun": 21, "blockstun": 14, "hitstop": 6, "hit_level": "mid",
			"advance_speed": 1.4,
			"cancel_routes": {"rk": "kick"},
			"clip_start": cp_s, "contact_start": cp_c1, "contact_end": cp_c2, "clip_end": cp_e,
		}),
		"quick_kick": _make_move_v2({
			"id": "quick_kick", "display_name": "Front Boot (3)" if is_asim else "Low Shin Kick (3)", "clip": &"FrontKick" if is_asim else &"LeftKick",
			"startup": 10, "active": 3, "recovery": 18, "damage": 11,
			"reach": 2.05, "low": 0.35, "height": 0.75, "knockback": 3.8,
			"hitstun": 19, "blockstun": 13, "hitstop": 5, "hit_level": "low",
			"clip_start": lk_s, "contact_start": lk_c1, "contact_end": lk_c2, "clip_end": lk_e,
		}),
		"kick": _make_move_v2({
			"id": "kick", "display_name": "Heavy Kick (4)", "clip": &"MmaKick",
			"startup": 12, "active": 4, "recovery": 22, "damage": 17,
			"reach": 2.4, "low": 1.15, "height": 0.95, "knockback": 6.0,
			"hitstun": 25, "blockstun": 17, "hitstop": 7, "hit_level": "mid",
			"clip_start": k_s, "contact_start": k_c1, "contact_end": k_c2, "clip_end": k_e,
		}),
		"crouch_jab": _make_move_v2({
			"id": "crouch_jab", "display_name": "Body Blow (d+1)" if is_asim else "Right Hook (d+1)", "clip": &"BodyPunch" if is_asim else &"RightHook",
			"startup": 7, "active": 3, "recovery": 13, "damage": 8,
			"reach": 1.75, "low": 1.0, "height": 0.75, "knockback": 3.2,
			"hitstun": 16, "blockstun": 11, "hitstop": 4, "hit_level": "mid",
			"clip_start": rhk_s, "contact_start": rhk_c1, "contact_end": rhk_c2, "clip_end": rhk_e,
		}),
		"low_sweep": _make_move_v2({
			"id": "low_sweep", "display_name": "Boot Sweep (d+3)" if is_asim else "Chappal Sweep (d+3)", "clip": &"SweepKick" if is_asim else &"CrescentSweep",
			"startup": 18, "active": 5, "recovery": 32, "damage": 16,
			"reach": 2.25, "low": 0.25, "height": 0.75, "knockback": 4.5,
			"hitstun": 30, "blockstun": 22, "hitstop": 7, "hit_level": "low",
			"knockdown": true,
			"clip_start": sw_s, "contact_start": sw_c1, "contact_end": sw_c2, "clip_end": sw_e,
		}),
		"launcher": _make_move_v2({
			"id": "launcher", "display_name": "Commander Uppercut (df+2)" if is_asim else "Flip Kick Launcher (df+2)",
			"clip": &"UppercutRight" if is_asim else &"FlipKick",
			"startup": 18, "active": 5, "recovery": 32, "damage": 15,
			"reach": 2.10, "low": 1.2, "height": 1.25, "knockback": 2.2,
			"hitstun": 38, "blockstun": 16, "hitstop": 8, "hit_level": "mid",
			"launcher": true, "launch_velocity": Vector2(2.2, 8.8), "advance_speed": 1.4,
			"clip_start": fl_s, "contact_start": fl_c1, "contact_end": fl_c2, "clip_end": fl_e,
		}),
		"command_heavy": _make_move_v2({
			"id": "command_heavy",
			"display_name": "Iron Headbutt (f+2)" if is_asim else "Kaptaan Barrage (f+2)",
			"clip": &"Headbutt" if is_asim else &"QuadPunch",
			"startup": 14, "active": 4, "recovery": 20, "damage": 20,
			"reach": 2.1, "low": 1.5, "height": 1.0, "knockback": 8.2,
			"hitstun": 27, "blockstun": 16, "hitstop": 8, "hit_level": "mid",
			"tracking": "homing", "wall_splat": true, "advance_speed": 3.5,
			"clip_start": hb_s, "contact_start": hb_c1, "contact_end": hb_c2, "clip_end": hb_e,
		}),
		"power_kick": _make_move_v2({
			"id": "power_kick",
			"display_name": "Commander Roundhouse (b+4)" if is_asim else "Kaptaan Roundhouse (b+4)",
			"clip": &"RoundhouseKick",
			"startup": 15, "active": 5, "recovery": 24, "damage": 22,
			"reach": 2.55, "low": 1.2, "height": 1.05, "knockback": 9.5,
			"hitstun": 29, "blockstun": 18, "hitstop": 9, "hit_level": "mid",
			"tracking": "homing", "wall_splat": true,
			"clip_start": rh_s, "contact_start": rh_c1, "contact_end": rh_c2, "clip_end": rh_e,
		}),
		"throw_front": _make_move_v2({
			"id": "throw_front", "display_name": "Military Throw (1+3)" if is_asim else "Pakad Throw (1+3)",
			"clip": &"GrabThrow" if is_asim else &"Punch",
			"startup": 10, "active": 3, "recovery": 22, "damage": 22,
			"reach": 1.55, "low": 1.0, "height": 1.5, "knockback": 7.0,
			"hitstun": 30, "blockstun": 0, "hitstop": 6, "hit_level": "throw",
			"knockdown": true,
			"clip_start": 0.25 if is_asim else p_s,
			"contact_start": 0.65 if is_asim else p_c1,
			"contact_end": 0.85 if is_asim else p_c2,
			"clip_end": 1.75 if is_asim else p_e,
		}),
		"signature": _make_move_v2({
			"id": "signature",
			"display_name": "Salute & Strike (1+2)" if is_asim else "Bouncer Kick (1+2)",
			"clip": &"QuadPunch" if is_asim else &"SignatureKick",
			"startup": 20, "active": 6, "recovery": 32, "damage": 24,
			"reach": 2.35, "low": 1.3, "height": 1.1, "knockback": 9.2,
			"hitstun": 32, "blockstun": 18, "hitstop": 9, "hit_level": "mid",
			"knockdown": true, "wall_splat": true,
			"armour_hits": 1 if is_asim else 0, "advance_speed": 3.0,
			"clip_start": sk_s, "contact_start": sk_c1, "contact_end": sk_c2, "clip_end": sk_e,
		}),
		"super_jalwa": _make_move_v2({
			"id": "super_jalwa",
			"display_name": "Commander Jalwa (JOSH)" if is_asim else "Kaptaan Jalwa (JOSH)",
			"clip": &"ComboPunchKick" if is_asim else &"JalwaSuper",
			"startup": 11, "active": 6, "recovery": 26 if is_asim else 34, "damage": 34,
			"reach": 2.65, "low": 1.0, "height": 1.4, "knockback": 11.0,
			"hitstun": 40, "blockstun": 20, "hitstop": 12, "hit_level": "mid",
			"tracking": "homing", "knockdown": true, "wall_splat": true,
			"chip_damage": 8, "josh_cost": 100, "advance_speed": 5.0,
			"clip_start": 0.95 if is_asim else 0.20,
			"contact_start": 1.55 if is_asim else 1.78,
			"contact_end": 2.25 if is_asim else 2.15,
			"clip_end": 2.85 if is_asim else 3.25,
		}),
		"air_punch": _make_move_v2({
			"id": "air_punch",
			"display_name": "Flying Knee Punch (Air 1/2)",
			"clip": &"JumpPunch",
			"startup": 7, "active": 6, "recovery": 14, "damage": 13,
			"reach": 2.15, "low": 0.45, "height": 1.25, "knockback": 4.2,
			"hitstun": 24, "blockstun": 14, "hitstop": 6, "hit_level": "mid",
			"tracking": "linear",
			"clip_start": 0.12, "contact_start": 0.62, "contact_end": 0.88, "clip_end": 1.02,
		}),
		"air_kick": _make_move_v2({
			"id": "air_kick",
			"display_name": "Drop Kick (Air 3/4)",
			"clip": &"JumpKick",
			"startup": 9, "active": 7, "recovery": 16, "damage": 16,
			"reach": 2.45, "low": 0.25, "height": 1.20, "knockback": 7.2,
			"hitstun": 28, "blockstun": 16, "hitstop": 8, "hit_level": "mid",
			"tracking": "linear", "knockdown": true,
			"clip_start": 0.06, "contact_start": 0.42, "contact_end": 0.70, "clip_end": 0.85,
		}),
	}
	if not is_asim:
		moves["rock_throw"] = _make_move_v2({
			"id": "rock_throw", "display_name": "Patthar Throw (1+3)",
			"clip": &"ThrowRock",
			"startup": 44, "active": 4, "recovery": 32, "damage": 18,
			"reach": 10.0, "low": 1.6, "height": 1.2, "knockback": 8.5,
			"hitstun": 34, "blockstun": 14, "hitstop": 5, "hit_level": "high",
			"tracking": "linear",
			"clip_start": 0.55, "contact_start": 2.42, "contact_end": 2.52, "clip_end": 3.25,
		})
	else:
		moves["pistol_shoot"] = _make_move_v2({
			"id": "pistol_shoot", "display_name": "M1911 Pistol Shot (1+3)",
			"clip": &"ShootPistol",
			"startup": 18, "active": 4, "recovery": 30, "damage": 16,
			"reach": 12.0, "low": 1.65, "height": 1.0, "knockback": 7.0,
			"hitstun": 28, "blockstun": 14, "hitstop": 4, "hit_level": "high",
			"tracking": "linear", "chip_damage": 3,
			"clip_start": 0.02, "contact_start": 0.24, "contact_end": 0.34, "clip_end": 1.12,
		})
	return moves


static func create_khan_default() -> CharacterDef:
	var def := CharacterDef.new()
	def.id = "khan"
	def.display_name = "KHAN SAHAB"
	def.archetype = "Kaptaan"
	def.model_path = "res://assets/characters/khan_recovery_trial.glb"
	def.model_scale = 1.95
	def.model_yaw_rad = PI * 0.5
	def.xfade_time = 0.06
	def.clip_map = {
		"idle": &"Idle",
		"guard": &"Idle2",
		"walk": &"Walk",
		"walk_back": &"WalkBack",
		"jump": &"Jump",
		"crouch": &"CrouchIdle",
		"crouch_walk": &"CrouchWalk",
		"crouch_walk_back": &"CrouchWalkBack",
		"dash_forward": &"DashForward",
		"backdash": &"Backdash",
		"sidestep": &"Sidestep",
		"block_hit": &"BlockHit",
		"taunt": &"Taunt",
		"turn_180": &"Turn180",
		"hit_head": &"HitHead",
		"hit_body": &"HitBody",
		"knockdown": &"SweepFall",
		"ko": &"KnockdownDeath",
		"wakeup": &"WakeupStand",
		"entry": &"Entry",
		"victory": &"VictoryCelebrate",
		"punch": &"Punch",
		"kick": &"MmaKick",
	}
	def.loop_clips = PackedStringArray(["Idle", "Idle2", "Walk", "WalkBack", "CrouchIdle", "CrouchWalk", "CrouchWalkBack", "VictoryCelebrate"])
	def.voice_bank = {
		"taunt": "res://assets/audio/khan_taunt_absolutely_not.ogg",
	}
	def.moves = _build_shared_moves(false)
	return def


static func create_asim_default() -> CharacterDef:
	var def := CharacterDef.new()
	def.id = "asim"
	def.display_name = "ASIM JANI"
	def.archetype = "Commander"
	def.model_path = "res://assets/characters/asim_model1.glb"
	def.model_scale = 1.95
	def.model_yaw_rad = PI * 0.5
	def.xfade_time = 0.06
	def.clip_map = {
		"idle": &"Idle",
		"guard": &"Idle2",
		"walk": &"Walk",
		"walk_back": &"WalkBack",
		"jump": &"Jump",
		"crouch": &"CrouchIdle",
		"crouch_walk": &"CrouchWalk",
		"crouch_walk_back": &"CrouchWalkBack",
		"dash_forward": &"DashForward",
		"backdash": &"Backdash",
		"sidestep": &"Sidestep",
		"block_hit": &"BlockHit",
		"taunt": &"Taunt",
		"turn_180": &"Turn180",
		"hit_head": &"HitHead",
		"hit_body": &"HitBody",
		"knockdown": &"SweepFall",
		"ko": &"KnockdownDeath",
		"wakeup": &"WakeupStand",
		"entry": &"Entry",
		"victory": &"VictoryCelebrate",
		"punch": &"JabLeft",
		"kick": &"MmaKick",
		"quad_punch": &"QuadPunch",
		"roundhouse_kick": &"RoundhouseKick",
		"headbutt": &"Headbutt",
	}
	def.loop_clips = PackedStringArray(["Idle", "Idle2", "Walk", "WalkBack", "CrouchIdle", "CrouchWalk", "CrouchWalkBack", "VictoryCelebrate"])
	def.voice_bank = {
		"taunt": "res://assets/audio/asim_taunt_salute.ogg",
	}
	def.moves = _build_shared_moves(true)
	return def


static func load_or_default(char_id: String) -> CharacterDef:
	var fallback := create_khan_default() if char_id == "khan" else create_asim_default()
	var path := "res://characters/%s/CharacterDef.tres" % char_id
	if ResourceLoader.exists(path):
		var loaded := load(path)
		if loaded is CharacterDef:
			var def := loaded as CharacterDef
			for ckey in fallback.clip_map:
				if not def.clip_map.has(ckey):
					def.clip_map[ckey] = fallback.clip_map[ckey]
			for lc in fallback.loop_clips:
				if not (lc in def.loop_clips):
					def.loop_clips.append(lc)
			for key in fallback.moves:
				if not def.moves.has(key) or def.moves[key] == null:
					def.moves[key] = fallback.moves[key]
			return def
	return fallback
