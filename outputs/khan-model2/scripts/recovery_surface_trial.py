"""Offline, length-constrained garment cage, driving the original textured mesh."""
import bpy, bmesh, numpy as np, math, json, hashlib
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3];OUT=ROOT/'outputs/khan-model2'
scene=bpy.data.scenes['Khan_Garment_Prototype'];bpy.context.window.scene=scene
body=bpy.data.objects['Khan_Garment_Body'];rig=bpy.data.objects['Khan_Garment_Rig'];mesh=body.data
assert len(rig.data.bones)==59 and mesh.shape_keys is None
tag=body.vertex_groups['Kameez_Surface'].index
# Remove hidden inner return faces accidentally captured by the old height cut,
# then add surface resolution for bending. Original UVs interpolate on each face.
bm=bmesh.new();bm.from_mesh(mesh);deform=bm.verts.layers.deform.active
inside=[]
for f in bm.faces:
    c=f.calc_center_median()
    if all(v[deform].get(tag,0)>.5 for v in f.verts) and c.z<.68 and (c.x/.26)**2+(c.y/.17)**2<.72:inside.append(f)
bmesh.ops.delete(bm,geom=inside,context='FACES')
edges=[e for e in bm.edges if all(v[deform].get(tag,0)>.5 and v.co.z<.99 for v in e.verts) and e.calc_length()>.035]
bmesh.ops.subdivide_edges(bm,edges=edges,cuts=2,use_grid_fill=True)
bm.to_mesh(mesh);bm.free();mesh.update()
cloth={v.index for v in mesh.vertices if any(g.group==tag for g in v.groups)}
names={g.index:g.name for g in body.vertex_groups}
saved={i:{names[g.group]:g.weight for g in mesh.vertices[i].groups if names[g.group] in rig.data.bones} for i in cloth}
# The earlier reconstructed upper trousers extruded every fold in the knee ring
# all the way to the waist. Refit only that artificial extension to a thigh-sized
# envelope, blending continuously into the untouched original lower trousers.
refitted=0
for v in mesh.vertices:
    if v.index in cloth or not (.54001<v.co.z<.98501):continue
    weights={names[g.group]:g.weight for g in v.groups}
    lower=sum(weights.get(n,0) for n in ['mixamorig:Hips','mixamorig:LeftUpLeg','mixamorig:RightUpLeg'])
    if lower<.95:continue
    side=1 if v.co.x>=0 else -1
    z=v.co.z;cx=side*(.1256+(.8372-z)*.0627)
    dx=v.co.x-cx;dy=v.co.y-.015
    r=math.hypot(dx,dy);limit=.105
    t=max(0,min(1,(z-.54)/.065));t=t*t*(3-2*t)
    if r>limit:
        scale=1-t+t*limit/r;v.co.x=cx+dx*scale;v.co.y=.015+dy*scale;refitted+=1
mesh.update()
uv=np.empty(len(mesh.uv_layers.active.data)*2,dtype=np.float32);mesh.uv_layers.active.data.foreach_get('uv',uv)
NA=18;NZ=10;LOW=.578;HIGH=1.035
def angle(i):return (-math.pi/2+(i%9)*math.pi/8)+(math.pi if i>=9 else 0)
rest=[]
for j in range(NZ):
    t=j/(NZ-1);z=LOW+(HIGH-LOW)*t
    for i in range(NA):
        a=angle(i);rest.append(((.25-.052*t)*math.sin(a),-(.166-.029*t)*math.cos(a),z))
rest=np.array(rest)
def mapping(co):
    a=math.atan2(co.x,-co.y)
    side=0 if co.y<=0 else 1
    if side and a<0:a+=2*math.pi
    u=max(0,min(8,(a-(-math.pi/2+side*math.pi))*8/math.pi))
    z=max(0,min(NZ-1,(co.z-LOW)/(HIGH-LOW)*(NZ-1)))
    i=min(7,int(u));j=min(NZ-2,int(z));u-=i;z-=j;i+=side*9
    return [(j,i,(1-u)*(1-z)),(j,i+1,u*(1-z)),(j+1,i,(1-u)*z),(j+1,i+1,u*z)]
for t in rig.animation_data.nla_tracks:t.mute=True
rig.animation_data.action=None;rig.data.pose_position='REST'
for o in scene.objects:o.select_set(False)
rig.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.object.mode_set(mode='EDIT');inv=rig.matrix_world.inverted()
for j in range(NZ):
    for i in range(NA):
        b=rig.data.edit_bones.new(f'drape_{j}_{i}');b.head=inv@Vector(rest[j*NA+i]);b.tail=b.head+Vector((0,.025,0));b.parent=rig.data.edit_bones['mixamorig:Hips']
