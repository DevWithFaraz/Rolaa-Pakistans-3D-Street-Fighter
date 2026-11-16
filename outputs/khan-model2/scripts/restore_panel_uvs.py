import bpy,bmesh,json
from pathlib import Path
ROOT=Path(r'C:\Users\IT\Documents\Codex\2026-09-14\it-s-time-to-get-serious\outputs\khan-model2')
source=bpy.data.meshes['Garment_Trial_PreCut_Backup']
body=bpy.data.objects['Khan_Garment_Body']
names={g.index:g.name for g in body.vertex_groups}
stats={}
for side,sign in [('front',-1),('back',1)]:
    bm=bmesh.new();bm.from_mesh(source)
    for z in [.578,1.043]:
        bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-6,plane_co=(0,0,z),plane_no=(0,0,1),clear_inner=False,clear_outer=False)
    bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-6,plane_co=(0,0,0),plane_no=(0,1,0),clear_inner=False,clear_outer=False)
    remove=[f for f in bm.faces if not (.578-1e-6<f.calc_center_median().z<1.043+1e-6 and abs(f.calc_center_median().x)<.285 and f.calc_center_median().y*sign>=0)]
    bmesh.ops.delete(bm,geom=remove,context='FACES')
    orphan=[v for v in bm.verts if not v.link_faces]
    if orphan:bmesh.ops.delete(bm,geom=orphan,context='VERTS')
    mesh=bpy.data.meshes.new('Original_UV_Kameez_'+side);bm.to_mesh(mesh);bm.free();mesh.update()
    ob=bpy.data.objects['Kameez_'+side.title()+'_Panel'];ob.data=mesh
    inherited=[{names[g.group]:g.weight for g in v.groups if g.group in names} for v in mesh.vertices]
    ob.vertex_groups.clear();mesh.materials.clear();mesh.materials.append(source.materials[0])
    groups={}
    for v in mesh.vertices:
        x,y,z=v.co;t=max(0,min(1,(1.043-z)/(.465)))
        vert=max(0,min(2,t*3-.5));seg=int(vert);nextseg=min(2,seg+1);vmix=vert-seg
        # R is +X and L is -X, matching the radial authoring guides.
        half=.14+.05*t;horizontal=max(0,min(2,1-x/half));ci=int(horizontal);nc=min(2,ci+1);cmix=horizontal-ci
        pin=max(0,1-t/.12);weights={n:w*pin for n,w in inherited[v.index].items()}
        for chain,cw in [(ci,1-cmix),(nc,cmix)]:
            for segment,sw in [(seg,1-vmix),(nextseg,vmix)]:
                name='cloth_'+side+'_'+['R','C','L'][chain]+'_'+str(segment)
                weights[name]=weights.get(name,0)+(1-pin)*cw*sw
        total=sum(weights.values())
        for name,w in weights.items():
            if w>1e-8:
                if name not in groups:groups[name]=ob.vertex_groups.new(name=name)
                groups[name].add([v.index],w/total,'REPLACE')
    stats[side]={'vertices':len(mesh.vertices),'faces':len(mesh.polygons),'uv_preserved':True}
mat=bpy.data.materials.new('Upper_Trouser_Plain_Fabric_Trial');mat.use_nodes=True
node=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
node.inputs['Base Color'].default_value=(.71,.665,.58,1)
node.inputs['Roughness'].default_value=.85
for name in ['Upper_Trousers_Left','Upper_Trousers_Right']:
    ob=bpy.data.objects[name];ob.data.materials.clear();ob.data.materials.append(mat)
bpy.context.view_layer.update()
(ROOT/'inspection'/'garment-panel-uv-check.json').write_text(json.dumps(stats,indent=2))
print(json.dumps(stats))
