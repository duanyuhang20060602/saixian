// Scan sector-aligned SXDLT001, then upload the complete file once to SDRAM.
module delta_loader #(parameter CLOCK_HZ=100000000,MAX_SECTOR=1048575,MAX_FILE_BYTES=7467008,USE_START_HINT=0,SKIP_KNOWN_MEDIA=0)(
 input clk,input rst,input sd_init,output reg req,output reg [31:0] sector,
 input valid,input [7:0] data,input block_end,input fifo_full,
 output reg upload_we,output reg [31:0] upload_data,
 output reg ready,output reg [20:0] file_words,output reg [5:0] frame_count,
 output reg [2:0] error,output reg [3:0] state,output [31:0] payload_crc,
 input start_hint_valid,input [31:0] start_hint
);
localparam WAIT=0,ISSUE=1,READ=2,CHECK=3,DONE=4,FAILED=5,FINAL_CHECK=6;
reg [9:0] in_block;reg loading;reg [31:0] start_sector;
reg hint_tried;
reg [23:0] bytes_loaded;reg [23:0] file_bytes;
reg [351:0] header;reg [23:0] low_bytes;reg [31:0] crc;
assign payload_crc=header[319:288];
reg [29:0] timer;reg [34:0] scan_timer;
reg init_expired,read_expired,scan_expired;
function [31:0] crc_byte;
 input [31:0] old;input [7:0] v;reg [31:0] c;integer k;
 begin c=old^{24'd0,v};for(k=0;k<8;k=k+1)c=c[0] ? (c>>1)^32'hEDB88320 : c>>1;crc_byte=c;end
endfunction
// All 44 header bytes arrive well before the sector ends. Register the
// independent checks to keep the SD 100 MHz state transitions shallow.
reg [6:0] header_checks;
reg [3:0] crc_checks;
reg last_sector;
// Without a boot hint, skip complete contiguous BMP/AUD files using the
// formats already used by the photo/music reader, rather than reading PCM
// and image payloads sector by sector just to find a later DLT header.
wire bmp_header=header[15:0]==16'h4d42 && header[143:112]==40 &&
                header[223:208]==1 && header[239:224]==24 && header[271:240]==0;
wire aud_header=header[63:0]==64'h3130304455415853 && header[127:96]==48000 &&
                header[143:128]==16 && header[159:144]==2;
wire [31:0] media_bytes=bmp_header ? header[47:16] : header[95:64];
reg media_skip_valid,media_skip_in_window;
reg [20:0] media_sectors;reg [31:0] media_next_sector;
wire [32:0] media_target={1'b0,sector}+media_sectors;
always @(posedge clk)begin
 if(rst)begin media_skip_valid<=0;media_sectors<=0;media_next_sector<=0;media_skip_in_window<=0;end
 else begin
  media_skip_valid<=(bmp_header || aud_header) && media_bytes>=54 && media_bytes[31:29]==0;
  media_sectors<=media_bytes[28:9]+(|media_bytes[8:0])+(aud_header ? 21'd1 : 21'd0);
  media_next_sector<=media_target[31:0];media_skip_in_window<=media_target<=MAX_SECTOR;
 end
end
wire header_ok=&header_checks;
wire bad_input=in_block[9] || (loading && bytes_loaded[1:0]==3 && fifo_full);
always @(posedge clk)begin
 if(rst)begin header_checks<=0;crc_checks<=0;last_sector<=0;end
 else begin
  header_checks[0]<=header[63:0]==64'h313030544c445853;
  header_checks[1]<=header[79:64]==1 && header[95:80]==512;
  header_checks[2]<=header[111:96]==480 && header[127:112]==480;
  header_checks[3]<=header[159:134]==0 && header[133:128]!=0;
  header_checks[4]<=header[191:160]>=2048 && header[191:160]<=MAX_FILE_BYTES && header[168:160]==0;
  header_checks[5]<=header[223:192]==115200 && header[255:224]==1 && header[287:256]==32;
  header_checks[6]<=header[351:327]==0 && header[326:320]=={1'b0,header[133:128]}+7'd1;
  crc_checks[0]<=(crc[7:0]^8'hff)==header[295:288];
  crc_checks[1]<=(crc[15:8]^8'hff)==header[303:296];
  crc_checks[2]<=(crc[23:16]^8'hff)==header[311:304];
  crc_checks[3]<=(crc[31:24]^8'hff)==header[319:312];
  // Sector is constant throughout the 512-byte read before CHECK.
  last_sector<=sector==MAX_SECTOR;
 end
end
always @(posedge clk) begin
 if(rst) begin
  state<=WAIT;req<=0;sector<=0;in_block<=0;loading<=0;start_sector<=0;hint_tried<=0;
  bytes_loaded<=0;file_bytes<=0;header<=0;low_bytes<=0;crc<=32'hffffffff;
  timer<=0;scan_timer<=0;init_expired<=0;read_expired<=0;scan_expired<=0;
  upload_we<=0;upload_data<=0;ready<=0;file_words<=0;frame_count<=0;error<=0;
 end else begin
  upload_we<=0;
  init_expired<=!sd_init && timer==CLOCK_HZ*8-2;
  read_expired<=state==READ && timer==CLOCK_HZ*10-2;
  scan_expired<=!loading && sd_init && scan_timer==35'd240*CLOCK_HZ-2;
  if(state!=DONE && state!=FAILED) begin
   if(!sd_init && init_expired) begin error<=1;state<=FAILED;req<=0;end
   else if(state==READ && read_expired) begin error<=4;state<=FAILED;req<=0;end
   else if(!loading && sd_init && scan_expired) begin error<=3;state<=FAILED;req<=0;end
   else begin
    if(!sd_init || state==READ)timer<=timer+1'b1;else timer<=0;
    if(!loading && sd_init)scan_timer<=scan_timer+1'b1;
    case(state)
     WAIT:if(sd_init)begin sector<=USE_START_HINT && start_hint_valid ? start_hint : 32'd0;hint_tried<=USE_START_HINT && start_hint_valid;state<=ISSUE;timer<=0;end
     ISSUE:begin req<=1;in_block<=0;state<=READ;timer<=0;end
     READ:begin
      if(valid) begin
       // Header validation requires a sector-aligned length. CHECK stops
       // after its last sector; the byte limit within READ is therefore 512.
       if(bad_input) begin error<=6;state<=FAILED;req<=0;end
       else begin
        in_block<=in_block+1'b1;
        // Header bytes are sequential. A shared shift enable replaces 44
        // independently decoded byte-write enables; byte order is identical.
        if(!loading)begin if(in_block<44)header<={data,header[351:8]};end
        else begin
         if(bytes_loaded>=512)crc<=crc_byte(crc,data);
         bytes_loaded<=bytes_loaded+1'b1;
         if(bytes_loaded[1:0]==3)begin upload_we<=1;upload_data<={data,low_bytes};end
         else low_bytes[bytes_loaded[1:0]*8+:8]<=data;
        end
       end
      end
      if(block_end && !(valid && bad_input))begin req<=0;state<=CHECK;end
     end
     CHECK:begin
      if(in_block!=512)begin error<=4;state<=FAILED;end
      else if(!loading)begin
       if(MAX_FILE_BYTES<7467008 && header[63:0]==64'h313030544c445853 && header[191:160]>MAX_FILE_BYTES)begin
        error<=7;state<=FAILED;
       end else if(header_ok)begin
        loading<=1;start_sector<=sector;file_bytes<=header[183:160];
        file_words<=header[182:162];frame_count<=header[133:128];
        bytes_loaded<=0;crc<=32'hffffffff;state<=ISSUE;
       end else if(hint_tried)begin hint_tried<=0;sector<=0;state<=ISSUE;end
       else if(SKIP_KNOWN_MEDIA && media_skip_valid && media_skip_in_window)begin sector<=media_next_sector;state<=ISSUE;end
       else if(last_sector)begin error<=3;state<=FAILED;end
       else begin sector<=sector+1'b1;state<=ISSUE;end
      end else if(bytes_loaded==file_bytes)state<=FINAL_CHECK;
      else begin sector<=sector+1'b1;state<=ISSUE;end
     end
     // The last byte's CRC and all four comparisons settle before this state.
     FINAL_CHECK:begin
      if(&crc_checks)begin ready<=1;state<=DONE;end
      else begin error<=5;state<=FAILED;end
     end
    endcase
   end
  end
 end
end
endmodule
