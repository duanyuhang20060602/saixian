module saixian_hmi_status_tx_before #(
    parameter integer CLK_FREQ_HZ = 75_000_000,
    parameter integer BAUD_RATE = 115_200,
    parameter integer ENHANCEMENT_FEEDBACK = 0
)(
    input wire clk, rst,
    input wire [2:0] image_count,
    input wire [2:0] audio_count,
    input wire [2:0] error_code,
    input wire initializing,
    input wire [2:0] page_id,
    input wire refresh_request,
    input wire [1:0] sharpness,
    input wire [3:0] brightness, contrast, saturation, volume,
    input wire invert, vintage,
    input wire [1:0] enhancement,
    input wire [3:0] event_state,
    input wire [6:0] minutes,
    input wire [5:0] seconds,
    output reg uart_tx,
    output reg command_sent_pulse
);
localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
localparam [1:0] TX_IDLE=0, TX_START=1, TX_DATA=2, TX_STOP=3;
reg [1:0] tx_state;
reg [4:0] next_field;
reg [2:0] active_page;
reg [31:0] refresh_count;
reg [15:0] baud_count;
reg [4:0] message_id, prepared_id;
reg [7:0] command_rom [0:1023];
reg [7:0] prefix_byte;
integer rom_index;
reg [47:0] message_suffix, prepared_suffix;
reg [5:0] prefix_length, suffix_length;
reg [5:0] message_len, prepared_len, byte_index;
wire [4:0] next_byte_index=byte_index[4:0]+5'd1;
reg [2:0] bit_index;
reg [7:0] shift_byte;
reg [6:0] minutes_snapshot;
reg [5:0] seconds_snapshot;
reg [3:0] state_snapshot;
reg [4:0] field_count;
reg refresh_pending;
reg [21:0] settings_seen;
wire [1:0] feedback_enhancement=ENHANCEMENT_FEEDBACK ? enhancement:2'd0;
wire [21:0] settings_live={feedback_enhancement,sharpness,brightness,contrast,saturation,volume,invert,vintage};
reg [7:0] value;
integer prefix_len;

