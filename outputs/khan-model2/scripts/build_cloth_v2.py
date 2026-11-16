"""Second garment trial: wider body attachment and a connected fabric-control grid."""
import bpy,bmesh,math,json
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from pathlib import Path
ROOT=Path(r'C:\Users\IT\Documents\Codex\2026-09-14\it-s-time-to-get-serious')
scene=bpy.data.scenes['Khan_Garment_Prototype'];bpy.context.window.scene=scene
rig=bpy.data.objects['Khan_Garment_Rig'];body=bpy.data.objects['Khan_Garment_Body']
source=bpy.data.meshes['Garment_Trial_PreCut_Backup']
assert 'fabric_front_c0_0' not in rig.data.bones,'Do not stack v2 builds.'
rig.data.pose_position='REST'
verts=[v.co.copy() for v in source.vertices]
bvh=BVHTree.FromPolygons(verts,[tuple(p.vertices) for p in source.polygons],all_triangles=True)
names={g.index:g.name for g in body.vertex_groups}
grid={};COLS=5;ROWS=6;TOP=1.015;HEM=.578
for side,sign in [('front',-1),('back',1)]:
    points=[]
    for row in range(ROWS):
        z=TOP+(HEM-TOP)*row/(ROWS-1)
        for col in range(COLS):
            angle=.065+(math.pi-.13)*col/(COLS-1)
            direction=Vector((math.cos(angle),sign*math.sin(angle),0))
            hit,_,_,_=bvh.ray_cast(Vector((0,0,z))+direction*.32,-direction,.33)
            assert hit is not None,(side,row,col)
            points.append(hit+direction*.006)
    grid[side]=points
for ob in scene.objects:ob.select_set(False)
rig.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.object.mode_set(mode='EDIT')
for bone in list(rig.data.edit_bones):
    if bone.name.startswith('cloth_'):rig.data.edit_bones.remove(bone)
inverse=rig.matrix_world.inverted()
for side,points in grid.items():
    for col in range(COLS):
        parent=rig.data.edit_bones['mixamorig:Hips']
        for row in range(ROWS-1):
            bone=rig.data.edit_bones.new(f'fabric_{side}_c{col}_{row}')
            bone.head=inverse@points[row*COLS+col];bone.tail=inverse@points[(row+1)*COLS+col]
            bone.parent=parent;bone.use_connect=row>0;parent=bone
bpy.ops.object.mode_set(mode='OBJECT')
stats={}
for side,sign in [('front',-1),('back',1)]:
    bm=bmesh.new();bm.from_mesh(source)
    for z in [HEM,1.16]:
        bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-6,plane_co=(0,0,z),plane_no=(0,0,1))
    bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-6,plane_co=(0,0,0),plane_no=(0,1,0))
    remove=[]
    for f in bm.faces:
        p=f.calc_center_median();limit=.22 if p.z>.97 else .285
        if not (HEM-1e-6<p.z<1.160001 and abs(p.x)<limit and p.y*sign>=0):remove.append(f)
    bmesh.ops.delete(bm,geom=remove,context='FACES')
    orphan=[v for v in bm.verts if not v.link_faces]
    if orphan:bmesh.ops.delete(bm,geom=orphan,context='VERTS')
    mesh=bpy.data.meshes.new('Kameez_v2_'+side);bm.to_mesh(mesh);bm.free();mesh.update()
    ob=bpy.data.objects['Kameez_'+side.title()+'_Panel'];ob.data=mesh
    inherited=[{names[g.group]:g.weight for g in v.groups if g.group in names} for v in mesh.vertices]
    ob.vertex_groups.clear();mesh.materials.clear();mesh.materials.append(source.materials[0]);groups={}
    for v in mesh.vertices:
        x,y,z=v.co
        # Fully body-skinned overlap hides the original cut; the free panel begins below it.
        pin=max(0,min(1,(z-.965)/.075));pin=pin*pin*(3-2*pin)
        angle=math.atan2(abs(y),x);horizontal=max(0,min(4,(angle-.065)/(math.pi-.13)*4))
        c0=int(horizontal);c1=min(4,c0+1);mixc=horizontal-c0
        vertical=max(0,min(4,(TOP-z)/(TOP-HEM)*5-.5))
        r0=int(vertical);r1=min(4,r0+1);mixr=vertical-r0
        weights={n:w*pin for n,w in inherited[v.index].items()}
        for col,cw in [(c0,1-mixc),(c1,mixc)]:
            for row,rw in [(r0,1-mixr),(r1,mixr)]:
                name=f'fabric_{side}_c{col}_{row}';weights[name]=weights.get(name,0)+(1-pin)*cw*rw
        total=sum(weights.values())
        for name,w in weights.items():
            if w>1e-8:
                if name not in groups:groups[name]=ob.vertex_groups.new(name=name)
                groups[name].add([v.index],w/total,'REPLACE')
        if z<1.035:
            v.co.y+=sign*.004*(1-pin)
    stats[side]={'vertices':len(mesh.vertices),'faces':len(mesh.polygons)}
rig.data.pose_position='POSE';scene.frame_set(1);bpy.context.view_layer.update()
(ROOT/'outputs/khan-model2/inspection/cloth-v2-build.json').write_text(json.dumps({'panels':stats,'bones':len(rig.data.bones),'grid_columns':COLS,'grid_rows':ROWS,'attachment_top':1.16},indent=2))
print(json.dumps(stats))
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'outputs/khan-model2/blender/khan-model2-cloth-hands-v2.blend'))
