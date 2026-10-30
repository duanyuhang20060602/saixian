// Read-only FAT16/FAT32 root-directory lookup and fragmented file-sector map.
// The client keeps its old virtual FONT_BASE+offset interface. Physical LBAs
// are resolved here; no writes, FAT allocation, or contiguous-file assumption.
module demo_fat_font #(parameter HZ=75000000,VIRTUAL_BASE=2209)(
 input clk,rst,card_ready,input request,input[31:0] address,
 output valid,output[7:0] data,output finish,output reg[3:0] error,
 output reg read_sector,output reg[31:0] sector,
 input byte_valid,input[7:0] byte_data,input sector_end);
localparam START=0,BOOT_ISSUE=1,BOOT_WAIT=2,BOOT_PARSE=3,PARTITION=4,
 GEOMETRY=5,GEOMETRY2=6,GEOMETRY3=7,ROOT_ISSUE=8,ROOT_WAIT=9,ROOT_NEXT=10,
 IDLE=11,SEEK_START=12,SEEK=13,FAT_ISSUE=14,FAT_WAIT=15,FAT_NEXT=16,
 DATA_ISSUE=17,DATA_WAIT=18,DATA_CHECK=19,GEOMETRY_OFFSET=20,GEOMETRY_COUNT=21,FAILED=31;
