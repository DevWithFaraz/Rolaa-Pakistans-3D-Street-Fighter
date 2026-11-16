extends SkeletonModifier3D
## Coupled coarse fabric grid. Collision envelopes include the shalwar volume.
const WIDTH := 5
const HEIGHT := 6
const PANEL_POINTS := WIDTH*HEIGHT
var points: Array[Vector3] = []
var previous: Array[Vector3] = []
var rest_points: Array[Vector3] = []
var bone_ids: Array[int] = []
var links: Array = []
var capsules: Array = []
var initialized := false
var paused := false
var max_penetration := 0.0
var hips := -1

func reset() -> void:
	initialized = false

func _prepare(sk: Skeleton3D) -> void:
	rest_points.clear(); bone_ids.clear(); links.clear()
	hips = sk.find_bone("mixamorig_Hips")
	for side in ["front","back"]:
		for row in range(HEIGHT):
			for column in range(WIDTH):
				var index := sk.find_bone("fabric_%s_c%d_%d" % [side,column,mini(row,HEIGHT-2)])
				bone_ids.append(index if row<HEIGHT-1 else -1)
				var p := sk.get_bone_global_rest(index).origin
				if row==HEIGHT-1:
					var preceding := sk.find_bone("fabric_%s_c%d_%d" % [side,column,HEIGHT-3])
					p += p-sk.get_bone_global_rest(preceding).origin
				rest_points.append(p)
	for panel in range(2):
		for row in range(HEIGHT):
			for column in range(WIDTH):
				var i := panel*PANEL_POINTS+row*WIDTH+column
				if row+1<HEIGHT: _link(i,i+WIDTH,1.0)
				if column+1<WIDTH: _link(i,i+1,1.0)
				if row+1<HEIGHT and column+1<WIDTH:
					_link(i,i+WIDTH+1,0.65); _link(i+1,i+WIDTH,0.65)
				if row+2<HEIGHT: _link(i,i+WIDTH*2,0.12)

func _link(a:int,b:int,strength:float) -> void:
	links.append([a,b,rest_points[a].distance_to(rest_points[b]),strength])

func _free(index:int) -> float:
	return 0.0 if index%PANEL_POINTS<WIDTH else 1.0

func _bone_world(sk:Skeleton3D,name:String) -> Vector3:
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(name)).origin

func _colliders(sk:Skeleton3D,body_world:Transform3D) -> void:
	capsules.clear()
	var hip := _bone_world(sk,"mixamorig_Hips")
	var up := (body_world.basis*Vector3.UP).normalized()
	capsules.append([hip-up*0.07,hip+up*0.13,0.175])
	for side in ["Left","Right"]:
		var thigh := _bone_world(sk,"mixamorig_"+side+"UpLeg")
		var knee := _bone_world(sk,"mixamorig_"+side+"Leg")
		var ankle := _bone_world(sk,"mixamorig_"+side+"Foot")
		capsules.append([thigh,knee,0.155])
		capsules.append([knee,ankle,0.125])

func _outside(p:Vector3) -> Vector3:
	for capsule in capsules:
		var a:Vector3=capsule[0];var b:Vector3=capsule[1]
		var axis:=b-a
		var nearest:=a+axis*clampf((p-a).dot(axis)/maxf(axis.length_squared(),0.000001),0.0,1.0)
		var offset:=p-nearest;var length:=offset.length();var radius:float=capsule[2]
		if length<radius:
			p=nearest+(offset/length if length>0.000001 else Vector3.FORWARD)*radius
	return p

func _solve_contacts() -> void:
	for i in range(points.size()):
		if _free(i)>0: points[i]=_outside(points[i])
	# Surface samples keep wide cells from spanning through a leg between control points.
	for panel in range(2):
		for row in range(HEIGHT-1):
			for column in range(WIDTH-1):
				var i:=panel*PANEL_POINTS+row*WIDTH+column
				var corners:=[i,i+1,i+WIDTH,i+WIDTH+1]
				var center:=Vector3.ZERO;var movable:=0.0
				for j in corners:center+=points[j]*0.25;movable+=_free(j)
				var correction:=_outside(center)-center
				if movable>0 and correction.length_squared()>0.00000001:
					for j in corners:
						if _free(j)>0:points[j]+=correction*(4.0/movable)

func _process_modification_with_delta(delta:float) -> void:
	var sk:=get_skeleton()
	if sk==null:return
	if rest_points.is_empty():_prepare(sk)
	var body_delta:=sk.get_bone_global_pose(hips)*sk.get_bone_global_rest(hips).affine_inverse()
	var to_world:=sk.global_transform*body_delta
	var world_delta:=to_world*sk.global_transform.affine_inverse()
	_colliders(sk,world_delta)
	if not initialized:
		points.clear();previous.clear()
		for p in rest_points:points.append(to_world*p)
		_solve_contacts();previous.assign(points);initialized=true
	if not paused and delta>0:
		var step:=minf(delta,1.0/30.0)/2.0
		for substep in range(2):
			for i in range(points.size()):
				var target:=to_world*rest_points[i]
				if _free(i)==0:points[i]=target;previous[i]=target;continue
				var velocity:Vector3=(points[i]-previous[i])*exp(-step*6.0)
				previous[i]=points[i]
				points[i]+=velocity+(Vector3.DOWN*4.0+(target-points[i])*5.0)*step*step
			for iteration in range(10):
				for link in links:
					var a:int=link[0];var b:int=link[1];var offset:=points[b]-points[a]
					var length:=offset.length();var wa:=_free(a);var wb:=_free(b)
					if length<0.000001 or wa+wb==0:continue
					var correction:=offset*((length-float(link[2]))/length)*float(link[3])/(wa+wb)
					points[a]+=correction*wa;points[b]-=correction*wb
				_solve_contacts()
	max_penetration=0.0
	for i in range(points.size()):
		if _free(i)>0:max_penetration=maxf(max_penetration,points[i].distance_to(_outside(points[i])))
	var inverse:=sk.global_transform.affine_inverse()
	for i in range(points.size()):
		var index:=bone_ids[i]
		if index<0:continue
		var base:=to_world*sk.get_bone_global_rest(index)
		var original_direction:Vector3=(to_world*rest_points[i+WIDTH]-base.origin).normalized()
		var direction:Vector3=(points[i+WIDTH]-points[i]).normalized()
		if direction.length_squared()<0.5:continue
		# Translation controls act as a continuous deformation lattice. Independent
		# segment rotations can invert triangles between neighboring columns.
		sk.set_bone_global_pose(index,inverse*Transform3D(base.basis,points[i]))
