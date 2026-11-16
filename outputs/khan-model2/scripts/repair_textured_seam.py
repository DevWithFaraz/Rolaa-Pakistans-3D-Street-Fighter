"""Baseline-only seam repair. Never run against the rejected revision 2."""
import bpy,bmesh,json,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'outputs/khan-model2'
scene=bpy.data.scenes['Khan_Garment_Prototype']
bpy.context.window.scene=scene
rig=bpy.data.objects['Khan_Garment_Rig'];body=bpy.data.objects['Khan_Garment_Body']
assert len(rig.data.bones)==59
rig.data.pose_position='REST'
source=bpy.data.meshes['Garment_Trial_PreCut_Backup']
names={g.index:g.name for g in body.vertex_groups}
# Refit only the previously reconstructed upper trousers, not the original lower legs.
changed=0
for v in body.data.vertices:
    x,y,z=v.co
    if not (.54001<z<.98501 and abs(x)<.30):continue
    ws={names[g.group]:g.weight for g in v.groups}
    side=1 if ws.get('mixamorig:LeftUpLeg',0)>ws.get('mixamorig:RightUpLeg',0) else -1
    if max(ws.get('mixamorig:LeftUpLeg',0),ws.get('mixamorig:RightUpLeg',0))+ws.get('mixamorig:Hips',0)<.95:continue
    t=(z-.54)/.445;cx=side*(.15*(1-t)+.081*t)
    v.co.x=cx+(x-cx)*(1-.25*t)
    v.co.y=.01+(y-.01)*(1-.30*t)
    changed+=1
# Re-extract the original textured surface exactly to the body's cut plane.
for side,sign in [('front',-1),('back',1)]:
    bm=bmesh.new();bm.from_mesh(source)
    for z in [.578,1.035]:
        bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-6,plane_co=(0,0,z),plane_no=(0,0,1))
    bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-6,plane_co=(0,0,0),plane_no=(0,1,0))
    remove=[f for f in bm.faces if not (.577999<f.calc_center_median().z<1.035001 and abs(f.calc_center_median().x)<.285 and f.calc_center_median().y*sign>=0)]
    bmesh.ops.delete(bm,geom=remove,context='FACES')
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
    mesh=bpy.data.meshes.new('Textured_Seam_'+side);bm.to_mesh(mesh);bm.free()
    inherited=[{names[g.group]:g.weight for g in v.groups if g.group in names} for v in mesh.vertices]
    ob=bpy.data.objects['Kameez_'+side.title()+'_Panel'];ob.data=mesh
    ob.vertex_groups.clear();mesh.materials.append(source.materials[0]);groups={}
    surface=ob.vertex_groups.new(name='Kameez_Surface')
    surface.add(list(range(len(mesh.vertices))),1.0,'REPLACE')
    for v in mesh.vertices:
        t=max(0,min(1,(1.035-v.co.z)/.457))
        pin=max(0,min(1,1-(1.035-v.co.z)/.12));pin=pin*pin*(3-2*pin)
        vertical=max(0,min(2,t*3-.5));a=int(vertical);b=min(2,a+1);mix=vertical-a
        weights={n:w*pin for n,w in inherited[v.index].items()}
        for seg,w in [(a,1-mix),(b,mix)]:
            n=f'cloth_{side}_C_{seg}';weights[n]=weights.get(n,0)+(1-pin)*w
        total=sum(weights.values())
        for n,w in weights.items():
            if w>1e-8:
                if n not in groups:groups[n]=ob.vertex_groups.new(name=n)
                groups[n].add([v.index],w/total,'REPLACE')
    for p in mesh.polygons:p.use_smooth=True
# Join and weld only the waist seam, preserving per-loop UV coordinates.
for ob in scene.objects:ob.select_set(ob.type=='MESH')
bpy.context.view_layer.objects.active=body
bpy.ops.object.join()
bm=bmesh.new();bm.from_mesh(body.data)
seam=[v for v in bm.verts if abs(v.co.z-1.035)<1e-5 and abs(v.co.x)<.286]
before=len(bm.verts)
bmesh.ops.remove_doubles(bm,verts=seam,dist=1e-5)
remaining=sum(1 for e in bm.edges if e.is_boundary and all(abs(v.co.z-1.035)<1e-5 for v in e.verts))
welded=before-len(bm.verts)
bm.to_mesh(body.data);bm.free();body.data.update()
rig.data.pose_position='POSE'
rig.animation_data.action=None
for t in rig.animation_data.nla_tracks:t.mute=False
for ob in scene.objects:ob.select_set(True)
bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(filepath=str(ROOT/'game/assets/characters/khan_textured_seam_trial.glb'),export_format='GLB',use_selection=True,use_active_scene=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True,export_frame_range=False,export_rest_position_armature=True,export_skins=True,export_influence_nb=8,export_all_influences=False,export_apply=False)
for t in rig.animation_data.nla_tracks:t.mute=True
rig.animation_data.action=bpy.data.actions['Khan_Idle2'];rig.animation_data.action_slot=rig.animation_data.action.slots[0]
scene.frame_set(1)
report={'welded_vertices':welded,'waist_boundary_edges_remaining':remaining,'refit_upper_trouser_vertices':changed,'materials':[m.name for m in body.data.materials],'uvs':[u.name for u in body.data.uv_layers],'status':'Awaiting visual and animation validation'}
(OUT/'inspection/textured-seam-build.json').write_text(json.dumps(report,indent=2));print(report)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'blender/khan-model2-textured-seam-trial.blend'))
