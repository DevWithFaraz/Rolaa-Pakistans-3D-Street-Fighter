extends SkeletonModifier3D
## Pose-dependent garment clearance before secondary motion. Visual only.
## Independent panels lift as a whole when a thigh enters their envelope.
var front_angle := 0.0
var back_angle := 0.0
var panel_rotations := [Quaternion.IDENTITY, Quaternion.IDENTITY]
var initialized := false

func reset() -> void:
	initialized = false

func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null: return
	var hips := sk.find_bone("mixamorig_Hips")
	var body_delta := sk.get_bone_global_pose(hips) * sk.get_bone_global_rest(hips).affine_inverse()
	var hip_world := sk.global_transform * sk.get_bone_global_pose(hips).origin
	var knees: Array[Vector3] = []
	for side in ["Left", "Right"]:
		var knee := sk.find_bone("mixamorig_"+side+"Leg")
		knees.append(sk.global_transform * sk.get_bone_global_pose(knee).origin)
	var high_knee: Vector3 = knees[0] if knees[0].y > knees[1].y else knees[1]
	var mix := 1.0-exp(-maxf(delta,0.0)*28.0)
	if not initialized: mix = 1.0; initialized = true
	for side_index in range(2):
		var side: String = ["front","back"][side_index]
		var root_index := sk.find_bone("cloth_"+side+"_C_0")
		var pivot := sk.global_transform * sk.get_bone_global_pose(root_index).origin
		var tip_index := sk.find_bone("cloth_"+side+"_C_2")
		var neutral_tip := sk.global_transform * (body_delta * sk.get_bone_global_rest(tip_index).origin)
		var hanging_direction := (neutral_tip-pivot).normalized()
		var outward := (pivot-hip_world).normalized()
		# Lift diagonally for side kicks as well as forward for a knee raise.
		var target_direction := (high_knee+outward*0.15+Vector3.UP*0.07-pivot).normalized()
		var amount := smoothstep(-0.44,-0.12,high_knee.y-pivot.y)
		amount *= 0.65 if side_index==0 else 0.35
		var desired := Quaternion.IDENTITY.slerp(Quaternion(hanging_direction,target_direction),amount)
		panel_rotations[side_index] = panel_rotations[side_index].slerp(desired,mix)
		var rotation := Basis(panel_rotations[side_index])
		if side_index==0: front_angle=panel_rotations[side_index].get_angle()
		else: back_angle=panel_rotations[side_index].get_angle()
		for segment in range(3):
			var index := sk.find_bone("cloth_"+side+"_C_"+str(segment))
			var original := sk.global_transform * (body_delta * sk.get_bone_global_rest(index))
			var target := Transform3D(rotation*original.basis,pivot+rotation*(original.origin-pivot))
			sk.set_bone_global_pose(index,sk.global_transform.affine_inverse()*target)
