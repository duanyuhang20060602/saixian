`timescale 1ns/1ps
// A complete line is @0: followed by GB2312 text and CR/LF. Four slots.
module demo_uart #(parameter HZ=75000000,BAUD=115200)(input clk,rst,rx,input send,input[7:0] tx_data,output tx,output busy,output reg valid,output reg[7:0] data);
localparam D=(HZ+BAUD/2)/BAUD;
reg m,s,run;reg[15:0] count;reg[3:0] bitno;reg[7:0] bits;
reg[9:0] shift;reg[15:0] tc;reg[3:0] tn;reg tr;
assign tx=tr?shift[0]:1'b1;assign busy=tr;
always @(posedge clk)begin
 if(rst)begin m<=1;s<=1;run<=0;valid<=0;count<=0;bitno<=0;data<=0;bits<=0;tr<=0;shift<=1023;tc<=0;tn<=0;end
 else begin
 m<=rx;s<=m;valid<=0;
 if(!run)begin if(!s)begin run<=1;count<=D/2;bitno<=0;end end
 else if(count!=0)count<=count-1'b1;
 else begin count<=D-1;
 if(bitno==0)begin if(s)run<=0;else bitno<=1;end
 else if(bitno<=8)begin bits[bitno-1]<=s;bitno<=bitno+1'b1;end
 else begin run<=0;if(s)begin data<=bits;valid<=1;end end end
 if(!tr)begin if(send)begin shift<={1'b1,tx_data,1'b0};tr<=1;tc<=D-1;tn<=0;end end
 else if(tc!=0)tc<=tc-1'b1;
 else begin tc<=D-1;if(tn==9)tr<=0;else begin shift<={1'b1,shift[9:1]};tn<=tn+1'b1;end end
 end end
endmodule

module demo_text #(parameter HZ=75000000,HOLD_FRAMES=180,FONT_BASE=2209)(
 input clk,rst,byte_valid,input[7:0] byte_data,input initialized,
 output reg sd_read,output reg[31:0] sd_address,input sd_valid,input[7:0] sd_data,input sd_end,
 input frame_tick,input[11:0] x,input[10:0] y,output wire[23:0] rgb,
 output reg reply,output reg[7:0] reply_data,output reg font_ready,output reg fault,input[2:0] sd_init_stage,output reg[15:0] rx_count,output reg[7:0] rx_last,input[3:0] fs_error);
reg[2:0] parse;reg[1:0] edit_slot;reg[4:0] chars;reg high;reg[7:0] hb;reg bad;
reg[13:0] codes[0:15];reg request;reg[1:0] request_slot;reg[4:0] request_length;
reg[3:0] banks,pending;reg[4:0] lengths[0:3],next_length[0:3];
reg mark_blink;reg[15:0] edit_mask,request_mask;reg[15:0] flash_mask[0:3],next_mask[0:3];
reg[3:0] state;reg[8:0] pos;reg magic;reg[31:0] watch;
reg[1:0] loading_slot;reg[4:0] loading_length;reg[3:0] glyph;reg[8:0] begin_offset;
reg[7:0] first_byte;reg we;reg[10:0] wa;reg[15:0] wd;
reg[1:0] visible;reg[8:0] frames;reg[5:0] blink;
reg[15:0] good_count,error_count;reg[1:0] newest_slot;
wire[1:0] following1=visible+2'd1,following2=visible+2'd2,following3=visible+2'd3;
wire filled1=(pending[following1]?next_length[following1]:lengths[following1])!=0;
wire filled2=(pending[following2]?next_length[following2]:lengths[following2])!=0;
wire filled3=(pending[following3]?next_length[following3]:lengths[following3])!=0;
wire[1:0] next_visible=filled1?following1:filled2?following2:filled3?following3:visible;
integer i;
function[7:0] magic_at;input[2:0] a;begin case(a)0:magic_at="S";1:magic_at="X";2:magic_at="F";3:magic_at="O";4:magic_at="N";5:magic_at="T";6:magic_at="0";default:magic_at="1";endcase end endfunction
wire idle=state==3 && !request && !pending[edit_slot];
wire[7:0] zone=hb-8'ha1,point=byte_data-8'ha1;
wire[13:0] zone_ext={6'd0,zone};
wire[13:0] gb_index=14'd128+(zone_ext<<6)+(zone_ext<<5)-(zone_ext<<1)+point;
// One RAM32K: 4 text slots x 2 banks x 16 characters x 16 rows x 16 bits.
wire in_text=x>=128 && x<1152 && y>=300 && y<364;
wire[10:0] local_x=x-12'd128;wire[10:0] local_y=y-11'd300;
wire[3:0] column=local_x[5:2];wire[3:0] character=local_x[9:6];
wire[10:0] ra={visible,banks[visible],character,local_y[5:2]};
wire[15:0] q;
`ifdef DEMO_BEHAVIORAL
reg[15:0] memory[0:2047];reg[15:0] qr;
always @(posedge clk)begin if(we)memory[wa]<=wd;qr<=memory[ra];end
assign q=qr;
`else
EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.ADDR_WIDTH_A(11),.DATA_DEPTH_A(2048),.DATA_WIDTH_B(16),.ADDR_WIDTH_B(11),.DATA_DEPTH_B(2048),.MODE("PDPW"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("32K")) cache(
 .clka(clk),.cea(1'b1),.ocea(1'b0),.wea(we),.rsta(1'b0),.dia(wd),.addra(wa),.doa(),.bea(1'b0),
 .clkb(clk),.ceb(1'b1),.oceb(1'b0),.web(1'b0),.rstb(1'b0),.dib(16'd0),.addrb(ra),.dob(q),.beb(1'b0));
`endif
reg region;reg[3:0] col;reg[23:0] background;
wire diag_active;wire[23:0] diag_color;reg[23:0] text_rgb;
demo_diagnostics diagnostics(clk,x,y,font_ready,fault,lengths[visible]==0,visible,blink,initialized,sd_init_stage,rx_count,rx_last,good_count,error_count,fs_error,diag_active,diag_color);
assign rgb=diag_active?diag_color:text_rgb;
always @(posedge clk)begin
 region<=in_text && character<lengths[visible] && (!flash_mask[visible][character] || !blink[5]);col<=column;
 background<=24'h101b2e;
 text_rgb<=(region && q[15-col])?24'hffd166:background;
