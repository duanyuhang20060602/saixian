`timescale 1ns/1ps
module tb_sd_command_response;
reg clk=0;always #5 clk=~clk;
reg rst=1,req=0,spi_ack=0;
reg [7:0] returned=8'hFF;
wire ack,error,spi_req,cs;wire [7:0] sent;
integer scenario=0,cooldown=0,polls=0,headers=0,data_bytes=0,steps;
sd_card_cmd dut(.sys_clk(clk),.rst(rst),.spi_clk_div(16'd126),
 .cmd_req(req),.cmd_req_ack(ack),.cmd_req_error(error),
 .cmd(48'h08000001AA87),.cmd_r1(8'h01),.cmd_data_len(16'd4),
 .block_read_req(1'b0),.block_write_req(1'b0),.block_write_data(8'd0),
 .spi_wr_req(spi_req),.spi_wr_ack(spi_ack),.spi_data_in(sent),.spi_data_out(returned),.nCS_ctrl(cs));
always @(negedge clk) begin
 spi_ack=0;
 if(rst) cooldown=0;
 else if(cooldown>0) cooldown=cooldown-1;
 else if(spi_req) begin
  spi_ack=1;cooldown=3;returned=8'hFF;
  if(dut.state==dut.S_CMD) begin
   if(dut.byte_cnt<6) begin returned=8'h01;headers=headers+1;end
   else begin
    polls=polls+1;
    case(scenario)
     0:returned=polls==3 ? 8'h01 : 8'hFF;
     1:returned=8'h04;
     2:returned=8'hFF;
     3:returned=polls==64 ? 8'h01 : 8'hFF;
    endcase
   end
  end else if(dut.state==dut.S_CMD_DATA) begin
   returned=8'hAA;data_bytes=data_bytes+1;
  end
 end
end
task run_case;
 input integer which,expected_polls;
 input expected_error;
 begin
  @(posedge clk);#2;scenario=which;headers=0;polls=0;data_bytes=0;req=1;
  steps=0;
  while(!ack && steps<1000) begin @(posedge clk);#2;steps=steps+1;end
  if(!ack || error!==expected_error || headers!=6 || polls!=expected_polls)
   $fatal(1,"R1 case=%0d headers=%0d polls=%0d ack=%b error=%b",which,headers,polls,ack,error);
  if(!expected_error && data_bytes!=4) $fatal(1,"R7 payload truncated");
  req=0;repeat(5) @(posedge clk);
 end
endtask
initial begin
 repeat(3) @(posedge clk);#2;rst=0;
 wait(dut.state==dut.S_WAIT);
 run_case(0,3,0);run_case(1,1,1);run_case(2,64,1);run_case(3,64,0);
 $display("PASS SD R1: no premature command-header ACK, bounded retry, wrong response, last-poll success, R7 payload");
 $finish;
end
endmodule
