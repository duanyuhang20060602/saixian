`timescale 1ns/1ps
module tb_hmi_bidirectional;
reg clk=0;always #5 clk=~clk;
reg rst=1,rx=1; reg [3:0] fixture_volume=5;
wire tx, sent, start, pause_set, resume, err;
wire [2:0] page;
wire page_notify; wire [3:0] controlled_state;
integer starts=0, pauses=0, resumes=0, errors=0, frames=0, field=0;
reg [7:0] received;
string command="", expected;
saixian_hmi_uart #(.CLK_FREQ_HZ(10000),.BAUD_RATE(1000)) receiver(
 .clk(clk),.rst(rst),.uart_rx(rx),.start_pulse(start),
 .pause_set_pulse(pause_set),.resume_pulse(resume),.page_id(page),.page_notify_pulse(page_notify),.frame_error_pulse(err));
saixian_hmi_status_tx #(.CLK_FREQ_HZ(10000),.BAUD_RATE(1000)) transmitter(
 .clk(clk),.rst(rst),.page_id(page),.refresh_request(page_notify),.image_count(3'd5),.audio_count(3'd5),
 .error_code(3'd0),.initializing(1'b0),.sharpness(2'd1),
 .brightness(4'd4),.contrast(4'd4),.saturation(4'd4),.volume(fixture_volume),
 .invert(1'b0),.vintage(1'b1),.event_state(4'd7),.minutes(7'd12),.seconds(6'd34),
 .uart_tx(tx),.command_sent_pulse(sent));
saixian_event_controller #(.CLK_FREQ_HZ(10000)) event_controller(
 .clk(clk),.rst(rst),.frame_start(1'b1),.key_start(start),
 .key_pause((pause_set && controlled_state==6) || (resume && controlled_state==7)),
 .key_end(1'b0),.project_switch(2'd0),.state(controlled_state));
always @(posedge clk) begin
 if(start)starts=starts+1;if(pause_set)pauses=pauses+1;
 if(resume)resumes=resumes+1;if(err)errors=errors+1;
end
task byte_out(input [7:0] b);
 begin
  @(negedge clk);rx=0;repeat(10)@(negedge clk);
  for(integer i=0;i<8;i=i+1)begin rx=b[i];repeat(10)@(negedge clk);end
  rx=1;repeat(10)@(negedge clk);
 end
endtask
task frame_out(input [7:0] cmd, value);
 begin byte_out(8'h55);byte_out(cmd);byte_out(value);byte_out(0);
 byte_out(255);byte_out(255);byte_out(255);repeat(5)@(negedge clk);end
endtask
initial begin
 repeat(4)@(negedge clk);rst=0;
 frame_out(8'h01,0);frame_out(8'h01,1);
 frame_out(8'h06,0);frame_out(8'h07,0);
 if(starts!=1 || pauses!=1 || resumes!=1 || errors!=1)$fatal(1,"RX actions/validation");
 wait(controlled_state==6);
 frame_out(8'h06,0);repeat(5)@(negedge clk);if(controlled_state!=7)$fatal(1,"Pause did not stop event");
 frame_out(8'h06,0);if(controlled_state!=7)$fatal(1,"Repeated pause resumed event");
 frame_out(8'h07,0);repeat(5)@(negedge clk);if(controlled_state!=6)$fatal(1,"Resume did not run event");
 frame_out(8'h07,0);if(controlled_state!=6)$fatal(1,"Repeated resume paused event");
 wait(frames>=3);
 frame_out(8'h30,1);wait(field==12);
 repeat(4000)@(negedge clk);if(transmitter.tx_state!=0 || transmitter.next_field!=12)$fatal(1,"Idle settings page refreshed without request");
 field=0;frame_out(8'h30,1);wait(field==12);
 repeat(5)@(negedge clk);field=0;fixture_volume=6;wait(field==12);
 frame_out(8'h30,2);wait(field==15);
 frame_out(8'h30,4);repeat(4000)@(negedge clk);
 if(transmitter.tx_state!=0 || tx!==1)$fatal(1,"Unsupported page must be idle");
 frame_out(8'h30,9);if(page!=4)$fatal(1,"Invalid page accepted");
 byte_out(8'h55);byte_out(8'h30);repeat(500)@(negedge clk);
 frame_out(8'h30,0);wait(frames>=19);
 $display("PASS named home/settings/game UART commands, page switching, pause/resume, malformed values and timeout recovery");$finish;
end
integer trailers=0;
initial begin
 wait(!rst);
 forever begin
  @(negedge tx);repeat(15)@(posedge clk);#1;
  for(integer b=0;b<8;b=b+1)begin received[b]=tx;if(b<7)begin repeat(10)@(posedge clk);#1;end end
  repeat(10)@(posedge clk);#1;if(tx!==1)$fatal(1,"Bad stop bit");
  if(received==255)trailers=trailers+1;
  else begin if(trailers!=0)$fatal(1,"Bad trailer");command={command,received};end
  if(trailers==3) begin
   if(command.substr(0,4)=="home.") begin
    if(command!="home.t_p.txt=\"5\"" && command!="home.t_m.txt=\"5\"" && command!="home.t_e.txt=\"OK\"")$fatal(1,"Bad home: %s",command);
   end else begin
    case(field)
     0:expected="settings.h_sharp.val=001";
     1:expected="settings.n_sharp.val=001";
     2:expected="settings.h_bright.val=050";
     3:expected="settings.n_bright.val=050";
     4:expected="settings.h_contrast.val=050";
     5:expected="settings.n_contrast.val=050";
     6:expected="settings.h_saturation.val=050";
     7:expected="settings.n_saturation.val=050";
     8:expected=fixture_volume==5?"settings.h_volume.val=063":"settings.h_volume.val=075";
     9:expected=fixture_volume==5?"settings.n_volume.val=063":"settings.n_volume.val=075";
     10:expected="settings.bt_invert.val=000";
     11:expected="settings.bt_vintage.val=001";
     12:expected="game.t4.txt=\"12:34\"";
     13:expected="game.t3.txt=\"12:34\"";
     14:expected="game.n_state.val=007";
     default:$fatal(1,"Unexpected field %0d: %s",field,command);
    endcase
    if(command!=expected)$fatal(1,"Expected %s received %s",expected,command);
    field=field+1;
   end
   frames=frames+1;command="";trailers=0;
  end
 end
end
initial begin #3000000;$fatal(1,"Timeout fields=%0d frames=%0d",field,frames);end
endmodule