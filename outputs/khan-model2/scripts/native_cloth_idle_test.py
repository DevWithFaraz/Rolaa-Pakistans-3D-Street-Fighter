"""Isolated native cloth evaluation. Does not replace any playable review."""
import bpy,bmesh,json,numpy as np
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3];OUT=ROOT/'outputs/khan-model2'
scene=bpy.data.scenes['Khan_Garment_Prototype'];bpy.context.window.scene=scene
body=bpy.data.objects['Khan_Garment_Body'];rig=bpy.data.objects['Khan_Garment_Rig']
tag=body.vertex_groups['Kameez_Surface'].index
for t in rig.animation_data.nla_tracks:t.mute=True
# Record the actual idle pose channels before building a slow rest-to-idle lead-in.
rig.animation_data.action=bpy.data.actions['Khan_Idle2'];rig.animation_data.action_slot=rig.animation_data.action.slots[0]
poses=[]
for f in range(1,61):
    scene.frame_set(f);bpy.context.view_layer.update()
    poses.append({p.name:(p.location.copy(),p.rotation_quaternion.copy(),p.scale.copy()) for p in rig.pose.bones})
action=bpy.data.actions.new('NativeCloth_Idle2_WithLeadIn');rig.animation_data.action=action
for frame in [1,20]:
    for p in rig.pose.bones:
        p.location=(0,0,0);p.rotation_quaternion=(1,0,0,0);p.scale=(1,1,1)
        for prop in ['location','rotation_quaternion','scale']:p.keyframe_insert(prop,frame=frame)
for f,pose in enumerate(poses,51):
    for name,(loc,rot,scale) in pose.items():
        p=rig.pose.bones[name];p.location=loc;p.rotation_quaternion=rot;p.scale=scale
        for prop in ['location','rotation_quaternion','scale']:p.keyframe_insert(prop,frame=f)
for layer in action.layers:
    for strip in layer.strips:
        for bag in strip.channelbags:
            for fc in bag.fcurves:
                for k in fc.keyframe_points:k.interpolation='LINEAR'
scene.frame_set(1);bpy.context.view_layer.update()
# Copy the original UV/material-bearing hanging surface and leave the body intact.
cloth=body.copy();cloth.data=body.data.copy();cloth.name='Native_Kameez_Test';scene.collection.objects.link(cloth)
bm=bmesh.new();bm.from_mesh(cloth.data);dw=bm.verts.layers.deform.active
remove=[f for f in bm.faces if not any(v[dw].get(tag,0)>.5 for v in f.verts)]
bmesh.ops.delete(bm,geom=remove,context='FACES')
bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
before_cleanup={'vertices':len(bm.verts),'faces':len(bm.faces),'boundary':sum(e.is_boundary for e in bm.edges)}
bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00002)
bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=.00002)
bm.verts.index_update();seen=set();duplicates=[]
for f in bm.faces:
    key=tuple(sorted(v.index for v in f.verts))
    if key in seen:duplicates.append(f)
    else:seen.add(key)
if duplicates:bmesh.ops.delete(bm,geom=duplicates,context='FACES_ONLY')
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
after_cleanup={'vertices':len(bm.verts),'faces':len(bm.faces),'boundary':sum(e.is_boundary for e in bm.edges),'nonmanifold':sum(not e.is_manifold and not e.is_boundary for e in bm.edges)}
print('CLOTH_TOPOLOGY',before_cleanup,after_cleanup,flush=True)
(OUT/'inspection/native-cloth-topology.json').write_text(json.dumps({'before':before_cleanup,'after':after_cleanup},indent=2))
bm.to_mesh(cloth.data);bm.free()
pin=cloth.vertex_groups.new(name='Cloth_Waist_Pin')
for v in cloth.data.vertices:
    w=max(0,min(1,(v.co.z-.99)/.035))
    if w>0:pin.add([v.index],w,'REPLACE')
