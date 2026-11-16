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
		"punch": &"Punch",
		"kick": &"MmaKick",
	}
	def.loop_clips = PackedStringArray(["Idle", "Idle2"])
	def.moves = {
		"punch": _make_move(
			"punch", "Punch", &"Punch",
			6, 3, 14, 10, 1.8, 1.95, 0.8, 4.5, 18, 12, 5,
			0.08, 0.56, 0.64, 1.05
		),
		"kick": _make_move(
			"kick", "Kick", &"MmaKick",
			12, 4, 22, 17, 2.4, 1.15, 0.95, 6.0, 25, 17, 7,
			0.05, 0.66, 0.76, 1.61
		),
	}
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
		"punch": &"Punch",
		"kick": &"MmaKick",
		"quad_punch": &"QuadPunch",
		"roundhouse_kick": &"RoundhouseKick",
		"headbutt": &"Headbutt",
	}
	def.loop_clips = PackedStringArray(["Idle", "Idle2", "Walk"])
	def.moves = {
		"punch": _make_move(
			"punch", "Punch", &"Punch",
			6, 3, 14, 10, 1.8, 1.95, 0.8, 4.5, 18, 12, 5,
			0.08, 0.52, 0.62, 1.28
		),
		"kick": _make_move(
			"kick", "Kick", &"MmaKick",
			12, 4, 22, 17, 2.4, 1.15, 0.95, 6.0, 25, 17, 7,
			0.06, 0.88, 0.98, 2.20
		),
	}
	return def


static func load_or_default(char_id: String) -> CharacterDef:
	var path := "res://characters/%s/CharacterDef.tres" % char_id
	if ResourceLoader.exists(path):
		var loaded := load(path)
		if loaded is CharacterDef:
			return loaded as CharacterDef
	if char_id == "khan":
		return create_khan_default()
	return create_asim_default()
