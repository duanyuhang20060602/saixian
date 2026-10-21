from pathlib import Path
import hashlib,json,re,shutil
ROOT=Path(__file__).resolve().parents[1];TD=ROOT/'project/src/td_project';OUT=ROOT/'results'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
timing=(TD/'SAIXIAN_PITCH_EXPERIMENT_pr.timing').read_text()
ns={key:float(re.search(key+r':\s*([-\d.]+)ns',timing)[1]) for key in ['SWNS','STNS','HWNS','HTNS']}
assert min(ns.values())>=0,ns
build=(TD/'td_build.log').read_text(errors='replace')
assert not re.search(r'^\S+ ERROR:',build,re.M)
for name in ['test_run.log','integration_run.log','quality_run.log','quality_validation.log','existing_audio_run.log']:
    text=(OUT/name).read_text(errors='replace')
    assert 'PASS' in text and 'Traceback' not in text and 'FATAL:' not in text,name
area=(TD/'SAIXIAN_PITCH_EXPERIMENT_phy.area').read_text()
resources={k:int(re.search(r'^#'+k+r'\s+(\d+)',area,re.M)[1]) for k in ['lut','reg','bram','bram32k','dsp']}
for k,limit in [('lut',19600),('reg',19600),('bram',64),('bram32k',16),('dsp',29)]:assert resources[k]<=limit
evidence=(OUT/'test_run.log').read_text()
latency=re.search(r'output (\d+) clocks, total work (\d+) clocks/sample',evidence)
assert latency and int(latency[2])<700
bit=TD/'SAIXIAN_PITCH_EXPERIMENT.bit'
inputs=[p for p in (ROOT/'project/src/user_source').rglob('*') if p.is_file()]
configs=[TD/n for n in ['SAIXIAN_PITCH_EXPERIMENT.al','build_pitch.tcl','key2_tf_flow.tcl']]
assert all(p.stat().st_mtime<=bit.stat().st_mtime for p in inputs+configs)
delivery=ROOT/'delivery';delivery.mkdir(exist_ok=True)
for p in [bit,TD/'SAIXIAN_PITCH_EXPERIMENT_pr.timing',TD/'SAIXIAN_PITCH_EXPERIMENT_phy.area',TD/'td_build.log']:
    shutil.copy2(p,delivery/p.name)
named_bit=delivery/'SAIXIAN_VOLUME5_BOOSTED_20261021.bit'
shutil.copy2(bit,named_bit)
manifest={'date':'2026-10-21','hardware_validation':'pending user listening test',
          'recommended_bit_file':named_bit.name,
          'default_volume_level':5,'previous_default_volume_level':5,'default_volume_amplitude_ratio':10/7,
          'volume_gain_numerator_over_8':[0,6,7,8,9,10,11,12,13],
          'base':'../pitch_experiment_20261019','place_seed':3,'final_build_start_step':'read_design',
          'improvements':['mode-specific 63-tap anti-alias FIR','Q16 four-point cubic interpolation',
                          'short smooth overlap with flat regions','stereo waveform matching during muted read-head resets',
                          'pipelined SAD background search'],
          'bypass_delay_samples':1183,'startup_fill_samples':2304,'startup_fade_samples':64,
          'rtl_output_latency_clocks':int(latency[1]),'rtl_total_work_clocks':int(latency[2]),
          'input_interval_clocks_tested':700,'video_clock_mhz':75,'audio_sample_rate':48000,
          'timing_ns':ns,'resources':resources,'bit_sha256':sha(bit),
          'verification':json.loads((OUT/'verification.json').read_text()),
          'quality_metrics':json.loads((OUT/'quality_metrics.json').read_text()),
          'filter_response':json.loads((OUT/'filter_validation.json').read_text()),
          'existing_audio':json.loads((OUT/'existing_audio.json').read_text()),
          'algorithm_model_sha256':{p.name:sha(p) for p in [ROOT/'tools/quality_model.py',ROOT/'tools/pitch_template.v',ROOT/'tools/prepare_pitch.py']},
          'source_sha256':{p.relative_to(ROOT).as_posix():sha(p) for p in sorted(inputs)},
          'project_config_sha256':{p.relative_to(ROOT).as_posix():sha(p) for p in configs},
          'test_evidence_sha256':{p.name:sha(p) for p in sorted(OUT.glob('*.log'))}}
(delivery/'manifest.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps({k:manifest[k] for k in ['timing_ns','resources','bit_sha256','rtl_total_work_clocks']},indent=2))