// Fixed ASCII prefixes use one synchronous block ROM instead of wide muxes.
initial begin
    for(rom_index=0;rom_index<1024;rom_index=rom_index+1) command_rom[rom_index]=8'h00;
    command_rom[0]=8'h73;
    command_rom[1]=8'h65;
    command_rom[2]=8'h74;
    command_rom[3]=8'h74;
    command_rom[4]=8'h69;
    command_rom[5]=8'h6e;
    command_rom[6]=8'h67;
    command_rom[7]=8'h73;
    command_rom[8]=8'h2e;
    command_rom[9]=8'h68;
    command_rom[10]=8'h5f;
    command_rom[11]=8'h73;
    command_rom[12]=8'h68;
    command_rom[13]=8'h61;
    command_rom[14]=8'h72;
    command_rom[15]=8'h70;
    command_rom[16]=8'h2e;
    command_rom[17]=8'h76;
    command_rom[18]=8'h61;
    command_rom[19]=8'h6c;
    command_rom[20]=8'h3d;
    command_rom[32]=8'h73;
    command_rom[33]=8'h65;
    command_rom[34]=8'h74;
    command_rom[35]=8'h74;
    command_rom[36]=8'h69;
    command_rom[37]=8'h6e;
    command_rom[38]=8'h67;
    command_rom[39]=8'h73;
    command_rom[40]=8'h2e;
    command_rom[41]=8'h6e;
    command_rom[42]=8'h5f;
    command_rom[43]=8'h73;
    command_rom[44]=8'h68;
    command_rom[45]=8'h61;
    command_rom[46]=8'h72;
    command_rom[47]=8'h70;
    command_rom[48]=8'h2e;
    command_rom[49]=8'h76;
    command_rom[50]=8'h61;
    command_rom[51]=8'h6c;
    command_rom[52]=8'h3d;
    command_rom[64]=8'h73;
    command_rom[65]=8'h65;
    command_rom[66]=8'h74;
    command_rom[67]=8'h74;
    command_rom[68]=8'h69;
    command_rom[69]=8'h6e;
    command_rom[70]=8'h67;
    command_rom[71]=8'h73;
    command_rom[72]=8'h2e;
    command_rom[73]=8'h68;
    command_rom[74]=8'h5f;
    command_rom[75]=8'h62;
    command_rom[76]=8'h72;
    command_rom[77]=8'h69;
    command_rom[78]=8'h67;
    command_rom[79]=8'h68;
    command_rom[80]=8'h74;
    command_rom[81]=8'h2e;
    command_rom[82]=8'h76;
    command_rom[83]=8'h61;
    command_rom[84]=8'h6c;
    command_rom[85]=8'h3d;
    command_rom[96]=8'h73;
    command_rom[97]=8'h65;
    command_rom[98]=8'h74;
    command_rom[99]=8'h74;
    command_rom[100]=8'h69;
    command_rom[101]=8'h6e;
    command_rom[102]=8'h67;
    command_rom[103]=8'h73;
    command_rom[104]=8'h2e;
    command_rom[105]=8'h6e;
    command_rom[106]=8'h5f;
    command_rom[107]=8'h62;
    command_rom[108]=8'h72;
    command_rom[109]=8'h69;
    command_rom[110]=8'h67;
    command_rom[111]=8'h68;
    command_rom[112]=8'h74;
    command_rom[113]=8'h2e;
    command_rom[114]=8'h76;
    command_rom[115]=8'h61;
    command_rom[116]=8'h6c;
    command_rom[117]=8'h3d;
    command_rom[128]=8'h73;
    command_rom[129]=8'h65;
    command_rom[130]=8'h74;
    command_rom[131]=8'h74;
    command_rom[132]=8'h69;
    command_rom[133]=8'h6e;
    command_rom[134]=8'h67;
    command_rom[135]=8'h73;
    command_rom[136]=8'h2e;
    command_rom[137]=8'h68;
    command_rom[138]=8'h5f;
    command_rom[139]=8'h63;
    command_rom[140]=8'h6f;
    command_rom[141]=8'h6e;
    command_rom[142]=8'h74;
    command_rom[143]=8'h72;
    command_rom[144]=8'h61;
    command_rom[145]=8'h73;
    command_rom[146]=8'h74;
    command_rom[147]=8'h2e;
    command_rom[148]=8'h76;
    command_rom[149]=8'h61;
    command_rom[150]=8'h6c;
    command_rom[151]=8'h3d;
    command_rom[160]=8'h73;
    command_rom[161]=8'h65;
    command_rom[162]=8'h74;
    command_rom[163]=8'h74;
    command_rom[164]=8'h69;
    command_rom[165]=8'h6e;
    command_rom[166]=8'h67;
    command_rom[167]=8'h73;
    command_rom[168]=8'h2e;
    command_rom[169]=8'h6e;
    command_rom[170]=8'h5f;
    command_rom[171]=8'h63;
    command_rom[172]=8'h6f;
    command_rom[173]=8'h6e;
    command_rom[174]=8'h74;
    command_rom[175]=8'h72;
    command_rom[176]=8'h61;
    command_rom[177]=8'h73;
    command_rom[178]=8'h74;
    command_rom[179]=8'h2e;
    command_rom[180]=8'h76;
    command_rom[181]=8'h61;
    command_rom[182]=8'h6c;
    command_rom[183]=8'h3d;
    command_rom[192]=8'h73;
    command_rom[193]=8'h65;
    command_rom[194]=8'h74;
    command_rom[195]=8'h74;
    command_rom[196]=8'h69;
    command_rom[197]=8'h6e;
    command_rom[198]=8'h67;
    command_rom[199]=8'h73;
    command_rom[200]=8'h2e;
    command_rom[201]=8'h68;
    command_rom[202]=8'h5f;
    command_rom[203]=8'h73;
    command_rom[204]=8'h61;
    command_rom[205]=8'h74;
    command_rom[206]=8'h75;
    command_rom[207]=8'h72;
    command_rom[208]=8'h61;
    command_rom[209]=8'h74;
    command_rom[210]=8'h69;
    command_rom[211]=8'h6f;
    command_rom[212]=8'h6e;
    command_rom[213]=8'h2e;
    command_rom[214]=8'h76;
    command_rom[215]=8'h61;
    command_rom[216]=8'h6c;
    command_rom[217]=8'h3d;
    command_rom[224]=8'h73;
    command_rom[225]=8'h65;
    command_rom[226]=8'h74;
    command_rom[227]=8'h74;
    command_rom[228]=8'h69;
    command_rom[229]=8'h6e;
    command_rom[230]=8'h67;
    command_rom[231]=8'h73;
    command_rom[232]=8'h2e;
    command_rom[233]=8'h6e;
    command_rom[234]=8'h5f;
    command_rom[235]=8'h73;
    command_rom[236]=8'h61;
    command_rom[237]=8'h74;
    command_rom[238]=8'h75;
    command_rom[239]=8'h72;
    command_rom[240]=8'h61;
    command_rom[241]=8'h74;
    command_rom[242]=8'h69;
    command_rom[243]=8'h6f;
    command_rom[244]=8'h6e;
    command_rom[245]=8'h2e;
    command_rom[246]=8'h76;
    command_rom[247]=8'h61;
    command_rom[248]=8'h6c;
    command_rom[249]=8'h3d;
    command_rom[256]=8'h73;
    command_rom[257]=8'h65;
    command_rom[258]=8'h74;
    command_rom[259]=8'h74;
    command_rom[260]=8'h69;
    command_rom[261]=8'h6e;
    command_rom[262]=8'h67;
    command_rom[263]=8'h73;
    command_rom[264]=8'h2e;
    command_rom[265]=8'h68;
    command_rom[266]=8'h5f;
    command_rom[267]=8'h76;
    command_rom[268]=8'h6f;
    command_rom[269]=8'h6c;
    command_rom[270]=8'h75;
    command_rom[271]=8'h6d;
    command_rom[272]=8'h65;
    command_rom[273]=8'h2e;
    command_rom[274]=8'h76;
    command_rom[275]=8'h61;
    command_rom[276]=8'h6c;
    command_rom[277]=8'h3d;
    command_rom[288]=8'h73;
    command_rom[289]=8'h65;
    command_rom[290]=8'h74;
    command_rom[291]=8'h74;
    command_rom[292]=8'h69;
    command_rom[293]=8'h6e;
    command_rom[294]=8'h67;
    command_rom[295]=8'h73;
    command_rom[296]=8'h2e;
    command_rom[297]=8'h6e;
    command_rom[298]=8'h5f;
    command_rom[299]=8'h76;
    command_rom[300]=8'h6f;
    command_rom[301]=8'h6c;
    command_rom[302]=8'h75;
    command_rom[303]=8'h6d;
    command_rom[304]=8'h65;
    command_rom[305]=8'h2e;
    command_rom[306]=8'h76;
    command_rom[307]=8'h61;
    command_rom[308]=8'h6c;
    command_rom[309]=8'h3d;
    command_rom[320]=8'h73;
    command_rom[321]=8'h65;
    command_rom[322]=8'h74;
    command_rom[323]=8'h74;
    command_rom[324]=8'h69;
    command_rom[325]=8'h6e;
    command_rom[326]=8'h67;
    command_rom[327]=8'h73;
    command_rom[328]=8'h2e;
    command_rom[329]=8'h62;
    command_rom[330]=8'h74;
    command_rom[331]=8'h5f;
    command_rom[332]=8'h69;
    command_rom[333]=8'h6e;
    command_rom[334]=8'h76;
    command_rom[335]=8'h65;
    command_rom[336]=8'h72;
    command_rom[337]=8'h74;
    command_rom[338]=8'h2e;
    command_rom[339]=8'h76;
    command_rom[340]=8'h61;
    command_rom[341]=8'h6c;
    command_rom[342]=8'h3d;
    command_rom[352]=8'h73;
    command_rom[353]=8'h65;
    command_rom[354]=8'h74;
    command_rom[355]=8'h74;
    command_rom[356]=8'h69;
    command_rom[357]=8'h6e;
    command_rom[358]=8'h67;
    command_rom[359]=8'h73;
    command_rom[360]=8'h2e;
    command_rom[361]=8'h62;
    command_rom[362]=8'h74;
    command_rom[363]=8'h5f;
    command_rom[364]=8'h76;
    command_rom[365]=8'h69;
    command_rom[366]=8'h6e;
    command_rom[367]=8'h74;
    command_rom[368]=8'h61;
    command_rom[369]=8'h67;
    command_rom[370]=8'h65;
    command_rom[371]=8'h2e;
    command_rom[372]=8'h76;
    command_rom[373]=8'h61;
    command_rom[374]=8'h6c;
    command_rom[375]=8'h3d;
    command_rom[384]=8'h67;
    command_rom[385]=8'h61;
    command_rom[386]=8'h6d;
    command_rom[387]=8'h65;
    command_rom[388]=8'h2e;
    command_rom[389]=8'h74;
    command_rom[390]=8'h34;
    command_rom[391]=8'h2e;
    command_rom[392]=8'h74;
    command_rom[393]=8'h78;
    command_rom[394]=8'h74;
    command_rom[395]=8'h3d;
    command_rom[396]=8'h22;
    command_rom[416]=8'h67;
    command_rom[417]=8'h61;
    command_rom[418]=8'h6d;
    command_rom[419]=8'h65;
    command_rom[420]=8'h2e;
    command_rom[421]=8'h74;
    command_rom[422]=8'h33;
    command_rom[423]=8'h2e;
    command_rom[424]=8'h74;
    command_rom[425]=8'h78;
    command_rom[426]=8'h74;
    command_rom[427]=8'h3d;
    command_rom[428]=8'h22;
    command_rom[448]=8'h67;
    command_rom[449]=8'h61;
    command_rom[450]=8'h6d;
    command_rom[451]=8'h65;
    command_rom[452]=8'h2e;
    command_rom[453]=8'h6e;
    command_rom[454]=8'h5f;
    command_rom[455]=8'h73;
    command_rom[456]=8'h74;
    command_rom[457]=8'h61;
    command_rom[458]=8'h74;
    command_rom[459]=8'h65;
    command_rom[460]=8'h2e;
    command_rom[461]=8'h76;
    command_rom[462]=8'h61;
    command_rom[463]=8'h6c;
    command_rom[464]=8'h3d;
    command_rom[480]=8'h68;
    command_rom[481]=8'h6f;
    command_rom[482]=8'h6d;
    command_rom[483]=8'h65;
    command_rom[484]=8'h2e;
    command_rom[485]=8'h74;
    command_rom[486]=8'h5f;
    command_rom[487]=8'h70;
    command_rom[488]=8'h2e;
    command_rom[489]=8'h74;
    command_rom[490]=8'h78;
    command_rom[491]=8'h74;
    command_rom[492]=8'h3d;
    command_rom[493]=8'h22;
    command_rom[512]=8'h68;
    command_rom[513]=8'h6f;
    command_rom[514]=8'h6d;
    command_rom[515]=8'h65;
    command_rom[516]=8'h2e;
    command_rom[517]=8'h74;
    command_rom[518]=8'h5f;
    command_rom[519]=8'h6d;
    command_rom[520]=8'h2e;
    command_rom[521]=8'h74;
    command_rom[522]=8'h78;
    command_rom[523]=8'h74;
    command_rom[524]=8'h3d;
    command_rom[525]=8'h22;
    command_rom[544]=8'h68;
    command_rom[545]=8'h6f;
    command_rom[546]=8'h6d;
    command_rom[547]=8'h65;
    command_rom[548]=8'h2e;
    command_rom[549]=8'h74;
    command_rom[550]=8'h5f;
    command_rom[551]=8'h65;
    command_rom[552]=8'h2e;
    command_rom[553]=8'h74;
    command_rom[554]=8'h78;
    command_rom[555]=8'h74;
    command_rom[556]=8'h3d;
    command_rom[557]=8'h22;
    command_rom[576]=8'h73;
    command_rom[577]=8'h65;
    command_rom[578]=8'h74;
    command_rom[579]=8'h74;
    command_rom[580]=8'h69;
    command_rom[581]=8'h6e;
    command_rom[582]=8'h67;
    command_rom[583]=8'h73;
    command_rom[584]=8'h2e;
    command_rom[585]=8'h68;
    command_rom[586]=8'h5f;
    command_rom[587]=8'h65;
    command_rom[588]=8'h6e;
    command_rom[589]=8'h68;
    command_rom[590]=8'h61;
    command_rom[591]=8'h6e;
    command_rom[592]=8'h63;
    command_rom[593]=8'h65;
    command_rom[594]=8'h2e;
    command_rom[595]=8'h76;
    command_rom[596]=8'h61;
    command_rom[597]=8'h6c;
    command_rom[598]=8'h3d;
    command_rom[608]=8'h73;
    command_rom[609]=8'h65;
    command_rom[610]=8'h74;
    command_rom[611]=8'h74;
    command_rom[612]=8'h69;
    command_rom[613]=8'h6e;
    command_rom[614]=8'h67;
    command_rom[615]=8'h73;
    command_rom[616]=8'h2e;
    command_rom[617]=8'h6e;
    command_rom[618]=8'h5f;
    command_rom[619]=8'h65;
    command_rom[620]=8'h6e;
    command_rom[621]=8'h68;
    command_rom[622]=8'h61;
    command_rom[623]=8'h6e;
    command_rom[624]=8'h63;
    command_rom[625]=8'h65;
    command_rom[626]=8'h2e;
    command_rom[627]=8'h76;
    command_rom[628]=8'h61;
    command_rom[629]=8'h6c;
    command_rom[630]=8'h3d;
