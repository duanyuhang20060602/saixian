`timescale 1ns/1ps
module tb_award_catalog_v3;
reg clk=0;always #5 clk=~clk;
reg rst=1,scan=0,valid=0,last=0;reg [7:0] data=0;
wire req,done,found,dlt,audio;wire [31:0] address;wire [2:0] total;
integer n,j,photos=0,awards=0,songs=0;reg [7:0] fixture[0:511];
bmp_read dut(.high_color(1'b0),.clk(clk),.rst(rst),.op_abort(1'b0),.scan_start(scan),.scan_stop(1'b0),.scan_resume(1'b0),
 .scan_start_sector(32'd0),.scan_max_sector(32'd21),.scan_target_count(3'd6),.scan_done(done),
 .scan_found_valid(found),.scan_found_dlt(dlt),.scan_found_total(total),.audio_found_valid(audio),
 .load_start(1'b0),.load_sector(32'd0),.sd_init_done(1'b1),.bmp_width(16'd1280),.bmp_height(16'd720),.write_req_ack(1'b0),
 .sd_sec_read(req),.sd_sec_read_addr(address),.sd_sec_read_data(data),.sd_sec_read_data_valid(valid),.sd_sec_read_end(last));
always @(negedge clk)begin
 if(found)begin if(dlt)awards=awards+1;else photos=photos+1;end
 if(audio)songs=songs+1;
end
initial begin
 $readmemh("tests/results/dlt_catalog_header.hex",fixture);
 repeat(4)@(negedge clk);rst=0;scan=1;@(negedge clk);scan=0;
 while(!done)begin
  wait(req || done);
  if(!done)begin
   n=address;
   for(j=0;j<512;j=j+1)begin
    @(negedge clk);valid=1;data=0;
    if(n<10 && n%2==0)case(j)
     0:data="S";1:data="X";2:data="A";3:data="U";4:data="D";5,6:data="0";7:data="1";
     8:data=4;12:data=8'h80;13:data=8'hbb;16:data=16;18:data=2;
    endcase
    else if(n>=10 && n<18)case(j)
     0:data="B";1:data="M";3:data=2;10:data=54;14:data=40;
     19:data=5;22:data=8'hd0;23:data=2;26:data=1;28:data=24;
    endcase
    else if(n==18)data=fixture[j];
   end
   @(negedge clk);valid=0;last=1;@(negedge clk);last=0;
   wait(!req);repeat(5)@(negedge clk);
  end
 end
 repeat(5)@(negedge clk);
 if(photos!=6 || total!=6 || songs!=5 || awards!=1)$fatal(1,"catalogue photos=%d total=%d audio=%d awards=%d",photos,total,songs,awards);
 $display("PASS five AUD plus eight BMP preceding DLT: six photos retained and independent DLT still discovered");$finish;
end
initial begin #1000000;$fatal(1,"catalogue timeout");end
endmodule
