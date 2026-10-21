from support import *
run('tb_volume_curve',[ROOT/'tests/tb_volume_curve.v',HDL/'top_tf_hdmi_audio.v'],True)
sources=[HDL/'top_tf_hdmi_audio.v',HDL/'saixian_audio_pitch.v',HDL/'saixian_audio_visualizer.v',HDL/'saixian_av_decimator.v']
run('tb_pitch_top',[ROOT/'tests/tb_pitch_top.v',*sources],True)
BASE=ROOT/'baseline/tests'
for top,name in [('tb_audio_visual_wave','saixian_audio_visualizer.v'),('tb_audio_visual_key3','saixian_audio_visualizer.v'),('tb_pcm_pause','top_tf_hdmi_audio.v')]:
    target=ROOT/'tests'/f'{top}.v';target.write_text((BASE/f'{top}.v').read_text(encoding='utf-8'),encoding='utf-8')
    run(top,[target,HDL/name])
top='tb_audio_visual_render'
tb=(BASE/f'{top}.v').read_text(encoding='utf-8').replace('.visual_mode(visual_mode)',".audio_fx_mode(3'd0),.audio_fx_ready(1'b1),.visual_low_mode(1'b0),.visual_mode(visual_mode)")
target=ROOT/'tests'/f'{top}.v';target.write_text(tb,encoding='utf-8')
run(top,[target,HDL/'saixian_osd_overlay.v'])
print('PASS pitch top and preserved visualization/playback regressions',flush=True)
