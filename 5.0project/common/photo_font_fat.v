// Short local comparisons followed by a registered lexicographic combine.
// Bounds are evaluated during explicit settle states, outside SD streaming.
module photo_font_less #(parameter W=27)(input clk,input[W-1:0] a,b,output reg result);
localparam N=(W+8)/9,PAD=N*9;
wire[PAD-1:0] pa={{(PAD-W){1'b0}},a},pb={{(PAD-W){1'b0}},b};
reg[N-1:0] less,equal;genvar part;
generate for(part=0;part<N;part=part+1)begin:chunks
 always @(posedge clk)begin less[part]<=pa[part*9+:9]<pb[part*9+:9];equal[part]<=pa[part*9+:9]==pb[part*9+:9];end
end endgenerate
integer j;reg combined;
always @*begin combined=0;for(j=0;j<N;j=j+1)combined=less[j] || (equal[j] && combined);end
always @(posedge clk)result<=combined;
endmodule
// Read-only FAT16/FAT32 root-directory lookup and fragmented file-sector map.
// The client keeps its old virtual FONT_BASE+offset interface. Physical LBAs
// are resolved here; no writes, FAT allocation, or contiguous-file assumption.
module photo_font_fat #(parameter HZ=75000000,VIRTUAL_BASE=2209,FONT_BYTES=287744,ADDR_BITS=32)(
 input clk,rst,card_ready,input request,input[31:0] address,
 output valid,output[7:0] data,output finish,output[3:0] error,
 output reg read_sector,output reg[31:0] sector,
 input byte_valid,input[7:0] byte_data,input sector_end);
localparam START=0,BOOT_ISSUE=1,BOOT_WAIT=2,BOOT_PARSE=3,PARTITION=4,
 GEOMETRY=5,GEOMETRY2=6,GEOMETRY3=7,ROOT_ISSUE=8,ROOT_WAIT=9,ROOT_NEXT=10,
 IDLE=11,SEEK_START=12,SEEK=13,FAT_ISSUE=14,FAT_WAIT=15,FAT_NEXT=16,
 DATA_ISSUE=17,DATA_WAIT=18,DATA_CHECK=19,GEOMETRY_OFFSET=20,GEOMETRY_COUNT=21,COUNT_SHIFT=22,CLUSTER_SHIFT=23,CLUSTER_ADD=24,DATA_OFFSET=25,ROOT_CHECK=26,DATA_VALIDATE=27,ROOT_SETTLE=28,DATA_SETTLE=29,CLUSTER_SETTLE=30,FAILED=31;