bpy.ops.object.mode_set(mode='OBJECT')
groups={(j,i):body.vertex_groups.new(name=f'drape_{j}_{i}') for j in range(NZ) for i in range(NA)}
for idx in cloth:
    v=mesh.vertices[idx];pin=max(0,min(1,(v.co.z-.99)/.045));pin=pin*pin*(3-2*pin)
    for n in saved[idx]:body.vertex_groups[n].remove([idx])
    for n,w in saved[idx].items():
        if pin*w>1e-8:body.vertex_groups[n].add([idx],pin*w,'REPLACE')
    for j,i,w in mapping(v.co):
        if w*(1-pin)>1e-8:groups[j,i].add([idx],w*(1-pin),'REPLACE')
rig.data.pose_position='POSE'
# Separate front/back panels have no links across the side slits.
edges=[]
for j in range(NZ):
    for i in range(NA):
        n=j*NA+i
        if j<NZ-1:edges.append((n,n+NA,1.0))
        if i%9<8:edges.append((n,n+1,1.0))
        if j<NZ-1 and i%9<8:
            edges.extend([(n,n+NA+1,.2),(n+1,n+NA,.2)])
        if j<NZ-2:edges.append((n,n+2*NA,.07))
ea=np.array([e[0] for e in edges]);eb=np.array([e[1] for e in edges]);stiff=np.array([e[2] for e in edges])
lengths=np.linalg.norm(rest[eb]-rest[ea],axis=1)
mass=np.ones(len(rest));mass[-NA:]=0
denom=np.maximum(mass[ea]+mass[eb],1e-8)
# Greedy edge coloring gives independent in-place constraint batches.
colors=[]
for e,(a,b,_) in enumerate(edges):
    for used,ids in colors:
        if a not in used and b not in used:used.update([a,b]);ids.append(e);break
    else:colors.append(({a,b},[e]))
colors=[np.array(ids) for _,ids in colors]
def capsules():
    out=[]
    for side in ['Left','Right']:
        p=rig.pose.bones['mixamorig:'+side+'UpLeg'];q=rig.pose.bones['mixamorig:'+side+'Leg']
        out.append((np.array(rig.matrix_world@p.head),np.array(rig.matrix_world@p.tail),.137))
        out.append((np.array(rig.matrix_world@q.head),np.array(rig.matrix_world@q.tail),.112))
    l=rig.pose.bones['mixamorig:LeftUpLeg'];r=rig.pose.bones['mixamorig:RightUpLeg']
    out.append((np.array(rig.matrix_world@l.head),np.array(rig.matrix_world@r.head),.14))
    return out
def collide(x,caps,pin):
    for a,b,r in caps:
        ab=b-a;t=np.clip(((x-a)*ab).sum(axis=1)/max(np.dot(ab,ab),1e-8),0,1)
        center=a+t[:,None]*ab;d=x-center;dist=np.linalg.norm(d,axis=1)
        n=d/np.maximum(dist[:,None],1e-8)
        x+=n*np.maximum(r-dist,0)[:,None]*mass[:,None]
    # Enforce contact between control points too, so an edge cannot pass through
    # a thigh while both its endpoints sit outside it.
    for a,b,r in caps:
        ab=b-a
        for fraction in [.25,.5,.75]:
            samples=x[ea]*(1-fraction)+x[eb]*fraction
            t=np.clip(((samples-a)*ab).sum(axis=1)/max(np.dot(ab,ab),1e-8),0,1)
            d=samples-(a+t[:,None]*ab);dist=np.linalg.norm(d,axis=1)
            correction=d/np.maximum(dist[:,None],1e-8)*np.maximum(r-dist,0)[:,None]
            accum=np.zeros_like(x);counts=np.zeros(len(x))
            np.add.at(accum,ea,correction*mass[ea,None]);np.add.at(accum,eb,correction*mass[eb,None])
            np.add.at(counts,ea,(dist<r)*mass[ea]);np.add.at(counts,eb,(dist<r)*mass[eb])
            x+=accum/np.maximum(counts[:,None],1)
    x[-NA:]=pin
def solve(x,prev,pin,caps,dt,target=None):
    old=x.copy();vel=(x-prev)*.965
    vel*=np.minimum(1,.04/np.maximum(np.linalg.norm(vel,axis=1),1e-8))[:,None]
    x+=vel;x[:,2]-=9.81*dt*dt
    if target is not None:
        # Weak shape memory restores the hanging silhouette after a leg releases it.
        # Contacts remain the final constraint; this is an authored bake, not a cloth guarantee.
        x+=(target-x)*.018*mass[:,None]
    x[-NA:]=pin
    for iteration in range(16):
        for ids in colors:
            a=ea[ids];b=eb[ids];d=x[b]-x[a];l=np.linalg.norm(d,axis=1)
            correction=d*((l-lengths[ids])*stiff[ids]/np.maximum(l,1e-8)/denom[ids])[:,None]
            x[a]+=correction*mass[a,None];x[b]-=correction*mass[b,None]
        collide(x,caps,pin)
    return x,old