end
always @(posedge clk)begin
 if(rst)begin
 parse<=0;edit_slot<=0;chars<=0;high<=0;hb<=0;bad<=0;request<=0;request_slot<=0;request_length<=0;
 state<=0;pos<=0;magic<=0;sd_read<=0;sd_address<=FONT_BASE;watch<=0;font_ready<=0;fault<=0;
 loading_slot<=0;loading_length<=0;glyph<=0;begin_offset<=0;first_byte<=0;we<=0;wa<=0;wd<=0;
 banks<=0;pending<=0;visible<=0;frames<=0;blink<=0;reply<=0;reply_data<=0;
 mark_blink<=0;edit_mask<=0;request_mask<=0;
 rx_count<=0;rx_last<=0;
 good_count<=0;error_count<=0;newest_slot<=0;
 for(i=0;i<4;i=i+1)begin lengths[i]<=0;next_length[i]<=0;flash_mask[i]<=0;next_mask[i]<=0;end
 end else begin
 sd_read<=0;we<=0;reply<=0;request<=0;
 if(byte_valid)begin rx_count<=rx_count+1'b1;rx_last<=byte_data;end
 if(reply && reply_data=="K")good_count<=good_count+1'b1;
 if(reply && reply_data=="E")error_count<=error_count+1'b1;
 if(frame_tick)begin
 blink<=blink+1'b1;
 for(i=0;i<4;i=i+1)if(pending[i])begin banks[i]<=~banks[i];lengths[i]<=next_length[i];flash_mask[i]<=next_mask[i];pending[i]<=0;end
 if(pending[newest_slot] && next_length[newest_slot]!=0)begin visible<=newest_slot;frames<=0;end
 else if(frames==HOLD_FRAMES-1 || (pending[visible]?next_length[visible]:lengths[visible])==0)begin frames<=0;visible<=next_visible;end
 else frames<=frames+1'b1;
 end
 if(byte_valid && byte_data=="?" && parse==0)begin
 reply<=1;reply_data<=font_ready?"R":fault?"E":(initialized && sd_init_stage==4)?"H":8'd48+sd_init_stage;
 end else if(byte_valid)begin
 if(byte_data==10)begin end
 else if(byte_data==13)begin
 if(parse==3 && !bad && !high && !mark_blink && font_ready && idle)begin request<=1;request_slot<=edit_slot;request_length<=chars;request_mask<=edit_mask;end
 else begin reply<=1;reply_data<=8'h45;end
 parse<=0;chars<=0;high<=0;bad<=0;
 end else case(parse)
 0:if(byte_data=="@")parse<=1;
 1:if(byte_data>="0" && byte_data<="3")begin edit_slot<=byte_data[1:0];parse<=2;end else parse<=0;
 2:if(byte_data==":")begin parse<=3;chars<=0;high<=0;bad<=!idle;edit_mask<=0;mark_blink<=0;end else parse<=0;
 3:if(!bad)begin
 if(!idle)bad<=1;
 else if(high)begin
 high<=0;
 if(byte_data>=8'ha1 && byte_data<=8'hfe && chars<16)begin codes[chars[3:0]]<=gb_index;chars<=chars+1'b1;edit_mask[chars[3:0]]<=mark_blink;mark_blink<=0;end else bad<=1;
 end else if(byte_data=="^" && !mark_blink)mark_blink<=1;
 else if(byte_data>=8'ha1 && byte_data<=8'hfe)begin high<=1;hb<=byte_data;end
 else if(byte_data>=32 && byte_data<127 && chars<16)begin codes[chars[3:0]]<=byte_data;chars<=chars+1'b1;edit_mask[chars[3:0]]<=mark_blink;mark_blink<=0;end else bad<=1;
 end
 default:parse<=0;
 endcase
 end
 if(state!=0 && state!=3)begin if(watch==HZ*2)begin state<=15;fault<=1;reply<=1;reply_data<="E";end else watch<=watch+1'b1;end else watch<=0;
 case(state)
 0:if(initialized && sd_init_stage==4)begin sd_address<=FONT_BASE;sd_read<=1;pos<=0;magic<=1;state<=1;end
 1:begin
 if(sd_valid)begin if(pos<8 && sd_data!=magic_at(pos[2:0]))magic<=0;pos<=pos+1'b1;end
 if(sd_end)begin if(magic)begin font_ready<=1;state<=3;reply<=1;reply_data<="R";end else begin state<=15;fault<=1;reply<=1;reply_data<="E";end end
 end
 3:if(request)begin loading_slot<=request_slot;loading_length<=request_length;glyph<=0;next_mask[request_slot]<=request_mask;
 if(request_length==0)begin next_length[request_slot]<=0;pending[request_slot]<=1;newest_slot<=request_slot;reply<=1;reply_data<="K";end else state<=4;end
 4:begin sd_address<=FONT_BASE+1+{22'd0,codes[glyph][13:4]};begin_offset<={codes[glyph][3:0],5'd0};pos<=0;sd_read<=1;state<=5;end
 5:begin
 if(sd_valid)begin
 if(pos>=begin_offset && {1'b0,pos}<{1'b0,begin_offset}+10'd32)begin
 if(!pos[0])first_byte<=sd_data;
 else begin we<=1;wa<={loading_slot,!banks[loading_slot],glyph,pos[4:1]};wd<={first_byte,sd_data};end end
 pos<=pos+1'b1;
 end
 if(sd_end)begin if({1'b0,glyph}+5'd1==loading_length)state<=6;else begin glyph<=glyph+1'b1;state<=4;end end
 end
 6:begin next_length[loading_slot]<=loading_length;pending[loading_slot]<=1;newest_slot<=loading_slot;reply<=1;reply_data<="K";state<=3;end
 default:;
 endcase
 if(fs_error!=0)begin state<=15;fault<=1;font_ready<=0;if(!fault)begin reply<=1;reply_data<="E";end end
 end end
endmodule
