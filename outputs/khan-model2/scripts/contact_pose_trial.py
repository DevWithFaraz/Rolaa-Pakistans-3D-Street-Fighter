"""Single-pose actual-surface contact experiment. Preserve input; do not promote."""
import bpy,numpy as np,json
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[3];OUT=ROOT/'outputs/khan-model2'
scene=bpy.context.scene;body=bpy.data.objects['Khan_Garment_Body'];rig=bpy.data.objects['Khan_Garment_Rig']
for t in rig.animation_data.nla_tracks:t.mute=True
names={g.index:g.name for g in body.vertex_groups};tag=body.vertex_groups['Kameez_Surface'].index
cloth=[v.index for v in body.data.vertices if any(g.group==tag and g.weight>.5 for g in v.groups) and v.co.z<1.02]
controls=[b for b in rig.pose.bones if b.name.startswith('drape_')];ci={b.name:i for i,b in enumerate(controls)}
W=np.zeros((len(cloth),len(controls)))
for i,idx in enumerate(cloth):
    for g in body.data.vertices[idx].groups:
        if names[g.group] in ci:W[i,ci[names[g.group]]]=g.weight
lower={v.index for v in body.data.vertices if v.index not in set(cloth) and sum(g.weight for g in v.groups if names[g.group] in ['mixamorig:Hips','mixamorig:LeftUpLeg','mixamorig:RightUpLeg','mixamorig:LeftLeg','mixamorig:RightLeg'])>.8}
polys=[tuple(p.vertices) for p in body.data.polygons if all(i in lower for i in p.vertices)]
# Ridge protects unconstrained controls; neighboring controls resist spikes.
L=np.eye(len(controls))*.15
for name,i in ci.items():
    _,row,col=name.split('_');row=int(row);col=int(col)
    for other in [f'drape_{row+1}_{col}',f'drape_{row}_{col+1}' if col%9<8 else '']:
        if other in ci:
            j=ci[other];L[i,i]+=.5;L[j,j]+=.5;L[i,j]-=.5;L[j,i]-=.5
fit=np.linalg.solve(W.T@W+L,W.T)
action=bpy.data.actions['Draped_MmaKick'].copy();action.name='ContactPose_MmaKick';rig.animation_data.action=action;rig.animation_data.action_slot=action.slots[0]
scene.frame_set(18);bpy.context.view_layer.update()
hips=rig.pose.bones['mixamorig:Hips']
basis=rig.matrix_world.to_3x3() @ hips.matrix.to_3x3() @ hips.bone.matrix_local.to_3x3().inverted() @ controls[0].bone.matrix_local.to_3x3()
bi=np.array(basis.inverted());reports=[]
for iteration in range(10):
    ev=body.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh();coords=[v.co.copy() for v in me.vertices]
    bvh=BVHTree.FromPolygons(coords,polys);push=np.zeros((len(cloth),3));inside=0
    for i,idx in enumerate(cloth):
        p=coords[idx];hit,normal,face,dist=bvh.find_nearest(p)
        signed=(p-hit).dot(normal)
        if signed<.009 and dist<.16:
            push[i]=np.array(normal)*min(.045,.009-signed);inside+=1
    ev.to_mesh_clear()
    correction=fit@push
    correction*=np.minimum(1,.035/np.maximum(np.linalg.norm(correction,axis=1),1e-9))[:,None]
    for i,b in enumerate(controls):b.location+=Vector(bi@correction[i])
    bpy.context.view_layer.update();reports.append({'iteration':iteration,'near_or_inside_vertices':inside,'max_control_step':float(np.linalg.norm(correction,axis=1).max())})
for b in controls:b.keyframe_insert('location',frame=18)
for t in rig.animation_data.nla_tracks:
    if t.name=='MmaKick':t.strips[0].action=action;t.strips[0].action_slot=action.slots[0]
rig.animation_data.action=None
for t in rig.animation_data.nla_tracks:t.mute=False
for o in scene.objects:o.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(ROOT/'game/assets/characters/khan_contact_pose_trial.glb'),export_format='GLB',use_selection=True,use_active_scene=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True,export_frame_range=False,export_rest_position_armature=True,export_skins=True,export_influence_nb=8,export_all_influences=False,export_apply=False)
(OUT/'inspection/contact-pose-build.json').write_text(json.dumps(reports,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'blender/khan-model2-contact-pose-trial.blend'))
