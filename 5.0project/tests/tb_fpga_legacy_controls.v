`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,rx=1;always #5 clk=~clk;
reg[4:0] frame_count=0;wire ft=frame_count==19;
always @(posedge clk)if(rst || ft)frame_count<=0;else frame_count<=frame_count+1'b1;
wire start,pause,resume,pause_set,finish,sv,ev,av,ae,edv,ed,reset_settings;wire[2:0] sid;wire[7:0] sval;wire[4:0] effect_value;
saixian_hmi_uart #(.CLK_FREQ_HZ(10000),.BAUD_RATE(1000)) uart(.clk(clk),.rst(rst),.uart_rx(rx),
 .text_active(1'b0),.start_pulse(start),.pause_pulse(pause),.pause_set_pulse(pause_set),.resume_pulse(resume),.finish_pulse(finish),
 .setting_valid(sv),.setting_id(sid),.setting_value(sval),.effect_valid(ev),.effect_value(effect_value),.auto_valid(av),.auto_value(ae),
 .edge_valid(edv),.edge_value(ed),.reset_defaults_pulse(reset_settings));
wire[3:0] state,cd,cue;wire[6:0] minutes;wire[5:0] seconds;wire carousel;wire[1:0] project;
saixian_event_controller #(.CLK_FREQ_HZ(10000)) event_d(.clk(clk),.rst(rst),.frame_start(ft),.key_start(start),
 .key_pause(pause || (pause_set && state==6) || (resume && state==7)),.key_end(finish),.project_switch(2'd0),
 .state(state),.project_id(project),.minutes(minutes),.seconds(seconds),.countdown_value(cd),.cue_event(cue),.carousel_mode(carousel));
wire auto_enabled,edge_enabled;wire[4:0] fx;
photo_unified_settings_controller #(.CLK_FREQ_HZ(10000)) settings(.clk(clk),.rst(rst),.carousel_mode(carousel),
 .pointer_valid(1'b0),.pointer_increase(1'b0),.pointer_item(4'd0),.key_next_item(1'b0),.key_decrease(1'b0),.key_enter_exit(1'b0),.key_increase(1'b0),
 .hmi_setting_valid(sv),.hmi_setting_id(sid),.hmi_setting_value(sval),.hmi_reset_defaults(reset_settings),
 .effect_valid(ev),.effect_value(effect_value),.auto_valid(av),.auto_value(ae),.audio_view_valid(1'b0),.audio_view_value(1'b0),
 .edge_valid(edv),.edge_value(ed),.edge_enable(edge_enabled),.auto_enable(auto_enabled),.effect_select(fx));
wire[23:0] rgb;
saixian_osd_overlay #(.SHOW_SOURCE_RESOLUTION(0),.EMPTY_TEXT_BLANK(1),.HIDE_CAROUSEL_LABEL(1)) osd(.clk(clk),.rst(rst),.frame_tick(ft),
 .de_i(1'b1),.x_i(10'd2),.y_i(9'd200),.rgb_in_i(24'h112233),.display_valid(1'b1),.loading_phase(3'd0),.state(state),.project_id(project),
 .minutes(minutes),.seconds(seconds),.countdown_value(cd),.ticker_x(11'd0),.ticker_text_length(5'd0),.title_text_length(5'd0),.font_ready(1'b1),.font_bits(16'd0),
 .source_width_bcd(16'd0),.source_height_bcd(16'd0),.error_code(3'd0),.visual_height(7'd0),.visual_peak(7'd0),.visual_wave(32'd0),
 .visual_fft_valid(1'b0),.visual_wave_valid(1'b0),.waveform_mode(1'b0),.settings_mode(1'b0),.setting_item(3'd0),
 .volume_setting(4'd5),.brightness_setting(4'd4),.contrast_setting(4'd4),.sharpness_setting(2'd1),.saturation_setting(4'd4),
 .invert_setting(1'b0),.vintage_setting(1'b0),.enhancement_setting(2'd1),.rgb_out(rgb));
task byte_tx;input[7:0] b;integer i;begin
 @(negedge clk);rx=0;repeat(10)@(negedge clk);
 for(i=0;i<8;i=i+1)begin rx=b[i];repeat(10)@(negedge clk);end
 rx=1;repeat(10)@(negedge clk);
end endtask
task command;input[7:0] c,v;begin byte_tx(8'h55);byte_tx(c);byte_tx(v);byte_tx(0);byte_tx(255);byte_tx(255);byte_tx(255);repeat(25)@(negedge clk);end endtask
reg[5:0] paused_second;
initial begin
 repeat(5)@(negedge clk);rst=0;repeat(10)@(negedge clk);
 if(auto_enabled!==1 || edge_enabled!==1 || fx!==0)$fatal(1,"requested power-on defaults missing");
 command(8'h19,0);command(8'h18,5);command(8'h1c,0);
 if(auto_enabled!==0 || edge_enabled!==0 || fx!==5)$fatal(1,"screen carousel controls disconnected");
 command(8'h1f,0);if(auto_enabled!==1 || edge_enabled!==1 || fx!==0)$fatal(1,"restore defaults mismatch");
 command(1,0);wait(state==6);wait(seconds==1);repeat(8)@(negedge clk);
 if(rgb!==24'h00d46a)$fatal(1,"running green border missing: %h",rgb);
 command(6,0);if(state!==7)$fatal(1,"screen pause not applied");repeat(8)@(negedge clk);
 if(rgb!==24'hffb000)$fatal(1,"paused yellow border missing");
 paused_second=seconds;repeat(22000)@(negedge clk);if(seconds!=paused_second)$fatal(1,"paused timer advanced");
 command(7,0);if(state!==6)$fatal(1,"screen resume not applied");
 command(3,0);if(state!==8)$fatal(1,"screen finish not applied");repeat(8)@(negedge clk);
 if(rgb!==24'h112233)$fatal(1,"finish did not release running border");
 wait(carousel);if(project!==0)$fatal(1,"default event is not 100m");
 $display("PASS real UART carousel settings/reset; original 100m countdown/start/pause/resume/finish; green running/yellow paused border pixels; paused timer freeze and return to carousel");$finish;
end
initial begin #2000000;$fatal(1,"legacy-control timeout");end
endmodule
