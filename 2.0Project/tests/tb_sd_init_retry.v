`timescale 1ns/1ps
module tb_sd_init_retry;
reg clk=0;always #5 clk=~clk;
reg rst=1,ack=0,error=0;
wire req,done;wire [47:0] cmd;wire [15:0] div;
sd_card_sec_read_write #(.SPI_LOW_SPEED_DIV(126),.SPI_HIGH_SPEED_DIV(2)) dut(
 .clk(clk),.rst(rst),.sd_init_done(done),.cmd_req(req),.cmd_req_ack(ack),
 .cmd_req_error(error),.cmd(cmd),.spi_clk_div(div),
 .sd_sec_read(1'b0),.sd_sec_write(1'b0),.sd_sec_read_addr(32'd0),
 .sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),
 .block_read_valid(1'b0),.block_read_data(8'd0),.block_read_req_ack(1'b0),
 .block_write_data_rd(1'b0),.block_write_req_ack(1'b0));
task reply;
 input [7:0] number;input fail;
 begin
  wait(req && cmd[47:40]==number);
  repeat(3) @(negedge clk);
  if(done || div!=126) $fatal(1,"initialized or accelerated before CMD16 completion");
  ack=1;error=fail;@(negedge clk);ack=0;error=0;
  if(fail && req) $fatal(1,"retry request was not released");
  repeat(3) @(negedge clk);
 end
endtask
initial begin
 repeat(3) @(negedge clk);rst=0;
 reply(0,0);reply(8,0);reply(55,0);reply(41,1);
 reply(55,0);reply(41,1);reply(55,0);reply(41,0);
 wait(req && cmd[47:40]==16);
 repeat(5) @(negedge clk);
 if(done || div!=126) $fatal(1,"CMD16 readiness gate missing");
 ack=1;@(negedge clk);ack=0;
 if(!done || div!=2) $fatal(1,"CMD16 completion not published");
 $display("PASS SD initialization: ACMD41 idle retries, request release, low-speed CMD16, no premature ready");
 $finish;
end
initial begin #100000;$fatal(1,"initialization handshake timeout");end
endmodule
