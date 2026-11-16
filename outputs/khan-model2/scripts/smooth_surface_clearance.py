"""Separate textured trial: a smooth clearance field baked to garment controls.

Keeps mesh coordinates, UVs and material unchanged. This is a clip-specific
corrective rig, not a general-purpose cloth simulation.
"""
import bpy, math, json, hashlib
import numpy as np
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'outputs/khan-model2'
scene=bpy.data.scenes['Khan_Garment_Prototype'];bpy.context.window.scene=scene
body=bpy.data.objects['Khan_Garment_Body'];rig=bpy.data.objects['Khan_Garment_Rig']
mesh=body.data
assert mesh.shape_keys is None and len(rig.data.bones)==59
tag=body.vertex_groups['Kameez_Surface'].index
cloth={v.index for v in mesh.vertices if any(g.group==tag and g.weight>.5 for g in v.groups)}
names={g.index:g.name for g in body.vertex_groups}
saved={i:{names[g.group]:g.weight for g in mesh.vertices[i].groups if names[g.group] in rig.data.bones} for i in cloth}
coords=np.empty(len(mesh.vertices)*3,dtype=np.float32);mesh.vertices.foreach_get('co',coords)
uv=np.empty(len(mesh.uv_layers.active.data)*2,dtype=np.float32);mesh.uv_layers.active.data.foreach_get('uv',uv)
signatures={'coordinates':hashlib.sha256(coords.tobytes()).hexdigest(),'uv':hashlib.sha256(uv.tobytes()).hexdigest()}
lower_bones={'mixamorig:Hips','mixamorig:LeftUpLeg','mixamorig:RightUpLeg','mixamorig:LeftLeg','mixamorig:RightLeg'}
lower={v.index for v in mesh.vertices if sum(g.weight for g in v.groups if names.get(g.group) in lower_bones)>.8 and v.co.z<1.015 and v.index not in cloth}
polys=[tuple(p.vertices) for p in mesh.polygons if all(i in lower for i in p.vertices)]
used=sorted({i for p in polys for i in p});remap={v:i for i,v in enumerate(used)}
polys=[tuple(remap[i] for i in p) for p in polys]
NA=16; NZ=8; LOW=.578; HIGH=1.035
def mapping(co):
    a=(math.atan2(co.x,-co.y)%(2*math.pi))*NA/(2*math.pi)
    z=max(0,min(NZ-1,(co.z-LOW)/(HIGH-LOW)*(NZ-1)))
    i=int(a)%NA;j=min(NZ-2,int(z));u=a-int(a);v=z-j
    return [(j,i,(1-u)*(1-v)),(j,(i+1)%NA,u*(1-v)),(j+1,i,(1-u)*v),(j+1,(i+1)%NA,u*v)]
maps={i:mapping(mesh.vertices[i].co) for i in cloth}
for t in rig.animation_data.nla_tracks:t.mute=True
rig.animation_data.action=None
rig.data.pose_position='REST'
for o in scene.objects:o.select_set(False)
rig.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.object.mode_set(mode='EDIT')
inv=rig.matrix_world.inverted()
for j in range(NZ):
    for i in range(NA):
        angle=i*2*math.pi/NA;z=LOW+(HIGH-LOW)*j/(NZ-1)
        b=rig.data.edit_bones.new(f'fit_{j}_{i}')
        b.head=inv@Vector((.25*math.sin(angle),-.16*math.cos(angle),z))
        b.tail=b.head+Vector((0,.035,0))
        b.parent=rig.data.edit_bones['mixamorig:Hips'];b.use_deform=True
bpy.ops.object.mode_set(mode='OBJECT')
groups={(j,i):body.vertex_groups.new(name=f'fit_{j}_{i}') for j in range(NZ) for i in range(NA)}
for idx in cloth:
    v=mesh.vertices[idx]
    pin=max(0,min(1,(v.co.z-.99)/(.035)));pin=pin*pin*(3-2*pin)
    for name in saved[idx]:body.vertex_groups[name].remove([idx])
    # The original attached waistband stays intact, including its existing weights.
    for name,w in saved[idx].items():
        if pin*w>1e-8:body.vertex_groups[name].add([idx],pin*w,'REPLACE')
    for j,i,w in maps[idx]:
        if w*(1-pin)>1e-8:groups[j,i].add([idx],w*(1-pin),'REPLACE')
