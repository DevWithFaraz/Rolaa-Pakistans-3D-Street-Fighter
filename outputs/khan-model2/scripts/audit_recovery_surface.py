import bpy,json
from pathlib import Path
from mathutils.bvhtree import BVHTree
out=Path(__file__).resolve().parents[1]/'inspection/recovery-surface-audit.json'
body=bpy.data.objects['Khan_Garment_Body'];rig=bpy.data.objects['Khan_Garment_Rig'];scene=bpy.context.scene
for track in rig.animation_data.nla_tracks:track.mute=True
tag=body.vertex_groups['Kameez_Surface'].index
names={g.index:g.name for g in body.vertex_groups}
cloth={v.index for v in body.data.vertices if any(g.group==tag and g.weight>.5 for g in v.groups)}
lower={v.index for v in body.data.vertices if v.index not in cloth and sum(g.weight for g in v.groups if names[g.group] in ['mixamorig:Hips','mixamorig:LeftUpLeg','mixamorig:RightUpLeg','mixamorig:LeftLeg','mixamorig:RightLeg'])>.8}
cp=[tuple(p.vertices) for p in body.data.polygons if all(i in cloth for i in p.vertices) and sum(body.data.vertices[i].co.z for i in p.vertices)/len(p.vertices)<.98]
lp=[tuple(p.vertices) for p in body.data.polygons if all(i in lower for i in p.vertices)]
rows=[]
for clip,frames in [('Idle2',[1,30,60]),('Punch',[1,12,24,32]),('MmaKick',[1,10,18,26,36,49])]:
    action=bpy.data.actions['Draped_'+clip];rig.animation_data.action=action;rig.animation_data.action_slot=action.slots[0]
    for f in frames:
        scene.frame_set(f);bpy.context.view_layer.update()
        ev=body.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh();coords=[v.co.copy() for v in me.vertices]
        c=BVHTree.FromPolygons(coords,cp);p=BVHTree.FromPolygons(coords,lp);overlap=c.overlap(p)
        rows.append({'clip':clip,'frame':f,'overlapping_garment_trouser_face_pairs':len(overlap)})
        ev.to_mesh_clear()
        print(rows[-1],flush=True)
out.write_text(json.dumps({'note':'Geometric diagnostic only; visual acceptance still required. Excludes waist join above 0.98m.','samples':rows},indent=2))
