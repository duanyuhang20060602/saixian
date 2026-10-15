"""Export immutable baselines. Run once when starting a fresh project."""
from pathlib import Path
import subprocess, shutil, re, json
ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
if (ROOT/'common/photo_link.v').exists():
    raise SystemExit('Baselines already imported; refusing to overwrite the implementation.')
def source(ref, path):
    return subprocess.check_output(['git','-C',str(REPO),'show',f'{ref}:{path}']).decode('utf-8')
def put(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding='utf-8', newline='\n')
for role, old in [('board_a','board_a_receiver'),('board_b','board_b_sd_sender')]:
    src=REPO/'dual_board_1280x720_transfer/projects'/old/'src'
    dst=ROOT/'projects'/role/'src'
    shutil.copytree(src,dst,dirs_exist_ok=True)
common=ROOT/'common'
sd=['bmp_read','saixian_media_header','sd_card_cmd','sd_card_sec_read_write','sd_card_top','spi_master']
for name in sd:
    text=source('d23efef',f'2.0Project/src/user_source/hdl_source/SD/{name}.v')
    if name=='bmp_read':
        text=text.replace('saixian_load_scaler u_scaler(', 'saixian_load_scaler #(.OUT_WIDTH(1280),.OUT_HEIGHT(720)) u_scaler(')
    put(common/'photo_sd'/f'{name}.v',text)
top=source('d23efef','2.0Project/src/user_source/hdl_source/top_tf_hdmi_audio.v')
modules=['saixian_settings_controller','saixian_adaptive_enhance','saixian_picture_adjust_pipe','saixian_picture_adjust','saixian_hmi_color_style','saixian_hmi_status_tx']
parts=[]
for name in modules:
    m=re.search(r'(?m)^module '+name+r'\b.*?\bendmodule',top,re.S)
    assert m,name
    text=m.group()
    if name=='saixian_adaptive_enhance':
        text=text.replace('reg [19:0] stat_sum','reg [20:0] stat_sum').replace('reg [11:0] stat_count','reg [12:0] stat_count').replace('wire [19:0] stat_count_ext={8\'d0,stat_count}','wire [20:0] stat_count_ext={8\'d0,stat_count}')
    parts.append(text)
put(common/'photo_processing.v','\n\n'.join(parts)+'\n')
for name in ['saixian_hmi_uart','saixian_key_debounce']:
    put(common/f'{name}.v',source('d23efef',f'2.0Project/src/user_source/hdl_source/{name}.v'))
text=source('d23efef','2.0Project/src/user_source/hdl_source/saixian_transition.v')
# Even offsets are necessary: the SDRAM words contain pairs of pixels.
text=re.sub(r"11'd(\d+)",lambda m: "11'd"+str(round(int(m[1])*1280/1280/2)*2),text)
put(common/'saixian_transition.v',text)
for role in ['board_a','board_b']:
    hdl=ROOT/'projects'/role/'src/user_source/hdl_source'
    # Keep the dual-board FIFO fixes (registered output and write arbitration).
    text=(hdl/'frame_store.v').read_text(encoding='utf-8')
    text=text.replace('input mem_clk,','input [1:0] write_slot,read_slot,new_slot, input slide_active,slide_right, input [10:0] slide_offset,input [2:0] transition_mode,\n input mem_clk,')
    for direction in ['read','write']:
        text=text.replace(f'.{direction}_addr_1(21\'d0)',f'.{direction}_addr_1(21\'d460800)').replace(f'.{direction}_addr_2(21\'d0)',f'.{direction}_addr_2(21\'d921600)')
        text=text.replace(f'.{direction}_addr_index(2\'d0)',f'.{direction}_addr_index({direction}_slot)')
    text=text.replace(".slide_active(1'b0),.slide_old_index(2'd0),.slide_new_index(2'd0),.slide_offset(11'd0)",'.slide_active(slide_active),.slide_old_index(read_slot),.slide_new_index(new_slot),.slide_offset(slide_offset)')
    text=text.replace(".slide_right(1'b0),.transition_mode(3'd0)",'.slide_right(slide_right),.transition_mode(transition_mode)')
    put(hdl/'frame_store.v',text)
    # Generalise the photo mapper's row effects to 720 lines and 640 words.
    p=hdl/'SD/frame_fifo_read.v'
    text=p.read_text(encoding='utf-8')
    # Dual baseline uses the same mapper, with row thresholds hard-coded at 90.
    for val in [630,540,450,360,270,180,90]:
        text=re.sub(r'(?<!\d)'+str(val)+r'(?!\d)',str(val*720//720),text)
    text=text.replace('diagonal_limit=({1\'b0,offset}<<1)+(offset>>1);',"diagonal_limit=({1'b0,offset}<<1)+(offset>>3);\n    if(offset>=FRAME_WIDTH) diagonal_limit=FRAME_WIDTH+720;")
    text=text.replace('use_new=blind_local_y<((offset>>3)+(offset>>6));','use_new=blind_local_y<((offset>>3)+(offset>>7));\n            if(offset>=FRAME_WIDTH) use_new=1;')
    # See configure_projects.py for the common source list; inherited files
    # remain for reference but unused RTL is excluded from the build.
    put(p,text)
put(ROOT/'baseline.json',json.dumps({'dual':'c13937bdabe0d3879fdd337da1cd3fbf2b0a7895','photo':'d23efefcd6d098a4d055ec064981315d4418196a','width':1280,'height':720,'frame_words':460800},indent=2)+'\n')
