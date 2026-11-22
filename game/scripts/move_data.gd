class_name MoveData
extends Resource
## Data-driven frame data, hitbox dimensions, and animation phase timing for a single attack.

@export var id: String = "punch"
@export var display_name: String = "Punch"
@export var animation_clip: StringName = &"Punch"
@export var startup_ticks: int = 6
@export var active_ticks: int = 3
@export var recovery_ticks: int = 14
@export var damage: int = 10
@export var reach: float = 1.8
@export var box_low: float = 1.95
@export var box_height: float = 0.8
@export var knockback: float = 4.5
@export var hitstun_ticks: int = 18
@export var blockstun_ticks: int = 12
@export var hitstop_ticks: int = 5
@export var hit_level: String = "mid"
@export var tracking: String = "linear"
@export var launcher: bool = false
@export var launch_velocity: Vector2 = Vector2(2.2, 8.8)
@export var knockdown: bool = false
@export var wall_splat: bool = false
@export var armour_hits: int = 0
@export var chip_damage: int = 0
@export var advance_speed: float = 0.0
@export var cancel_routes: Dictionary = {}
@export var josh_cost: int = 0
@export var clip_start_sec: float = 0.08
@export var contact_start_sec: float = 0.56
@export var contact_end_sec: float = 0.64
@export var clip_end_sec: float = 1.05


func total_ticks() -> int:
	return startup_ticks + active_ticks + recovery_ticks


func on_hit_advantage() -> int:
	return hitstun_ticks - recovery_ticks


func on_block_advantage() -> int:
	return blockstun_ticks - recovery_ticks


func sample_clip_time(tick: int, clip_length: float = 0.0) -> float:
	if tick <= startup_ticks:
		return lerpf(clip_start_sec, contact_start_sec, float(tick) / float(maxi(1, startup_ticks)))
	if tick <= startup_ticks + active_ticks:
		return lerpf(contact_start_sec, contact_end_sec, float(tick - startup_ticks) / float(maxi(1, active_ticks)))
	var end_t := minf(clip_end_sec, clip_length - 0.01) if clip_length > 0.0 else clip_end_sec
	return lerpf(
		contact_end_sec,
		end_t,
		clampf(float(tick - startup_ticks - active_ticks) / float(maxi(1, recovery_ticks)), 0.0, 1.0)
	)


func to_legacy_dict() -> Dictionary:
	return {
		"startup": startup_ticks,
		"active": active_ticks,
		"recovery": recovery_ticks,
		"damage": damage,
		"reach": reach,
		"knockback": knockback,
		"hitstun": hitstun_ticks,
		"blockstun": blockstun_ticks,
		"hitstop": hitstop_ticks,
		"low": box_low,
		"height": box_height,
		"hit_level": hit_level,
		"tracking": tracking,
		"launcher": launcher,
		"launch_velocity": launch_velocity,
		"knockdown": knockdown,
		"wall_splat": wall_splat,
		"armour_hits": armour_hits,
		"chip_damage": chip_damage,
		"advance_speed": advance_speed,
		"cancel_routes": cancel_routes.duplicate(),
		"josh_cost": josh_cost,
	}
