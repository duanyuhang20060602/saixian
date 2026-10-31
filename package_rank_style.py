from pathlib import Path
import sys,json,hashlib,shutil,zipfile,subprocess
root=Path.cwd();sys.path.insert(0,str(root/'5.0project/tools'))
from build_v4_port import inputs
out=root/'delivery-rank-style-fix-20261031';out.mkdir(exist_ok=True)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
boards={}
for b,d in [('a',sys.argv[1]),('b',sys.argv[2] if len(sys.argv)>2 else 'build-rank-style-small-r1')]:
 p=root/d/f'builds/board_{b}/result.json';r=json.loads(p.read_text());assert r['status']=='passed'
 assert r['inputs_sha256']==inputs('board_'+b) and r['inputs_unchanged'] and r['toolchain_unchanged']
 for kind in ['bit','area','timing']:
  src=Path(r[kind]['path']);assert sha(src)==r[kind]['sha256'];shutil.copy2(src,out/src.name)
 shutil.copy2(p,out/f'board_{b}_build.json');boards[b]=r
for name in ['validation-rank-style','validation-rank-uart']:
 r=json.loads((root/name/'result.json').read_text());assert r['passed']
 for p,h in r['inputs_sha256'].items():assert sha(Path(p))==h,p
 shutil.copytree(root/name,out/name,dirs_exist_ok=True,ignore=shutil.ignore_patterns('*.vvp','frame.hex'))
assert 'PASS 3200' in (root/'rank-full-glyph.log').read_text()
shutil.copy2(root/'rank-full-glyph.log',out/'rank-full-glyph.log')
shutil.copytree(root/'rank-serial-examples',out/'rank-serial-examples',dirs_exist_ok=True)
shutil.copy2(root/'5.0project/tools/send_serial_title.py',out/'send_serial_title.py')
shutil.copy2(root/'../saixian-serial-title-20261031/GLYPHS.BIN',out/'GLYPHS.BIN')
extra=['5.0project/common/photo_rank_text.v','5.0project/common/rank_names.mif','5.0project/common/rank_names.hex',
 '5.0project/common/rank_digits.mif','5.0project/common/rank_digits.hex','5.0project/tests/tb_rank_style.v','5.0project/tests/before_battle.v',
 '5.0project/tests/rank_style_ram_model.v','5.0project/tests/rank_style_update.hex','5.0project/tests/tb_editable_rank_uart.v',
 'fix_rank_style.py','shrink_rank_score.py','preserve_full_rank_glyph.py','5.0project/tests/rank_style_expected_score.hex','5.0project/tests/tb_rank_full_glyph.v','run_rank_style_test.py','run_rank_uart_test.py','package_rank_style.py']
changed=subprocess.check_output(['git','diff','--name-only'],stderr=subprocess.DEVNULL).decode().splitlines()
with zipfile.ZipFile(out/'source-and-tests.zip','w',zipfile.ZIP_DEFLATED) as z:
 for name in dict.fromkeys(changed+extra):z.write(root/name,name)
text='''# 排名显示样式修正版

在上一版开机进度条、默认文字、高光、串口姓名成绩版本上修复显示样式。

- 保留名次、道次，姓名和成绩分列对齐；成绩数字与“秒”单位统一缩小一档。
- 所有行初始姓名和串口更新姓名使用同一16x16字库、同一大小、同一列位置。
- 所有行成绩使用原页面图集缩小后的抗锯齿字形，统一24行字框，数字与小数点步进12/12/4/12/12像素；“秒”也同比例缩小。
- 初始姓名继续为选手01～选手08，初始成绩保持原值；不是只给更新行使用另一套字体。
- 空姓名更新在收到全部8对行字后只提交一次，避免反复切换字形bank。
- 保留原名次/道次对应关系；姓名成绩编辑不改变道次。四名以下背景条纹按用户要求保持原样。

## 使用

两块板可配套烧录 PHOTO_BOARD_A.bit、PHOTO_BOARD_B.bit。
继续使用原 GLYPHS.BIN、AWARD720.DLT、RELIEF720.DLT；无需更换 SD 素材。本包附同一字库方便恢复。
原SD扫描范围约512 MiB，所有需要识别的字库记录仍需在此范围内。

A板串口115200、8N1、3.3V TTL，中文GB2312，每行以实际0D 0A结尾。
标题@0:文字，轮播@1:文字；排名@R1:张三,12.34。
R1～R8指定名次，不自动排序；姓名最多8字，成绩00.00～99.99秒。
SSCOM勾选“16进制发送”，第一名张三12.34秒：

```
40 52 31 3A D5 C5 C8 FD 2C 31 32 2E 33 34 0D 0A
```

每条间隔建议1秒，数据只在运行RAM中保存；编辑只更新数据，进入排名和前三名页面后查看。
原开机仅进度条、默认标题100米/轮播欢迎来到运动会、增强奖杯高光均保留。

## 最终资源和时序

| 板 | LUT | 寄存器 | RAM9K | RAM32K | DSP | Setup/Hold ns |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
'''
for b in 'ab':
 r=boards[b];v=r['resources'];t=r['timing_ns'];text+=f"| {b.upper()} | {v['lut']} | {v['reg']} | {v['bram']} | {v['bram32k']} | {v['dsp']} | {t['SWNS']:.3f}/{t['HWNS']:.3f} |\n"
text+='''
原时钟和引脚约束下最终setup/hold通过；这次为恢复原数字字形使用了A板剩余两块RAM9K，双板RAM9K和RAM32K均已满。

## 验证

- 整帧921600像素检查，无未知像素，视频延迟未改。
- 823680个固定名次、道次、背景像素与原始图集精确一致。
- 更新后的12.34秒区域2352个像素与缩小后的抗锯齿参考精确一致。姓名保持完整16行字形，不裁切首末笔画。
- 真正UART、双板控制、SD扇区索引和字形缓存联合回归，覆盖8行编辑、独立更新、8字姓名、非法输入及空姓名单次提交。
- validation-rank-style/preview.png 是RTL整帧仿真预览，第一行已改张三12.34秒，其他行保留初始数据。

当前修正版尚未完成实体板验证。构建JSON包含完整源码、工具链与产物哈希。
'''
(out/'README.md').write_text(text,encoding='utf-8')
manifest={p.relative_to(out).as_posix():sha(p) for p in sorted(out.rglob('*')) if p.is_file() and p.name!='SHA256SUMS.json'}
(out/'SHA256SUMS.json').write_text(json.dumps(manifest,indent=2))
with zipfile.ZipFile(root/'delivery-rank-style-fix-20261031.zip','w',zipfile.ZIP_DEFLATED) as z:
 for p in sorted(out.rglob('*')):
  if p.is_file():z.write(p,p.relative_to(root))
print('PASS verified rank-style firmware pair packaged')
