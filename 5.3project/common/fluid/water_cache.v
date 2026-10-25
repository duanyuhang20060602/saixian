// Two RAM32K macros per 2048x32 bank. Registered address + synchronous read.
module water_cache #(parameter BANKS=5,TAIL_HALF=0)(input clk,
 input [13:0] ra,wa,input we,input [31:0] wd,output [31:0] rd);
reg [13:0] ra_q,wa_q;reg we_q;reg [31:0] wd_q;reg [2:0] select_q;
wire [31:0] q[0:BANKS-1];
always @(posedge clk)begin
 ra_q<=ra;wa_q<=wa;we_q<=we;wd_q<=wd;select_q<=ra_q[13:11];
end
genvar b,h;
generate for(b=0;b<BANKS;b=b+1)begin:bank
 if(TAIL_HALF && b==BANKS-1)begin:compact_tail
`ifdef WATER_SIM
  reg[31:0] mem[0:1023];reg[31:0] qr;
  always @(posedge clk)begin
   if(we_q && wa_q[13:11]==b)mem[wa_q[9:0]]<=wd_q;
   qr<=mem[ra_q[9:0]];
  end
  assign q[b]=qr;
`else
  EG_LOGIC_BRAM #(.DATA_WIDTH_A(32),.ADDR_WIDTH_A(10),.DATA_DEPTH_A(1024),
   .DATA_WIDTH_B(32),.ADDR_WIDTH_B(10),.DATA_DEPTH_B(1024),.BYTE_ENABLE(0),
   .MODE("PDPW"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
   .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("32K")) ram(
   .clka(clk),.rsta(1'b0),.cea(1'b1),.wea(we_q&&wa_q[13:11]==b),.ocea(1'b1),.bea(1'b0),
   .addra(wa_q[9:0]),.dia(wd_q),.doa(),
   .clkb(clk),.rstb(1'b0),.ceb(1'b1),.web(1'b0),.oceb(1'b1),.beb(1'b0),
   .addrb(ra_q[9:0]),.dib(32'd0),.dob(q[b]));
`endif
 end else begin:full_bank
 for(h=0;h<2;h=h+1)begin:half
`ifdef WATER_SIM
  reg [15:0] mem[0:2047];reg [15:0] qr;
  always @(posedge clk)begin
   if(we_q && wa_q[13:11]==b)mem[wa_q[10:0]]<=wd_q[h*16+:16];
   qr<=mem[ra_q[10:0]];
  end
  assign q[b][h*16+:16]=qr;
`else
  EG_PHY_BRAM32K #(.MODE("DP16K"),.DATA_WIDTH_A("16"),.DATA_WIDTH_B("16"),
   .REGMODE_A("NOREG"),.REGMODE_B("NOREG")) ram(
   .clka(clk),.rsta(1'b0),.csa(we_q&&wa_q[13:11]==b),.wea(1'b1),.ocea(1'b1),
   .addra(wa_q[10:0]),.dia(wd_q[h*16+:16]),.bytea(1'b0),.bytewea(1'b0),.doa(),
   .clkb(clk),.rstb(1'b0),.csb(1'b1),.web(1'b0),.oceb(1'b1),
   .addrb(ra_q[10:0]),.dib(16'd0),.byteb(1'b0),.byteweb(1'b0),.dob(q[b][h*16+:16]));
`endif
 end
end end endgenerate
assign rd=select_q<BANKS ? q[select_q]:32'd0;
endmodule

// 640 atomic four-pixel entries: 512 direct entries plus a 128-entry tail.
// The tail uses two byte-wide true-dual-port RAMs. Each receives one 32-bit
// word every two clocks and reads four bytes across the same two-clock slot.
// Native row ownership makes tail reads and tail writes mutually exclusive.
module water_native_cache(input clk,input[9:0] ra,input[10:0] wa,
 input we,input[31:0] wd,output[63:0] rd,input rst,read_valid);
reg[9:0] ra_q;reg[10:0] wa_q;reg we_q,tail_select;reg[31:0] wd_q;
always @(posedge clk)begin
 ra_q<=ra;wa_q<=wa;we_q<=we&&!rst;wd_q<=wd;tail_select<=ra_q[9];
end
wire[63:0] head_data,tail_data;
genvar h;
generate for(h=0;h<4;h=h+1)begin:lane
 wire selected=we_q&&!wa_q[10]&&(wa_q[0]!=(h/2));
`ifdef WATER_SIM
 reg[15:0] mem[0:511];reg[15:0] qr;
 always @(posedge clk)begin
  if(selected)mem[wa_q[9:1]]<=wd_q[(h%2)*16+:16];
  qr<=mem[ra_q[8:0]];
 end
 assign head_data[h*16+:16]=qr;
`else
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.ADDR_WIDTH_A(9),.DATA_DEPTH_A(512),
  .DATA_WIDTH_B(16),.ADDR_WIDTH_B(9),.DATA_DEPTH_B(512),.BYTE_ENABLE(0),
  .MODE("PDPW"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
  .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("9K")) ram(
  .clka(clk),.rsta(1'b0),.cea(1'b1),.wea(selected),.ocea(1'b1),.bea(1'b0),
  .addra(wa_q[9:1]),.dia(wd_q[(h%2)*16+:16]),.doa(),
  .clkb(clk),.rstb(1'b0),.ceb(1'b1),.web(1'b0),.oceb(1'b1),.beb(1'b0),
  .addrb(ra_q[8:0]),.dib(16'd0),.dob(head_data[h*16+:16]));
`endif
end endgenerate
reg read_pending;reg[6:0] saved_read;
reg write_pending,write_half;reg[6:0] saved_write;reg[15:0] saved_low;
wire tail_write=we_q&&wa_q[10];
always @(posedge clk)begin
 read_pending<=read_valid&&ra[9]&&!rst;
 if(read_valid) saved_read<=ra[6:0];
 write_pending<=tail_write&&!rst;
 if(tail_write)begin saved_write<=wa_q[7:1];saved_low<=wd_q[15:0];write_half<=wa_q[0];end
 if(rst)begin read_pending<=0;write_pending<=0;end
end
generate for(h=0;h<2;h=h+1)begin:tail
 wire first_write=tail_write&&(wa_q[0]==h);
 wire second_write=write_pending&&(write_half==h);
 wire write_port=first_write||second_write;
 wire[6:0] group_address=first_write ? wa_q[7:1]:second_write ? saved_write:read_pending ? saved_read:ra[6:0];
 wire second=second_write||(!first_write&&read_pending);
 wire[8:0] address_a={group_address,second,1'b0},address_b={group_address,second,1'b1};
 wire[15:0] write_data=first_write ? wd_q[31:16]:saved_low;
 wire[7:0] qa,qb;reg[15:0] first_read;
 always @(posedge clk)if(read_pending)first_read<={qa,qb};
`ifdef WATER_SIM
 reg[7:0] memory[0:511];reg[7:0] qra,qrb;
 always @(posedge clk)begin
  if(write_port)begin memory[address_a]<=write_data[15:8];memory[address_b]<=write_data[7:0];end
  qra<=memory[address_a];qrb<=memory[address_b];
 end
 assign qa=qra;assign qb=qrb;
 always @(posedge clk)if(!rst)begin
  if(first_write&&second_write)$fatal(1,"tail write slots overlap");
  if((read_pending||(read_valid&&ra[9]))&&write_port)$fatal(1,"tail read/write ownership collision");
 end
`else
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.ADDR_WIDTH_A(9),.DATA_DEPTH_A(512),
  .DATA_WIDTH_B(8),.ADDR_WIDTH_B(9),.DATA_DEPTH_B(512),.BYTE_ENABLE(0),
  .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
  .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("9K")) ram(
  .clka(clk),.rsta(1'b0),.cea(1'b1),.wea(write_port),.ocea(1'b1),.bea(1'b0),
  .addra(address_a),.dia(write_data[15:8]),.doa(qa),
  .clkb(clk),.rstb(1'b0),.ceb(1'b1),.web(write_port),.oceb(1'b1),.beb(1'b0),
  .addrb(address_b),.dib(write_data[7:0]),.dob(qb));
`endif
 assign tail_data[h==0 ? 63:31 -:32]={first_read,qa,qb};
end endgenerate
assign rd=tail_select ? tail_data:head_data;
endmodule
