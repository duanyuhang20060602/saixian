`timescale 1ns/1ps
module tb;
reg ac=0,bc=0,mc=0,lc=0;always #6.667 ac=~ac;always #5 bc=~bc;always #10 mc=~mc;always #20 lc=~lc;
reg rst=1,en=0,tick=0,start=0,tv=0;reg [19:0] ti=0;reg [31:0] td=0;
reg [4:0] angle=0;reg signed [5:0] lx=-16,ly=6;reg [3:0] volume=5;
wire sclk,cs,mosi,miso,pcm_valid;wire [23:0] left,right;wire [15:0] errors,underflows;
wire available,beginp,wv,finish,commit,sent;wire [31:0] query,sentd,wd;wire [8:0] wi;
wire active,bank,pwe,wwe;wire [4:0] shown_angle;wire signed [5:0] shown_lx,shown_ly;
wire [8:0] pwa;wire [31:0] pwd;wire [7:0] wwa;wire [23:0] wwd;
wire b_ready,b_request,b_active;wire [31:0] b_desc,b_data,b_query;wire [8:0] b_address;
wire req;wire [7:0] epoch;wire [2:0] track;reg [7:0] active_epoch=0;reg [2:0] active_track=0;
reg corrupt=0;wire wire_miso=miso ^ (corrupt && a.relief_transfer && a.word_index==387 && a.bit_index==7);
photo_audio_spi_a #(.FIFO_AW(11),.HALF_DIV(10),.EXTENDED_AV(1),.REMOTE_RELIEF(1),.TYPED_PAGE(1),.PAGE_CUE(1)) a(
 .clk(ac),.rst(rst),.next_track(1'b0),.bg_enable(1'b1),.repair_enable(1'b1),.playback_hold(1'b0),.volume(volume),.cue_event(4'd0),
 .spi_miso(wire_miso),.spi_sclk(sclk),.spi_cs(cs),.spi_mosi(mosi),.sample_valid(pcm_valid),.audio_left(left),.audio_right(right),.packet_errors(errors),.underflows(underflows),
 .av_available(1'b1),.page_event(1'b0),.page_style(4'd0),.relief_enable(en),.relief_available(available),.relief_descriptor(query),
 .relief_begin(beginp),.relief_word_valid(wv),.relief_finish(finish),.relief_commit(commit),.relief_sent(sent),.relief_sent_descriptor(sentd),.relief_word_index(wi),.relief_word(wd));
photo_audio_spi_b #(.CATALOG_STATUS(1),.EXTENDED_AV(1),.TYPED_PAGE(1),.PAGE_CUE(1),.REMOTE_RELIEF(1)) b(
 .clk(bc),.rst(rst),.spi_sclk(sclk),.spi_cs(cs),.spi_mosi(mosi),.spi_miso(miso),.packet_active(b_active),
 .catalog_complete(1'b1),.active_epoch(active_epoch),.active_track(active_track),.track_count(3'd2),.switching(1'b0),
 .fifo_used(14'd4096),.processed_pcm(32'h5a1b13c7),.bg_enabled(1'b1),.request_valid(req),.request_epoch(epoch),.request_track(track),
 .av_data(32'h41563103),.page_ready(1'b1),.relief_ready(b_ready),.relief_descriptor(b_desc),.relief_data(b_data),.relief_address(b_address),.relief_request(b_request),.relief_query(b_query));
always @(posedge bc)if(req)begin active_epoch<=epoch;active_track<=track;end
photo_relief_coprocessor_b processor(.link_clk(lc),.link_rst(rst),.relief_start(start),.relief_abort(1'b0),.tap_valid(tv),.tap_index(ti),.tap_data(td),
 .clk(mc),.rst(rst),.spi_clk(bc),.spi_rst(rst),.packet_active(b_active),.request_valid(b_request),.request_descriptor(b_query),.read_address(b_address),
 .response_valid(b_ready),.response_descriptor(b_desc),.response_data(b_data));
photo_relief_tables_compact_a tables(.clk(ac),.rst(rst),.enable(en),.frame_tick(tick),.desired_angle(angle),.desired_light_x(lx),.desired_light_y(ly),
 .request_descriptor(query),.request_sent(sent),.sent_descriptor(sentd),.available(available),.begin_packet(beginp),.word_valid(wv),.finish_packet(finish),.commit_packet(commit),
 .word_index(wi),.word_data(wd),.active_valid(active),.active_bank(bank),.display_angle(shown_angle),.display_light_x(shown_lx),.display_light_y(shown_ly),
 .wall_we(wwe),.wall_wa(wwa),.wall_wd(wwd),.mem_clk(mc),.mem_rst(rst),.mem_enable(en),.palette_we(pwe),.palette_wa(pwa),.palette_wd(pwd),.rejected());
reg [31:0] palette[0:511],raw[0:6143],gold[0:18431];reg [23:0] walls[0:255];
integer frame_count=0,samples=0,commits=0,packets=0,i;reg previous_bank=0;reg [4:0] previous_angle=0;
always @(posedge mc)if(pwe)palette[pwa]<=pwd;
always @(posedge ac)begin
 if(wwe)walls[wwa]<=wwd;
 if(!rst)begin
  if(pcm_valid && a.playing && !a.held)begin
   if(left!==24'h13c700 || right!==24'h5a1b00)$fatal(1,"PCM changed %h/%h",left,right);
   samples=samples+1;
  end
  if(underflows!=0)$fatal(1,"audio underflow during table transfer");
  if(commit)packets=packets+1;
  #1;
  if(active && (bank!=previous_bank || shown_angle!=previous_angle))begin
   if(!tick)$fatal(1,"table or angle changed mid-frame");commits=commits+1;
  end
  previous_bank=bank;previous_angle=shown_angle;
 end
end
always @(negedge ac)begin
 if(rst)begin frame_count=0;tick=0;end
 else begin tick=frame_count==1237499;frame_count=frame_count==1237499 ? 0:frame_count+1;end
end
task check_table;input integer q;begin
 for(i=0;i<256;i=i+1)if(palette[bank*256+i]!==gold[q*384+i])$fatal(1,"SPI palette %0d got %h expected %h",i,palette[bank*256+i],gold[q*384+i]);
 for(i=0;i<128;i=i+1)if(walls[bank*128+i]!==gold[q*384+256+i][31:8])$fatal(1,"SPI wall %0d",i);
end endtask
initial begin
 $readmemh("raw_palettes.hex",raw);$readmemh("tables_expected.hex",gold);
 repeat(10)@(negedge lc);rst=0;start=1;@(negedge lc);start=0;
 for(i=0;i<6144;i=i+1)begin tv=1;ti=460864+i;td=raw[i];@(negedge lc);end tv=0;en=1;
 wait(active);@(negedge ac);check_table(0);
 // A corrupt result cannot replace the displayed frame.
 angle=23;lx=24;ly=-16;corrupt=1;
 wait(a.relief_transfer && a.word_index==387);wait(cs);@(negedge ac);corrupt=0;
 repeat(20)@(negedge ac);if(errors==0)$fatal(1,"corrupt CRC not detected");
 wait(shown_angle==23);@(negedge ac);check_table(47);
 // Audio control aborts a table packet but the complete visible bank survives.
 wait(a.relief_transfer && a.word_index==20);@(negedge ac);volume=6;
 wait(cs);repeat(300000)@(negedge ac);if(!active || shown_angle!=23)$fatal(1,"audio reset lost visible material");
 check_table(47);
 // Leave and reenter while SPI continues; stale owner responses are discarded.
 en=0;repeat(30000)@(negedge ac);if(active)$fatal(1,"scene exit retained eligibility");
 angle=0;lx=-16;ly=6;en=1;wait(active);@(negedge ac);check_table(0);
 repeat(1500000)@(negedge ac);
 if(samples<3000 || packets<3 || commits<3)$fatal(1,"incomplete integration coverage samples=%0d packets=%0d commits=%0d",samples,packets,commits);
 $display("PASS real 75/100/50/25MHz SPI and coprocessor, 48kHz stereo exact, zero underflows, CRC rejection, audio-epoch abort, scene reentry and coherent blanking commits; samples=%0d packets=%0d commits=%0d",samples,packets,commits);$finish;
end
initial begin #250000000;$fatal(1,"SPI integration timeout active=%0d ready=%0d receiving=%0d count=%0d owner=%0d bdesc=%h query=%h packets=%0d",active,b_ready,tables.receiving,tables.expected_index,tables.owner,b_desc,query,packets);end
endmodule
