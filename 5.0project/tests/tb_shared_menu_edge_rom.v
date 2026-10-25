`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg[9:0]address=0;reg[6:0]edge_address=0;wire[7:0]data,old_data,edge_weight;
reg[7:0]expected_weights[0:127];integer a,b,checks=0;
photo_menu_text_lookup #(.SHARED_EDGE_WEIGHT(1)) dut(.clk(clk),.address(address),.data(data),.edge_address(edge_address),.edge_weight(edge_weight));
photo_menu_text_lookup_before reference(.clk(clk),.address(address),.data(old_data));
initial begin
 $readmemh("edge_weights.hex",expected_weights);
 for(a=0;a<1024;a=a+1)for(b=0;b<128;b=b+1)begin
  @(negedge clk);address=a;edge_address=b;@(posedge clk);#1;
  if(data!==old_data || edge_weight!==expected_weights[b])$fatal(1,"packed ROM mismatch text=%d edge=%d got=%h/%h old=%h/%h",a,b,data,edge_weight,old_data,expected_weights[b]);
  checks=checks+1;
 end
 $display("PASS shared ROM: %0d simultaneous menu/edge address pairs; all 1024 original menu bytes and 128 coefficients, reserved slot zero masking and exact one-clock reads",checks);$finish;
end
endmodule
