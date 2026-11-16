"""Replace intersecting underlayer tubes with a continuation sewn to the cut rings."""
import bpy,bmesh,json
from mathutils import Vector
from pathlib import Path
root=Path(r'C:\Users\IT\Documents\Codex\2026-09-14\it-s-time-to-get-serious\outputs\khan-model2')
body=bpy.data.objects['Khan_Garment_Body']
assert not body.get('sewn_trousers_trial'), 'Already applied; restore pre-sew data to repeat.'
backup=body.data.copy();backup.name='Garment_Body_PreSewnTrousers';backup.use_fake_user=True
bm=bmesh.new();bm.from_mesh(body.data)
uv=bm.loops.layers.uv.active;deform=bm.verts.layers.deform.active
edges={e for e in bm.edges if e.is_boundary and all(abs(v.co.z-.540)<1e-5 for v in e.verts)}
groups={g.name:g.index for g in body.vertex_groups}
records=[]
while edges:
    first=edges.pop();component={first};stack=[first]
    while stack:
        edge=stack.pop()
        for vert in edge.verts:
            for other in vert.link_edges:
                if other in edges: edges.remove(other);component.add(other);stack.append(other)
    base=set(v for e in component for v in e.verts)
    center=sum((v.co for v in base),Vector())/len(base)
    side='Left' if center.x>0 else 'Right';sign=1 if center.x>0 else -1
    leg=groups['mixamorig:'+side+'UpLeg'];hips=groups['mixamorig:Hips']
    coordinates={v:v.co.copy() for v in base}
    weights={v:dict(v[deform]) for v in base}
    # Each edge keeps its own UV seam, copied from its adjoining original face.
    edge_uv={}
    for edge in component:
        face=edge.link_faces[0]
        edge_uv[edge]={v:next(l[uv].uv.copy() for l in face.loops if l.vert==v) for v in edge.verts}
    previous={v:v for v in base}
    rows=14
    for row in range(1,rows+1):
        t=row/rows;z=.54+(.985-.54)*t;current={}
        for original in base:
            co=coordinates[original].copy()
            co.x=sign*(abs(center.x)*(1-t)+.081*t)+(co.x-center.x)*(1-.12*t)
            co.y=.010+(co.y-.010)*(1+.08*t)
            co.z=z
            vert=bm.verts.new(co);current[original]=vert
            hip=max(0,min(1,(z-.78)/.205));blend=min(1,(z-.54)/.09)
            dw=vert[deform]
            for index,w in weights[original].items(): dw[index]=w*(1-blend)
            dw[leg]=dw.get(leg,0)+(1-hip)*blend
            dw[hips]=dw.get(hips,0)+hip*blend
        for edge in component:
            a,b=edge.verts
            face=bm.faces.new((previous[a],previous[b],current[b],current[a]))
            face.material_index=0;face.smooth=True
            for loop,original in zip(face.loops,[a,b,b,a]):loop[uv].uv=edge_uv[edge][original]
        previous=current
    records.append({'side':side,'sewn_boundary_vertices':len(base),'rings':rows})
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
bm.to_mesh(body.data);bm.free();body.data.update()
body['sewn_trousers_trial']=True
for name in ['Upper_Trousers_Left','Upper_Trousers_Right']:
    ob=bpy.data.objects.get(name)
    if ob: ob.data.use_fake_user=True;bpy.data.objects.remove(ob,do_unlink=True)
(root/'inspection'/'sewn-trousers.json').write_text(json.dumps({'joins':records,'vertices':len(body.data.vertices),'status':'Continuous geometry; upper cloth texture stretched from cut boundary, needs final art.'},indent=2))
print(json.dumps(records))
