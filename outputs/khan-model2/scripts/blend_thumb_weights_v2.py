import bpy,json
from mathutils.kdtree import KDTree
from pathlib import Path
body=bpy.data.objects['Khan_Garment_Body'];source=bpy.data.meshes['Body_Before_Finger_Separation']
names={g.index:g.name for g in body.vertex_groups};groups={g.name:g for g in body.vertex_groups}
data=json.loads(Path(r'C:\Users\IT\Documents\Codex\2026-09-14\it-s-time-to-get-serious\outputs\khan-model2\inspection\finger-rig-v2.json').read_text())
kd=KDTree(len(source.vertices))
for v in source.vertices:kd.insert(v.co,v.index)
kd.balance();bounds=[-.12,-.064,-.038,-.012,.035];digits=['Index','Middle','Ring','Pinky'];count=0
for v in body.data.vertices:
    x,y,z=v.co
    if abs(x)<.34 or not .70<z<.884:continue
    digit=next((i for i in range(4) if bounds[i]<=y<bounds[i+1]),None)
    if digit is None:continue
    side='Left' if x>0 else 'Right';name=digits[digit];chain=data['chains'][side+'_'+name]
    _,nearest,_=kd.find(v.co)
    original={names[g.group]:g.weight for g in source.vertices[nearest].groups if g.group in names}
    thumb={n:w for n,w in original.items() if 'HandThumb' in n}
    thumb_sum=min(1,sum(thumb.values()))
    pin=max(0,min(1,(z-chain[0][2])/(.884-chain[0][2])));pin=pin*pin*(3-2*pin)
    weights=dict(thumb);weights['mixamorig:'+side+'Hand']=(1-thumb_sum)*pin
    blend1=max(0,min(1,(chain[1][2]+.008-z)/.016));blend2=max(0,min(1,(chain[2][2]+.008-z)/.016))
    for j,w in enumerate([(1-blend1)*(1-blend2),blend1*(1-blend2),blend2]):weights[f'finger_{side}_{name}_{j}']=(1-thumb_sum)*(1-pin)*w
    for index in [g.group for g in v.groups]:body.vertex_groups[index].remove([v.index])
    total=sum(weights.values())
    for n,w in weights.items():
        if w>1e-8:groups[n].add([v.index],w/total,'REPLACE')
    count+=1
bpy.context.view_layer.update();print('Smoothed thumb transition on',count,'vertices')
