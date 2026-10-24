from pathlib import Path
import sys,json,hashlib,math,struct,time
import numpy as np
from PIL import Image
import OpenEXR
W=Path('E:/Codex/Work/saixian-relief-seams-20261024');ROOT=Path('E:/Codex/Downloads/qiansai/5.0project');sys.path.insert(0,str(ROOT/'tools'))
from test_relief_bus import decode,decode_hq
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def exr(p):
 c=OpenEXR.File(str(p)).channels();return (c['RGB'] if 'RGB' in c else next(iter(c.values()))).pixels.copy()
start=time.monotonic();asset=W/'media/RELIEF720.DLT';baseline=W/'baseline/award_media/RELIEF720.DLT';_,plate,tail,expected=decode(asset);_,old_plate,_,_=decode(baseline);assert np.array_equal(plate,old_plate)
pal,images=decode_hq(tail);source=np.load(W/'native_materials.npz');assert np.array_equal(pal,source['palettes']) and np.array_equal(images,source['frames'])
evidence=[Path(__file__),asset,asset.with_suffix('.json'),baseline,W/'native_materials.npz',ROOT/'tools/test_relief_bus.py'];scores=[]
for a in range(24):
 mfile=W/'artwork'/f'mask_{a+1:04d}.exr';pfile=W/'artwork'/f'angle_{a:02d}.png';evidence.extend([mfile,pfile]);mask=exr(mfile)[48:624,352:928]>.45;assert np.array_equal(mask,images[a]!=0),a
 c=(pal[a][images[a]]>>16);rgb=np.stack(((((c>>11)&31)<<3)|(((c>>11)&31)>>2),(((c>>5)&63)<<2)|(((c>>5)&63)>>4),((c&31)<<3)|((c&31)>>2)),axis=-1).astype(float);orig=np.asarray(Image.open(pfile).convert('RGB').crop((352,48,928,624)),float);score=float(10*np.log10(255**2/np.mean((rgb[mask]-orig[mask])**2)));scores.append(score);assert score>30,a
metadata=json.loads(asset.with_suffix('.json').read_text(encoding='utf-8'));assert metadata['hold_frames']==10 and metadata['brightness_exposure']==2 and metadata['tail_words']==524288 and len(expected)==985088
hashes={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in evidence};out=W/'material_tests';out.mkdir(exist_ok=True);log=out/'native_materials.log';log.write_text('PASS all 24 native views: exact 7962624 decoded material indices, mask silhouette identical to fixed-model coverage in every view, original background byte-identical, mean RGB565 source PSNR '+str(float(np.mean(scores)))+' dB; firmware exposure and speed metadata preserved. Software asset evidence; hardware recheck pending.\n',encoding='utf-8')
r=dict(test='native_materials',passed=True,inputs_sha256=hashes,inputs_unchanged=all(sha(Path(k) if Path(k).is_absolute() else ROOT/k)==h for k,h in hashes.items()),asset_sha256=sha(asset),log=str(log),log_sha256=sha(log),seconds=round(time.monotonic()-start,2),details=dict(native_pixels=int(images.size),angles=24,background_identical=True,mask_match_all_angles=True,mean_color_psnr_db=float(np.mean(scores)),minimum_color_psnr_db=min(scores)))
(out/'results.json').write_text(json.dumps([r],indent=2)+'\n',encoding='utf-8');print(log.read_text(),flush=True)
# Independently test actual final Blender solids, rather than trusting declared joins.
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
bpy.ops.wm.open_mainfile(filepath=str(W/'gold_relief_joined.blend'));bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get();cup=bpy.data.objects['CUP | turntable root'];hosts={}
def host(obj):
 if obj.name not in hosts:
  ev=obj.evaluated_get(deps);mesh=ev.to_mesh();hosts[obj.name]=BVHTree.FromPolygons([v.co.copy() for v in mesh.vertices],[tuple(p.vertices) for p in mesh.polygons]);ev.to_mesh_clear()
 return hosts[obj.name]
def contains(obj,world):
 point=obj.matrix_world.inverted()@world;direction=Vector((1,.173,.319)).normalized();tree=host(obj);nearest=tree.find_nearest(point);assert nearest[3]>1e-5
 count=0;origin=point.copy()
 for i in range(32):
  hit=tree.ray_cast(origin,direction,100)
  if hit[0] is None:return bool(count%2)
  count+=1;origin=hit[0]+direction*.0001
 raise AssertionError('Ray parity did not converge')
bowl=bpy.data.objects['Cup | platinum bell bowl'];base=bpy.data.objects['Cup | upper chased tier'];handles={}
for o in cup.children_recursive:
 if o.name.startswith('Cup | cast guardian handle'):handles[1 if o.data.splines[0].bezier_points[0].co.x>0 else -1]=o
checks=[];old_failures=0;changes=json.loads((W/'geometry_changes.json').read_text(encoding='utf-8'))['modified_objects']
for change in changes:
 o=bpy.data.objects[change['object']];points=o.data.splines[0].bezier_points;assert o.data.use_fill_caps
 if o.name.startswith('Cup | sculpted claw bracket'):targets=[base,bowl]
 elif o.name.startswith('Cup | guardian wing rib'):targets=[handles[1 if points[0].co.x>0 else -1],bowl]
 else:targets=[bowl,bowl]
 for which,(p,t) in enumerate(zip([points[0],points[-1]],targets)):
  assert contains(t,o.matrix_world@p.co),(o.name,which,t.name)
  old=Vector(change['before'][0 if which==0 else -1]);old_inside=contains(t,o.matrix_world@old)
  if not old_inside:old_failures+=1
  checks.append(dict(object=o.name,endpoint=which,target=t.name,center_inside_target=True,old_center_inside_target=old_inside))
assert len(checks)==32 and old_failures>=4
files=[Path(__file__),W/'gold_relief_joined.blend',W/'geometry_changes.json',W/'render_joined.py'];hashes={str(p):sha(p) for p in files};out=W/'model_tests';out.mkdir(exist_ok=True);log=out/'model_joins.log';log.write_text('PASS 16 repaired curve objects, all 32 endpoint centers inside their intended support solids by independent BVH ray-parity tests, all tubes capped. '+str(old_failures)+' original endpoint centers were outside target solids.\n'+json.dumps(checks,indent=2)+'\n',encoding='utf-8');r=dict(test='model_joins',passed=True,inputs_unchanged=all(sha(Path(k))==h for k,h in hashes.items()),inputs_sha256=hashes,asset_sha256=sha(asset),log=str(log),log_sha256=sha(log),checks=checks,old_outside_endpoints=old_failures,scope='Actual final Blender meshes checked independently with local solid ray parity; all camera angles share rigid object transforms. Material silhouette and firmware pixel output are tested separately.')
(out/'results.json').write_text(json.dumps([r],indent=2)+'\n',encoding='utf-8');print(log.read_text().splitlines()[0],flush=True)
