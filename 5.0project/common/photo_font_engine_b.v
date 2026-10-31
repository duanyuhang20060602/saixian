// The UART bridge and shared SD PHY stay at 100 MHz. Glyph lookup/cache
// runs on the existing 50 MHz memory clock; acknowledged bundles own data.
module photo_font_engine_b #(parameter FAST_HZ=100000000,SLOW_HZ=50000000,HOLD_CYCLES=150000000)(
 input fast_clk,fast_rst,clk,rst,tick,input[31:0] session,
 input received,input[159:0] incoming,output pending,output[159:0] message,input sent,boot_ready,
 input card_ready,output font_ready,font_fault,
 output read_sector,output[31:0] sector,input byte_valid,input[7:0] byte_data,input sector_end);
reg tick_toggle;
always @(posedge fast_clk or posedge fast_rst)
 if(fast_rst)tick_toggle<=0;else if(tick)tick_toggle<=!tick_toggle;
(* async_reg="true" *)reg tick_meta,tick_sync,card_meta,card_sync;
reg tick_seen;
(* async_reg="true" *)reg[31:0] session_meta,session_sync;
always @(posedge clk or posedge rst)
 if(rst)begin tick_meta<=0;tick_sync<=0;tick_seen<=0;card_meta<=0;card_sync<=0;session_meta<=0;session_sync<=0;end
 else begin tick_meta<=tick_toggle;tick_sync<=tick_meta;tick_seen<=tick_sync;
  card_meta<=card_ready;card_sync<=card_meta;session_meta<=session;session_sync<=session_meta;end
wire slow_tick=tick_sync!=tick_seen;
// A new session discards queued words, then allows the loader's existing
// replay logic to restart at word 128. Stored user strings remain intact.
reg[31:0] session_seen;reg session_changed;
always @(posedge fast_clk or posedge fast_rst)
 if(fast_rst)begin session_seen<=0;session_changed<=0;end
 else begin session_seen<=session;session_changed<=session!=session_seen;end
wire flush=fast_rst || rst || session_changed;
(* async_reg="true" *)reg[3:0] slow_reset_pipe;
(* async_reg="true" *)reg[1:0] fast_reset_pipe;
always @(posedge clk or posedge flush)
 if(flush)slow_reset_pipe<=4'b1111;else slow_reset_pipe<={slow_reset_pipe[2:0],1'b0};
always @(posedge fast_clk or posedge flush)
 if(flush)fast_reset_pipe<=2'b11;else fast_reset_pipe<={fast_reset_pipe[0],1'b0};
wire slow_queue_rst=slow_reset_pipe[3],fast_queue_rst=fast_reset_pipe[1];

wire line_valid,line_ready,line_source_ready,line_destination_valid,loader_ready;
wire[255:0] line,line_bundle;
(* async_reg="true" *)reg ready_meta,ready_sync;
always @(posedge fast_clk or posedge fast_rst)
 if(fast_rst)begin ready_meta<=0;ready_sync<=0;end
 else begin ready_meta<=loader_ready;ready_sync<=ready_meta;end
assign line_ready=ready_sync && line_source_ready && !fast_queue_rst;
photo_font_mailbox #(.W(256)) line_queue(
 .source_clk(fast_clk),.source_rst(fast_queue_rst),.source_valid(line_valid && line_ready),
 .source_data(line),.source_ready(line_source_ready),.destination_clk(clk),.destination_rst(slow_queue_rst),
 .destination_valid(line_destination_valid),.destination_data(line_bundle),.destination_ready(loader_ready));

wire word_pending,word_ack,word_source_ready,word_destination_valid;
wire[7:0] generation,index;wire[4:0] length;wire[31:0] data;wire[15:0] mask;
wire[68:0] word_bundle;
wire[15:0] key={generation,index};
reg[15:0] observed_key,queued_key;reg observed_valid,queued_valid,word_active;reg[1:0] settle;
wire word_source_valid=word_pending && observed_valid && key==observed_key && settle==0 &&
 (!queued_valid || key!=queued_key);
wire loader_ack=word_active && word_source_ready;
always @(posedge clk or posedge slow_queue_rst)
 if(slow_queue_rst)begin observed_key<=0;queued_key<=0;observed_valid<=0;queued_valid<=0;word_active<=0;settle<=3;end
 else begin
  // The first SEND follows the final cache write. Generation/index have
  // already been stable throughout the load, so key changes alone cannot
  // guard this first synchronous RAM read. Re-arm on entry to every SEND.
  if(!word_pending)begin observed_valid<=0;settle<=3;end
  else if(!observed_valid || key!=observed_key)begin observed_key<=key;observed_valid<=1;settle<=3;end
  else if(settle!=0)settle<=settle-1'b1;
  if(word_source_valid && word_source_ready)begin queued_key<=key;queued_valid<=1;word_active<=1;end
  if(loader_ack)word_active<=0;
 end
photo_font_mailbox #(.W(69)) glyph_queue(
 .source_clk(clk),.source_rst(slow_queue_rst),.source_valid(word_source_valid),
 .source_data({generation,index,length,data,mask}),.source_ready(word_source_ready),
 .destination_clk(fast_clk),.destination_rst(fast_queue_rst),.destination_valid(word_destination_valid),
 .destination_data(word_bundle),.destination_ready(word_ack));
reg word_fast;reg[7:0] generation_fast,index_fast;reg[4:0] length_fast;
reg[31:0] data_fast;reg[15:0] mask_fast;
always @(posedge fast_clk or posedge fast_queue_rst)
 if(fast_queue_rst)begin word_fast<=0;generation_fast<=0;index_fast<=0;length_fast<=0;data_fast<=0;mask_fast<=0;end
 else begin word_fast<=word_destination_valid;
  if(word_destination_valid){generation_fast,index_fast,length_fast,data_fast,mask_fast}<=word_bundle;end
photo_text_bridge_b #(.HZ(FAST_HZ)) bridge(
 .clk(fast_clk),.rst(fast_rst),.session(session),.received(received),.incoming(incoming),
 .pending(pending),.message(message),.sent(sent),.line_valid(line_valid),.line(line),.line_ready(line_ready),
 .word_pending(word_fast && boot_ready),.generation(generation_fast),.index(index_fast),.length(length_fast),
 .data(data_fast),.mask(mask_fast),.word_ack(word_ack),.tick(tick));

wire request,valid,finish;wire[31:0] address;wire[7:0] file_byte;wire[3:0] file_error;
photo_text_font_b #(.HZ(SLOW_HZ),.HOLD_CYCLES(HOLD_CYCLES)) loader(
 .clk(clk),.rst(rst),.line_valid(line_destination_valid),.line(line_bundle),.line_ready(loader_ready),
 .card_ready(card_sync),.fs_error(file_error),.request(request),.address(address),
 .byte_valid(valid),.byte_data(file_byte),.sector_end(finish),.word_pending(word_pending),
 .generation(generation),.index(index),.length(length),.data(data),.mask(mask),.word_ack(loader_ack),
 .session(session_sync),.font_ready(font_ready),.fault(font_fault),.tick(slow_tick));
photo_font_file_b #(.SLOW_HZ(SLOW_HZ),.ADDR_BITS(27),.SLOW_CLIENT(1)) filesystem(
 .clk(fast_clk),.rst(fast_rst),.slow_clk(clk),.slow_rst(rst),.card_ready(card_ready),
 .request(request),.address(address),.valid(valid),.data(file_byte),.finish(finish),.error(file_error),
 .read_sector(read_sector),.sector(sector),.byte_valid(byte_valid),.byte_data(byte_data),.sector_end(sector_end));
endmodule
