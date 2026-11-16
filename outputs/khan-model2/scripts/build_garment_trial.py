"""Run in Blender on Khan_Garment_Prototype. Earlier source scenes stay intact.
Creates an experimental two-panel lower kameez and hidden upper trousers.
"""
import bpy, bmesh, math, json
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(r'C:\Users\IT\Documents\Codex\2026-09-14\it-s-time-to-get-serious\outputs\khan-model2')
scene = bpy.data.scenes['Khan_Garment_Prototype']
bpy.context.window.scene = scene
body = bpy.data.objects['Khan_Garment_Body']
rig = bpy.data.objects['Khan_Garment_Rig']
assert not bpy.data.objects.get('Kameez_Front_Panel'), 'Do not stack garment trials.'
rig.data.pose_position = 'REST'
bpy.context.view_layer.update()
original = body.data.copy()
original.name = 'Garment_Trial_PreCut_Backup'
original.use_fake_user = True
verts = [v.co.copy() for v in original.vertices]
faces = [tuple(p.vertices) for p in original.polygons]
bvh = BVHTree.FromPolygons(verts, faces, all_triangles=True)
uvdata = original.uv_layers.active.data
material = original.materials[0]

def uv_at(point, index):
    p = original.polygons[index]
    a,b,c = [verts[i] for i in p.vertices]
    u,v,t = b-a,c-a,point-a
    uu,uv,vv,tu,tv = u.dot(u),u.dot(v),v.dot(v),t.dot(u),t.dot(v)
    den = uu*vv-uv*uv
    if abs(den)<1e-24: return tuple(uvdata[p.loop_start].uv)
    wb,wc = (vv*tu-uv*tv)/den,(uu*tv-uv*tu)/den
    return tuple(sum((uvdata[p.loop_start+k].uv * w for k,w in enumerate([1-wb-wc,wb,wc])), Vector((0,0))))

def sample(theta,z):
    direction=Vector((math.cos(theta),math.sin(theta),0))
    hit,normal,index,distance=bvh.ray_cast(Vector((0,0,z))+direction*.30,-direction,.31)
    if hit is None: raise RuntimeError('Garment ray missed: '+str((theta,z)))
    return hit,uv_at(hit,index)

TOP,BOTTOM=1.043,.578
ROWS,COLS=24,32
panels={}
for side,sign in [('front',-1),('back',1)]:
    coords=[];uvs=[];polys=[]
    for row in range(ROWS+1):
        z=TOP+(BOTTOM-TOP)*row/ROWS
        for col in range(COLS+1):
            # Separate side edges, with a small open slit below the upper join.
            angle=.018+(math.pi-.036)*col/COLS
            point,uv=sample(sign*angle,z)
            point += Vector((0,sign*.0015,0))
            coords.append(tuple(point));uvs.append(uv)
    for row in range(ROWS):
        for col in range(COLS):
            a=row*(COLS+1)+col;b=a+1;c=a+COLS+2;d=a+COLS+1
            polys.append((a,b,c,d) if side=='front' else (d,c,b,a))
    mesh=bpy.data.meshes.new('Kameez_'+side+'_Grid');mesh.from_pydata(coords,[],polys);mesh.update()
    uv=mesh.uv_layers.new(name='UVMap')
    for poly in mesh.polygons:
        poly.use_smooth=True
        for li in poly.loop_indices:uv.data[li].uv=uvs[mesh.loops[li].vertex_index]
    ob=bpy.data.objects.new('Kameez_'+side.title()+'_Panel',mesh);scene.collection.objects.link(ob)
    ob.data.materials.append(material);panels[side]=ob
    ob['purpose']='Independent lower kameez test panel; top attached, rest has garment-only weights.'

# Add three independent vertical control chains to each panel.
for ob in scene.objects:ob.select_set(False)
rig.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.object.mode_set(mode='EDIT')
inverse=rig.matrix_world.inverted()
chains=[]
for side,ob in panels.items():
    for label,col in [('R',4),('C',16),('L',28)]:
        previous=None;names=[]
        for segment in range(3):
            r0=segment*8;r1=(segment+1)*8
            head=Vector(ob.data.vertices[r0*(COLS+1)+col].co)
            tail=Vector(ob.data.vertices[r1*(COLS+1)+col].co)
            bone=rig.data.edit_bones.new('cloth_'+side+'_'+label+'_'+str(segment))
            bone.head=inverse@head;bone.tail=inverse@tail
            bone.parent=previous if previous else rig.data.edit_bones['mixamorig:Hips']
            bone.use_connect=bool(previous);previous=bone;names.append(bone.name)
        chains.append({'side':side,'column':label,'bones':names})
