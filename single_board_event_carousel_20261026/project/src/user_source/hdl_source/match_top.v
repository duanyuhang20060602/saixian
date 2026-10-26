`timescale 1ns/1ps
module top(input clk,input [3:0] key,input [1:0] sw,input hdmi_hpd,
 output [3:0] led,output [5:0] seg_sel,output [7:0] seg_data,
 output HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P,
 output HDMI_DDC_SCL,inout HDMI_DDC_SDA,
 output sd_ncs,sd_dclk,sd_mosi,input sd_miso,input hmi_uart_rx,output hmi_uart_tx);
wire video_clk,hdmi_5x_clk,locked;
video_pll u_video_pll(.refclk(clk),.reset(1'b0),.clk0_out(video_clk),.clk1_out(hdmi_5x_clk),.locked(locked));
reg [18:0] por_count;
always @(posedge clk or negedge locked)if(!locked)por_count<=0;else if(!por_count[18])por_count<=por_count+1'b1;
wire reset_request=!locked || !por_count[18];
wire rst_video,rst_hdmi;
match_reset rv(.clk(video_clk),.arst(reset_request),.rst(rst_video));
match_reset rh(.clk(hdmi_5x_clk),.arst(reset_request),.rst(rst_hdmi));
reg [10:0] h;reg [9:0] v;
always @(posedge video_clk or posedge rst_video)begin
 if(rst_video)begin h<=0;v<=0;end
 else if(h==1649)begin h<=0;v<=v==749 ? 0:v+1'b1;end
 else h<=h+1'b1;
end
wire de=h<1280 && v<720;
wire vs=v>=725 && v<730;
wire frame_tick=h==0 && v==720;
wire [3:0] short_key,long_key;wire [2:0] state,team_a,team_b;
wire [9:0] score_a,score_b;wire [8:0] remaining;wire [1:0] countdown,duration_index;wire [3:0] cue_event;
wire [1:0] page;wire last_valid,award_summary;wire [2:0] last_a,last_b;wire [9:0] last_score_a,last_score_b;
wire [6:0] last_number,next_number,active_number;
match_keys keys(.clk(video_clk),.rst(rst_video),.key_n(key),.key_scene(state),.short_key(short_key),.long_key(long_key));
event_flow control(.clk(video_clk),.rst(rst_video),.short_key(short_key),.long_key(long_key),
 .state(state),.team_a(team_a),.team_b(team_b),.score_a(score_a),.score_b(score_b),
 .remaining(remaining),.countdown(countdown),.duration_index(duration_index),.cue_event(cue_event),
 .page(page),.last_valid(last_valid),.last_a(last_a),.last_b(last_b),.last_score_a(last_score_a),.last_score_b(last_score_b),
 .last_number(last_number),.next_number(next_number),.active_number(active_number),.award_summary(award_summary));
wire [23:0] rgb;wire render_de,render_vs;
match_render screen(.clk(video_clk),.rst(rst_video),.frame_tick(frame_tick),.de(de),.vs(vs),.x(h),.y(v),
 .state(state),.team_a(team_a),.team_b(team_b),.score_a(score_a),.score_b(score_b),
 .remaining(remaining),.countdown(countdown),.duration_index(duration_index),.rgb(rgb),.out_de(render_de),.out_vs(render_vs),
 .page(page),.last_valid(last_valid),.last_a(last_a),.last_b(last_b),.last_score_a(last_score_a),.last_score_b(last_score_b),
 .round_number(state==5 && page==3 && last_valid ? last_number:state==0 || state==5 ? next_number:active_number),.award_summary(award_summary));
wire audio_valid;wire [23:0] audio_left,audio_right;wire acr_valid;wire [19:0] acr_cts,acr_n;
saixian_audio_cue #(.CLK_FREQ_HZ(75000000)) cues(.clk(video_clk),.rst(rst_video),.cue_event(cue_event),
 .audio_valid(audio_valid),.audio_left(audio_left),.audio_right(audio_right),.audio_level(),.cue_busy(),.spectrum_active(),.spectrum_tone_bin());
audio_arc_calculate #(.ACR_N(6144)) acr(.I_clk(video_clk),.I_rst(rst_video),.I_audio_valid(audio_valid),
 .O_acr_valid(acr_valid),.O_acr_cts(acr_cts),.O_acr_n(acr_n));
wire axis_user,axis_valid,axis_last,axis_ready;wire [23:0] axis_data;
video_rgb_to_axis_640x480 #(.H_ACTIVE(1280)) axis(.I_clk(video_clk),.I_rst(rst_video),.I_vs(render_vs),.I_de(render_de),.I_rgb(rgb),
 .O_video_user(axis_user),.O_video_valid(axis_valid),.O_video_last(axis_last),.O_video_data(axis_data));
(* async_reg="true" *)reg [1:0] hpd_sync;reg hpd_old;reg [21:0] edid_wait;reg edid_trig;
always @(posedge video_clk or posedge rst_video)begin
 if(rst_video)begin hpd_sync<=0;hpd_old<=0;edid_wait<=0;edid_trig<=0;end
 else begin
  hpd_sync<={hpd_sync[0],hdmi_hpd};hpd_old<=hpd_sync[1];edid_trig<=0;
  if(!hpd_sync[1])edid_wait<=0;
  else if(!hpd_old)edid_wait<=1;
  else if(edid_wait!=0)begin
   if(edid_wait==1500000)begin edid_trig<=1;edid_wait<=0;end
   else edid_wait<=edid_wait+1'b1;
  end
 end
end
wire [9:0] ch0,ch1,ch2,chclk;
hdmi_1_4b_transmitter_core_wrapper #(.DEVICE("EG"),.HTOTAL(1650),.HSA(40),.HFP(110),.HBP(220),.HACTIVE(1280),
 .VTOTAL(750),.VSA(5),.VFP(5),.VBP(20),.VACTIVE(720),.VIDEO_VIC(4),.VIDEO_TPG("Disable"),
 .VIDEO_FORMAT("RGB"),.AUDIO_SAMPLE_RATE("48K"),.IIC_SCL_DIV(375)) u_hdmi_tx(
 .I_pixel_clk(video_clk),.I_rst(rst_video),.I_edid_read_trig(edid_trig),.O_edid_read_valid(),.O_edid_read_data(),
 .I_axis_s_user(axis_user),.I_axis_s_valid(axis_valid),.I_axis_s_last(axis_last),.I_axis_s_data(axis_data),.O_axis_s_ready(axis_ready),
 .I_audio_valid(audio_valid),.I_audio_left_data(audio_left),.I_audio_right_data(audio_right),
 .I_acr_valid(acr_valid),.I_acr_cts(acr_cts),.I_acr_n(acr_n),.O_video_locked(),.O_ddc_scl(HDMI_DDC_SCL),.IO_ddc_sda(HDMI_DDC_SDA),
 .O_ch0_tmds_data(ch0),.O_ch1_tmds_data(ch1),.O_ch2_tmds_data(ch2),.O_clk_tmds_data(chclk));
hdmi_phy_wrapper #(.DEVICE("EG")) u_hdmi_phy(.I_pixel_clk(video_clk),.I_serial_clk(hdmi_5x_clk),.I_rst(rst_hdmi),
 .I_tmds_channel_0(ch0),.I_tmds_channel_1(ch1),.I_tmds_channel_2(ch2),.I_tmds_channel_clk(chclk),
 .O_tmds_ch0_p(HDMI_D0_P),.O_tmds_ch1_p(HDMI_D1_P),.O_tmds_ch2_p(HDMI_D2_P),.O_tmds_clk_p(HDMI_CLK_P));
assign sd_ncs=1;assign sd_dclk=0;assign sd_mosi=1;assign hmi_uart_tx=1;
assign led={state==4,state==3,state==2,locked};assign seg_sel=6'b111111;assign seg_data=8'hff;
endmodule
module match_reset(input clk,arst,output rst);
(* async_reg="true" *)reg [2:0] pipe;
always @(posedge clk or posedge arst)if(arst)pipe<=7;else pipe<={pipe[1:0],1'b0};
assign rst=pipe[2];
endmodule
