extends "res://scripts/fighter_view.gd"
## Compatibility wrapper preserving khan_stage_fighter.gd while delegating to CharacterDef + FighterView.


func _ready() -> void:
	if character_def == null:
		character_def = CharacterDef.load_or_default("khan")
	super._ready()
