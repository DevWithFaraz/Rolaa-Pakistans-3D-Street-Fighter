"""Rebuild only the experimental hanging panels, preserving prior mesh datablocks."""
import bpy, math
from mathutils import Vector
from mathutils.bvhtree import BVHTree
rig=bpy.data.objects['Khan_Garment_Rig'];body=bpy.data.objects['Khan_Garment_Body']
source=bpy.data.meshes['Garment_Trial_PreCut_Backup']
rig.data.pose_position='REST'
bvh=BVHTree.FromPolygons([v.co for v in source.vertices],[tuple(p.vertices) for p in source.polygons])
names={g.index:g.name for g in body.vertex_groups}
mat=bpy.data.materials.get('Experimental_Kameez_Fabric') or bpy.data.materials.new('Experimental_Kameez_Fabric')
mat.use_nodes=True
bsdf=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
bsdf.inputs['Base Color'].default_value=(.80,.77,.68,1)
bsdf.inputs['Roughness'].default_value=.82
ROWS,COLS=36,32
for side,sign in [('front',-1),('back',1)]:
    coords=[];faces=[];weights=[]
    for row in range(ROWS+1):
        z=1.10-(1.10-.578)*row/ROWS
        pin=max(0,min(1,(z-.965)/.075));pin=pin*pin*(3-2*pin)
        for col in range(COLS+1):
            angle=.065+(math.pi-.13)*col/COLS
            direction=Vector((math.cos(angle),sign*math.sin(angle),0))
            radius=.225 if z>.98 else .30
            hit,normal,idx,dist=bvh.ray_cast(Vector((0,0,z))+direction*radius,-direction,radius+.01)
            assert hit is not None,(side,row,col)
            coords.append(hit+direction*.003)
            poly=source.polygons[idx]
            nearest=min(poly.vertices,key=lambda i:(source.vertices[i].co-hit).length_squared)
            torso={names[g.group]:g.weight for g in source.vertices[nearest].groups if g.group in names and ('Spine' in names[g.group] or 'Hips' in names[g.group])}
            if not torso:torso={'mixamorig:Hips':1.0}
            inherited={name:w/sum(torso.values())*pin for name,w in torso.items()}
            u=col/COLS*4;c0=min(3,int(u));c1=c0+1;fx=u-c0
            v=max(0,min(4,(1.015-z)/(1.015-.578)*5));r0=min(3,int(v));r1=r0+1;fy=v-r0
            for c,cw in [(c0,1-fx),(c1,fx)]:
                for r,rw in [(r0,1-fy),(r1,fy)]:
                    name=f'fabric_{side}_c{c}_{r}'
                    inherited[name]=inherited.get(name,0)+(1-pin)*cw*rw
            weights.append(inherited)
    for row in range(ROWS):
        for col in range(COLS):
            a=row*(COLS+1)+col
            face=(a,a+1,a+COLS+2,a+COLS+1)
            faces.append(face if sign<0 else tuple(reversed(face)))
    ob=bpy.data.objects['Kameez_'+side.title()+'_Panel']
    ob.data.use_fake_user=True
    mesh=bpy.data.meshes.new('Regular_Fabric_'+side)
    mesh.from_pydata(coords,[],faces);mesh.update()
    ob.data=mesh;ob.vertex_groups.clear();mesh.materials.append(mat)
    groups={}
    for i,ws in enumerate(weights):
        total=sum(ws.values())
        for name,w in ws.items():
            if w>1e-8:
                if name not in groups:groups[name]=ob.vertex_groups.new(name=name)
                groups[name].add([i],w/total,'REPLACE')
    for p in mesh.polygons:p.use_smooth=True
rig.data.pose_position='POSE'
bpy.context.view_layer.update()
print('Regular panels:',len(coords),'vertices each; original panel meshes preserved')