records=[]
for clip in ['Idle','Idle2','Punch','MmaKick']:
    original=bpy.data.actions['Khan_'+clip];action=original.copy();action.name='Draped_'+clip
    rig.animation_data.action=action;rig.animation_data.action_slot=action.slots[0]
    start,end=map(int,original.frame_range)
    scene.frame_set(start);bpy.context.view_layer.update()
    hips=rig.pose.bones['mixamorig:Hips']
    def delta():return rig.matrix_world@hips.matrix@hips.bone.matrix_local.inverted()@rig.matrix_world.inverted()
    m=delta();x=np.array([m@Vector(p) for p in rest]);prev=x.copy();caps=capsules()
    directions=np.array([m.to_3x3()@Vector((math.sin(angle(i%NA)),-math.cos(angle(i%NA)),0)) for i in range(len(rest))])
    # Establish the outside of the posed legs before relaxing into the first pose.
    for _ in range(65):
        for a,b,r in caps:
            ab=b-a;t=np.clip(((x-a)*ab).sum(axis=1)/max(np.dot(ab,ab),1e-8),0,1)
            dist=np.linalg.norm(x-(a+t[:,None]*ab),axis=1)
            x+=directions*((dist<r)*.008*mass)[:,None]
    prev=x.copy()
    # Settle a clean, simple control cage. The dense generated surface is not simulated.
    for _ in range(75):x,prev=solve(x,prev,x[-NA:].copy(),caps,1/90)
    all_offsets=[];maxstretch=0
    old_caps=caps;old_pin=x[-NA:].copy()
    for frame in range(start,end+1):
        scene.frame_set(frame);bpy.context.view_layer.update();m=delta();mi=m.inverted()
        caps=capsules();pin=np.array([m@Vector(p) for p in rest[-NA:]])
        for sub in range(3):
            t=(sub+1)/3;inter=[(a0*(1-t)+a*t,b0*(1-t)+b*t,r) for (a0,b0,_),(a,b,r) in zip(old_caps,caps)]
            target=np.array([m@Vector(p) for p in rest])
            x,prev=solve(x,prev,old_pin*(1-t)+pin*t,inter,1/90,target)
        old_caps=caps;old_pin=pin
        offset=np.array([mi@Vector(p) for p in x])-rest
        assert np.isfinite(offset).all() and np.abs(offset).max()<1,(clip,frame)
        all_offsets.append(offset)
        maxstretch=max(maxstretch,float(np.max(np.linalg.norm(x[eb]-x[ea],axis=1)/lengths)))
        if frame%30==0:print('DRAPE',clip,frame,flush=True)
    for k,frame in enumerate(range(start,end+1)):
        scene.frame_set(frame)
        for j,i in groups:
            p=rig.pose.bones[f'drape_{j}_{i}'];p.location=p.bone.matrix_local.to_3x3().inverted()@inv.to_3x3()@Vector(all_offsets[k][j*NA+i]);p.keyframe_insert('location',frame=frame,group='Draped garment')
    for track in rig.animation_data.nla_tracks:
        if track.name==clip:track.strips[0].action=action;track.strips[0].action_slot=action.slots[0]
    records.append({'end_start_offset_rms_m':float(np.sqrt(np.mean((all_offsets[-1]-all_offsets[0])**2))),'clip':clip,'frames':len(all_offsets),'max_control_edge_stretch':maxstretch})
    print(records[-1],flush=True)
rig.animation_data.action=None
for t in rig.animation_data.nla_tracks:t.mute=False
for o in scene.objects:o.select_set(True)
bpy.context.view_layer.objects.active=rig
bpy.ops.export_scene.gltf(export_format='GLB',filepath=str(ROOT/'game/assets/characters/khan_recovery_trial.glb'),use_selection=True,use_active_scene=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_force_sampling=True,export_frame_range=False,export_rest_position_armature=True,export_skins=True,export_influence_nb=8,export_all_influences=False,export_apply=False)
for t in rig.animation_data.nla_tracks:t.mute=True
rig.animation_data.action=bpy.data.actions['Draped_Idle2'];rig.animation_data.action_slot=rig.animation_data.action.slots[0];scene.frame_set(1)
uv2=np.empty_like(uv);mesh.uv_layers.active.data.foreach_get('uv',uv2);assert np.array_equal(uv,uv2)
(OUT/'inspection/recovery-trial-build.json').write_text(json.dumps({'clips':records,'refitted_artificial_upper_trouser_vertices':refitted,'uv_unchanged':True,'status':'Awaiting visual acceptance; baked capsule cage, not runtime cloth'},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'blender/khan-model2-recovery-trial.blend'))
