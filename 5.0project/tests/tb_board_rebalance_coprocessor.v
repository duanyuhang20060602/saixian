`timescale 1ns/1ps
module tb;
reg clk=0,sc=0,lc=0;always #10 clk=~clk;always #5 sc=~sc;always #20 lc=~lc;
reg rst=1,start=0,abort=0,tv=0,active=0,query=0;reg [19:0] ti=0;reg [31:0] td=0,descriptor=0;reg [8:0] ra=0;
wire ready;wire [31:0] response,data;
reg [31:0] palettes[0:6143],queries[0:47],gold[0:18431];integer i,j,q,count;
photo_relief_coprocessor_b dut(.link_clk(lc),.link_rst(rst),.relief_start(start),.relief_abort(abort),.tap_valid(tv),.tap_index(ti),.tap_data(td),
 .clk(clk),.rst(rst),.spi_clk(sc),.spi_rst(rst),.packet_active(active),.request_valid(query),.request_descriptor(descriptor),.read_address(ra),
 .response_valid(ready),.response_descriptor(response),.response_data(data));
initial begin
 $readmemh("raw_palettes.hex",palettes);$readmemh("queries.hex",queries);$readmemh("tables_expected.hex",gold);
 repeat(6)@(negedge lc);rst=0;start=1;@(negedge lc);start=0;
 for(i=0;i<6144;i=i+1)begin tv=1;ti=460864+i;td=palettes[i];@(negedge lc);if(i%7==0)begin tv=0;@(negedge lc);end end
 tv=0;repeat(8)@(negedge clk);if(!dut.loaded_sync)$fatal(1,"raw palette not captured");
 for(q=0;q<48;q=q+1)begin
  @(negedge sc);descriptor=queries[q];query=1;@(negedge sc);query=0;
  count=0;while(!ready || response!=queries[q])begin @(negedge sc);count=count+1;if(count>20000)$fatal(1,"B result timeout");end
  // Hold a packet open while a new query is computed: published data is immutable.
  active=1;
  for(j=0;j<384;j=j+1)begin ra=j;repeat(4)@(negedge sc);
   if(data!==gold[q*384+j])$fatal(1,"B table q=%0d index=%0d %h/%h",q,j,data,gold[q*384+j]);
  end
  active=0;repeat(6)@(negedge sc);
 end
 // A new asset invalidates every result, including a partly captured asset.
 @(negedge lc);start=1;@(negedge lc);start=0;repeat(10)@(negedge sc);if(ready)$fatal(1,"stale result after reload");
 @(negedge lc);abort=1;@(negedge lc);abort=0;repeat(10)@(negedge sc);if(ready)$fatal(1,"aborted palette published");
 $display("PASS 6144 palette words across mixed 32K/9K boundaries, 48 exact complete tables, asynchronous clocks, reload and abort");$finish;
end
initial begin #20000000;$fatal(1,"coprocessor timeout");end
endmodule
