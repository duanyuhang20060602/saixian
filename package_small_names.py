from pathlib import Path
import json,hashlib,shutil,zipfile,sys
root=Path.cwd();sys.path.insert(0,str(root/'5.0project/tools'))
from build_v4_port import inputs
out=root/'delivery-small-names-20261031';out.mkdir(exist_ok=True)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
reports={}
for b,d in [('a','build-name-small-safe-r1'),('b','build-rank-style-small-r1')]:
 p=root/d/f'builds/board_{b}/result.json';r=json.loads(p.read_text());assert r['status']=='passed'
 assert r['inputs_sha256']==inputs('board_'+b) and r['inputs_unchanged'] and r['toolchain_unchanged']
 assert r['timing_ns']['SWNS']>=0 and r['timing_ns']['HWNS']>=0
 for kind in ['bit','area','timing']:
  src=Path(r[kind]['path']);assert sha(src)==r[kind]['sha256'];shutil.copy2(src,out/src.name)
 shutil.copy2(p,out/f'board_{b}_build.json');reports[b]=r
for n in ['validation-rank-style','validation-rank-uart']:
 r=json.loads((root/n/'result.json').read_text());assert r['passed']
 for f,h in r['inputs_sha256'].items():assert sha(Path(f))==h,f
 shutil.copytree(root/n,out/n,dirs_exist_ok=True,ignore=shutil.ignore_patterns('*.vvp','frame.hex'))
for n,token in [('rank-small-name-reference.log','PASS 32768'),('rank-name-small.log','PASS 3200')]:
 assert token in (root/n).read_text();shutil.copy2(root/n,out/n)
shutil.copytree(root/'rank-serial-examples',out/'rank-serial-examples',dirs_exist_ok=True)
shutil.copy2(root/'5.0project/tools/send_serial_title.py',out/'send_serial_title.py')
shutil.copy2(root/'delivery-rank-style-fix-20261031/GLYPHS.BIN',out/'GLYPHS.BIN')
# Full source snapshot: no dependence on uncommitted files outside this package.
with zipfile.ZipFile(out/'source-and-tests.zip','w',zipfile.ZIP_DEFLATED) as z:
 for p in sorted((root/'5.0project').rglob('*')):
  if p.is_file() and p.suffix.lower() in ['.v','.vh','.vhd','.mif','.hex','.al','.json','.sdc','.adc','.cwc','.tcl','.py','.ipc'] and not any(n.endswith('_Runs') for n in p.parts):z.write(p,p.relative_to(root))
 for n in ['resize_rank_names.py','package_small_names.py','build_serial_title.py','retry_serial_title.py','run_rank_style_test.py','run_rank_uart_test.py']:z.write(root/n,n)
text='''# 姓名缩小一号版（保底固件）

默认和串口修改后的选手姓名统一使用24×24像素字框，与成绩数字及“秒”的24行字框一致。姓名每字步进24像素，起始列保持不变。姓名仍支持8字，排名页面与前三名页面同步生效。
此包不包含双方计分功能，保留原有开机进度条、默认标题/轮播、奖杯高光和串口编辑。四名以下背景条纹按此前要求暂不处理。

PHOTO_BOARD_A.bit 为本次新编译；B板逻辑未改，PHOTO_BOARD_B.bit 复用已验证配套固件，构建输入哈希逐项一致。可配套下载两块板，已有上一修正版B固件时仅更新A即可。无需更换原SD动画和字库；附GLYPHS.BIN供恢复。

串口115200、8N1、GB2312，命令须有实际CRLF。例 @R1:张三,12.34；标题@0:100米；轮播@1:欢迎来到运动会。姓名最多8字，成绩00.00～99.99。手动指定名次，不自动排序，断电恢复默认数据。

| 板 | LUT | 寄存器 | RAM9K | RAM32K | DSP | Setup/Hold ns |
|---|---:|---:|---:|---:|---:|---|
'''
for b in 'ab':
 v=reports[b]['resources'];t=reports[b]['timing_ns'];text+=f"| {b.upper()} | {v['lut']} | {v['reg']} | {v['bram']} | {v['bram32k']} | {v['dsp']} | +{t['SWNS']:.3f}/+{t['HWNS']:.3f} |\n"
text+='''
原频率、原引脚及原时序约束下通过最终布局布线。全帧921600像素检查、串口及双板字库联合回归通过；32768像素独立参考验证8字符完整16行/列缩放、24×24边界、排名/前三名及读延迟。另有3200像素全实心字形边界检查。
validation-rank-style/preview.png 为RTL仿真预览。尚未进行本次实体板验收。
'''
attempt=root.parent/'saixian-match-attempt-20261031/build-match-attempt-r4/builds/board_a'
if (attempt/'result.json').exists():
 r=json.loads((attempt/'result.json').read_text());assert r['status']=='failed'
 log=(attempt/'build.log').read_text(errors='replace');assert 'PHY-9015 ERROR' in log
 failed=out/'match-attempt-failed';failed.mkdir(exist_ok=True)
 shutil.copy2(attempt/'result.json',failed/'result.json');shutil.copy2(attempt/'build.log',failed/'build.log')
 text+='''
## 双方计分尝试结果

已在独立工程接入单板提交a74f498的计分控制、显示、按键和提示音，复用现有HDMI/音频输出，改为分时十进制转换并用移位加法替代进度乘法。综合及映射后A板RAM32K为17/16，RAM9K为64/64，LUT为19569/19600，DSP为28/29。布局报PHY-9015：emb32数量17超过16，未进入成功布线与最终时序验收，也未生成可交付计分版bit。
按要求本次仅交付姓名缩小版；上述失败工程不混入可下载固件。match-attempt-failed保留该次构建JSON和日志，资源数字属于失败尝试，不是本包固件用量。计分功能尚未完成系统仿真及实板验收。
'''
(out/'README.md').write_text(text,encoding='utf-8')
manifest={p.relative_to(out).as_posix():sha(p) for p in sorted(out.rglob('*')) if p.is_file() and p.name!='SHA256SUMS.json'}
(out/'SHA256SUMS.json').write_text(json.dumps(manifest,indent=2))
with zipfile.ZipFile(str(out)+'.zip','w',zipfile.ZIP_DEFLATED) as z:
 for p in sorted(out.rglob('*')):
  if p.is_file():z.write(p,p.relative_to(root))
assert all(sha(out/n)==h for n,h in manifest.items())
with zipfile.ZipFile(str(out)+'.zip') as z:assert z.testzip() is None
print('PASS verified small-name firmware pair packaged',str(out)+'.zip')
