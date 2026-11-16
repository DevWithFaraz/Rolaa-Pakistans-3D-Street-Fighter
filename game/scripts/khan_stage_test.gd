extends "res://scripts/stage_proof.gd"
## Test copy of stage_proof integrating data-driven rigged Khan Sahab (P1) and Asim Jani (P2).

const FighterViewScript = preload("res://scripts/fighter_view.gd")


func _ready() -> void:
	super._ready()
	testing = "--khan-stage-test" in OS.get_cmdline_user_args()
	reset()
	if testing:
		call_deferred("_validate_khan_stage")


func _validate_khan_stage() -> void:
	if not capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(capture_dir)

	var khan := fighters[0] as FighterViewScript
	var asim := fighters[1] as FighterViewScript
	await _tick(15)
	_check(
		khan != null and is_instance_valid(khan.anim_tree) and khan.character_def != null and khan.character_def.id == "khan",
		"Khan rigged fighter mounted cleanly via CharacterDef"
	)
	_check(
		asim != null and is_instance_valid(asim.anim_tree) and asim.character_def != null and asim.character_def.id == "asim",
		"Asim rigged fighter mounted cleanly via CharacterDef"
	)
	_check(khan.is_on_floor() and asim.is_on_floor(), "Khan and Asim stand on road collision")
	_check(khan.current_anim_state == "idle" and asim.current_anim_state == "idle", "Neutral state plays Idle clip for both fighters")
	_check(khan.has_finite_bones() and asim.has_finite_bones(), "Both skeleton poses are finite in Idle")
	await _save_capture("khan-stage-idle")

	# P1 (Khan) Punch synchronization check against P2 (Asim).
	khan.position.x = -0.85
	asim.position.x = 0.85
	await _tick(4)
	Input.action_press("p1_punch")
	await _tick(2)
	Input.action_release("p1_punch")
	await _tick(2)
	_check(khan.state == "attack" and khan.attack_kind == "punch" and khan.current_anim_state == "punch", "P1 60 Hz Punch triggers rigged Punch animation")
	_check(asim.health == 100, "P1 Punch startup frames do not damage prematurely")
	await _tick(6)
	_check(khan.has_finite_bones() and asim.has_finite_bones(), "Both skeletons stay finite at P1 Punch impact")
	_check(asim.health == 90 and asim.state == "hitstun", "P1 Punch active frames land 10 dmg hit on Asim")
	await _save_capture("khan-stage-punch")
	await _tick(35)
	_check(khan.state == "idle" and khan.current_anim_state == "idle", "P1 Punch recovery returns cleanly to Idle")

	# P1 (Khan) Kick synchronization check against P2 (Asim).
	reset()
	await _tick(4)
	khan.position.x = -1.25
	asim.position.x = 1.25
	await _tick(4)
	Input.action_press("p1_kick")
	await _tick(2)
	Input.action_release("p1_kick")
	await _tick(4)
	_check(khan.state == "attack" and khan.attack_kind == "kick" and khan.current_anim_state == "kick", "P1 60 Hz Kick triggers rigged MmaKick animation")
	_check(asim.health == 100, "P1 MmaKick startup frames do not damage prematurely")
	await _tick(10)
	_check(khan.has_finite_bones() and asim.has_finite_bones(), "Both skeletons stay finite at P1 MmaKick impact")
	_check(asim.health == 83 and asim.state == "hitstun", "P1 MmaKick active frames deal 17 dmg to Asim")
	await _save_capture("khan-stage-kick")
	await _tick(45)
	_check(khan.state == "idle" and khan.current_anim_state == "idle", "P1 MmaKick recovery returns cleanly to Idle")

	# P2 (Asim) Punch synchronization check against P1 (Khan).
	reset()
	await _tick(4)
	khan.position.x = -0.85
	asim.position.x = 0.85
	await _tick(4)
	Input.action_press("p2_punch")
	await _tick(2)
	Input.action_release("p2_punch")
	await _tick(2)
	_check(asim.state == "attack" and asim.attack_kind == "punch" and asim.current_anim_state == "punch", "P2 60 Hz Punch triggers Asim rigged Punch animation")
	_check(khan.health == 100, "P2 Punch startup frames do not damage prematurely")
	await _tick(6)
	_check(asim.has_finite_bones() and khan.has_finite_bones(), "Both skeletons stay finite at P2 Punch impact")
	_check(khan.health == 90 and khan.state == "hitstun", "P2 Punch active frames land 10 dmg hit on Khan")
	await _save_capture("asim-stage-punch")
	await _tick(35)
	_check(asim.state == "idle" and asim.current_anim_state == "idle", "P2 Punch recovery returns cleanly to Idle")

	# P2 (Asim) Kick synchronization check against P1 (Khan).
	reset()
	await _tick(4)
	khan.position.x = -1.25
	asim.position.x = 1.25
	await _tick(4)
	Input.action_press("p2_kick")
	await _tick(2)
	Input.action_release("p2_kick")
	await _tick(4)
	_check(asim.state == "attack" and asim.attack_kind == "kick" and asim.current_anim_state == "kick", "P2 60 Hz Kick triggers Asim rigged MmaKick animation")
	_check(khan.health == 100, "P2 MmaKick startup frames do not damage prematurely")
	await _tick(10)
	_check(asim.has_finite_bones() and khan.has_finite_bones(), "Both skeletons stay finite at P2 MmaKick impact")
	_check(khan.health == 83 and khan.state == "hitstun", "P2 MmaKick active frames deal 17 dmg to Khan")
	await _save_capture("asim-stage-kick")
	await _tick(45)
	_check(asim.state == "idle" and asim.current_anim_state == "idle", "P2 MmaKick recovery returns cleanly to Idle")

	# Side-switch facing and attack checks for both fighters.
	reset()
	await _tick(4)
	khan.position.x = 0.85
	asim.position.x = -0.85
	await _tick(4)
	_check(khan.facing < 0.0 and asim.facing > 0.0, "Both fighters flip facing toward opponent after side swap")
	Input.action_press("p1_punch")
	await _tick(2)
	Input.action_release("p1_punch")
	await _tick(8)
	_check(asim.health == 90 and khan.has_finite_bones() and asim.has_finite_bones(), "Flipped P1 lands Punch onto P2 on the left with finite bones")
	await _save_capture("khan-stage-flipped")
	await _tick(35)
	khan.position.x = 0.85
	asim.position.x = -0.85
	await _tick(4)
	Input.action_press("p2_punch")
	await _tick(2)
	Input.action_release("p2_punch")
	await _tick(8)
	_check(khan.health == 90 and khan.has_finite_bones() and asim.has_finite_bones(), "Flipped P2 lands Punch onto P1 on the right with finite bones")
	await _tick(35)

	# Guard and blockstun checks for Khan.
	reset()
	await _tick(4)
	khan.position.x = -0.8
	asim.position.x = 0.8
	await _tick(3)
	Input.action_press("p1_guard")
	await _tick(5)
	_check(khan.state == "guard" and khan.current_anim_state == "guard", "Khan Guard enters Idle2 stance cleanly")
	await _save_capture("khan-stage-guard")
	Input.action_press("p2_punch")
	await _tick(2)
	Input.action_release("p2_punch")
	await _tick(8)
	Input.action_release("p1_guard")
	_check(khan.health == 100 and khan.state == "blockstun" and khan.has_finite_bones(), "Khan Guard blocks Asim punch without taking damage")
	await _tick(25)

	# Guard and blockstun checks for Asim.
	reset()
	await _tick(4)
	khan.position.x = -0.8
	asim.position.x = 0.8
	await _tick(3)
	Input.action_press("p2_guard")
	await _tick(5)
	_check(asim.state == "guard" and asim.current_anim_state == "guard", "Asim Guard enters Idle2 stance cleanly")
	Input.action_press("p1_punch")
	await _tick(2)
	Input.action_release("p1_punch")
	await _tick(8)
	Input.action_release("p2_guard")
	_check(asim.health == 100 and asim.state == "blockstun" and asim.has_finite_bones(), "Asim Guard blocks Khan punch without taking damage")
	await _tick(25)

	# Jump checks for both fighters.
	reset()
	await _tick(4)
	Input.action_press("p1_jump")
	Input.action_press("p2_jump")
	await _tick(2)
	Input.action_release("p1_jump")
	Input.action_release("p2_jump")
	await _tick(16)
	_check(
		khan.position.y > 0.8 and asim.position.y > 0.8 and khan.has_finite_bones() and asim.has_finite_bones(),
		"Both fighters jump smoothly with finite skeleton transforms"
	)
	await _save_capture("khan-stage-jump")
	await _tick(45)
	_check(khan.is_on_floor() and asim.is_on_floor(), "Both fighters land back on stage road")

	# KO checks for Khan (hit by Asim) and Asim (hit by Khan).
	reset()
	await _tick(4)
	khan.position.x = -0.8
	asim.position.x = 0.8
	khan.health = 10
	await _tick(3)
	Input.action_press("p2_punch")
	await _tick(2)
	Input.action_release("p2_punch")
	await _tick(8)
	_check(khan.health == 0 and khan.state == "ko" and round_state == "round_over", "Lethal Asim hit puts Khan into KO and ends round")
	await _tick(28)
	_check(khan.has_finite_bones() and asim.has_finite_bones(), "Both skeletons stay finite through Khan KO fall")
	await _save_capture("khan-stage-ko")

	reset()
	await _tick(4)
	khan.position.x = -0.8
	asim.position.x = 0.8
	asim.health = 10
	await _tick(3)
	Input.action_press("p1_punch")
	await _tick(2)
	Input.action_release("p1_punch")
	await _tick(8)
	_check(asim.health == 0 and asim.state == "ko" and round_state == "round_over", "Lethal Khan hit puts Asim into KO and ends round")
	await _tick(28)
	_check(asim.has_finite_bones() and khan.has_finite_bones(), "Both skeletons stay finite through Asim KO fall")

	reset()
	await _tick(4)
	_check(
		khan.health == 100 and asim.health == 100 and khan.state == "idle" and asim.state == "idle" and khan.current_anim_state == "idle" and asim.current_anim_state == "idle",
		"Reset restores both fighters' health and Idle state"
	)

	var report := {
		"passed": checks,
		"failed": failures,
		"khan_scale": khan.model.scale.x,
		"asim_scale": asim.model.scale.x,
		"khan_anim_list": Array(khan.anim_player.get_animation_list()),
		"asim_anim_list": Array(asim.anim_player.get_animation_list()),
		"khan_bone_count": khan.skeleton.get_bone_count(),
		"asim_bone_count": asim.skeleton.get_bone_count(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"engine": Engine.get_version_info().string,
	}
	if not capture_dir.is_empty():
		var file := FileAccess.open(capture_dir.path_join("khan-stage-validation.json"), FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(report, "  "))
	print("KHAN_STAGE_VALIDATION " + JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
