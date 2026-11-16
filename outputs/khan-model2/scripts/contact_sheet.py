"""Arrange captured review frames for visual inspection; no image retouching."""
from pathlib import Path
from PIL import Image,ImageDraw
import sys
root=Path(__file__).resolve().parents[1]/'inspection'/(sys.argv[1] if len(sys.argv)>1 else 'surface-fit')
for clip in ['Idle','Idle2','Punch','MmaKick']:
    frames=sorted(root.glob(clip+'_front_*.png'))
    if not frames:continue
    chosen=[frames[min(len(frames)-1,round(i*(len(frames)-1)/3))].stem.rsplit('_',1)[1] for i in range(4)]
    out=Image.new('RGB',(4*330,3*400),'#20252b');draw=ImageDraw.Draw(out)
    for row,view in enumerate(['front','back','side']):
        for col,frame in enumerate(chosen):
            path=root/f'{clip}_{view}_{frame}.png'
            if not path.exists():continue
            im=Image.open(path).convert('RGB').crop((360,90,900,680))
            im.thumbnail((330,370))
            out.paste(im,(col*330+(330-im.width)//2,row*400+25))
            draw.text((col*330+8,row*400+5),f'{clip} {view} frame {frame}',fill='white')
    out.save(root/f'sheet-{clip}.jpg',quality=92)
