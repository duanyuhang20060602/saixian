from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]
required=['tb_real_fifo_link','tb_real_fifo_link_delay','tb_no_crc_system_async','tb_render','tb_read_data_align','tb_hmi','tb_playback_controls']
results={}
for path in sorted((ROOT/'tests/results').glob('*results.json'),key=lambda p:p.stat().st_mtime):
 for v in json.loads(path.read_text(encoding='utf-8')):results[v['test']]=v
boards=[json.loads((ROOT/'delivery'/f'{role}_manifest.json').read_text(encoding='utf-8')) for role in ['board_a','board_b']]
if all(b.get('a_cache_frames')==4 for b in boards):
 text='# 720p 50 MHz B板处理、A板按键、HDMI菜单及MODEFAST双模式调度构建记录\n\n本次将图像处理移至B板，由A板按键/HMI控制，并新增HDMI中文设置界面。本次改为播放优先/设置保护双模式：正常播放解锁当前原图，设置期间才保护，保留50ms参数合并。未运行功能仿真，实板验证待完成。已有 tests/results 下的 PASS 日志属于此前控制器，不能作为本版本通过依据。\n\n## 时序及资源\n\n| 板 | SWNS/ns | HWNS/ns | LUT | REG | BRAM9K | DSP |\n|---|---:|---:|---:|---:|---:|---:|\n'
 for b in boards:
  t=b['timing_ns'];r=b['resources'];text+=f"| {b['role']} | {t['SWNS']} | {t['HWNS']} | {r['lut']} | {r['reg']} | {r['bram9k']} | {r['dsp']} |\n"
 text+='\n编译、布局布线及时序报告已生成；帧 CRC 保持关闭，B板增强/锐化、参数确认及缓存刷新、中文菜单、真实线缆与SDRAM连续切换效果待确认。\n'
 (ROOT/'VALIDATION.md').write_text(text,encoding='utf-8')
 print('Four-frame build evidence collected; simulation and hardware pending.')
 raise SystemExit(0)
assert all(n in results and results[n]['passed'] for n in required),'720p required simulations missing or failed'
text='# 720p 双板 12.5MHz 自动轮播与转场控制验证记录\n\nA板保留SDRAM读数据对齐修正，B板链路时钟改为12.5MHz。每槽460800个32位字，图片CRC、增强和锐化仍关闭。新增随机/固定转场选择与五秒自动轮播；本次版本实板效果待验证。\n\n## 仿真\n\n| 测试 | 结果 | 秒 |\n|---|---|---:|\n'
for n in required:text+=f"| {n} | PASS | {results[n]['seconds']} |\n"
text+='\n## 时序及资源\n\n| 板 | SWNS/ns | HWNS/ns | STNS/HTNS | LUT | REG | BRAM9K | DSP |\n|---|---:|---:|---|---:|---:|---:|---:|\n'
for b in boards:
 t=b['timing_ns'];r=b['resources'];text+=f"| {b['role']} | {t['SWNS']} | {t['HWNS']} | {t['STNS']}/{t['HTNS']} | {r['lut']} | {r['reg']} | {r['bram9k']} | {r['dsp']} |\n"
text+='\n## 限制\n\n应用层仿真未运行加密SDRAM核或实板电气模型；12.5MHz链路的信号质量、连续快速切换及自动轮播仍需实板验证。图片CRC保持关闭。\n'
(ROOT/'VALIDATION.md').write_text(text,encoding='utf-8')
(ROOT/'tests/results/summary.json').write_text(json.dumps([results[n] for n in required],indent=2),encoding='utf-8')
print('720p 12.5MHz playback evidence collected; hardware pending.')