reg[3:0] shift_count;reg cluster_for_root;
reg[4:0] state;
reg[8:0] position;
reg sector_low_ok,sector_high_ok,fats_ok,total16_present;reg[7:0] ext_flags;reg version_ok;
reg part_found,part_supported;reg[31:0] part_lba;
wire[5:0] part_offset=position-9'd446;
reg[15:0] signature;reg partitioned;reg[1:0] part_index;
reg[ADDR_BITS-1:0] volume,total,fat_size,fat_start,root_start,data_start,cluster_count;
reg geometry_overflow;
reg[15:0] reserved,root_entries;reg[1:0] fats;reg[7:0] spc;reg[3:0] cluster_shift;
reg fat32;reg[15:0] root_sectors;
reg[7:0] root_in_cluster;reg[12:0] directory_reads;
reg root_more_sectors;
always @(posedge clk)
 if(rst)root_more_sectors<=0;else root_more_sectors<=({1'b0,root_in_cluster}+9'd1)<{1'b0,spc};
reg match_name,found,end_directory;reg[1:0] attr;reg[27:0] entry_cluster;reg size_ge,file_size_ok;
reg[ADDR_BITS-1:0] file_cluster;
reg pending;reg[9:0] wanted_sector,target_index,current_index;reg[ADDR_BITS-1:0] current_cluster;
reg cached;
reg root_follow;reg[8:0] fat_offset;reg[31:0] fat_value;
localparam WB=$clog2(HZ*2+1);reg[WB-1:0] watchdog;
// These lifetimes do not overlap: partition LBA -> directory LBA, root
// cluster -> file start cluster, and root base -> current data-sector LBA.
wire[ADDR_BITS-1:0] root_cluster=file_cluster,root_lba=volume,data_lba=root_start;
wire root_below_data,root_below_end,data_below_data,data_below_end;
photo_font_less #(.W(ADDR_BITS)) root_data_bound(clk,root_lba,data_start,root_below_data);
photo_font_less #(.W(ADDR_BITS)) root_end_bound(clk,root_lba,total,root_below_end);
photo_font_less #(.W(ADDR_BITS)) data_start_bound(clk,data_lba,data_start,data_below_data);
photo_font_less #(.W(ADDR_BITS)) data_end_bound(clk,data_lba,total,data_below_end);
wire root_range_ok=(!fat32 || !root_below_data) && root_below_end;
wire data_range_ok=!data_below_data && data_below_end;
reg[ADDR_BITS-1:0] volume_offset;
wire[31:0] next_cluster=fat32?{4'd0,fat_value[27:0]}:{16'd0,fat_value[15:0]};
reg current_cluster_ok,file_cluster_ok,next_cluster_ok,eoc;
reg settle_for_fat;
always @(posedge clk)begin
 if(rst)begin current_cluster_ok<=0;file_cluster_ok<=0;next_cluster_ok<=0;eoc<=0;end
 else begin
  current_cluster_ok<=|current_cluster[ADDR_BITS-1:1];
  file_cluster_ok<=|file_cluster[ADDR_BITS-1:1];
  next_cluster_ok<=fat32 ? |fat_value[27:1]:|fat_value[15:1];
  eoc<=fat32 ? fat_value[27:0]>=28'hffffff8:fat_value[15:0]>=16'hfff8;
 end
end
wire[31:0] fat_sector_index=fat32?(current_cluster>>7):(current_cluster>>8);
wire fat_index_ok;
photo_font_less #(.W(ADDR_BITS)) fat_bound(clk,fat_sector_index[ADDR_BITS-1:0],fat_size,fat_index_ok);
wire[31:0] arithmetic_cluster=state==GEOMETRY3?root_cluster:state==FAT_NEXT?next_cluster:current_cluster;
// Select short predicates instead of multiplexing three whole cluster buses
// before the same lower-bound comparison.
wire bad_cluster=(state==GEOMETRY3 || state==ROOT_NEXT) ? !file_cluster_ok:
 state==FAT_NEXT ? !next_cluster_ok:!current_cluster_ok;
// Filesystem arithmetic is infrequent and strictly sequential. Share one
// LBA adder across mount, FAT lookup and data reads instead of routing an
// independent wide carry chain for each expression.
reg[ADDR_BITS-1:0] add_a,add_b;
reg[ADDR_BITS-1:0] operand_a,operand_b;
reg[ADDR_BITS:0] lba_sum;
reg[2:0] arithmetic_phase;
wire sum_below_data,root_last_sector;
photo_font_less #(.W(ADDR_BITS+1)) root_last_bound(clk,lba_sum,{1'b0,data_start},sum_below_data);
assign root_last_sector=!sum_below_data;
wire arithmetic_state=state==GEOMETRY || state==GEOMETRY2 || state==GEOMETRY_OFFSET ||
 state==GEOMETRY_COUNT || state==COUNT_SHIFT || state==ROOT_NEXT || state==FAT_ISSUE ||
 state==CLUSTER_ADD || state==DATA_OFFSET;
assign error=state==FAILED ? 4'd1:4'd0;
wire bad_request=request && !pending &&
 (address<VIRTUAL_BASE || address-VIRTUAL_BASE>((FONT_BYTES-1)>>9));
always @*begin
 add_a=data_start;add_b=volume_offset;
 case(state)
 GEOMETRY:begin add_a=volume;add_b=reserved;end
 GEOMETRY2:begin add_a=volume_offset;add_b=fats==2 ? fat_size<<1:fat_size;end
 GEOMETRY_OFFSET:begin add_a=volume_offset;add_b=fat32 && ext_flags[7] && ext_flags[3:0]==1 ? fat_size:0;end
 GEOMETRY_COUNT:begin add_a=root_start;add_b=root_sectors;end
 COUNT_SHIFT:begin add_a=volume;add_b=total;end
 ROOT_NEXT:begin add_a=root_lba;add_b=1;end
 FAT_ISSUE:begin add_a=fat_start;add_b=fat_sector_index;end
 DATA_OFFSET:begin add_a=data_lba;add_b=wanted_sector&({2'd0,spc}-1'b1);end
 default:;
 endcase
end
wire bpb_shape=sector_low_ok && sector_high_ok && cluster_shift!=15 && fats_ok;
assign valid=state==DATA_WAIT && byte_valid;
assign data=byte_data;
assign finish=state==DATA_WAIT && sector_end;
function[7:0] name_byte;input[3:0] n;begin case(n)
0:name_byte="F";1:name_byte="O";2:name_byte="N";3:name_byte="T";4:name_byte="S";
5,6,7:name_byte=" ";8:name_byte="B";9:name_byte="I";default:name_byte="N";endcase end endfunction
function[3:0] shift_for;input[7:0] n;begin case(n)
1:shift_for=0;2:shift_for=1;4:shift_for=2;8:shift_for=3;16:shift_for=4;
32:shift_for=5;64:shift_for=6;128:shift_for=7;default:shift_for=15;endcase end endfunction
always @(posedge clk)begin
 if(rst)begin
 operand_a<=0;operand_b<=0;lba_sum<=0;arithmetic_phase<=0;settle_for_fat<=0;
 geometry_overflow<=0;shift_count<=0;cluster_for_root<=0;sector_low_ok<=0;sector_high_ok<=0;fats_ok<=0;total16_present<=0;ext_flags<=0;version_ok<=0;state<=START;position<=0;signature<=0;partitioned<=0;part_index<=0;part_found<=0;part_supported<=0;part_lba<=0;
 volume<=0;total<=0;fat_size<=0;fat_start<=0;root_start<=0;data_start<=0;cluster_count<=0;
 reserved<=0;root_entries<=0;fats<=0;spc<=0;cluster_shift<=0;fat32<=0;root_sectors<=0;root_in_cluster<=0;directory_reads<=0;
 match_name<=0;found<=0;end_directory<=0;attr<=0;entry_cluster<=0;size_ge<=0;file_size_ok<=0;file_cluster<=0;
 pending<=0;wanted_sector<=0;target_index<=0;current_cluster<=0;current_index<=0;cached<=0;
 root_follow<=0;fat_offset<=0;fat_value<=0;watchdog<=0;read_sector<=0;sector<=0;volume_offset<=0;
 end else begin
 read_sector<=0;
 // Isolate operand selection, the shared adder and result validation into
 // separate clocks. The SD byte stream is forwarded only in WAIT states.
 if(!arithmetic_state)arithmetic_phase<=0;
 else if(arithmetic_phase==0)begin operand_a<=add_a;operand_b<=add_b;arithmetic_phase<=1;end
 else if(arithmetic_phase==1)begin lba_sum<={1'b0,operand_a}+{1'b0,operand_b};arithmetic_phase<=2;end
 else if(arithmetic_phase<4)arithmetic_phase<=arithmetic_phase+1'b1;
 else arithmetic_phase<=0;
 if(request && !pending && address>=VIRTUAL_BASE)begin
 if(address-VIRTUAL_BASE>((FONT_BYTES-1)>>9))begin state<=FAILED;end else begin pending<=1;wanted_sector<=address-VIRTUAL_BASE;end end
 if(state==START || state==IDLE || byte_valid || sector_end)watchdog<=0;
 else if(watchdog<HZ*2)watchdog<=watchdog+1'b1;
 if(bad_request || (state!=FAILED && state!=START && state!=IDLE && watchdog==HZ*2))begin state<=FAILED;end
 else if(!arithmetic_state || arithmetic_phase==4)case(state)
 START:if(card_ready)state<=BOOT_ISSUE;
 BOOT_ISSUE:begin geometry_overflow<=0;sector<=volume;read_sector<=1;position<=0;signature<=0;state<=BOOT_WAIT;end
 BOOT_WAIT:begin
 if(byte_valid)begin
 case(position)
 11:sector_low_ok<=byte_data==0;
 12:sector_high_ok<=byte_data==2;
 13:begin spc<=byte_data;cluster_shift<=shift_for(byte_data);end
 14:reserved[7:0]<=byte_data;15:reserved[15:8]<=byte_data;
 16:begin fats<=byte_data[1:0];fats_ok<=byte_data==1 || byte_data==2;end
 17:root_entries[7:0]<=byte_data;
 18:begin root_entries[15:8]<=byte_data;root_sectors<=({byte_data,root_entries[7:0]}+17'd15)>>4;end
 19:total<={24'd0,byte_data};
 20:begin total[15:8]<=byte_data;total16_present<=({byte_data,total[7:0]}!=0);end
 22:fat_size<={24'd0,byte_data};
 23:begin fat_size[15:8]<=byte_data;fat32<=({byte_data,fat_size[7:0]}==0);end
 32:if(!total16_present)total[7:0]<=byte_data;
 33:if(!total16_present)total[15:8]<=byte_data;
 34:if(!total16_present)total[23:16]<=byte_data;
 35:if(!total16_present)begin total[ADDR_BITS-1:24]<=byte_data[ADDR_BITS-25:0];if((byte_data>>(ADDR_BITS-24))!=0)geometry_overflow<=1;end
 36:if(fat32)fat_size[7:0]<=byte_data;
 37:if(fat32)fat_size[15:8]<=byte_data;
 38:if(fat32)fat_size[23:16]<=byte_data;
 39:if(fat32)begin fat_size[ADDR_BITS-1:24]<=byte_data[ADDR_BITS-25:0];if((byte_data>>(ADDR_BITS-24))!=0)geometry_overflow<=1;end
 40:ext_flags<=byte_data;
 42:version_ok<=byte_data==0;43:version_ok<=version_ok && byte_data==0;
 44:file_cluster[7:0]<=byte_data;45:file_cluster[15:8]<=byte_data;46:file_cluster[23:16]<=byte_data;
 47:begin file_cluster[ADDR_BITS-1:24]<=byte_data[ADDR_BITS-25:0]&8'h0f;if(((byte_data&8'h0f)>>(ADDR_BITS-24))!=0)geometry_overflow<=1;end
endcase
 if(!partitioned && !part_found && position>=446 && position<510)begin
 case(part_offset[3:0])
  4:part_supported<=byte_data==4 || byte_data==6 || byte_data==14 || byte_data==11 || byte_data==12;
  8:part_lba[7:0]<=byte_data;9:part_lba[15:8]<=byte_data;10:part_lba[23:16]<=byte_data;11:part_lba[31:24]<=byte_data;
  15:if(part_supported && part_lba!=0 && !part_found)begin part_found<=1;end
 endcase
end
 if(position==510)signature[7:0]<=byte_data;
 if(position==511)signature[15:8]<=byte_data;
 position<=position+1'b1;
 end
 if(sector_end)state<=BOOT_PARSE;
 end
 BOOT_PARSE:begin
 if(signature!=16'haa55)begin state<=FAILED;end
 else if(bpb_shape)begin
 state<=GEOMETRY;
 end else if(!partitioned)begin part_index<=0;state<=PARTITION;end
 else begin state<=FAILED;end
 end
 PARTITION:begin
 if(part_found && (part_lba < (33'd1<<ADDR_BITS)))begin volume<=part_lba;partitioned<=1;state<=BOOT_ISSUE;end
 else begin state<=FAILED;end
 end
 GEOMETRY:begin
 volume_offset<=lba_sum[ADDR_BITS-1:0];
 if(geometry_overflow || reserved==0 || fat_size==0 || cluster_shift==15 || total==0 ||
 (fat32 && ext_flags[7] && ext_flags[3:0]>=fats) || lba_sum[ADDR_BITS])begin state<=FAILED;end
 else state<=GEOMETRY2;
 end
 GEOMETRY2:begin
 if(lba_sum[ADDR_BITS])begin state<=FAILED;end
 else begin root_start<=lba_sum[ADDR_BITS-1:0];state<=GEOMETRY_OFFSET;end
 end
 GEOMETRY_OFFSET:begin
 if(lba_sum[ADDR_BITS])begin state<=FAILED;end
 else begin fat_start<=lba_sum[ADDR_BITS-1:0];state<=GEOMETRY_COUNT;end
 end
 GEOMETRY_COUNT:begin
 if(lba_sum[ADDR_BITS])begin state<=FAILED;end
 else begin data_start<=lba_sum[ADDR_BITS-1:0];state<=COUNT_SHIFT;end
 end
 // Convert the BPB length to an exclusive absolute end once. All reads can
 // then check the same bound without a fresh LBA-minus-volume subtractor.
 COUNT_SHIFT:if(lba_sum[ADDR_BITS])begin state<=FAILED;end
 else begin total<=lba_sum[ADDR_BITS-1:0];state<=GEOMETRY3;end
 GEOMETRY3:begin
 if(fat32 && bad_cluster)begin state<=FAILED;end
 else begin
 if(fat32)begin volume_offset<=arithmetic_cluster-2;shift_count<=cluster_shift;cluster_for_root<=1;state<=CLUSTER_SHIFT;end else begin volume<=root_start;state<=ROOT_CHECK;end
 root_in_cluster<=0;directory_reads<=0;found<=0;end_directory<=0;
 end end
 ROOT_CHECK:state<=ROOT_SETTLE;
 ROOT_SETTLE:state<=ROOT_ISSUE;
 ROOT_ISSUE:if(!root_range_ok)begin state<=FAILED;end else begin
 sector<=root_lba;read_sector<=1;position<=0;match_name<=0;entry_cluster<=0;size_ge<=1;state<=ROOT_WAIT;
 end
 ROOT_WAIT:begin
 if(byte_valid)begin
 position<=position+1'b1;
 if(position[4:0]==0)begin match_name<=byte_data=="F";if(byte_data==0)end_directory<=1;entry_cluster<=0;size_ge<=1;end
 else if(position[4:0]<11)match_name<=match_name && byte_data==name_byte(position[3:0]);
 case(position[4:0])
 11:attr<=byte_data[4:3];
 20:if(fat32)entry_cluster[23:16]<=byte_data;
 21:if(fat32)entry_cluster[27:24]<=byte_data[3:0];
 26:entry_cluster[7:0]<=byte_data;27:entry_cluster[15:8]<=byte_data;
 28:size_ge<=byte_data>=((FONT_BYTES>>0)&255);
 29:size_ge<=byte_data>((FONT_BYTES>>8)&255) || (byte_data==((FONT_BYTES>>8)&255) && size_ge);
 30:size_ge<=byte_data>((FONT_BYTES>>16)&255) || (byte_data==((FONT_BYTES>>16)&255) && size_ge);
 31:if(match_name && !end_directory && !found && attr==0)begin
 found<=1;file_cluster<=entry_cluster;file_size_ok<=byte_data>((FONT_BYTES>>24)&255) || (byte_data==((FONT_BYTES>>24)&255) && size_ge);end
 default:;
 endcase end
 if(sector_end)state<=ROOT_NEXT;
 end
 ROOT_NEXT:begin
 if(found)begin
 if(bad_cluster || !file_size_ok)begin state<=FAILED;end
 else begin cached<=0;state<=IDLE;end
 end else if(end_directory || directory_reads==4095)begin state<=FAILED;end
 else begin
 directory_reads<=directory_reads+1'b1;
 if(!fat32)begin if(root_last_sector)begin state<=FAILED;end else begin volume<=lba_sum[ADDR_BITS-1:0];state<=ROOT_CHECK;end end
 else if(root_more_sectors)begin root_in_cluster<=root_in_cluster+1'b1;volume<=lba_sum[ADDR_BITS-1:0];state<=ROOT_CHECK;end
 else begin current_cluster<=root_cluster;root_follow<=1;state<=FAT_ISSUE;end
 end end
 IDLE:if(pending)begin
 target_index<=wanted_sector;shift_count<=cluster_shift;state<=SEEK_START;end
 SEEK_START:if(shift_count!=0)begin target_index<=target_index>>1;shift_count<=shift_count-1'b1;end else begin
 // The seek registers themselves retain the last resolved cluster while
 // IDLE; a second bank of identical cached registers is unnecessary.
 if(!cached || current_index>target_index)begin current_cluster<=file_cluster;current_index<=0;end
 root_follow<=0;settle_for_fat<=0;state<=CLUSTER_SETTLE;
 end
 CLUSTER_SETTLE:state<=settle_for_fat ? FAT_NEXT:SEEK;
 SEEK:begin
 if(bad_cluster)begin state<=FAILED;end
 else if(current_index==target_index)begin cached<=1;state<=DATA_ISSUE;end
 else state<=FAT_ISSUE;
 end
 FAT_ISSUE:begin
 // FAT_ISSUE already waits for the arithmetic pipeline, so this registered
 // bounds result is settled before the request can be issued.
 if(!fat_index_ok)begin state<=FAILED;end
 else begin
 sector<=lba_sum[ADDR_BITS-1:0];fat_offset<=fat32?{current_cluster[6:0],2'b00}:{current_cluster[7:0],1'b0};
 fat_value<=0;position<=0;read_sector<=1;state<=FAT_WAIT;end
 end
 FAT_WAIT:begin
 if(byte_valid)begin
 if(position==fat_offset)fat_value[7:0]<=byte_data;
 if(position==fat_offset+1)fat_value[15:8]<=byte_data;
 if(fat32 && position==fat_offset+2)fat_value[23:16]<=byte_data;
 if(fat32 && position==fat_offset+3)fat_value[31:24]<=byte_data;
 position<=position+1'b1;
 end
 if(sector_end)begin settle_for_fat<=1;state<=CLUSTER_SETTLE;end
 end
 FAT_NEXT:begin
 if(eoc || bad_cluster)begin state<=FAILED;end
 else if(root_follow)begin file_cluster<=next_cluster;volume_offset<=arithmetic_cluster-2;shift_count<=cluster_shift;cluster_for_root<=1;root_in_cluster<=0;state<=CLUSTER_SHIFT;end
 else begin current_cluster<=next_cluster;current_index<=current_index+1'b1;settle_for_fat<=0;state<=CLUSTER_SETTLE;end
 end
 DATA_ISSUE:begin volume_offset<=arithmetic_cluster-2;shift_count<=cluster_shift;cluster_for_root<=0;state<=CLUSTER_SHIFT;end
 CLUSTER_SHIFT:if(shift_count!=0)begin
 if(volume_offset[ADDR_BITS-1])begin state<=FAILED;end else begin volume_offset<=volume_offset<<1;shift_count<=shift_count-1'b1;end
 end else state<=CLUSTER_ADD;
 CLUSTER_ADD:if(lba_sum[ADDR_BITS])begin state<=FAILED;end else if(cluster_for_root)begin volume<=lba_sum[ADDR_BITS-1:0];state<=ROOT_CHECK;end else begin root_start<=lba_sum[ADDR_BITS-1:0];state<=DATA_OFFSET;end
 DATA_OFFSET:if(lba_sum[ADDR_BITS])begin state<=FAILED;end else begin root_start<=lba_sum[ADDR_BITS-1:0];state<=DATA_VALIDATE;end
 DATA_VALIDATE:state<=DATA_SETTLE;
 DATA_SETTLE:state<=DATA_CHECK;
 DATA_CHECK:begin
 if(!data_range_ok)begin state<=FAILED;end
 else begin sector<=data_lba;read_sector<=1;state<=DATA_WAIT;end end
 DATA_WAIT:if(sector_end)begin pending<=0;state<=IDLE;end
 default:;
 endcase
 end end
endmodule
