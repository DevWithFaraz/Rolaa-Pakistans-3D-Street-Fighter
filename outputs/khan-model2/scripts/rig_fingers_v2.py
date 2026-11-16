import bpy,math,json,statistics
from mathutils import Vector,Quaternion
from pathlib import Path
ROOT=Path(r'C:\Users\IT\Documents\Codex\2026-09-14\it-s-time-to-get-serious\outputs\khan-model2')
body=bpy.data.objects['Khan_Garment_Body'];rig=bpy.data.objects['Khan_Garment_Rig'];scene=bpy.context.scene
assert 'finger_Left_Index_0' not in rig.data.bones,'Already added.'
rig.data.pose_position='REST'
bounds=[-.12,-.064,-.038,-.012,.035];digits=['Index','Middle','Ring','Pinky'];chains={}
for side,sign in [('Left',1),('Right',-1)]:
    for digit in range(4):
        pool=[v.co.copy() for v in body.data.vertices if v.co.x*sign>.384 and bounds[digit]+.001<v.co.y<bounds[digit+1]-.001 and .7<v.co.z<.89]
        root_z=[.852,.856,.852,.843][digit];tip_z=min(p.z for p in pool)+.0025
        levels=[root_z,root_z+(tip_z-root_z)*.43,root_z+(tip_z-root_z)*.76,tip_z]
        points=[]
        for z in levels:
            layer=[p for p in pool if abs(p.z-z)<.009]
            assert layer,(side,digit,z)
            points.append(Vector((statistics.median(p.x for p in layer),statistics.median(p.y for p in layer),z)))
        chains[(side,digits[digit])]=points
for ob in scene.objects:ob.select_set(False)
rig.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.object.mode_set(mode='EDIT');inverse=rig.matrix_world.inverted()
for (side,digit),points in chains.items():
    parent=rig.data.edit_bones['mixamorig:'+side+'Hand'];sign=1 if side=='Left' else -1
    for part in range(3):
        bone=rig.data.edit_bones.new(f'finger_{side}_{digit}_{part}');bone.head=inverse@points[part];bone.tail=inverse@points[part+1]
        bone.parent=parent;bone.use_connect=part>0
        bone.align_roll(inverse.to_3x3()@Vector((-sign,0,0)));parent=bone
bpy.ops.object.mode_set(mode='OBJECT')
groups={g.name:g for g in body.vertex_groups}
for side,digit in chains:
    for part in range(3):
        name=f'finger_{side}_{digit}_{part}';groups[name]=body.vertex_groups.new(name=name)
counts={}
for vertex in body.data.vertices:
    x,y,z=vertex.co
    if abs(x)<.34 or z>=.884 or z<.70:continue
    # The thumb is already a separate mesh branch and has its own Mixamo chain.
    if abs(x)<.384 and y<-.055 and z>.778:continue
    side='Left' if x>0 else 'Right';digit=next((i for i in range(4) if bounds[i]<=y<bounds[i+1]),None)
    if digit is None:continue
    name=digits[digit];chain=chains[(side,name)]
    pin=max(0,min(1,(z-chain[0].z)/(.884-chain[0].z)))
    pin=pin*pin*(3-2*pin)
    w=[1.0,0.0,0.0]
    for joint in [1,2]:
        blend=max(0,min(1,(chain[joint].z+.008-z)/.016))
        if joint==1:w=[1-blend,blend,0]
        else:w[0]*=1-blend;w[1]*=1-blend;w[2]=blend
    for group in list(vertex.groups):body.vertex_groups[group.group].remove([vertex.index])
    if pin>0:groups['mixamorig:'+side+'Hand'].add([vertex.index],pin,'REPLACE')
    for part,weight in enumerate(w):
        if weight*(1-pin)>1e-8:groups[f'finger_{side}_{name}_{part}'].add([vertex.index],weight*(1-pin),'REPLACE')
    counts[side+'_'+name]=counts.get(side+'_'+name,0)+1
for track in rig.animation_data.nla_tracks:track.mute=True
for action_name,curl in [('Khan_Idle',[0,0,0]),('Khan_Idle2',[.06,.12,.08]),('Khan_Punch',[.50,.85,.40]),('Khan_MmaKick',[.10,.18,.12])]:
    action=bpy.data.actions[action_name];rig.animation_data.action=action;rig.animation_data.action_slot=action.slots[0]
    start,end=[int(v) for v in action.frame_range]
    for (side,digit) in chains:
        for part in range(3):
            pb=rig.pose.bones[f'finger_{side}_{digit}_{part}'];pb.rotation_mode='QUATERNION'
            pb.rotation_quaternion=Quaternion((1,0,0),curl[part])
            for frame in [start,end]:pb.keyframe_insert(data_path='rotation_quaternion',frame=frame,group='Independent Fingers')
rig.animation_data.action=bpy.data.actions['Khan_Idle2'];rig.animation_data.action_slot=rig.animation_data.action.slots[0]
rig.data.pose_position='POSE';scene.frame_set(1);bpy.context.view_layer.update()
(ROOT/'inspection/finger-rig-v2.json').write_text(json.dumps({'new_bones':24,'weighted_vertices':counts,'thumb':'existing independent chain retained','chains':{s+'_'+d:[list(p) for p in pts] for (s,d),pts in chains.items()}},indent=2))
print(json.dumps(counts))
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'blender/khan-model2-cloth-hands-v2.blend'))
