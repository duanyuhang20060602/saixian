from pathlib import Path
import sys,json,hashlib,shutil,subprocess,zipfile
root=Path.cwd();sys.path.insert(0,str(root/'5.0project/tools'))
from build_v4_port import inputs
out=root/'delivery-display-ranking-20261031';out.mkdir(exist_ok=True)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
boards={}
for b,d in [('a','build-display-ranking-r1'),('b','build-display-ranking-b19')]:
 p=root/d/f'builds/board_{b}/result.json';r=json.loads(p.read_text())
 assert r['status']=='passed' and r['inputs_unchanged'] and r['toolchain_unchanged']
 assert inputs('board_'+b)==r['inputs_sha256']
 for kind in ['bit','area','timing']:
  f=Path(r[kind]['path']);assert sha(f)==r[kind]['sha256'];shutil.copy2(f,out/f.name)
 shutil.copy2(p,out/f'board_{b}_build.json');boards[b]=r
for name in ['validation-indexed-title','validation-rank-uart']:
 r=json.loads((root/name/'result.json').read_text());assert r['passed']
 for p,h in r['inputs_sha256'].items():assert sha(Path(p))==h,p
 shutil.copytree(root/name,out/name,dirs_exist_ok=True,ignore=shutil.ignore_patterns('*.vvp'))
assert all(t['passed'] for t in json.loads((root/'validation-hmi/results.json').read_text()))
shutil.copytree(root/'validation-hmi',out/'validation-hmi',dirs_exist_ok=True,ignore=shutil.ignore_patterns('*.vvp'))
for f in ['polish.log','rank-pixels.log','preserved-battle.log','validation-display/defaults.log']:
 assert 'PASS ' in (root/f).read_text() and 'FATAL' not in (root/f).read_text()
 shutil.copy2(root/f,out/Path(f).name)
shutil.copytree(root/'rank-serial-examples',out/'rank-serial-examples',dirs_exist_ok=True)
shutil.copy2(root/'5.0project/tools/send_serial_title.py',out/'send_serial_title.py')
shutil.copy2(root/'../saixian-serial-title-20261031/GLYPHS.BIN',out/'GLYPHS.BIN')
extra=['5.0project/common/photo_rank_text.v','5.0project/tests/tb_editable_rank_uart.v','5.0project/tests/tb_display_polish.v','5.0project/tests/previous_relief_shade.v',
 '5.0project/tests/tb_rank_pixels.v','5.0project/tests/before_battle.v','5.0project/tests/tb_preserved_battle.v','5.0project/tests/default_font_ram_model.v','5.0project/tests/tb_default_titles.v',
 'validation-display/default_font.hex','validation-display/defaults_expected.hex','run_rank_uart_test.py','package_display_ranking.py']
changed=subprocess.check_output(['git','diff','--name-only'],stderr=subprocess.DEVNULL).decode().splitlines()
with zipfile.ZipFile(out/'source-and-tests.zip','w',zipfile.ZIP_DEFLATED) as z:
 for name in dict.fromkeys(changed+extra):z.write(root/name,name)
