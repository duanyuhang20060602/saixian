// One outstanding, acknowledged bundle. The source holds the whole bundle
// until the destination consumes it; synchronized toggles carry ownership.
module photo_font_mailbox #(parameter W=32)(
 input source_clk,source_rst,input source_valid,input[W-1:0] source_data,output source_ready,
 input destination_clk,destination_rst,output destination_valid,output[W-1:0] destination_data,input destination_ready);
reg[W-1:0] held;reg request_toggle,acknowledge_toggle,ack_seen;
(* async_reg="true" *)reg ack_meta,ack_sync,request_meta,request_sync;
wire ack_event=ack_sync!=ack_seen;
assign source_ready=request_toggle==ack_sync && !ack_event;
assign destination_valid=request_sync!=acknowledge_toggle;
assign destination_data=held;
always @(posedge source_clk or posedge source_rst)begin
 if(source_rst)begin held<=0;request_toggle<=0;ack_seen<=0;ack_meta<=0;ack_sync<=0;end
 else begin
  ack_meta<=acknowledge_toggle;ack_sync<=ack_meta;ack_seen<=ack_sync;
  if(source_valid && source_ready)begin held<=source_data;request_toggle<=!request_toggle;end
 end
end
always @(posedge destination_clk or posedge destination_rst)begin
 if(destination_rst)begin request_meta<=0;request_sync<=0;acknowledge_toggle<=0;end
 else begin
  request_meta<=request_toggle;request_sync<=request_meta;
  if(destination_valid && destination_ready)acknowledge_toggle<=request_sync;
 end
end
endmodule

// Keep the shared SD PHY/client at 100 MHz. Run only the low-rate FAT address
// calculations on the board's existing 50 MHz memory clock. Register every
// bundle at each receiving boundary; no clock or timing exception is added.
module photo_font_file_b #(parameter SLOW_HZ=50000000,ADDR_BITS=27,SLOW_CLIENT=0)(
 input clk,rst,slow_clk,slow_rst,card_ready,input request,input[31:0] address,
 output valid,output[7:0] data,output finish,output[3:0] error,
 output read_sector,output[31:0] sector,input byte_valid,input[7:0] byte_data,input sector_end);
wire request_ready,request_slow;wire[31:0] address_slow;
generate if(SLOW_CLIENT)begin:native_client
 assign request_ready=1'b1;assign request_slow=request;assign address_slow=address;
