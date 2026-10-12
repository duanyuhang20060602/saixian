from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]
required=['tb_real_fifo_link','tb_real_fifo_link_delay','tb_no_crc_system_async','tb_render','tb_read_data_align']
results={}
for path in sorted((ROOT/'tests/results').glob('*results.json'),key=lambda p:p.stat().st_mtime):
 for v in json.loads(path.read_text(encoding='utf-8')):results[v['test']]=v
assert all(n in results and results[n]['passed'] for n in required),'720p required simulations missing or failed'
boards=[json.loads((ROOT/'delivery'/f'{role}_manifest.json').read_text(encoding='utf-8')) for role in ['board_a','board_b']]
text='# 720p A读数据对齐迁移版验证记录\n\nSDRAM状态机及75MHz视频PLL来自photo d23efef；A板SDRAM读数据延迟一拍、valid不延迟，B板逻辑保持。640 字行跨度，720 行，460800 字/槽。板间时钟6.25MHz；图片 CRC、增强、锐化关闭；实板效果待观察。\n\n## 仿真\n\n| 测试 | 结果 | 秒 |\n|---|---|---:|\n'
for n in required:text+=f"| {n} | PASS | {results[n]['seconds']} |\n"
text+='\n## 时序及资源\n\n| 板 | SWNS/ns | HWNS/ns | STNS/HTNS | LUT | REG | BRAM9K | DSP |\n|---|---:|---:|---|---:|---:|---:|---:|\n'
for b in boards:
 t=b['timing_ns'];r=b['resources'];text+=f"| {b['role']} | {t['SWNS']} | {t['HWNS']} | {t['STNS']}/{t['HTNS']} | {r['lut']} | {r['reg']} | {r['bram9k']} | {r['dsp']} |\n"
text+='\n## 限制\n\n应用层仿真未运行加密 SDRAM 核或实板电气模型。测试不能代替实板固定纹波检查。控制/事务测试使用短帧；本次实际FIFO测试为2048字，6.25MHz链路对50MHz内存时钟；本次为改动相关的五项回归。新增读数据对齐测试是人为早一拍模型，不能代替真实内核验证。12.5MHz基线的460800字全帧记录保留在原NOENHANCE工程，本次未重跑完整帧。720p基线已完成的15项检查记录保留在原工程。对照工程仍有三槽缓存、板间链路及 A 显示包装，因此不等同完整 2.0 单板工程。\n'
(ROOT/'VALIDATION.md').write_text(text,encoding='utf-8')
(ROOT/'tests/results/summary.json').write_text(json.dumps([results[n] for n in required],indent=2),encoding='utf-8')
print('720 comparison evidence collected, 5 required tests; hardware pending.')