rig.data.pose_position='POSE'
bpy.context.view_layer.update()
report={'kind':'Baked smooth garment clearance; not cloth simulation','signatures_before':signatures,'clips':[],'cloth_vertices':len(cloth),'controls':NA*NZ}
for clip in ['Idle','Idle2','Punch','MmaKick']:
    original=bpy.data.actions['Khan_'+clip]
    action=original.copy();action.name='SurfaceFit_'+clip
    rig.animation_data.action=action;rig.animation_data.action_slot=action.slots[0]
    start,end=map(int,original.frame_range)
    fields=[]
    for frame in range(start,end+1):
        scene.frame_set(frame)
        for j,i in groups:rig.pose.bones[f'fit_{j}_{i}'].location=(0,0,0)
        bpy.context.view_layer.update()
        hips=rig.pose.bones['mixamorig:Hips']
        delta=rig.matrix_world@hips.matrix@hips.bone.matrix_local.inverted()@rig.matrix_world.inverted()
        transform=delta.inverted()@body.matrix_world
        evaluated=body.evaluated_get(bpy.context.evaluated_depsgraph_get());posed=evaluated.to_mesh()
        vertices=[transform@posed.vertices[i].co for i in used]
        bvh=BVHTree.FromPolygons(vertices,polys)
        evaluated.to_mesh_clear()
        field=np.zeros((NZ,NA),dtype=np.float64)
        for idx in cloth:
            co=mesh.vertices[idx].co
            if co.z>=1.005:continue
            # The old height-based extraction also tagged inner return surfaces
            # beneath the hem. They are not the outside of the garment and must
            # not drive an outward clearance envelope for the visible fabric.
            if co.z<.68 and (co.x/.26)**2+(co.y/.17)**2<.72:continue
            radial=Vector((co.x,co.y,0));radius=radial.length
            if radius<.02:continue
            d=radial/radius
            hit,_,_,_=bvh.ray_cast(Vector((0,0,co.z))+d*1.4,-d,1.4)
            if hit is None:continue
            depth=max(0,hit.dot(d)+.018-radius)
            for j,i,w in maps[idx]:
                if w>1e-5:field[j,i]=max(field[j,i],depth)
        # Spread necessary clearance across neighboring controls, avoiding the
        # jagged independent vertex projection rejected in the previous trial.
        for _ in range(4):
            other=np.maximum(np.roll(field,1,axis=1),np.roll(field,-1,axis=1))-.026
            other[1:]=np.maximum(other[1:],field[:-1]-.035)
            other[:-1]=np.maximum(other[:-1],field[1:]-.035)
            field=np.maximum(field,other)
        field[-1]=0
        assert np.isfinite(field).all() and field.max()<1.0,(clip,frame,float(field.max()))
        fields.append(field)
        if frame%30==0:print('SAMPLE',clip,frame,round(float(field.max()),4),flush=True)
    raw=np.array(fields)
    # A symmetric conservative temporal filter avoids single-frame popping.
    fields=raw.copy()
    for f in range(len(fields)):
        fields[f]=np.maximum(raw[f],raw[max(0,f-2):min(len(raw),f+3)].mean(axis=0))
    for k,frame in enumerate(range(start,end+1)):
        scene.frame_set(frame)
        for j,i in groups:
            a=i*2*math.pi/NA
            offset=Vector((math.sin(a),-math.cos(a),0))*float(fields[k,j,i])
            p=rig.pose.bones[f'fit_{j}_{i}']
            p.location=p.bone.matrix_local.to_3x3().inverted()@inv.to_3x3()@offset
            p.keyframe_insert('location',frame=frame,group='Garment clearance')
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fc in bag.fcurves:
                    if 'fit_' in fc.data_path:
                        for kp in fc.keyframe_points:kp.interpolation='LINEAR'
    for track in rig.animation_data.nla_tracks:
        if track.name==clip:
            track.strips[0].action=action
            track.strips[0].action_slot=action.slots[0]
    report['clips'].append({'clip':clip,'frames':len(fields),'max_clearance':float(fields.max())})
    print('BAKED',report['clips'][-1],flush=True)
coords2=np.empty_like(coords);mesh.vertices.foreach_get('co',coords2)
uv2=np.empty_like(uv);mesh.uv_layers.active.data.foreach_get('uv',uv2)
assert np.array_equal(coords,coords2) and np.array_equal(uv,uv2)
report['coordinates_and_uv_unchanged']=True
rig.animation_data.action=None
for track in rig.animation_data.nla_tracks:track.mute=False
for o in scene.objects:o.select_set(True)
bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=str(ROOT/'game/assets/characters/khan_surface_fit_trial.glb'),use_selection=True,use_active_scene=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True,export_frame_range=False,export_rest_position_armature=True,export_skins=True,export_influence_nb=8,export_all_influences=False,export_apply=False)
for track in rig.animation_data.nla_tracks:track.mute=True
rig.animation_data.action=bpy.data.actions['SurfaceFit_Idle2'];rig.animation_data.action_slot=rig.animation_data.action.slots[0]
scene.frame_set(1)
(OUT/'inspection/surface-fit-build.json').write_text(json.dumps(report,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'blender/khan-model2-surface-fit-trial.blend'))