bpy.ops.object.mode_set(mode='OBJECT')

for side,ob in panels.items():
    groups={}
    def group(name):
        if name not in groups:groups[name]=ob.vertex_groups.new(name=name)
        return groups[name]
    for row in range(ROWS+1):
        t=row/ROWS;vertical=max(0,min(2,t*3-.5))
        seg=int(vertical);next_seg=min(2,seg+1);fraction=vertical-seg
        pin=max(0,1-t/.12)
        for col in range(COLS+1):
            index=row*(COLS+1)+col
            horizontal=max(0,min(2,(col-4)/12));chain=int(horizontal);next_chain=min(2,chain+1);mix=horizontal-chain
            weights={'mixamorig:Hips':pin}
            for ci,cw in [(chain,1-mix),(next_chain,mix)]:
                for si,sw in [(seg,1-fraction),(next_seg,fraction)]:
                    name='cloth_'+side+'_'+['R','C','L'][ci]+'_'+str(si)
                    weights[name]=weights.get(name,0)+(1-pin)*cw*sw
            for name,weight in weights.items():
                if weight>1e-8:group(name).add([index],weight,'REPLACE')
    modifier=ob.modifiers.new('Kameez_Garment_Rig','ARMATURE');modifier.object=rig

# Cut only the central lower-shirt/upper-trouser band on this disposable body copy.
bm=bmesh.new();bm.from_mesh(body.data)
for z in [.540,1.035]:
    bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=.000001,plane_co=(0,0,z),plane_no=(0,0,1),clear_inner=False,clear_outer=False)
remove=[f for f in bm.faces if .540001<f.calc_center_median().z<1.034999 and abs(f.calc_center_median().x)<.285]
bmesh.ops.delete(bm,geom=remove,context='FACES')
orphan=[v for v in bm.verts if not v.link_faces]
if orphan:bmesh.ops.delete(bm,geom=orphan,context='VERTS')
bm.to_mesh(body.data);bm.free();body.data.update()

# The generated original has no complete hidden upper trousers. Add a lightweight
# underlayer with overlap into the preserved lower trousers. It needs art review.
for side,sign in [('Left',1),('Right',-1)]:
    coords=[];uvs=[];polys=[];nr,nc=16,40
    for row in range(nr+1):
        t=row/nr;z=.512+(.985-.512)*t
        cx=sign*(.15-.06*t);rx=.115-.015*t;ry=.109+.010*t
        for col in range(nc):
            theta=2*math.pi*col/nc
            point=Vector((cx+rx*math.cos(theta),.012+ry*math.sin(theta),z))
            lookup=Vector((sign*.15+.112*math.cos(theta),.012+.11*math.sin(theta),.50-.11*t))
            hit,normal,idx,dist=bvh.find_nearest(lookup)
            coords.append(tuple(point));uvs.append(uv_at(hit,idx))
    for row in range(nr):
        for col in range(nc):
            a=row*nc+col;b=row*nc+(col+1)%nc;c=b+nc;d=a+nc;polys.append((a,b,c,d))
    mesh=bpy.data.meshes.new('Upper_Trousers_'+side);mesh.from_pydata(coords,[],polys);mesh.update()
    uv=mesh.uv_layers.new(name='UVMap')
    for p in mesh.polygons:
        p.use_smooth=True
        for li in p.loop_indices:uv.data[li].uv=uvs[mesh.loops[li].vertex_index]
    ob=bpy.data.objects.new('Upper_Trousers_'+side,mesh);scene.collection.objects.link(ob);ob.data.materials.append(material)
    hips=ob.vertex_groups.new(name='mixamorig:Hips');leg=ob.vertex_groups.new(name='mixamorig:'+side+'UpLeg')
    for v in mesh.vertices:
        weight=max(0,min(1,(v.co.z-.73)/.19))
        if weight>0:hips.add([v.index],weight,'REPLACE')
        if weight<1:leg.add([v.index],1-weight,'REPLACE')
    modifier=ob.modifiers.new('Trouser_Body_Rig','ARMATURE');modifier.object=rig
    ob['purpose']='Experimental hidden trouser continuation, inspect during kicks.'

rig.data.pose_position='POSE'
scene.frame_set(1);bpy.context.view_layer.update()
report={'panel_vertices_each':(ROWS+1)*(COLS+1),'panel_quads_each':ROWS*COLS,'chains':chains,'top_m':TOP,'hem_m':BOTTOM,'removed_band_faces':len(remove),'status':'Geometry/control prototype; dynamics and collision still to be tested.'}
(ROOT/'inspection'/'garment-build.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report))
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'blender'/'khan-model2-garment-trial.blend'))