reg[4:0] state;
reg[7:0] boot[0:89];reg[7:0] partition_bytes[0:63];reg[8:0] position;
reg[15:0] signature;reg partitioned;reg[1:0] part_index;
reg[31:0] volume,partition_size,total,fat_size,fat_start,root_start,data_start,cluster_count;
reg[15:0] reserved,root_entries;reg[7:0] fats,spc;reg[3:0] cluster_shift;
reg fat32;reg[31:0] root_cluster,root_lba;reg[15:0] root_sectors;
reg[7:0] root_in_cluster;reg[12:0] directory_reads;
reg match_name,found,end_directory;reg[7:0] attr;reg[31:0] entry_cluster,entry_size;
reg[31:0] file_cluster,file_size;
reg pending;reg[31:0] wanted_sector,target_index,current_cluster,current_index;
reg cached;reg[31:0] cached_cluster,cached_index;
reg root_follow;reg[8:0] fat_offset;reg[31:0] fat_value;
reg[31:0] watchdog;
reg[31:0] data_lba;
reg[31:0] volume_offset;
wire[31:0] selected_fat_size={boot[39],boot[38],boot[37],boot[36]};
wire[31:0] boot_total32={boot[35],boot[34],boot[33],boot[32]};
wire[15:0] boot_total16={boot[20],boot[19]};
wire[15:0] boot_fat16={boot[23],boot[22]};
wire[31:0] next_cluster=fat32?{4'd0,fat_value[27:0]}:{16'd0,fat_value[15:0]};
wire eoc=fat32?next_cluster>=32'h0ffffff8:next_cluster>=32'hfff8;
wire[31:0] fat_sector_index=fat32?(current_cluster>>7):(current_cluster>>8);
wire[31:0] next_file_lba=data_start+((current_cluster-2)<<cluster_shift)+(wanted_sector&({24'd0,spc}-1));
wire bpb_shape=boot[11]==0 && boot[12]==2 && boot[13]!=0 && (boot[13]&(boot[13]-1'b1))==0 && (boot[16]==1 || boot[16]==2);
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
 state<=START;position<=0;signature<=0;partitioned<=0;part_index<=0;
 volume<=0;partition_size<=0;total<=0;fat_size<=0;fat_start<=0;root_start<=0;data_start<=0;cluster_count<=0;
 reserved<=0;root_entries<=0;fats<=0;spc<=0;cluster_shift<=0;fat32<=0;root_cluster<=0;root_lba<=0;root_sectors<=0;root_in_cluster<=0;directory_reads<=0;
 match_name<=0;found<=0;end_directory<=0;attr<=0;entry_cluster<=0;entry_size<=0;file_cluster<=0;file_size<=0;
 pending<=0;wanted_sector<=0;target_index<=0;current_cluster<=0;current_index<=0;cached<=0;cached_cluster<=0;cached_index<=0;
 root_follow<=0;fat_offset<=0;fat_value<=0;watchdog<=0;read_sector<=0;sector<=0;error<=0;data_lba<=0;volume_offset<=0;
 end else begin
 read_sector<=0;
 if(request && !pending && address>=VIRTUAL_BASE)begin pending<=1;wanted_sector<=address-VIRTUAL_BASE;end
 if(state==START || state==IDLE || byte_valid || sector_end)watchdog<=0;
 else if(watchdog<HZ*2)watchdog<=watchdog+1'b1;
 if(state!=FAILED && state!=START && state!=IDLE && watchdog==HZ*2)begin state<=FAILED;error<=6;end
 else case(state)
 START:if(card_ready)state<=BOOT_ISSUE;
 BOOT_ISSUE:begin sector<=volume;read_sector<=1;position<=0;signature<=0;state<=BOOT_WAIT;end
 BOOT_WAIT:begin
 if(byte_valid)begin
 if(position<90)boot[position[6:0]]<=byte_data;
 if(!partitioned && position>=446 && position<510)partition_bytes[position-446]<=byte_data;
 if(position==510)signature[7:0]<=byte_data;
 if(position==511)signature[15:8]<=byte_data;
 position<=position+1'b1;
 end
 if(sector_end)state<=BOOT_PARSE;
 end
 BOOT_PARSE:begin
 if(signature!=16'haa55)begin state<=FAILED;error<=1;end
 else if(bpb_shape)begin
 reserved<={boot[15],boot[14]};fats<=boot[16];spc<=boot[13];cluster_shift<=shift_for(boot[13]);
 root_entries<={boot[18],boot[17]};root_sectors<=({boot[18],boot[17]}+17'd15)>>4;
 total<=boot_total16!=0?{16'd0,boot_total16}:boot_total32;
 fat32<=boot_fat16==0;fat_size<=boot_fat16!=0?{16'd0,boot_fat16}:selected_fat_size;
 root_cluster<={4'd0,boot[47][3:0],boot[46],boot[45],boot[44]};
 state<=GEOMETRY;
 end else if(!partitioned)begin part_index<=0;state<=PARTITION;end
 else begin state<=FAILED;error<=2;end
 end
 PARTITION:begin
 if((partition_bytes[{part_index,4'd4}]==4 || partition_bytes[{part_index,4'd4}]==6 || partition_bytes[{part_index,4'd4}]==14 || partition_bytes[{part_index,4'd4}]==11 || partition_bytes[{part_index,4'd4}]==12) &&
 {partition_bytes[{part_index,4'd11}],partition_bytes[{part_index,4'd10}],partition_bytes[{part_index,4'd9}],partition_bytes[{part_index,4'd8}]}!=0)begin
 volume<={partition_bytes[{part_index,4'd11}],partition_bytes[{part_index,4'd10}],partition_bytes[{part_index,4'd9}],partition_bytes[{part_index,4'd8}]};
 partition_size<={partition_bytes[{part_index,4'd15}],partition_bytes[{part_index,4'd14}],partition_bytes[{part_index,4'd13}],partition_bytes[{part_index,4'd12}]};partitioned<=1;state<=BOOT_ISSUE;
 end else if(part_index==3)begin state<=FAILED;error<=2;end else part_index<=part_index+1'b1;
 end
 GEOMETRY:begin
 root_start<=volume+reserved+(fats==2?(fat_size<<1):fat_size);
 fat_start<=volume+reserved;
 if(fat32 && boot[40][7] && boot[40][3:0]==1)fat_start<=volume+reserved+fat_size;
 if(reserved==0 || fat_size==0 || cluster_shift==15 || total==0 || (partitioned && total>partition_size) ||
 (fat32 && (root_entries!=0 || boot[42]!=0 || boot[43]!=0 || (boot[40][7] && boot[40][3:0]>=fats))))begin error<=2;state<=FAILED;end
 else state<=GEOMETRY2;
 end
 GEOMETRY2:begin
 data_start<=root_start+root_sectors;state<=GEOMETRY_OFFSET;
 end
 GEOMETRY_OFFSET:begin
 volume_offset<=data_start-volume;
 if(root_start<volume || data_start<root_start)begin state<=FAILED;error<=5;end
 else state<=GEOMETRY_COUNT;
 end
 GEOMETRY_COUNT:begin
 if(volume_offset>=total)begin state<=FAILED;error<=5;end
 else begin cluster_count<=(total-volume_offset)>>cluster_shift;state<=GEOMETRY3;end
 end
 GEOMETRY3:begin
 if(cluster_count<4085 || (fat32 && cluster_count<65525) || (!fat32 && (cluster_count>=65525 || root_entries==0)) ||
 (fat32 && (root_cluster<2 || root_cluster>cluster_count+1)))begin state<=FAILED;error<=2;end
 else begin
 root_lba<=fat32?data_start+((root_cluster-2)<<cluster_shift):root_start;
 root_in_cluster<=0;directory_reads<=0;found<=0;end_directory<=0;state<=ROOT_ISSUE;
 end end
 ROOT_ISSUE:begin
 sector<=root_lba;read_sector<=1;position<=0;match_name<=0;entry_cluster<=0;entry_size<=0;state<=ROOT_WAIT;
 end
 ROOT_WAIT:begin
 if(byte_valid)begin
 position<=position+1'b1;
 if(position[4:0]==0)begin match_name<=byte_data=="F";if(byte_data==0)end_directory<=1;entry_cluster<=0;entry_size<=0;end
 else if(position[4:0]<11)match_name<=match_name && byte_data==name_byte(position[3:0]);
 case(position[4:0])
 11:attr<=byte_data;
 20:if(fat32)entry_cluster[23:16]<=byte_data;
 21:if(fat32)entry_cluster[27:24]<=byte_data[3:0];
 26:entry_cluster[7:0]<=byte_data;27:entry_cluster[15:8]<=byte_data;
 28:entry_size[7:0]<=byte_data;29:entry_size[15:8]<=byte_data;30:entry_size[23:16]<=byte_data;
 31:if(match_name && !end_directory && !found && (attr&8'h18)==0 && attr!=8'h0f)begin
 found<=1;file_cluster<=entry_cluster;file_size<={byte_data,entry_size[23:0]};end
 default:;
 endcase end
 if(sector_end)state<=ROOT_NEXT;
 end
 ROOT_NEXT:begin
 if(found)begin
 if(file_cluster<2 || file_cluster>cluster_count+1 || file_size<512)begin state<=FAILED;error<=4;end
 else begin cached<=0;state<=IDLE;end
 end else if(end_directory || directory_reads==4095)begin state<=FAILED;error<=3;end
 else begin
 directory_reads<=directory_reads+1'b1;
 if(!fat32)begin if(root_lba+1>=data_start)begin state<=FAILED;error<=3;end else begin root_lba<=root_lba+1'b1;state<=ROOT_ISSUE;end end
 else if(root_in_cluster+1<spc)begin root_in_cluster<=root_in_cluster+1'b1;root_lba<=root_lba+1'b1;state<=ROOT_ISSUE;end
 else begin current_cluster<=root_cluster;root_follow<=1;state<=FAT_ISSUE;end
 end end
 IDLE:if(pending)begin
 if(wanted_sector>((file_size-1)>>9))begin state<=FAILED;error<=5;end
 else begin target_index<=wanted_sector>>cluster_shift;state<=SEEK_START;end end
 SEEK_START:begin
 if(cached && cached_index<=target_index)begin current_cluster<=cached_cluster;current_index<=cached_index;end
 else begin current_cluster<=file_cluster;current_index<=0;end
 root_follow<=0;state<=SEEK;
 end
 SEEK:begin
 if(current_cluster<2 || current_cluster>cluster_count+1)begin state<=FAILED;error<=4;end
 else if(current_index==target_index)begin cached<=1;cached_cluster<=current_cluster;cached_index<=current_index;state<=DATA_ISSUE;end
 else state<=FAT_ISSUE;
 end
 FAT_ISSUE:begin
 if(fat_sector_index>=fat_size)begin state<=FAILED;error<=4;end
 else begin
 sector<=fat_start+fat_sector_index;fat_offset<=fat32?{current_cluster[6:0],2'b00}:{current_cluster[7:0],1'b0};
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
 if(sector_end)state<=FAT_NEXT;
 end
 FAT_NEXT:begin
 if(eoc || next_cluster<2 || next_cluster>cluster_count+1)begin state<=FAILED;error<=root_follow?3:4;end
 else if(root_follow)begin root_cluster<=next_cluster;root_lba<=data_start+((next_cluster-2)<<cluster_shift);root_in_cluster<=0;state<=ROOT_ISSUE;end
 else begin current_cluster<=next_cluster;current_index<=current_index+1'b1;state<=SEEK;end
 end
 DATA_ISSUE:begin data_lba<=next_file_lba;state<=DATA_CHECK;end
 DATA_CHECK:begin
 if(data_lba<data_start || data_lba-volume>=total)begin state<=FAILED;error<=5;end
 else begin sector<=data_lba;read_sector<=1;state<=DATA_WAIT;end end
 DATA_WAIT:if(sector_end)begin pending<=0;state<=IDLE;end
 default:;
 endcase
 end end
endmodule
