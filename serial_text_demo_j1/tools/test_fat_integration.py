"""Real UART -> text core -> fragmented FAT32 -> native RAM -> display pixels."""
from pathlib import Path
import argparse,subprocess
from test_fat_font import make,FONT,ROOT
ap=argparse.ArgumentParser();ap.add_argument('--work',required=True,type=Path);a=ap.parse_args();a.work.mkdir(parents=True,exist_ok=True)
sectors=make(True,2048,1)
(a.work/'lbas.hex').write_text(''.join(f'{k:08x}\n' for k in sorted(sectors)),encoding='ascii')
(a.work/'blocks.hex').write_text(''.join(f'{b:02x}\n' for k in sorted(sectors) for b in sectors[k]),encoding='ascii')
(a.work/'font.hex').write_text(''.join(f'{b:02x}\n' for b in FONT),encoding='ascii')
s=(ROOT/'tests/tb_demo.v').read_text(encoding='utf-8')
s=s.replace('wire[15:0] rx_count;', '''wire physical_read,mapped_valid,mapped_end;wire[31:0] physical_sector;wire[7:0] mapped_byte;wire[3:0] fs_error;
reg[31:0] lbas[0:2047];reg[7:0] blocks[0:1048575];integer match_index,t;
demo_fat_font filesystem(.clk(clk),.rst(rst),.card_ready(initialized && init_stage==4),.request(read),.address(address),.valid(mapped_valid),.data(mapped_byte),.finish(mapped_end),.error(fs_error),.read_sector(physical_read),.sector(physical_sector),.byte_valid(valid),.byte_data(b),.sector_end(last));
wire[15:0] rx_count;''')
s=s.replace('address,valid,b,last,frame','address,mapped_valid,mapped_byte,mapped_end,frame').replace('rx_last,4\'d0','rx_last,fs_error')
s=s.replace('if(read)begin if(state!=0)', 'if(physical_read)begin if(state!=0)')
s=s.replace('base<=(address-2209)*512;',f'''match_index=-1;for(t=0;t<{len(sectors)};t=t+1)if(lbas[t]==physical_sector)match_index=t;
if(match_index<0)$fatal(1,"unexpected physical LBA");base<=match_index*512;''')
s=s.replace('b<=font[base+position]','b<=blocks[base+position]')
s=s.replace('$readmemh("font.hex",font);',f'''$readmemh("font.hex",font);$readmemh("lbas.hex",lbas,0,{len(sectors)-1});$readmemh("blocks.hex",blocks,0,{len(sectors)*512-1});''')
(a.work/'integration.v').write_text(s,encoding='utf-8')
iv=Path('C:/iverilog/bin/iverilog.exe');out=a.work/'integration.vvp'
for native in (False,True):
 flags=['-g2012','-s','tb','-o',str(out)];files=[ROOT/'rtl/demo_core.v',ROOT/'rtl/demo_diagnostics.v',ROOT/'rtl/demo_fat_font.v',a.work/'integration.v']
 if not native:flags+=['-DDEMO_BEHAVIORAL']
 else:
  (a.work/'ip_init_map.vh').write_text('localparam HEX_FILE="";\n');flags+=['-I'+str(a.work)]
  files += [ROOT.parent/'5.0project/tests/ip_vendor_ram_adapter.v',Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/ip/depot/AXI_Ethernet_Lite_1.0/AXI_Ethernet_Lite/RTL/ram_infer.v')]
 r=subprocess.run([str(iv),*flags,*map(str,files)],capture_output=True,text=True);assert r.returncode==0,r.stderr
 r=subprocess.run([str(iv.with_name('vvp.exe')),str(out)],cwd=a.work,capture_output=True,text=True,timeout=120);print('native',native,r.stdout[-600:],flush=True)
 (a.work/('native.log' if native else 'behavioral.log')).write_text(r.stdout+r.stderr,encoding='utf-8');assert r.returncode==0 and 'PASS' in r.stdout,(r.stdout,r.stderr)