# Body-only copy is the collider. Remove hanging garment faces from visible body too.
bm=bmesh.new();bm.from_mesh(body.data);dw=bm.verts.layers.deform.active
bmesh.ops.delete(bm,geom=[f for f in bm.faces if any(v[dw].get(tag,0)>.5 for v in f.verts)],context='FACES')
bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
bm.to_mesh(body.data);bm.free()
collider=body.copy();collider.data=body.data.copy();collider.name='Native_Cloth_Collider';scene.collection.objects.link(collider)
for o in scene.objects:o.select_set(False)
collider.select_set(True);bpy.context.view_layer.objects.active=collider
rig.data.pose_position='REST'
dec=collider.modifiers.new('CollisionSimplification','DECIMATE');dec.ratio=.035
bpy.ops.object.modifier_move_up(modifier=dec.name)
bpy.ops.object.modifier_apply(modifier=dec.name)
collision=collider.modifiers.new('GarmentCollision','COLLISION')
collider.collision.thickness_outer=.003;collider.collision.thickness_inner=.001
collider.hide_render=True
rig.data.pose_position='POSE'
modifier=cloth.modifiers.new('NativeCloth','CLOTH')
settings=modifier.settings
settings.vertex_group_mass=pin.name;settings.quality=8;settings.mass=.2;settings.air_damping=4
settings.tension_stiffness=25;settings.compression_stiffness=25;settings.shear_stiffness=15;settings.bending_stiffness=.5
modifier.collision_settings.use_collision=True;modifier.collision_settings.distance_min=.003
modifier.collision_settings.collision_quality=6;modifier.collision_settings.use_self_collision=True;modifier.collision_settings.self_distance_min=.002
modifier.point_cache.frame_start=1;modifier.point_cache.frame_end=110
scene.frame_start=1;scene.frame_end=110
snapshots={}
for frame in range(1,111):
    scene.frame_set(frame);deps=bpy.context.evaluated_depsgraph_get();evaluated=cloth.evaluated_get(deps);m=evaluated.to_mesh()
    if frame in [20,50,65,80,95,110]:
        coords=np.empty(len(m.vertices)*3,dtype=np.float32);m.vertices.foreach_get('co',coords)
        snapshots[frame]={'vertices':len(m.vertices),'finite':bool(np.isfinite(coords).all()),'min':coords.reshape(-1,3).min(axis=0).tolist(),'max':coords.reshape(-1,3).max(axis=0).tolist()}
        print('CLOTH_FRAME',frame,snapshots[frame],flush=True)
        if not snapshots[frame]['finite'] or abs(coords).max()>2.0:
            (OUT/'inspection/native-cloth-idle.json').write_text(json.dumps({'status':'REJECTED: unstable bounds','snapshots':snapshots},indent=2))
            raise RuntimeError('Native cloth left the character bounds; do not export this result.')
    evaluated.to_mesh_clear()
    if frame==80:
        # Freeze evaluated meshes into a separate static scene for independent rendering.
        static=bpy.data.scenes.new('Native_Cloth_Idle_Static')
        for ob in [body,cloth]:
            eval_ob=ob.evaluated_get(deps)
            snapshot=bpy.data.objects.new(ob.name+'_Snapshot',bpy.data.meshes.new_from_object(eval_ob,depsgraph=deps))
            snapshot.matrix_world=ob.matrix_world.copy();static.collection.objects.link(snapshot)
(OUT/'inspection/native-cloth-idle.json').write_text(json.dumps(snapshots,indent=2))
bpy.context.window.scene=bpy.data.scenes['Native_Cloth_Idle_Static']
for ob in bpy.context.scene.objects:ob.select_set(True)
bpy.context.view_layer.objects.active=next(iter(bpy.context.scene.objects))
bpy.ops.export_scene.gltf(filepath=str(ROOT/'game/assets/characters/khan_native_cloth_idle_static.glb'),export_format='GLB',use_selection=True,use_active_scene=True,export_animations=False,export_skins=False)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'blender/khan-model2-native-cloth-idle-test.blend'))
