// Vendor controller: four consecutive, aligned words form one SDR burst.
// A RAM that accepts unrelated addresses every clock masks this violation.
module sdram_contract(input clk,rst,en,input[20:0] address);
reg[1:0] phase=0;reg[20:0] start_addr;
always @(posedge clk)begin
 if(rst)phase<=0;
 else if(en)begin
  if(phase==0)begin
   if(address[1:0]!=0)$fatal(1,"SDRAM burst starts unaligned: %0d",address);
   start_addr<=address;
  end else if(address!==start_addr+phase)
   $fatal(1,"SDRAM burst changed address: phase%0d address%0d expected%0d",phase,address,start_addr+phase);
  phase<=phase+1'b1;
 end else if(phase!=0)$fatal(1,"SDRAM burst interrupted after %0d words",phase);
end
endmodule
