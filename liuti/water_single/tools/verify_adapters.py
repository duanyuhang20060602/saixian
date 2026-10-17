from pathlib import Path
import hashlib,json,subprocess,argparse
ROOT=Path(__file__).resolve().parents[1]
TEST=ROOT/'tests';RTL=ROOT/'rtl';OUT=ROOT/'validation'

def main():
    suite={'mapper':[TEST/'mapper_2_0_reference.v',RTL/'water_frame_mapper.v'],
           'expand_recovery':[RTL/'water_expand.v'],
           'serializer':[RTL/'water_hdmi_phy.v',ROOT.parent/'vendor/hdmi_phy_wrapper.v',ROOT.parent/'vendor/lane_lvds_10_1.v'],
           'sd_clock':[ROOT.parent/'vendor'/x for x in ['sd_card_top.v','sd_card_cmd.v','sd_card_sec_read_write.v','spi_master.v']],
           'audio_output':[RTL/'water_audio_output.v'],
           'audio_chain':[RTL/'water_audio_output.v',ROOT.parent/'vendor/audio_arc_calculate.v']+[ROOT/'vendor'/x for x in ['sd_card_bmp.v','afifo_32_16_256.v','board_helpers.v']],
           'music_select':[ROOT/'vendor/bmp_read.v',ROOT/'vendor/saixian_media_header.v'],
           'sample_phase':[RTL/'water_pack.v',RTL/'water_reconstruct.v'],
           'origin':[RTL/x for x in ['water_pack.v','water_reader.v','water_effect_map.v','water_extra_effect_map.v','water_math.v','water_blend.v','water_cache.v','water_frame_mapper.v','water_reconstruct.v','../tests/sdram_contract.v']],
           'handoff':[RTL/x for x in ['water_reader.v','water_effect_map.v','water_extra_effect_map.v','water_math.v','water_blend.v','water_cache.v','water_frame_mapper.v','water_reconstruct.v','../tests/sdram_contract.v']],
           'storage':[RTL/x for x in ['water_pack.v','water_reader.v','water_effect_map.v','water_extra_effect_map.v','water_math.v','water_blend.v','water_cache.v','water_frame_mapper.v','water_reconstruct.v','water_image_writer.v',
              '../vendor/frame_read_write.v','../vendor/frame_fifo_write.v','../vendor/afifo_16_32_256.v','../vendor/afifo_32_16_256.v','../tests/sdram_contract.v']]}
    ap=argparse.ArgumentParser();ap.add_argument('--only',nargs='+',choices=list(suite));args=ap.parse_args()
    manifest=OUT/'adapter_tests.json'
    results=[] if not args.only else [entry for entry in json.loads(manifest.read_text(encoding='utf-8')) if entry['test'] not in args.only]
    for name,sources in suite.items():
        if args.only and name not in args.only:continue
        sources=[TEST/f'tb_{name}.v',*sources]
        inputs={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
        if name in ('origin','handoff','storage'):
            for rom in ['water_sine.hex','water_wave.hex','water_inverse.hex','water_flip.hex','water_roll.hex','water_strip.hex','water_fx_recip.hex','water_fx_wave.hex']:
                p=TEST/rom;inputs[str(p)]=hashlib.sha256(p.read_bytes()).hexdigest()
        if name in ('audio_output','audio_chain'):
            p=TEST/'water_tone.hex';inputs[str(p)]=hashlib.sha256(p.read_bytes()).hexdigest()
        if name=='music_select':
            p=TEST/'selected_audio_header.hex';inputs[str(p)]=hashlib.sha256(p.read_bytes()).hexdigest()
        subprocess.run([r'C:\iverilog\bin\iverilog.exe','-DWATER_SIM','-g2012','-s','tb','-o',str(TEST/f'{name}.vvp'),*map(str,sources)],check=True)
        result=subprocess.run([r'C:\iverilog\bin\vvp.exe',str(TEST/f'{name}.vvp')],cwd=TEST,capture_output=True,text=True)
        assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==digest for p,digest in inputs.items()),'Inputs changed during test'
        print(result.stdout+result.stderr,flush=True)
        assert result.returncode==0 and 'PASS ' in result.stdout
        (OUT/f'{name}_test.log').write_text(result.stdout+result.stderr,encoding='utf-8')
        results.append(dict(test=name,inputs=inputs,stdout=result.stdout,stderr=result.stderr))
    for entry in results:
        assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==digest for p,digest in entry['inputs'].items()),'Stale test: '+entry['test']
    (OUT/'adapter_tests.json').write_text(json.dumps(results,indent=2),encoding='utf-8')

if __name__=='__main__':main()
