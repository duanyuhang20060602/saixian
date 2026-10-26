"""Check real SD records -> duplex UART -> vendor font RAM -> OSD pixels."""
from pathlib import Path
import argparse, hashlib, json, subprocess
from PIL import Image
from configure_sd_title import compile_texts

ROOT = Path(__file__).resolve().parents[1]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', type=Path, required=True)
    args = ap.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    title, ticker = '标题测试', '底部独立文字'
    data, rows = compile_texts(title, ticker, Path('C:/Windows/Fonts/msyh.ttc'))
    (out/'TITLE2.BIN').write_bytes(data)
    (out/'title_records.hex').write_text(''.join(f'{b:02x}\n' for b in data), encoding='ascii')
    (out/'ip_init_map.vh').write_text('localparam HEX_FILE="";\n', encoding='ascii')
    s = (ROOT/'tests/tb_sd_title_protocol.v').read_text(encoding='utf-8')
    s = s.replace('module tb;', 'module tb;\nreg render=0;wire[10:0] font_addr;')
    s = s.replace('wire [6:0] word_index,title_address', 'wire [7:0] word_index,title_address')
    s = s.replace('word_length,published_length;', 'word_length,published_length,published_ticker;')
    s = s.replace('photo_sd_title_store store', 'photo_sd_title_store #(.INDEPENDENT_TEXT(1)) store')
    s = s.replace('.TITLE_SD(1))', '.TITLE_SD(1),.INDEPENDENT_TEXT(1))')
    s = s.replace('.title_length(published_length)', '.ticker_length(published_ticker),.title_length(published_length)')
    s = s.replace('.glyph_id(glyph),.row(row)', '.glyph_id(render ? font_addr[10:4]:glyph),.row(render ? font_addr[3:0]:row)')
    s = s.replace('writes[6:0]', 'writes[7:0]').replace('i<1024', 'i<2048').replace('writes!=128', 'writes!=256').replace('i<256', 'i<512')
    s = s.replace('published_length!=16', 'published_length!=4 || published_ticker!=6')
    s = s.replace('wait(a.send && a.message[159:152]==34);drop_ack=1;', 'wait(a.send && a.message[159:152]==34 && a.message[119:112]==128);drop_ack=1;')
    s = s.replace('a.incoming[119:112]==0', 'a.incoming[119:112]==128').replace('first_retries<2', 'first_retries<1')
    s = s.replace(' glyph=37;row=5;', ' glyph=37;row=5;')
    start = s.index(' glyph=37;row=5;')
    end = s.index('initial begin #', start)
    s = s[:start] + r'''
 render=1;fd=$fopen("title.ppm","wb");$fwrite(fd,"P6\n128 32\n255\n");
 for(py=0;py<32;py=py+1)for(px=0;px<128;px=px+1)begin
  @(negedge clk);sx=20+px;sy=16+py;repeat(7)@(negedge clk);
  if((^rgb)===1'bx)$fatal(1,"unknown title pixel");
  $fwrite(fd,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
 end
 $fclose(fd);fd=$fopen("ticker.ppm","wb");$fwrite(fd,"P6\n192 32\n255\n");
 for(py=0;py<32;py=py+1)for(px=0;px<192;px=px+1)begin
  @(negedge clk);sx=px;sy=432+py;repeat(7)@(negedge clk);
  if((^rgb)===1'bx)$fatal(1,"unknown ticker pixel");
  $fwrite(fd,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
 end
 $fclose(fd);
 if(a.error || b.error)$fatal(1,"configuration changed control errors");
 $display("PASS independent title/ticker native-RAM pixels after full duplex UART, high-bit ACK retry and all 512 font rows");$finish;
end
''' + s[end:]
    s = s.replace('#15000000', '#40000000')
    s = s.replace('integer writes=0', '''reg[9:0] sx=0;reg[8:0] sy=0;
wire[23:0] rgb;integer fd,px,py;
saixian_osd_overlay #(.SHOW_SOURCE_RESOLUTION(0),.SHARED_TITLE(1),.INDEPENDENT_TEXT(1)) osd(
 .clk(clk),.rst(rst),.frame_tick(frame_tick),.de_i(1'b1),.x_i(sx),.y_i(sy),.rgb_in_i(24'h123456),
 .display_valid(1'b1),.loading_phase(3'd0),.state(4'd0),.project_id(2'd0),.minutes(7'd0),.seconds(6'd0),.countdown_value(4'd0),
 .ticker_x(11'd192),.ticker_text_length(published_ticker),.title_text_length(published_length),.font_addr(font_addr),.font_bits(bits),.font_ready(1'b1),
 .source_width_bcd(16'd0),.source_height_bcd(16'd0),.error_code(3'd0),.visual_height(7'd0),.visual_peak(7'd0),.visual_wave(32'd0),
 .visual_fft_valid(1'b0),.visual_wave_valid(1'b0),.waveform_mode(1'b0),.settings_mode(1'b0),.setting_item(3'd0),
 .volume_setting(4'd4),.brightness_setting(4'd4),.contrast_setting(4'd4),.sharpness_setting(2'd1),.saturation_setting(4'd4),
 .invert_setting(1'b0),.vintage_setting(1'b0),.enhancement_setting(2'd1),.rgb_out(rgb));
integer writes=0''')
    bench = out/'pixels.v'
    bench.write_text(s, encoding='ascii')
    vendor = Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/ip/depot/AXI_Ethernet_Lite_1.0/AXI_Ethernet_Lite/RTL/ram_infer.v')
    files = [bench, ROOT/'tests/ip_vendor_ram_adapter.v', vendor] + [ROOT/p for p in (
        'common/photo_cached_control_a.v', 'common/photo_control.v', 'common/photo_uart.v',
        'common/photo_sd_title_store.v', 'common/audio_ui/saixian_font_rom.v', 'common/audio_ui/saixian_osd_overlay.v')]
    iv = ROOT.parents[1]/'.tools/iverilog/bin/iverilog.exe'
    binary = out/'pixels.vvp'
    r = subprocess.run([str(iv), '-g2012', '-I'+str(out), '-s', 'tb', '-o', str(binary), *map(str, files)], cwd=out, capture_output=True, text=True)
    log = r.stdout+r.stderr
    if r.returncode == 0:
        r = subprocess.run([str(iv.with_name('vvp.exe')), str(binary)], cwd=out, capture_output=True, text=True, timeout=600)
        log += r.stdout+r.stderr
    (out/'pixels.log').write_text(log, encoding='utf-8')
    print(log[-2500:], flush=True)
    assert r.returncode == 0 and 'PASS ' in log and 'FATAL' not in log
    captures = []
    for name, bank, count, color in [('title',0,4,(255,255,255)), ('ticker',512,6,(255,209,102))]:
        image = Image.open(out/(name+'.ppm')).convert('RGB')
        for y in range(32):
            for x in range(count*32):
                offset = bank+(x//32)*32+(y//2)*2
                row = int.from_bytes(rows[offset:offset+2], 'big')
                expected = color if row & (1 << (15-(x%32)//2)) else (9,26,43)
                assert image.getpixel((x,y)) == expected, (name,x,y,image.getpixel((x,y)),expected)
        image.save(out/(name+'.png'))
        captures.append({'bank':name,'verified_pixels':count*32*32})
    (out/'results.json').write_text(json.dumps({'passed':True,'title':title,'ticker':ticker,'captures':captures,
        'hardware_validation':'pending','inputs_sha256':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}, indent=2, ensure_ascii=False),encoding='utf-8')
    print('PASS exact independently expected title and ticker pixels', flush=True)

if __name__ == '__main__':
    main()
