import bpy,bmesh,json
from pathlib import Path
ROOT=Path(r'C:\Users\IT\Documents\Codex\2026-09-14\it-s-time-to-get-serious\outputs\khan-model2')
body=bpy.data.objects['Khan_Garment_Body'];rig=bpy.data.objects['Khan_Garment_Rig']
assert not body.get('finger_slits_v2'),'Already separated.'
backup=body.data.copy();backup.name='Body_Before_Finger_Separation';backup.use_fake_user=True
rig.data.pose_position='REST'
for o in bpy.context.scene.objects:o.select_set(False)
body.select_set(True);bpy.context.view_layer.objects.active=body
coords=[];faces=[]
for sign in [-1,1]:
    for y in [-.064,-.038,-.012]:
        lo,hi=sorted([sign*.33,sign*.49]);offset=len(coords)
        coords.extend([(lo,y-.0014,.69),(hi,y-.0014,.69),(hi,y+.0014,.69),(lo,y+.0014,.69),(lo,y-.0014,.836),(hi,y-.0014,.836),(hi,y+.0014,.836),(lo,y+.0014,.836)])
        faces.extend([tuple(offset+i for i in f) for f in [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]])
mesh=bpy.data.meshes.new('Finger_Gap_Cutters');mesh.from_pydata(coords,[],faces);mesh.update()
cutter=bpy.data.objects.new('Finger_Gap_Cutters',mesh);bpy.context.scene.collection.objects.link(cutter)
mat=bpy.data.materials.new('Finger_Inner_Skin');mat.use_nodes=True
shader=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
shader.inputs['Base Color'].default_value=(.42,.20,.12,1);shader.inputs['Roughness'].default_value=.6
body.data.materials.append(mat)
for m in body.data.materials:cutter.data.materials.append(m)
for f in cutter.data.polygons:f.material_index=len(body.data.materials)-1
modifier=body.modifiers.new('Separate_Touching_Fingers','BOOLEAN');modifier.operation='DIFFERENCE';modifier.solver='EXACT';modifier.object=cutter
if hasattr(modifier,'use_hole_tolerant'):modifier.use_hole_tolerant=True
while list(body.modifiers).index(modifier)>0:bpy.ops.object.modifier_move_up(modifier=modifier.name)
bpy.ops.object.modifier_apply(modifier=modifier.name)
bpy.data.objects.remove(cutter,do_unlink=True)
result=[]
for sign in [-1,1]:
    ids={v.index for v in body.data.vertices if v.co.x*sign>.34 and .70<v.co.z<.80}
    adj={i:[] for i in ids}
    for e in body.data.edges:
        a,b=e.vertices
        if a in ids and b in ids:adj[a].append(b);adj[b].append(a)
    remaining=set(ids);components=[]
    while remaining:
        i=remaining.pop();stack=[i];part=[i]
        while stack:
            for n in adj[stack.pop()]:
                if n in remaining:remaining.remove(n);part.append(n);stack.append(n)
        if len(part)>20:components.append(len(part))
    result.append({'side':'Left' if sign>0 else 'Right','distal_components':components})
assert all(len(r['distal_components'])>=5 for r in result),result
body['finger_slits_v2']=True
(ROOT/'inspection/finger-separation-v2.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result))
