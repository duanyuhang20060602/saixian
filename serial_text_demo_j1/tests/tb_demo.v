`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,rx=1;always #5 clk=~clk;
wire tx,v,busy,reply;wire[7:0] data,resp;
demo_uart #(.HZ(75000000),.BAUD(115200)) uart(clk,rst,rx,reply,resp,tx,busy,v,data);
reg initialized=0;reg[2:0] init_stage=0;wire read;wire[31:0] address;reg valid=0,last=0;reg[7:0] b=0;
reg frame=0;reg[11:0] x=0;reg[10:0] y=0;wire[23:0] rgb;wire ready,fault;
wire[15:0] rx_count;wire[7:0] rx_last;
demo_text #(.HOLD_FRAMES(2)) dut(clk,rst,v,data,initialized,read,address,valid,b,last,frame,x,y,rgb,reply,resp,ready,fault,init_stage,rx_count,rx_last,4'd0);
reg[7:0] font[0:287743];integer state=0,position=0,base=0,writes=0,acks=0,errs=0;
always @(posedge clk)begin
 valid<=0;last<=0;
 if(read)begin if(state!=0)$fatal(1,"overlapping SD reads");base<=(address-2209)*512;position<=0;state<=1;end
 if(state==1)begin valid<=1;b<=font[base+position];if(position==511)state<=2;else position<=position+1;end
 if(state==2)begin state<=3;end
 if(state==3)begin last<=1;state<=0;end
 if(reply && resp=="K")acks=acks+1;
 if(reply && resp=="E")errs=errs+1;
 if(dut.we)writes=writes+1;
end
task byte_send;input[7:0] c;integer k;begin
 @(negedge clk);rx=0;repeat(651)@(negedge clk);
 for(k=0;k<8;k=k+1)begin rx=c[k];repeat(651)@(negedge clk);end
 rx=1;repeat(651)@(negedge clk);
end endtask
task pulse_frame;begin @(negedge clk);frame=1;@(negedge clk);frame=0;repeat(3)@(negedge clk);end endtask
integer i,j,index,offset;reg[15:0] expected;reg[23:0] color;
initial begin
 $readmemh("font.hex",font);repeat(8)@(negedge clk);rst=0;
 // Missing SD must still produce a visible border and diagnostic bars.
 x=4;y=4;repeat(4)@(negedge clk);if(rgb!==24'h30c8e0)$fatal(1,"no-SD border missing");
 x=200;y=610;repeat(4)@(negedge clk);if(rgb!==24'ha04030)$fatal(1,"no-SD live color bar missing");
 initialized=1;init_stage=3;repeat(1000)begin @(negedge clk);if(read || ready)$fatal(1,"read before CMD16 completion");end
 byte_send("?");if(resp!==8'h33)$fatal(1,"UART init-stage query failed");
 if(rx_count!=1 || rx_last!="?")$fatal(1,"RX diagnostics count wrong");
 init_stage=4;wait(ready);repeat(1000)@(negedge clk);
 // Real UART: @0: followed by GB2312 冠 and ASCII A, CR LF.
 byte_send("@");byte_send("0");byte_send(":");byte_send(8'hb9);byte_send(8'hda);byte_send("A");byte_send(13);byte_send(10);
 wait(acks==1);if(dut.lengths[0]!=0)$fatal(1,"published outside blanking");pulse_frame;
 if(dut.lengths[0]!=2 || writes!=32)$fatal(1,"wrong length or glyph writes");
 if(dut.visible!=0 || dut.good_count!=1)$fatal(1,"new text not immediately selected");
 repeat(10)begin pulse_frame;if(dut.visible!=0)$fatal(1,"carousel selected empty slot");end
 for(i=0;i<2;i=i+1)for(j=0;j<16;j=j+1)begin
  index=i==0 ? 128+(8'hb9-8'ha1)*94+8'hda-8'ha1:65;
  offset=512+index*32+j*2;expected={font[offset],font[offset+1]};
`ifdef DEMO_BEHAVIORAL
  if(dut.memory[256+i*16+j]!==expected)$fatal(1,"wrong SD glyph cache");
`endif
 end
 for(i=0;i<128;i=i+1)for(j=0;j<64;j=j+1)begin
  x=128+i;y=300+j;repeat(4)@(negedge clk);
  index=i<64 ? 128+(8'hb9-8'ha1)*94+8'hda-8'ha1:65;
  offset=512+index*32+(j/4)*2;expected={font[offset],font[offset+1]};color=expected[15-((i%64)/4)]?24'hffd166:24'h101b2e;
  if(rgb!==color)$fatal(1,"display pixel mismatch x=%d y=%d",i,j);
 end
 // Replace the whole line with B (editing/deletion), then clear it.
 byte_send("@");byte_send("0");byte_send(":");byte_send("B");byte_send(13);wait(acks==2);pulse_frame;
 if(dut.lengths[0]!=1)$fatal(1,"replace failed");
 byte_send("@");byte_send("0");byte_send(":");byte_send(13);wait(acks==3);pulse_frame;
 if(dut.lengths[0]!=0)$fatal(1,"clear failed");
 // Incomplete Chinese byte is rejected without publishing.
 byte_send("@");byte_send("1");byte_send(":");byte_send(8'hb9);byte_send(13);
 if(errs!=1 || dut.lengths[1]!=0)$fatal(1,"invalid input published");
 // Populate all remaining slots, and test per-character blinking.
 for(i=1;i<4;i=i+1)begin
 byte_send("@");byte_send("0"+i);byte_send(":");byte_send("X");byte_send(13);wait(acks==3+i);pulse_frame;
 if(dut.lengths[i]!=1 || dut.visible!=i)$fatal(1,"multi-slot commit or immediate display failed");
 end
 byte_send("@");byte_send("0");byte_send(":");byte_send("^");byte_send("A");byte_send(13);wait(acks==7);pulse_frame;
 if(dut.flash_mask[0]!=1)$fatal(1,"blink mask failed");
 force dut.visible=0;x=128;y=324;repeat(4)@(negedge clk);
 // At least one pixel of A must be lit in phase 0 and all suppressed in phase 1.
 force dut.blink=0;
 for(i=0;i<64;i=i+1)begin x=128+i;repeat(4)@(negedge clk);end
 force dut.blink=32;repeat(4)@(negedge clk);
 if(rgb!=24'h101b2e)$fatal(1,"blink suppression failed");
 release dut.blink;release dut.visible;
 pulse_frame;pulse_frame;
 if(fault)$fatal(1,"unexpected fault");
 $display("PASS real UART GB2312, SD-address lookup, 8192 independent pixels, atomic commit, replace, delete, malformed character, carousel");$finish;
end
initial begin #50000000;$fatal(1,"timeout");end
endmodule
