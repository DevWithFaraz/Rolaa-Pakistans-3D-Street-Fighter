import bpy,json,struct
from pathlib import Path
ROOT=Path(r'C:\Users\IT\Documents\Codex\2026-09-14\it-s-time-to-get-serious')
scene=bpy.data.scenes['Khan_Garment_Prototype'];bpy.context.window.scene=scene
rig=bpy.data.objects['Khan_Garment_Rig']
# Keep panel width coherent: merge transverse guide weights into the center chain.
for side in ['front','back']:
    ob=bpy.data.objects['Kameez_'+side.title()+'_Panel']
    names={g.index:g.name for g in ob.vertex_groups};saved=[]
    for vertex in ob.data.vertices:
        weights={}
        for g in vertex.groups:
            name=names.get(g.group)
            if name and name.startswith('cloth_'):name='cloth_'+side+'_C_'+name.rsplit('_',1)[1]
            if name:weights[name]=weights.get(name,0)+g.weight
        saved.append(weights)
    ob.vertex_groups.clear();groups={}
    for index,weights in enumerate(saved):
        total=sum(weights.values())
        for name,weight in weights.items():
            if name not in groups:groups[name]=ob.vertex_groups.new(name=name)
            groups[name].add([index],weight/total,'REPLACE')
for ob in scene.objects:
    if ob.type=='MESH' and ob.parent!=rig:
        matrix=ob.matrix_world.copy();ob.parent=rig;ob.matrix_world=matrix
    ob.select_set(True)
bpy.context.view_layer.objects.active=rig
rig.data.pose_position='POSE';rig.animation_data.action=None
for track in rig.animation_data.nla_tracks:track.mute=False
path=ROOT/'game'/'assets'/'characters'/'khan_garment_trial.glb'
bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,use_active_scene=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True,export_frame_range=False,export_rest_position_armature=True,export_skins=True,export_influence_nb=8,export_all_influences=False,export_apply=False)
with path.open('rb') as f:
    f.read(12);length,kind=struct.unpack('<II',f.read(8));data=json.loads(f.read(length))
report={'bytes':path.stat().st_size,'animations':[a.get('name') for a in data.get('animations',[])],'meshes':len(data.get('meshes',[])),'skin_bones':[len(s['joints']) for s in data.get('skins',[])],'active_garment_chains':['cloth_front_C','cloth_back_C'],'unused_guide_bones_retained':True}
assert report['meshes']==3 and report['skin_bones']==[59],report
(ROOT/'outputs'/'khan-model2'/'inspection'/'garment-export.json').write_text(json.dumps(report,indent=2));print(json.dumps(report))
for track in rig.animation_data.nla_tracks:track.mute=True
rig.animation_data.action=bpy.data.actions['Khan_Idle2'];rig.animation_data.action_slot=rig.animation_data.action.slots[0]
scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'outputs'/'khan-model2'/'blender'/'khan-model2-garment-trial.blend'))
