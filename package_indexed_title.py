from pathlib import Path
import sys,json,hashlib,shutil,subprocess,zipfile
root=Path.cwd();sys.path.insert(0,str(root/'5.0project/tools'))
from build_v4_port import inputs
out=root/'delivery-indexed-title-20261031';out.mkdir(exist_ok=True)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
rs={}
for b,buildroot in zip('ab',sys.argv[1:3]):
 p=root/buildroot/f'builds/board_{b}/result.json';r=json.loads(p.read_text())
 assert r['status']=='passed' and r['inputs_unchanged'] and r['toolchain_unchanged']
 assert r['inputs_sha256']==inputs('board_'+b),'stale build'
 assert r['timing_ns']['SWNS']>=0 and r['timing_ns']['HWNS']>=0
 for key in ['bit','area','timing']:
  src=Path(r[key]['path']);assert sha(src)==r[key]['sha256'];shutil.copy2(src,out/src.name)
 shutil.copy2(p,out/f'board_{b}_build.json');rs[b]=r
test=json.loads((root/'validation-indexed-title/result.json').read_text());assert test['passed']
for p,h in test['inputs_sha256'].items():assert sha(Path(p))==h
assert all(r['passed'] for r in json.loads((root/'validation-hmi/results.json').read_text()))
assert len((root/'GLYPHS.BIN').read_bytes())==573952
assert 'PASS real A/B SPI' in (root/'trophy-current.log').read_text()
for name in ['validation-indexed-title','validation-hmi']:
 shutil.copytree(root/name,out/name,dirs_exist_ok=True,ignore=shutil.ignore_patterns('*.vvp','*.hex'))

shutil.copy2(root/'trophy-current.log',out/'trophy-current.log')
shutil.copy2(root/'串口修改标题和轮播文字.md',out/'使用说明.md')
shutil.copy2(root/'GLYPHS.BIN',out/'GLYPHS.BIN')
shutil.copy2(root/'5.0project/tools/make_glyph_records.py',out/'make_glyph_records.py')
shutil.copy2(root/'5.0project/tools/send_serial_title.py',out/'send_serial_title.py')
changed=subprocess.check_output(['git','diff','--name-only']).decode().splitlines()
extra=['5.0project/common/photo_serial_text.v','5.0project/common/photo_scan_font_index.v','5.0project/common/photo_scan_glyph_b.v',
 '5.0project/tests/tb_serial_title_index.v','5.0project/tests/serial_title_ram_model.v','5.0project/tools/make_glyph_records.py','5.0project/tools/send_serial_title.py',
 'run_index_test.py','run_hmi_regression.py','build_serial_title.py','retry_serial_title.py','package_indexed_title.py']
with zipfile.ZipFile(out/'source-and-tests.zip','w',zipfile.ZIP_DEFLATED) as z:
 for name in dict.fromkeys(changed+extra):z.write(root/name,name)
rows=[]
for b in 'ab':
 r=rs[b];v=r['resources'];t=r['timing_ns'];rows.append(f"| {b.upper()} | {v['lut']} | {v['reg']} | {v['bram']} | {v['bram32k']} | {v['dsp']} | {t['SWNS']} / {t['HWNS']} |")
text='''# 串口标题/轮播替换版

基线 c7a00926e6661a7a4f3e5b99c0e294e7e467af52。
PHOTO_BOARD_A.bit 给 HDMI/串口屏所在 A 板，PHOTO_BOARD_B.bit 给插 TF 卡的 B 板，必须配套使用。
移除活动路径中的 SXTTL SD 标题记录读取；串口 @0: 修改原标题，@1: 修改原轮播文字。
具体接线、GB2312 编码及限制见使用说明.md。屏端发送事件需要调整，本包不含屏端 TFT。

| 板 | LUT | 寄存器 | RAM9K | RAM32K | DSP | Setup / Hold ns |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
'''+ '\n'.join(rows)+'''

原频率与管脚约束下双板布线时序通过；实体板验证待完成。
完整仿真包含真实 HMI UART、真实双板控制 UART、1121 组乱序和重复扇区记录、字形 RAM，以及媒体/奖杯/设置的事务模型。
实际 SD 控制器和整板媒体仲裁尚需实体板验证；仿真以延迟扇区返回模型检查扇区索引取字形。
另有旧 HMI/触摸回归及 5078 PCM 字/116 HMI 字节/奖杯数据的真实 SPI 联合仿真。

字形通过原控制 UART 传输，没有更改音频和奖杯 SPI 帧。A 复用原字形 RAM；B 使用 GLYPHS.BIN 自描述记录的扇区索引，未加入 FAT。索引复用原扫描，需要记录位于原约 512 MiB 的扫描范围。索引提高了 RAM 用量，资源以表中最终报告为准。
不带入独立 demo 的四槽轮播、调试画面、心跳或计数器。两个原区域可独立更新/清空，每次一行，忙时丢弃新行。
'''
(out/'README.md').write_text(text,encoding='utf-8')
manifest={p.relative_to(out).as_posix():sha(p) for p in out.rglob('*') if p.is_file() and p.name!='SHA256SUMS.json'}
(out/'SHA256SUMS.json').write_text(json.dumps(manifest,indent=2))
with zipfile.ZipFile(root/'delivery-indexed-title-20261031.zip','w',zipfile.ZIP_DEFLATED) as z:
 for p in out.rglob('*'):
  if p.is_file():z.write(p,p.relative_to(root))
print('PASS matched firmware package created');print(rs['a']['timing_ns'],rs['b']['timing_ns'])
