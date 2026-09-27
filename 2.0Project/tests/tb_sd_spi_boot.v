`timescale 1ns/1ps
module tb_sd_spi_boot;
parameter integer DROP_CMD8=1;
reg clk=0; always #5 clk=~clk;
reg rst=1, miso=1, read_req=0;
wire cs,sck,mosi,done,valid,read_end;
wire [2:0] stage; wire [7:0] data;
sd_card_top #(.SPI_LOW_SPEED_DIV(2),.SPI_HIGH_SPEED_DIV(0)) dut(
 .clk(clk),.rst(rst),.SD_nCS(cs),.SD_DCLK(sck),.SD_MOSI(mosi),.SD_MISO(miso),
 .sd_init_done(done),.init_stage(stage),.sd_sec_read(read_req),.sd_sec_read_addr(32'd123),
 .sd_sec_read_data(data),.sd_sec_read_data_valid(valid),.sd_sec_read_end(read_end),
 .sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0));
integer bit_count=0,token_count=0,cmd_number=0,qread=0,qwrite=0;
integer cmd8_count=0,acmd_count=0,samples=0,cycles=0;
reg [7:0] rx=0,tx=8'hff,queue[0:2047];
task enqueue; input [7:0] b; begin queue[qwrite]=b;qwrite=qwrite+1;end endtask
always @(posedge cs) begin bit_count=0;token_count=0;qread=0;qwrite=0;rx=0;tx=8'hff;miso=1;end
always @(negedge sck) if(!cs) begin
 if(bit_count==0) begin
  tx=8'hff;
  if(qread<qwrite) begin tx=queue[qread];qread=qread+1;end
 end
 miso=tx[7-bit_count];
end
always @(posedge sck) if(!cs) begin
 rx={rx[6:0],mosi};
 if(bit_count==7) begin
  bit_count=0;
  if(token_count==0) begin
   if(rx[7:6]==2'b01) begin cmd_number=rx[5:0];token_count=1;end
  end else if(token_count==5) begin
   token_count=0;
   case(cmd_number)
    0: enqueue(8'h01);
    8: begin
     cmd8_count=cmd8_count+1;
     // First CMD8 is deliberately silent: exercise timeout plus real SPI retry.
     if(!DROP_CMD8 || cmd8_count>1) begin enqueue(1);enqueue(0);enqueue(0);enqueue(1);enqueue(8'haa);end
    end
    55:enqueue(1);
    41:begin acmd_count=acmd_count+1;enqueue(acmd_count<3 ? 1 : 0);end
    16:enqueue(0);
    17:begin
     enqueue(0);enqueue(8'hff);enqueue(8'hfe);
     for(integer k=0;k<512;k=k+1) enqueue(k[7:0]);
     enqueue(8'hff);enqueue(8'hff);
    end
    default:$fatal(1,"Unexpected SPI command %0d",cmd_number);
   endcase
  end else token_count=token_count+1;
 end else bit_count=bit_count+1;
end
always @(posedge clk) begin
 cycles=cycles+1;
 if(cycles>250000) $fatal(1,"Boot hang: stage=%0d CMD8=%0d ACMD41=%0d",stage,cmd8_count,acmd_count);
 if(valid) begin
  if(data!==samples[7:0]) $fatal(1,"Sector byte mismatch at %0d",samples);
  samples=samples+1;
 end
end
initial begin
 repeat(5) @(negedge clk);rst=0;
 wait(stage==4);@(negedge clk);read_req=1;
 wait(read_end);@(negedge clk);read_req=0;
 if(samples!=512 || cmd8_count!=(DROP_CMD8 ? 2 : 1) || acmd_count<3) $fatal(1,"Incomplete recovery/sector");
 $display("PASS physical SPI edges: silent CMD8 recovery, ACMD41 busy retries, CMD16 and 512-byte read (%0d clocks)",cycles);
 $finish;
end
endmodule
