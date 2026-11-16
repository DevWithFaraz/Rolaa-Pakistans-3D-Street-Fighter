"""Pose-specific contact trial on the textured seam copy; no runtime cloth claim."""
import bpy,numpy as np,json,math
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[3];OUT=ROOT/'outputs/khan-model2'
scene=bpy.data.scenes['Khan_Garment_Prototype'];bpy.context.window.scene=scene
body=bpy.data.objects['Khan_Garment_Body'];rig=bpy.data.objects['Khan_Garment_Rig']
assert body.data.shape_keys is None
mesh=body.data;group=body.vertex_groups['Kameez_Surface'].index
cloth={v.index for v in mesh.vertices if any(g.group==group for g in v.groups)}
active=[i for i in cloth if mesh.vertices[i].co.z<1.020]
polys=[tuple(p.vertices) for p in mesh.polygons if not any(i in cloth for i in p.vertices) and max(mesh.vertices[i].co.z for i in p.vertices)<1.0]
base=np.empty(len(mesh.vertices)*3,dtype=np.float32);mesh.vertices.foreach_get('co',base);base=base.reshape((-1,3))
body.shape_key_add(name='Basis')
keydata=body.data.shape_keys;keydata.animation_data_create()
names={g.index:g.name for g in body.vertex_groups}
weights={i:[(names[g.group],g.weight) for g in mesh.vertices[i].groups if names[g.group] in rig.data.bones] for i in active}
inverse_body=body.matrix_world.inverted();inverse_rig=rig.matrix_world.inverted()
all_keys=[];clips={};records=[]
for track in rig.animation_data.nla_tracks:track.mute=True
for clip,step in [('Idle',10),('Idle2',3),('Punch',3),('MmaKick',3)]:
    action=bpy.data.actions['Khan_'+clip]
    rig.animation_data.action=action;rig.animation_data.action_slot=action.slots[0]
    start,end=[int(x) for x in action.frame_range]
    frames=sorted(set(list(range(start,end+1,step))+[end]));entries=[]
    for frame in frames:
        scene.frame_set(frame);bpy.context.view_layer.update()
        evaluated=body.evaluated_get(bpy.context.evaluated_depsgraph_get());posed=evaluated.to_mesh()
        vertices=[v.co.copy() for v in posed.vertices]
        bvh=BVHTree.FromPolygons(vertices,polys)
        evaluated.to_mesh_clear()
        matrices={n:inverse_body@rig.matrix_world@p.matrix@p.bone.matrix_local.inverted()@inverse_rig@body.matrix_world for n,p in rig.pose.bones.items()}
        hips=matrices['mixamorig:Hips'].to_3x3()
        result=base.copy();count=0;maximum=0.0
        for i in active:
            rest=Vector(base[i]);v=vertices[i]
            # Outward relative to the character, with front/back preserved during turns.
            radial=Vector((rest.x*.5,rest.y,0)).normalized()
            direction=(hips@radial).normalized()
            hit,normal,idx,dist=bvh.ray_cast(v+direction*.75,-direction,1.5)
            if hit is None:continue
            depth=(hit-v).dot(direction)+.008
            if depth<=0:continue
            attachment=max(0,min(1,(1.020-rest.z)/.045))
            correction=direction*depth*attachment
            blend=Matrix(((0,0,0),(0,0,0),(0,0,0)))
            total=sum(w for _,w in weights[i])
            for name,w in weights[i]:blend+=matrices[name].to_3x3()*(w/total)
            if abs(blend.determinant())<1e-8:continue
            result[i]+=np.array(blend.inverted()@correction)
            count+=1;maximum=max(maximum,correction.length)
        key=body.shape_key_add(name=f'Contact_{clip}_{frame:03d}')
        key.data.foreach_set('co',result.reshape(-1));key.value=0
        all_keys.append(key);entries.append((frame,key))
        records.append({'clip':clip,'frame':frame,'moved':count,'max_offset':maximum})
        print('CONTACT',clip,frame,count,round(maximum,4),flush=True)
    clips[clip]=(start,end,entries)
# Separate morph NLA tracks share clip names with the skeletal tracks on export.
for clip,(start,end,entries) in clips.items():
    action=bpy.data.actions.new('GarmentContact_'+clip);keydata.animation_data.action=action
    for key in all_keys:
        key.value=0;key.keyframe_insert('value',frame=start);key.keyframe_insert('value',frame=end)
    for j,(frame,key) in enumerate(entries):
        if j>0:key.value=0;key.keyframe_insert('value',frame=entries[j-1][0])
        key.value=1;key.keyframe_insert('value',frame=frame)
        if j+1<len(entries):key.value=0;key.keyframe_insert('value',frame=entries[j+1][0])
        key.value=0
    # Linear interpolation prevents corrective shape overshoot between samples.
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fc in bag.fcurves:
                    for point in fc.keyframe_points:point.interpolation='LINEAR'
    track=keydata.animation_data.nla_tracks.new();track.name=clip
    track.strips.new(clip,start,action)
keydata.animation_data.action=None;rig.animation_data.action=None
for t in rig.animation_data.nla_tracks:t.mute=False
for o in scene.objects:o.select_set(True)
bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=str(ROOT/'game/assets/characters/khan_contact_trial.glb'),export_format='GLB',use_selection=True,use_active_scene=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True,export_frame_range=False,export_rest_position_armature=True,export_skins=True,export_influence_nb=8,export_all_influences=False,export_apply=False)
(OUT/'inspection/contact-bake.json').write_text(json.dumps({'samples':records,'shape_count':len(all_keys),'cloth_vertices':len(active),'status':'Contact projection trial; render validation required'},indent=2))
for t in rig.animation_data.nla_tracks:t.mute=True
for t in keydata.animation_data.nla_tracks:t.mute=True
rig.animation_data.action=bpy.data.actions['Khan_Idle2'];rig.animation_data.action_slot=rig.animation_data.action.slots[0]
scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'blender/khan-model2-contact-trial.blend'))