readme='''# 进度条开机、默认文字、高光与可编辑排名

基线：8797178900367d0686735622de20c8c22e098342。
PHOTO_BOARD_A.bit 烧录 HDMI/串口屏所在 A 板；PHOTO_BOARD_B.bit 烧录插 TF 卡的 B 板，配套使用。

## 本次行为

1. 开机画面只显示进度条，背景为黑色；保留原启动准备条件和退出时机。
2. 标题默认“100米”，底部轮播默认“欢迎来到运动会”。字形写在原有 OSD RAM 初始内容中，不额外申请 RAM。
3. 旋转奖杯高光通道幅度增强约一倍，光源、旋转时序、墙面材质响应保持原样，无需替换 RELIEF720.DLT。
4. 根据用户后续要求，排名条纹保持原样，本次未修复或移除。
5. 串口可以修改八个名次的姓名、成绩；前三名展示使用对应行的数据。未修改的行继续显示原有内容。

## 串口

A 板 J1 接线与上版相同；115200、8N1、3.3V TTL。中文为 GB2312，结尾必须为真实字节 0D 0A。
标题 @0:文字，轮播 @1:文字，每行仍最多16字。

排名格式：@R名次:姓名,成绩 + CR LF，例如 @R1:张三,12.34。
名次为1～8，姓名最多8字符，成绩固定两位整数和两位小数，范围00.00～99.99秒。
R1直接指定第一名，R8指定第八名，不自动按成绩排序。可通过逐行发送指定完整排名。
姓名、成绩和名次只保存在运行RAM，断电后还原；目前不支持将修改保存回 SD 卡。
每次发送完整一行，测试建议间隔1秒；装载忙时新行会被丢弃。每行收齐字形后在帧消隐切换，保留更新前行直到提交。

SSCOM 勾选“16进制发送”，第一名张三12.34秒：

```
40 52 31 3A D5 C5 C8 FD 2C 31 32 2E 33 34 0D 0A
```

编辑命令只更新数据，不自动打开排名页。先回到照片轮播并退出设置/奖杯页面，再用原屏按钮或命令55 22 00 00 FF FF FF进入排名；按原流程继续到前三名展示。
rank-serial-examples 中有 R1～R8 的 BIN 与 examples.json，show-ranking.bin 为进入排名命令。

电脑生成/发送：

```
python send_serial_title.py rank1 张三 --score 12.34 --out rank1.bin
python send_serial_title.py rank1 张三 --score 12.34 --port COM5
```

实际通过电脑端口发送需要 pyserial；也可直接用 SSCOM 发送 BIN。屏端 HMI 发送事件需配置，此包不包含新屏端 TFT。

## SD 素材

继续使用上一版 GLYPHS.BIN、AWARD720.DLT 和 RELIEF720.DLT；文件内容无需修改。
本包另附相同的 GLYPHS.BIN 方便恢复。字库仍需在原前1048576逻辑扇区、约512 MiB扫描范围内。
新默认文字不需要 SD 查字，但后续中文姓名和文字修改仍需 GLYPHS.BIN。

## 最终资源与时序

| 板 | LUT | 寄存器 | RAM9K | RAM32K | DSP | Setup/Hold ns |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
'''
for b in 'ab':
 r=boards[b];v=r['resources'];t=r['timing_ns'];readme+=f"| {b.upper()} | {v['lut']} | {v['reg']} | {v['bram']} | {v['bram32k']} | {v['dsp']} | {t['SWNS']:.3f}/{t['HWNS']:.3f} |\n"
readme+='''
默认文字不增加 RAM；排名姓名双缓冲使用 A 板最后一块 RAM32K。A、B 的 RAM32K 均已满，B 的 RAM9K 也已满。
两板保持原时钟和引脚约束，最终布线 setup/hold 均通过。选择B板19号布局，时序裕量优于31号布局。

## 已完成验证

- 完整 UART/索引/双板控制：原文字功能回归、全部8行姓名成绩更新、最长8字替换、不同名次相互隔离、错误成绩和超长姓名拒绝。
- 3200个排名与前三名页面像素：姓名大小、裁剪和8拍 RGB/DE 对齐。
- 277773个未编辑场景像素与8797178精确一致，包括蓝/红胜利、排名、前三名、背景与原条纹。
- 原启动退出条件、只显示进度条；176行默认字形与原字库逐位一致、串口覆盖标题保留默认轮播。
- 1000个着色样本，高光增强且墙面响应精确保持；85个奖杯样本实际变亮。
- HMI旧指令、触摸边界、忽略校验和、部分帧恢复及75MHz回归通过。

以上为仿真与厂商工具验证，当前新功能尚未上实体板确认；高光观感和屏端发送流程需上板复验。
'''
(out/'README.md').write_text(readme,encoding='utf-8')
manifest={p.relative_to(out).as_posix():sha(p) for p in sorted(out.rglob('*')) if p.is_file() and p.name!='SHA256SUMS.json'}
(out/'SHA256SUMS.json').write_text(json.dumps(manifest,indent=2))
with zipfile.ZipFile(root/'delivery-display-ranking-20261031.zip','w',zipfile.ZIP_DEFLATED) as z:
 for p in sorted(out.rglob('*')):
  if p.is_file():z.write(p,p.relative_to(root))
print('PASS packaged source-matched pair, glyphs, ranking commands and verification evidence')
