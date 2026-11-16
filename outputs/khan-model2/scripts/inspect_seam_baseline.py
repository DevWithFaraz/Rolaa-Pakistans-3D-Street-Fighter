import bpy,json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
scene=bpy.data.scenes['Khan_Garment_Prototype']
body=bpy.data.objects['Khan_Garment_Body']
report={'version':bpy.app.version_string,'scene':scene.name,'objects':[(o.name,o.type) for o in scene.objects],'body_matrix':[list(r) for r in body.matrix_world],'groups':[g.name for g in body.vertex_groups],'meshes':{}}
for ob in scene.objects:
    if ob.type!='MESH':continue
    mesh=ob.data
    report['meshes'][ob.name]={'verts':len(mesh.vertices),'polys':len(mesh.polygons),'groups':len(ob.vertex_groups),'uv_layers':[u.name for u in mesh.uv_layers],'materials':[m.name for m in mesh.materials],'seam_verts':sum(abs(v.co.z-1.035)<1e-5 for v in mesh.vertices)}
report['source']=bpy.data.meshes['Garment_Trial_PreCut_Backup'].name
report['pose_enum']=[i.identifier for i in bpy.types.Armature.bl_rna.properties['pose_position'].enum_items]
report['export_enums']={k:[i.identifier for i in bpy.ops.export_scene.gltf.get_rna_type().properties[k].enum_items] for k in ['export_format','export_animation_mode']}
(root/'inspection/seam-baseline.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report))
