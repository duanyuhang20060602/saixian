"""Actual UART + fragmented FAT + native 50MHz glyph engine, including replay."""
from pathlib import Path
import argparse, hashlib, importlib.util, json, subprocess

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', type=Path, required=True)
    out = ap.parse_args().out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    spec = importlib.util.spec_from_file_location('fat', ROOT/'tools/test_font_fat.py')
    fat = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fat)
    sectors = fat.make(True, 2048, 8, None)
    (out/'lbas.hex').write_text(''.join(f'{n:08x}\n' for n in sorted(sectors)))
    (out/'blocks.hex').write_text(''.join(f'{b:02x}\n' for n in sorted(sectors) for b in sectors[n]))
    font = ROOT/'sd_config/TF字库/FONTS.BIN'
    (out/'font.hex').write_text(''.join(f'{b:02x}\n' for b in font.read_bytes()))
    fixture = ROOT/'tests/tb_typed_text_slow.v'
    body = fixture.read_text()
    lines = body.splitlines()
    lines = [line for line in lines if not line.startswith(('photo_text_bridge_b #', 'photo_text_font_b #', 'photo_font_file_b #'))]
    body = '\n'.join(lines)+'\n'
    marker = 'reg[31:0] lbas'
    engine = '''photo_font_engine_b #(.FAST_HZ(100000),.SLOW_HZ(50000),.HOLD_CYCLES(500000)) engine(
 .fast_clk(clk),.fast_rst(rst),.clk(slow_clk),.rst(rst),.tick(text_tick),.session(b_session),
 .received(br),.incoming(bi),.pending(bp),.message(bm),.sent(bs),.boot_ready(1'b1),
 .card_ready(1'b1),.font_ready(fr),.font_fault(ff),.read_sector(fat_read),.sector(fat_sector),
 .byte_valid(pv),.byte_data(pd),.sector_end(pe));
assign gen=engine.generation;assign blr=engine.line_ready;assign blv=engine.line_valid;
assign bline=engine.line;assign fat_error=engine.file_error;
'''
    body = body.replace(marker, engine+marker, 1)
    body = body.replace('loader.', 'engine.loader.').replace('bridge_b.', 'engine.bridge.').replace('fs.', 'engine.filesystem.')
    old = 'if(!rejected || !duplicates || ff || engine.filesystem.fast_overflow || engine.filesystem.slow_overflow)'
    replay = '''oldgen=gen;
 fork
  begin
   prefix("0");byte_send(8'hd6);byte_send(8'hd0);byte_send("2");done;
  end
  begin
   wait(gen!=oldgen);wait(engine.loader.state==6 && engine.loader.index==10);
   force a.session=32'd2;force b.session=32'd2;
   repeat(4)@(negedge clk);release a.session;release b.session;
  end
 join
 expected[1]=50;check(2,0);
 $display("PASS native glyph engine: session changed during word transfer, complete replay and exact cache bytes");
'''
    assert old in body
    body = body.replace(old, replay+old)
    body = body.replace('#150000000;', '#250000000;')
    body = body.replace('endmodule', '''wire[68:0] queued_glyph={engine.generation,engine.index,engine.length,engine.data,engine.mask};
always @(posedge slow_clk)
 if(!rst && engine.word_source_valid && engine.word_source_ready)
  if((^queued_glyph)===1'bx)
   $fatal(1,"uninitialized glyph word gen=%h index=%h len=%h data=%h mask=%h row0=%h row1=%h settle=%d",engine.generation,engine.index,engine.length,engine.data,engine.mask,engine.loader.memory[0],engine.loader.memory[1],engine.settle);
initial forever begin
 #5000000;
 $display("PROGRESS t=%t loader=%d mapper=%d gen=%d word=%d pending=%b bridge=%d line_ready=%b queue=%b/%b",$time,
 engine.loader.state,engine.filesystem.mapper.state,gen,engine.loader.index,bp,
 engine.bridge.expected,blr,engine.word_source_ready,engine.word_destination_valid);
end
endmodule''', 1)
    bench = out/'font_engine.v'
    bench.write_text(body, encoding='utf-8')
    sources = [bench, *[ROOT/p for p in (
        'common/photo_font_engine_b.v', 'common/photo_font_file_b.v', 'common/photo_font_fat.v',
        'common/photo_text_crc.v', 'common/photo_typed_text_a.v', 'common/photo_typed_text_b.v',
        'common/photo_typed_control_b.v', 'common/photo_cached_control_a.v', 'common/photo_control.v',
        'common/photo_uart.v', 'common/audio_ui/saixian_font_rom.v', 'tests/title_font_ram_model.v')]]
    evidence = [Path(__file__), fixture, ROOT/'tools/test_font_fat.py', font, *sources,
                *[out/p for p in ('lbas.hex', 'blocks.hex', 'font.hex')]]
    hashes = {str(p): digest(p) for p in evidence}
    binary = out/'font_engine.vvp'
    build = subprocess.run(['C:/iverilog/bin/iverilog.exe', '-g2012', '-DTYPED_TEXT_SIM', '-s', 'tb',
                            '-o', str(binary), *map(str, sources)], capture_output=True, text=True)
    (out/'compile.log').write_text(build.stdout+build.stderr)
    build.check_returncode()
    log = out/'font_engine.log'
    with log.open('w', encoding='utf-8') as output:
        run = subprocess.run(['C:/iverilog/bin/vvp.exe', '-i', str(binary), f'+sectors={len(sectors)}'],
                             cwd=out, stdout=output, stderr=subprocess.STDOUT, text=True, timeout=1800)
    log_text = log.read_text(encoding='utf-8')
    passed = run.returncode == 0 and 'PASS native glyph engine' in log_text
    assert all(digest(Path(p)) == sha for p, sha in hashes.items())
    record = {'test': 'native_font_engine_uart_fat_replay', 'passed': passed,
              'source_sha256': hashes, 'log': str(log), 'log_sha256': digest(log),
              'scope': 'Independent 100/45.45MHz clocks, real UART, fragmented TF, 512 exact rows, CRC and ACK retry, session change at glyph word 10.'}
    (out/'results.json').write_text(json.dumps(record, indent=2)+'\n', encoding='utf-8')
    print(log_text[-6000:], flush=True)
    assert passed


if __name__ == '__main__':
    main()