end
always @(posedge clk) prefix_byte<=command_rom[{message_id,next_byte_index}];

// Reverse mapping chooses a stable representative of the FPGA's 0..8 levels.
function [7:0] percent;
    input [3:0] level;
    begin
        case(level)
            0:percent=0; 1:percent=13; 2:percent=25; 3:percent=38;
            4:percent=50; 5:percent=63; 6:percent=75; 7:percent=88;
            default:percent=100;
        endcase
    end
endfunction

// Format a constant prefix and short numeric suffix separately.
// Numeric settings always use three decimal digits (000..100).
always @* begin
    prepared_suffix=0; prepared_len=0; prepared_id=0; prefix_len=0; value=0;
    field_count=3;
    case(active_page)
        3'd1: begin
            field_count=ENHANCEMENT_FEEDBACK ? 14:12;
            case(next_field)
                0:begin prepared_id=5'd0;prefix_len=21;value={6'd0,sharpness};end
                1:begin prepared_id=5'd1;prefix_len=21;value={6'd0,sharpness};end
                2:begin prepared_id=5'd2;prefix_len=22;value=percent(brightness);end
                3:begin prepared_id=5'd3;prefix_len=22;value=percent(brightness);end
                4:begin prepared_id=5'd4;prefix_len=24;value=percent(contrast);end
                5:begin prepared_id=5'd5;prefix_len=24;value=percent(contrast);end
                6:begin prepared_id=5'd6;prefix_len=26;value=percent(saturation);end
                7:begin prepared_id=5'd7;prefix_len=26;value=percent(saturation);end
                8:begin prepared_id=5'd8;prefix_len=22;value=percent(volume);end
                9:begin prepared_id=5'd9;prefix_len=22;value=percent(volume);end
                10:begin prepared_id=5'd10;prefix_len=23;value={7'd0,invert};end
                11:begin prepared_id=5'd11;prefix_len=24;value={7'd0,vintage};end
                12:begin prepared_id=5'd18;prefix_len=23;value={6'd0,enhancement};end
                default:begin prepared_id=5'd19;prefix_len=23;value={6'd0,enhancement};end
            endcase
        end
        3'd2: begin
            field_count=3;
            case(next_field)
                0:begin prepared_id=5'd12;prefix_len=13;end
                1:begin prepared_id=5'd13;prefix_len=13;end
                default:begin prepared_id=5'd14;prefix_len=17;value={4'd0,state_snapshot};end
            endcase
        end
        3'd0: begin
            case(next_field)
                0:begin prepared_id=5'd15;prefix_len=14;end
                1:begin prepared_id=5'd16;prefix_len=14;end
                default:begin prepared_id=5'd17;prefix_len=14;end
            endcase
        end
        default:field_count=0; // settlement/keyboard pages have no telemetry targets
    endcase
    prepared_len=prefix_len;
    if(active_page==1 || (active_page==2 && next_field==2)) begin
        prepared_suffix={8'h30+value/8'd100,
            8'h30+(value/8'd10)%8'd10,8'h30+value%8'd10,24'd0};
        prepared_len=prefix_len+3;
    end else if(active_page==2) begin
        prepared_suffix={8'h30+{1'b0,minutes_snapshot}/8'd10,
            8'h30+{1'b0,minutes_snapshot}%8'd10,8'h3a,
            8'h30+{2'd0,seconds_snapshot}/8'd10,8'h30+{2'd0,seconds_snapshot}%8'd10,8'h22};
        prepared_len=prefix_len+6;
    end else if(active_page==0) begin
        case(next_field)
            0:begin
                prepared_suffix={8'h30+{5'd0,image_count},8'h22,32'd0};
                prepared_len=prefix_len+2;
            end
            1:begin
                prepared_suffix={{5'b00110,audio_count},8'h22,32'd0};
                prepared_len=prefix_len+2;
            end
            default:begin
                prepared_suffix={
                    error_code==0?(initializing?8'h49:8'h4f):8'h45,
                    error_code==0?(initializing?8'h4e:8'h4b):(8'h30+{5'd0,error_code}),8'h22,24'd0};
                prepared_len=prefix_len+3;
            end
        endcase
    end
    prepared_len=prepared_len+3;
end

always @(posedge clk or posedge rst) begin
    if(rst) begin
        uart_tx<=1;command_sent_pulse<=0;tx_state<=TX_IDLE;
        active_page<=0;next_field<=0;refresh_count<=0;
        baud_count<=0;message_id<=0;message_suffix<=0;prefix_length<=0;suffix_length<=0;message_len<=0;byte_index<=0;
        bit_index<=0;shift_byte<=0;
        minutes_snapshot<=0;seconds_snapshot<=0;state_snapshot<=0;
        refresh_pending<=0;settings_seen<=0;
    end else begin
        command_sent_pulse<=0;
        settings_seen<=settings_live;
        if(refresh_request || settings_seen!=settings_live) refresh_pending<=1;
        if(refresh_count>=CLK_FREQ_HZ/4-1) refresh_count<=0;
        else refresh_count<=refresh_count+1'b1;
        case(tx_state)
            TX_IDLE: begin
                // Page changes cannot cut a command in half. Reload at next idle.
                if(page_id<=4 && active_page!=page_id) begin
                    active_page<=page_id;next_field<=0;refresh_pending<=0;
                    minutes_snapshot<=minutes;seconds_snapshot<=seconds;state_snapshot<=event_state;
                end else if(next_field<field_count) begin
                    message_id<=prepared_id;message_suffix<=prepared_suffix;
                    prefix_length<=prefix_len;suffix_length<=prepared_len-prefix_len-3;message_len<=prepared_len;
                    next_field<=next_field+1'b1;byte_index<=0;
                    shift_byte<=(active_page==1 ? 8'h73 : active_page==2 ? 8'h67 : 8'h68);bit_index<=0;
                    baud_count<=0;uart_tx<=0;tx_state<=TX_START;
                end else if(refresh_pending || (refresh_count==0 && active_page!=1)) begin
                    refresh_pending<=0;
                    next_field<=0;
                    minutes_snapshot<=minutes;seconds_snapshot<=seconds;state_snapshot<=event_state;
                end
            end
            TX_START: if(baud_count==CLKS_PER_BIT-1) begin
                baud_count<=0;uart_tx<=shift_byte[0];shift_byte<=shift_byte>>1;
                bit_index<=0;tx_state<=TX_DATA;
            end else baud_count<=baud_count+1'b1;
            TX_DATA: if(baud_count==CLKS_PER_BIT-1) begin
                baud_count<=0;
                if(bit_index==7) begin uart_tx<=1;tx_state<=TX_STOP;end
                else begin uart_tx<=shift_byte[0];shift_byte<=shift_byte>>1;bit_index<=bit_index+1'b1;end
            end else baud_count<=baud_count+1'b1;
            TX_STOP: if(baud_count==CLKS_PER_BIT-1) begin
                baud_count<=0;
                if(byte_index+1'b1<message_len) begin
                    if(byte_index+1'b1<prefix_length)
                        shift_byte<=prefix_byte;
                    else if(byte_index+1'b1<prefix_length+suffix_length)
                        shift_byte<=message_suffix[47-((byte_index+1'b1-prefix_length)*8) -: 8];
                    else shift_byte<=8'hff;
                    byte_index<=byte_index+1'b1;uart_tx<=0;tx_state<=TX_START;
                end else begin uart_tx<=1;command_sent_pulse<=1;tx_state<=TX_IDLE;end
            end else baud_count<=baud_count+1'b1;
            default:tx_state<=TX_IDLE;
        endcase
    end
end
endmodule
