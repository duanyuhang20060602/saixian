// Diagnostic-only CDC; never drives the playback control or memory bus.
// Rightmost 3 digits show Ehh. Digit 4 shows the native SD init stage.
module delta_status #(parameter KEY_DEBOUNCE=1000000,SECOND_TICKS=50000000)(
 input clk,input rst,input [2:0] sd_error,input [2:0] sd_stage,
 input [3:0] memory_error,input [3:0] player_error,input underflow,
 output [5:0] seg_sel,output [7:0] seg_data,
 input debug_mode,input key_n,input [191:0] debug_data
);
(* async_reg="true",keep="true" *)reg [14:0] status_meta,status_sync;
(* async_reg="true",keep="true" *)reg [191:0] debug_meta,debug_sync;
(* async_reg="true",keep="true" *)reg mode_meta,mode_sync,key_meta,key_sync;
reg key_stable;reg [19:0] key_count;reg [3:0] page;
reg [25:0] second_count;reg [3:0] fault_second;reg [7:0] previous_code;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  status_meta<=0;status_sync<=0;debug_meta<=0;debug_sync<=0;
  mode_meta<=0;mode_sync<=0;key_meta<=1;key_sync<=1;
  key_stable<=1;key_count<=0;page<=0;
 end else begin
  status_meta<={sd_stage,sd_error,memory_error,player_error,underflow};status_sync<=status_meta;
  debug_meta<=debug_data;debug_sync<=debug_meta;
  mode_meta<=debug_mode;mode_sync<=mode_meta;key_meta<=key_n;key_sync<=key_meta;
  if(!mode_sync)page<=0;
  if(key_sync==key_stable)key_count<=0;
  else if(key_count==KEY_DEBOUNCE-1)begin
   key_count<=0;key_stable<=key_sync;
   if(!key_sync && mode_sync)page<=page==11 ? 0 : page+1'b1;
  end else key_count<=key_count+1'b1;
 end
end
wire [2:0] stage=status_sync[14:12],sd=status_sync[11:9];
wire [3:0] mem=status_sync[8:5],player=status_sync[4:1];
wire [7:0] code=sd!=0 ? (8'h10|{5'd0,sd}) :
 mem!=0 ? (8'h20|{4'd0,mem}) : player!=0 ? (8'h30|{4'd0,player}) :
 status_sync[0] ? 8'h40 : 8'h00;
// Five seconds of error code, then six one-second data pages; repeat.
// This remains usable even when the physical SW2 input cannot be toggled.
always @(posedge clk or posedge rst)begin
 if(rst)begin second_count<=0;fault_second<=0;previous_code<=0;end
 else begin
  previous_code<=code;
  if(code==0 || code!=previous_code)begin second_count<=0;fault_second<=0;end
  else if(second_count==SECOND_TICKS-1)begin
   second_count<=0;fault_second<=fault_second==10 ? 0 : fault_second+1'b1;
  end else second_count<=second_count+1'b1;
 end
end
wire auto_mode=code!=0 && fault_second>=5;
wire show_debug=mode_sync || auto_mode;
wire bist_fault=mem>=11 && mem<=15 && sd==0;
wire decode_fault=sd==0 && mem==0 && ((player>=1 && player<=6)||player==9);
wire [3:0] shown_page=mode_sync ? page : fault_second-4'd5+(bist_fault || decode_fault ? 4'd6 : 4'd0);
wire [6:0] low,high,init;
seg_decoder dl(code[3:0],low);seg_decoder dh(code[7:4],high);seg_decoder ds({1'b0,stage},init);
// Pages 0/1 expected CRC, 2/3 upload CRC, 4/5 readback CRC,
// 6/7 first actual word, 8/9 expected word, A/B absolute word address.
reg [15:0] value;
always @*case(shown_page)
 0:value=debug_sync[175:160];1:value=debug_sync[191:176];
 2:value=debug_sync[15:0];3:value=debug_sync[31:16];
 4:value=debug_sync[47:32];5:value=debug_sync[63:48];
 6:value=debug_sync[79:64];7:value=debug_sync[95:80];
 8:value=debug_sync[111:96];9:value=debug_sync[127:112];
 10:value=debug_sync[143:128];default:value=debug_sync[159:144];
endcase
wire [6:0] hex0,hex1,hex2,hex3,hexpage;
seg_decoder d0(value[3:0],hex0);seg_decoder d1(value[7:4],hex1);
seg_decoder d2(value[11:8],hex2);seg_decoder d3(value[15:12],hex3);seg_decoder dp(shown_page,hexpage);
seg_scan scan(.clk(clk),.rst_n(!rst),.seg_sel(seg_sel),.seg_data(seg_data),
 .seg_data_0(show_debug ? {1'b1,hex0} : {1'b1,low}),
 .seg_data_1(show_debug ? {1'b1,hex1} : {1'b1,high}),
 .seg_data_2(show_debug ? {1'b1,hex2} : code!=0 ? 8'h86 : 8'hff),
 .seg_data_3(show_debug ? {1'b1,hex3} : {1'b1,init}),
 .seg_data_4(show_debug ? 8'hff : 8'ha1),.seg_data_5(show_debug ? {1'b1,hexpage} : 8'hff));
endmodule
