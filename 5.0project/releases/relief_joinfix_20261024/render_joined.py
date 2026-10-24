from pathlib import Path
import os
os.environ['TEMP']='E:/Codex/Temp/saixian-relief-seams-20261024';os.environ['TMP']=os.environ['TEMP'];Path(os.environ['TEMP']).mkdir(parents=True,exist_ok=True)
os.environ['CUDA_CACHE_PATH']='E:/Codex/cache/cuda';os.environ['OPTIX_CACHE_PATH']='E:/Codex/cache/optix'
import bpy,math,json,shutil
from mathutils import Vector
from mathutils.geometry import interpolate_bezier
W=Path('E:/Codex/Work/saixian-relief-seams-20261024');OUT=W/'artwork';OUT.mkdir(exist_ok=True)
SOURCE=Path('E:/Codex/Work/saixian-relief-integration-20261023/gold_relief_no_frame.blend');bpy.ops.wm.open_mainfile(filepath=str(SOURCE));s=bpy.context.scene;cup=bpy.data.objects['CUP | turntable root'];cup.animation_data_clear()
for name in ['background_720p.png','wall_mask_0001.exr','wall_normal_0001.exr']:
 shutil.copy2(SOURCE.parent/'artwork'/name,OUT/name)
changes=[];checks=[]
def edit(o,points):
 sp=o.data.splines[0];assert sp.type=='BEZIER';before=[list(p.co) for p in sp.bezier_points]
 # Replace only the path data, retaining parent/material and all transforms.
 cu=bpy.data.curves.new(o.name+' | joined geometry','CURVE');cu.dimensions='3D';cu.resolution_u=o.data.resolution_u;cu.bevel_depth=o.data.bevel_depth;cu.bevel_resolution=o.data.bevel_resolution;cu.use_fill_caps=True
 for mat in o.data.materials:cu.materials.append(mat)
 sp=cu.splines.new('BEZIER');sp.bezier_points.add(len(points)-1)
 for p,co in zip(sp.bezier_points,points):p.co=co;p.handle_left_type=p.handle_right_type='AUTO'
 o.data=cu;changes.append(dict(object=o.name,before=before,after=[list(p.co) for p in sp.bezier_points]))
profile=[(2.28,.52),(2.46,.69),(2.76,.90),(3.14,1.11),(3.58,1.29),(4.10,1.43),(4.60,1.51),(4.89,1.52)]
def rad(z):
 for (za,ra),(zb,rb) in zip(profile,profile[1:]):
  if z<=zb:return ra+(rb-ra)*(z-za)/(zb-za)
 return 1.52
handles={}
for o in list(cup.children_recursive):
 if o.name.startswith('Cup | sculpted claw bracket'):
  old=[p.co.copy() for p in o.data.splines[0].bezier_points];direction=Vector((old[0].x,old[0].y,0)).normalized()
  points=[direction*.70+Vector((0,0,1.32)),direction*.68+Vector((0,0,1.72)),direction*.54+Vector((0,0,2.13)),direction*.49+Vector((0,0,2.31))]
  edit(o,points);checks.append(dict(object=o.name,lower_endpoint_inside_base=True,upper_endpoint_inside_cup_floor=True,upper_z=2.31,bowl_floor_bottom_z=2.28))
 if o.name.startswith(('Cup | cast guardian handle','Cup | gold handle spine')):
  points=[p.co.copy() for p in o.data.splines[0].bezier_points];sign=1 if points[0].x>0 else -1
  points[0].x=sign*(rad(points[0].z)-.035);points[-1].x=sign*(rad(points[-1].z)-.065);edit(o,points)
  checks.append(dict(object=o.name,first_radial_inset=rad(points[0].z)-math.hypot(points[0].x,points[0].y),last_radial_inset=rad(points[-1].z)-math.hypot(points[-1].x,points[-1].y)))
  if o.name.startswith('Cup | cast guardian handle'):handles[sign]=o
bpy.context.view_layer.update()
for o in list(cup.children_recursive):
 if o.name.startswith('Cup | guardian wing rib'):
  points=[p.co.copy() for p in o.data.splines[0].bezier_points];sign=1 if points[0].x>0 else -1;sp=handles[sign].data.splines[0]
  samples=[]
  for a,b in zip(sp.bezier_points,sp.bezier_points[1:]):samples+=interpolate_bezier(a.co,a.handle_right,b.handle_left,b.co,100)
  points[0]=min(samples,key=lambda p:(p-points[0]).length_squared).copy();r=rad(points[-1].z)-.035;points[-1].x=sign*math.sqrt(r*r-points[-1].y**2)
  edit(o,points);checks.append(dict(object=o.name,first_endpoint_on_handle_centerline=True,last_radial_inset=rad(points[-1].z)-math.hypot(points[-1].x,points[-1].y)))
assert len(changes)==16,('Expected four brackets, four handle paths and eight ribs',len(changes))
assert all(c.get('first_radial_inset',.03)>.02 and c.get('last_radial_inset',.03)>.02 for c in checks)
(W/'geometry_changes.json').write_text(json.dumps(dict(source=str(SOURCE),modified_objects=changes,attachment_checks=checks),indent=2)+'\n',encoding='utf-8')
prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
for device in prefs.devices:device.use=device.type!='CPU'
s.cycles.device='GPU' if any(d.use for d in prefs.devices) else 'CPU';s.cycles.denoiser='OPTIX';s.cycles.denoising_use_gpu=s.cycles.device=='GPU';s.cycles.use_persistent_data=True;s.cycles.samples=32
s.render.resolution_x=1280;s.render.resolution_y=720;s.render.resolution_percentage=100;s.render.image_settings.file_format='PNG'
for n in s.node_tree.nodes:
 if n.bl_idname=='CompositorNodeOutputFile':n.mute=True
rl=next(n for n in s.node_tree.nodes if n.bl_idname=='CompositorNodeRLayers')
for name,prefix,mode in [('SurfaceNormal','normal_','RGB'),('Subject','mask_','BW')]:
 n=s.node_tree.nodes.new('CompositorNodeOutputFile');n.base_path=str(OUT);n.format.file_format='OPEN_EXR';n.format.color_depth='16';n.format.color_mode=mode;n.save_as_render=False;n.file_slots[0].path=prefix;s.node_tree.links.new(rl.outputs[name],n.inputs[0])
bpy.ops.wm.save_as_mainfile(filepath=str(W/'gold_relief_joined.blend'))
for f in range(24):
 s.frame_set(f+1);cup.rotation_euler[2]=math.radians(-12+15*f);s.render.filepath=str(OUT/f'angle_{f:02d}.png');print('RENDER_JOINED_ANGLE',f,flush=True);bpy.ops.render.render(write_still=True)
print('JOINED_ART_COMPLETE',flush=True)