end else begin:fast_client
wire request_valid_slow;wire[31:0] address_bundle;
reg request_q;reg[31:0] address_q;
photo_font_mailbox #(.W(32)) virtual_request(
 .source_clk(clk),.source_rst(rst),.source_valid(request),.source_data(address),.source_ready(request_ready),
 .destination_clk(slow_clk),.destination_rst(slow_rst),.destination_valid(request_valid_slow),.destination_data(address_bundle),.destination_ready(1'b1));
always @(posedge slow_clk or posedge slow_rst)
 if(slow_rst)begin request_q<=0;address_q<=0;end
 else begin request_q<=request_valid_slow;if(request_valid_slow)address_q<=address_bundle;end
assign request_slow=request_q;assign address_slow=address_q;
end endgenerate

wire sector_request_slow,sector_ready,sector_valid_fast;wire[31:0] sector_slow,sector_bundle;
reg read_fast;reg[31:0] sector_fast;
photo_font_mailbox #(.W(32)) physical_request(
 .source_clk(slow_clk),.source_rst(slow_rst),.source_valid(sector_request_slow),.source_data(sector_slow),.source_ready(sector_ready),
 .destination_clk(clk),.destination_rst(rst),.destination_valid(sector_valid_fast),.destination_data(sector_bundle),.destination_ready(1'b1));
always @(posedge clk or posedge rst)
 if(rst)begin read_fast<=0;sector_fast<=0;end
 else begin read_fast<=sector_valid_fast;if(sector_valid_fast)sector_fast<=sector_bundle;end
assign read_sector=read_fast;assign sector=sector_fast;

// SD produces at most one byte per 16 system clocks (the current PHY uses
// 32). Queue a coincident sector end behind its last byte, rather than
// allowing two closely spaced toggle events to cancel one another.
reg byte_queued,end_queued,fast_overflow;reg[9:0] queued_byte;
wire byte_ready,byte_valid_slow;wire[9:0] byte_bundle;
photo_font_mailbox #(.W(10)) physical_bytes(
 .source_clk(clk),.source_rst(rst),.source_valid(byte_queued),.source_data(queued_byte),.source_ready(byte_ready),
 .destination_clk(slow_clk),.destination_rst(slow_rst),.destination_valid(byte_valid_slow),.destination_data(byte_bundle),.destination_ready(1'b1));
always @(posedge clk or posedge rst)begin
 if(rst)begin byte_queued<=0;end_queued<=0;queued_byte<=0;fast_overflow<=0;end
 else begin
  if(byte_queued && byte_ready)byte_queued<=0;
  if(!byte_queued && end_queued)begin byte_queued<=1;queued_byte<=10'b0100000000;end_queued<=0;end
  if(sector_end)end_queued<=1;
  if(request && !request_ready)fast_overflow<=1;
  if(byte_valid)begin
   if(byte_queued && !byte_ready)fast_overflow<=1;
   byte_queued<=1;queued_byte<={2'b10,byte_data};
  end
 end
end

(* async_reg="true" *)reg card_meta,card_sync;
reg slow_overflow;
wire file_valid_slow,file_finish_slow;wire[7:0] file_data_slow;wire[3:0] file_error_slow;
always @(posedge slow_clk or posedge slow_rst)
 if(slow_rst)begin card_meta<=0;card_sync<=0;slow_overflow<=0;end
 else begin card_meta<=card_ready;card_sync<=card_meta;if(sector_request_slow && !sector_ready)slow_overflow<=1;end
photo_font_fat #(.HZ(SLOW_HZ),.ADDR_BITS(ADDR_BITS)) mapper(
 .clk(slow_clk),.rst(slow_rst),.card_ready(card_sync),.request(request_slow),.address(address_slow),
 .valid(file_valid_slow),.data(file_data_slow),.finish(file_finish_slow),.error(file_error_slow),
 .read_sector(sector_request_slow),.sector(sector_slow),.byte_valid(byte_valid_slow && byte_bundle[9]),
 .byte_data(byte_bundle[7:0]),.sector_end(byte_valid_slow && byte_bundle[8]));

// Filter metadata bytes in the FAT domain, then transfer one-clock pulses
// back as levels spanning two fast clock periods, with stable byte storage.
reg file_valid_q,file_finish_q;reg[7:0] file_data_q;
always @(posedge slow_clk or posedge slow_rst)
 if(slow_rst)begin file_valid_q<=0;file_finish_q<=0;file_data_q<=0;end
 else begin file_valid_q<=file_valid_slow;file_finish_q<=file_finish_slow;if(file_valid_slow)file_data_q<=file_data_slow;end
(* async_reg="true" *)reg[1:0] valid_sync,finish_sync,error_sync;
reg valid_seen,finish_seen,valid_fast,finish_fast;reg[7:0] data_fast;
wire valid_event=valid_sync[1] && !valid_seen;
wire finish_event=finish_sync[1] && !finish_seen;
always @(posedge clk or posedge rst)begin
 if(rst)begin valid_sync<=0;finish_sync<=0;error_sync<=0;valid_seen<=0;finish_seen<=0;valid_fast<=0;finish_fast<=0;data_fast<=0;end
 else begin
  valid_sync<={valid_sync[0],file_valid_q};finish_sync<={finish_sync[0],file_finish_q};
  error_sync<={error_sync[0],(|file_error_slow) || slow_overflow};valid_seen<=valid_sync[1];finish_seen<=finish_sync[1];
  valid_fast<=valid_event;finish_fast<=finish_event;if(valid_event)data_fast<=file_data_q;
 end
end
generate if(SLOW_CLIENT)begin:native_response
 (* async_reg="true" *)reg overflow_meta,overflow_sync;
 always @(posedge slow_clk or posedge slow_rst)
  if(slow_rst)begin overflow_meta<=0;overflow_sync<=0;end
  else begin overflow_meta<=fast_overflow;overflow_sync<=overflow_meta;end
 assign valid=file_valid_slow;assign data=file_data_slow;assign finish=file_finish_slow;
 assign error={3'd0,((|file_error_slow) || slow_overflow || overflow_sync)};
end else begin:fast_response
 assign valid=valid_fast;assign data=data_fast;assign finish=finish_fast;
 assign error={3'd0,(error_sync[1] || fast_overflow)};
end endgenerate
endmodule
