from pathlib import Path
import re
import run_key2_tf as t
font=[0]*2048
for address,value in re.findall(r'(?m)^\s*([0-9A-Fa-f]{3})\s*:\s*([0-9A-Fa-f]{4})\s*;', (t.HDL/'saixian_font_rom.mif').read_text()):
    font[int(address,16)]=int(value,16)
assert all(any(font[glyph*16:(glyph+1)*16]) for glyph in [74,101,102,85])
path=t.WORK/'font.hex';path.write_text(''.join(f'{value:04x}\n' for value in font))
t.run('tb_audio_repair_osd',[t.ROOT/'tests/tb_audio_repair_osd.v',t.HDL/'saixian_osd_overlay.v'],args=[f'+FONT={path.as_posix()}'])
t.run('tb_loading_policy',[t.ROOT/'tests/tb_loading_policy.v',t.HDL/'top_tf_hdmi_audio.v'],missing=True)
print('PASS production Chinese font and loading policy')
