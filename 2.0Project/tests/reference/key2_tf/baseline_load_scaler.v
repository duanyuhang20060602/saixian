module baseline_load_scaler #(
    parameter integer OUT_WIDTH=1280, OUT_HEIGHT=720,
    parameter integer VERTICAL_PERIOD=16
)(
    input wire clk, rst, start,
    input wire [15:0] source_width, source_height,
    input wire pixel_valid, input wire [23:0] pixel_in,
    output reg pixel_out_valid, output reg [23:0] pixel_out,
    output wire busy, output reg fault
);
localparam integer CHUNKS=(OUT_WIDTH+511)/512;
reg active, native_size;
// VGA artwork/text needs crisp pixel replication, not two-axis blending.
// Latch the policy per image; other source sizes keep bilinear interpolation.
reg vga_crisp;
reg [3:0] vertical_pace;
reg [10:0] in_x, in_y, source_last_x, source_last_y;
reg [16:0] x_step, y_step;
reg [26:0] xpos, ypos;
reg [26:0] x_dividend,y_dividend,x_quotient,y_quotient;
reg [11:0] x_remainder,y_remainder;
reg [4:0] divide_count;
reg dividing;
wire [11:0] x_trial={x_remainder[10:0],x_dividend[26]};
wire [11:0] y_trial={y_remainder[10:0],y_dividend[26]};
wire x_div_bit=(x_trial>=OUT_WIDTH-1);
wire y_div_bit=(y_trial>=OUT_HEIGHT-1);
reg [10:0] hx, vx;
reg [9:0] vy;
reg [1:0] write_bank, h_bank, v_bank;
reg h_run, v_run;
wire vertical_step=v_run && vertical_pace==0;
reg [10:0] sample_x, sample_y, v_source_y;
reg [23:0] left_pixel, current_pixel, previous_pixel;
reg h_valid, h_last;
reg h_calc_valid, h_calc_last;
reg [10:0] h_calc_addr,h_calc_row;
reg [1:0] h_calc_bank;
reg [23:0] h_calc_base;
reg [7:0] h_calc_weight;
reg signed [8:0] hd_r,hd_g,hd_b;
reg [10:0] h_addr;
reg [1:0] h_bank_q;
reg [10:0] h_row_q;
reg [23:0] h_base;
reg signed [17:0] hp_r, hp_g, hp_b;
wire [26:0] h_position=(hx==OUT_WIDTH-1) ? {source_last_x,16'd0} : xpos;
// ceil(position)<=index iff floor(position)<index, or equal with zero
// fraction. Equivalent comparison avoids a wide increment/carry chain.
wire h_available=(h_position[26:16]<sample_x) ||
                 (h_position[26:16]==sample_x && h_position[15:0]==0);
wire [7:0] h_weight=vga_crisp ? 8'd0 : h_position[15:8];
wire [23:0] h_left=(sample_x==0 || h_position[15:0]==0 ||
                   (vga_crisp && h_position[15])) ? current_pixel : left_pixel;
// base + floor((current-base)*weight/256) stays between the two
// unsigned 8-bit endpoints for weight 0..255. The old 19-bit clamps are
// unreachable; retain exactly the low 8 bits of that proven-bounded sum.
wire [7:0] hr=h_base[23:16]+hp_r[15:8];
wire [7:0] hg=h_base[15:8]+hp_g[15:8];
wire [7:0] hb=h_base[7:0]+hp_b[15:8];
wire [15:0] h_word={hr[7:3],hg[7:2],hb[7:3]};
reg [1:0] read_chunk, read_bank;
wire [15:0] bank_read [0:2];
genvar bank,chunk;
generate for(bank=0;bank<3;bank=bank+1) begin: banks
    wire [15:0] q [0:CHUNKS-1];
    for(chunk=0;chunk<CHUNKS;chunk=chunk+1) begin: chunks
        reg [15:0] memory [0:511]; /* fehdl force_ram=1, ram_style="bram" */
        reg [15:0] qr;
        always @(posedge clk) begin
            if(h_valid && h_bank_q==bank && (h_addr>>9)==chunk)
                memory[h_addr[8:0]] <= h_word;
            if(v_run && (vx>>9)==chunk) qr<=memory[vx[8:0]];
        end
        assign q[chunk]=qr;
    end
    reg [15:0] selected;
    integer k;
    always @* begin
        selected=0;
        for(k=0;k<CHUNKS;k=k+1) if(read_chunk==k) selected=q[k];
    end
    assign bank_read[bank]=selected;
end endgenerate
reg read_first, read_valid, read_last, read_integer;
reg [7:0] read_weight;
reg mix_valid, mix_last;
reg select_valid, select_last;
reg [23:0] selected_current, selected_previous;
reg [7:0] selected_weight;
reg [23:0] mix_base;
reg signed [17:0] vp_r, vp_g, vp_b;
wire [7:0] vr=mix_base[23:16]+vp_r[15:8];
wire [7:0] vg=mix_base[15:8]+vp_g[15:8];
wire [7:0] vb=mix_base[7:0]+vp_b[15:8];
reg [15:0] current_word, previous_word;
reg [23:0] current_rgb, previous_rgb;
always @* begin
    case(read_bank)
        0:begin current_word=bank_read[0];previous_word=bank_read[2];end
        1:begin current_word=bank_read[1];previous_word=bank_read[0];end
        default:begin current_word=bank_read[2];previous_word=bank_read[1];end
    endcase
    // The 8-bit weight can quantize a NONZERO Q16 fraction to zero.
    // Only an exact Q16 integer addresses the current row rather than ceil-1.
    if(read_first || read_integer || (vga_crisp && read_weight[7])) previous_word=current_word;
    current_rgb={current_word[15:11],current_word[15:13],current_word[10:5],current_word[10:9],current_word[4:0],current_word[4:2]};
    previous_rgb={previous_word[15:11],previous_word[15:13],previous_word[10:5],previous_word[10:9],previous_word[4:0],previous_word[4:2]};
end
wire [26:0] next_ypos=(vy==OUT_HEIGHT-2) ? {source_last_y,16'd0} : ypos+y_step;
wire next_y_available=(next_ypos[26:16]<v_source_y) ||
                      (next_ypos[26:16]==v_source_y && next_ypos[15:0]==0);
assign busy=active;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        active<=0;native_size<=0;vga_crisp<=0;fault<=0;pixel_out_valid<=0;pixel_out<=0;vertical_pace<=0;
        in_x<=0;in_y<=0;source_last_x<=0;source_last_y<=0;x_step<=0;y_step<=0;xpos<=0;ypos<=0;
        x_dividend<=0;y_dividend<=0;x_quotient<=0;y_quotient<=0;
        x_remainder<=0;y_remainder<=0;divide_count<=0;dividing<=0;
        hx<=0;vx<=0;vy<=0;write_bank<=0;h_bank<=0;v_bank<=0;h_run<=0;v_run<=0;
        sample_x<=0;sample_y<=0;v_source_y<=0;left_pixel<=0;current_pixel<=0;previous_pixel<=0;
        h_valid<=0;h_last<=0;h_addr<=0;h_bank_q<=0;h_row_q<=0;h_base<=0;hp_r<=0;hp_g<=0;hp_b<=0;
        h_calc_valid<=0;h_calc_last<=0;h_calc_addr<=0;h_calc_row<=0;h_calc_bank<=0;
        h_calc_base<=0;h_calc_weight<=0;hd_r<=0;hd_g<=0;hd_b<=0;
        read_chunk<=0;read_bank<=0;read_first<=0;read_valid<=0;read_last<=0;read_weight<=0;read_integer<=0;
        mix_valid<=0;mix_last<=0;mix_base<=0;vp_r<=0;vp_g<=0;vp_b<=0;
        select_valid<=0;select_last<=0;selected_current<=0;selected_previous<=0;selected_weight<=0;
    end else if(start) begin
        active<=1;fault<=0;native_size<=(source_width==OUT_WIDTH && source_height==OUT_HEIGHT);vertical_pace<=0;
        vga_crisp<=(source_width==16'd640 && source_height==16'd480 &&
                    OUT_WIDTH==1280 && OUT_HEIGHT==720);
        // Compute terminal indices once, rather than subtracting in every
        // endpoint/ceil comparison on the 100MHz pixel-enable path.
        source_last_x<=source_width[10:0]-11'd1;source_last_y<=source_height[10:0]-11'd1;
        // Once per image: 27-cycle restoring division, not a huge
        // combinational divider in the 100MHz source-pixel path.
        x_dividend<={source_width[10:0]-11'd1,16'd0};
        y_dividend<={source_height[10:0]-11'd1,16'd0};
        x_quotient<=0;y_quotient<=0;x_remainder<=0;y_remainder<=0;
        divide_count<=0;dividing<=1;
        in_x<=0;in_y<=0;hx<=0;vx<=0;vy<=0;xpos<=0;ypos<=0;write_bank<=0;
        h_run<=0;v_run<=0;h_valid<=0;h_calc_valid<=0;read_valid<=0;select_valid<=0;mix_valid<=0;pixel_out_valid<=0;
    end else begin
        pixel_out_valid<=0;h_calc_valid<=0;h_valid<=h_calc_valid;read_valid<=vertical_step;select_valid<=read_valid;mix_valid<=select_valid;
        // Limit the vertical line burst to 6.25 Mpixel/s at 100 MHz.
        // Without pacing, packed writes can reach 50 Mword/s and compete
        // with the 75 MHz video consumer on the 50 MHz SDRAM interface.
        if(!v_run || vertical_pace==VERTICAL_PERIOD-1) vertical_pace<=0;
        else vertical_pace<=vertical_pace+1'b1;
        if(h_calc_valid) begin
            h_addr<=h_calc_addr;h_bank_q<=h_calc_bank;h_row_q<=h_calc_row;h_last<=h_calc_last;
            h_base<=h_calc_base;
            hp_r<=hd_r*$signed({1'b0,h_calc_weight});
            hp_g<=hd_g*$signed({1'b0,h_calc_weight});
            hp_b<=hd_b*$signed({1'b0,h_calc_weight});
        end
        if(dividing) begin
            x_dividend<={x_dividend[25:0],1'b0};y_dividend<={y_dividend[25:0],1'b0};
            x_quotient<={x_quotient[25:0],x_div_bit};y_quotient<={y_quotient[25:0],y_div_bit};
            x_remainder<=x_div_bit ? x_trial-(OUT_WIDTH-1) : x_trial;
            y_remainder<=y_div_bit ? y_trial-(OUT_HEIGHT-1) : y_trial;
            if(divide_count==26) begin
                x_step<={x_quotient[15:0],x_div_bit};y_step<={y_quotient[15:0],y_div_bit};dividing<=0;
            end else divide_count<=divide_count+1'b1;
        end
        if(pixel_valid && active) begin
            if(native_size) begin
                pixel_out_valid<=1;pixel_out<=pixel_in;
                if(in_x==source_last_x && in_y==source_last_y) active<=0;
            end else begin
                if(h_run || dividing) begin fault<=1;active<=0;end
                current_pixel<=pixel_in;
                left_pixel<=(in_x==0) ? pixel_in : previous_pixel;
                previous_pixel<=pixel_in;sample_x<=in_x;sample_y<=in_y;h_bank<=write_bank;h_run<=1;
            end
            if(in_x==source_last_x) begin
                in_x<=0;in_y<=in_y+1'b1;write_bank<=(write_bank==2) ? 0 : write_bank+1'b1;
            end else in_x<=in_x+1'b1;
        end
        if(h_run) begin
            if(h_available) begin
                h_calc_valid<=1;h_calc_addr<=hx;h_calc_bank<=h_bank;h_calc_row<=sample_y;h_calc_last<=(hx==OUT_WIDTH-1);
                h_calc_base<=h_left;h_calc_weight<=h_weight;
                hd_r<=$signed({1'b0,current_pixel[23:16]})-$signed({1'b0,h_left[23:16]});
                hd_g<=$signed({1'b0,current_pixel[15:8]})-$signed({1'b0,h_left[15:8]});
                hd_b<=$signed({1'b0,current_pixel[7:0]})-$signed({1'b0,h_left[7:0]});
                if(hx==OUT_WIDTH-1) begin hx<=0;xpos<=0;h_run<=0;end
                else begin hx<=hx+1'b1;xpos<=xpos+x_step;end
            end else h_run<=0;
        end
        if(h_valid && h_last) begin
            // Entire horizontally resampled row is now committed in line RAM.
            if(v_run) begin fault<=1;active<=0;end
            else if(ypos[26:16]<h_row_q || (ypos[26:16]==h_row_q && ypos[15:0]==0)) begin
                v_run<=1;v_bank<=h_bank_q;v_source_y<=h_row_q;vx<=0;
            end
        end
        if(vertical_step) begin
            read_chunk<=vx>>9;read_bank<=v_bank;read_first<=(v_source_y==0);
            read_integer<=(ypos[15:0]==0);
            read_weight<=ypos[15:8];read_last<=(vx==OUT_WIDTH-1 && vy==OUT_HEIGHT-1);
            if(vx==OUT_WIDTH-1) begin
                vx<=0;vy<=vy+1'b1;ypos<=next_ypos;
                if(vy==OUT_HEIGHT-1 || !next_y_available) v_run<=0;
            end else vx<=vx+1'b1;
        end
        if(read_valid) begin
            selected_current<=current_rgb;selected_previous<=previous_rgb;
            selected_weight<=vga_crisp ? 8'd0 : read_weight;select_last<=read_last;
        end
        if(select_valid) begin
            mix_base<=selected_previous;mix_last<=select_last;
            vp_r<=($signed({1'b0,selected_current[23:16]})-$signed({1'b0,selected_previous[23:16]}))*$signed({1'b0,selected_weight});
            vp_g<=($signed({1'b0,selected_current[15:8]})-$signed({1'b0,selected_previous[15:8]}))*$signed({1'b0,selected_weight});
            vp_b<=($signed({1'b0,selected_current[7:0]})-$signed({1'b0,selected_previous[7:0]}))*$signed({1'b0,selected_weight});
        end
        if(mix_valid) begin
            pixel_out_valid<=1;
            pixel_out<={vr,vg,vb};
            if(mix_last) active<=0;
        end
    end
end
endmodule
