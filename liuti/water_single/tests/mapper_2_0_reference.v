module mapper_2_0_reference #(
    parameter ADDR_BITS=21, FRAME_WIDTH=640
)(
    input [10:0] xpos, input [9:0] ypos,
    input [ADDR_BITS-1:0] old_base, new_base,
    input enabled, move_right, input [2:0] effect, input [10:0] offset,
    output [ADDR_BITS-1:0] address
);
localparam [11:0] WIDTH_U=FRAME_WIDTH;
reg [11:0] split, diagonal_position, diagonal_limit;
reg [10:0] half_reveal;
reg [6:0] blind_local_y;
reg [3:0] dissolve_pattern;
reg use_new, subtract_delta;
reg [11:0] delta;
reg [ADDR_BITS-1:0] selected_base;
reg signed [13:0] local_column;
wire signed [ADDR_BITS-1:0] extended_column=local_column;
assign address=selected_base+extended_column;
always @* begin
    split=WIDTH_U-{1'b0,offset};
    half_reveal=offset>>1;
    if(ypos<90) blind_local_y=ypos[6:0];
    else if(ypos<180) blind_local_y=ypos-10'd90;
    else if(ypos<270) blind_local_y=ypos-10'd180;
    else if(ypos<360) blind_local_y=ypos-10'd270;
    else if(ypos<450) blind_local_y=ypos-10'd360;
    else if(ypos<540) blind_local_y=ypos-10'd450;
    else if(ypos<630) blind_local_y=ypos-10'd540;
    else blind_local_y=ypos-10'd630;
    diagonal_position=move_right ? ({1'b0,(WIDTH_U-1'b1)-xpos}+ypos) : ({1'b0,xpos}+ypos);
    diagonal_limit=({1'b0,offset}<<1)+(offset>>1);
    dissolve_pattern={xpos[9]^ypos[9],xpos[8]^ypos[8],xpos[7]^ypos[7],xpos[6]^ypos[6]};
    use_new=0;
    if(enabled) case(effect)
        1:use_new=({1'b0,xpos}>=((WIDTH_U>>1)-{1'b0,half_reveal})) &&
                  ({1'b0,xpos}<((WIDTH_U>>1)+{1'b0,half_reveal}));
        2:use_new=blind_local_y<((offset>>3)+(offset>>6));
        3:use_new=diagonal_position<diagonal_limit;
        4:use_new={1'b0,(move_right ? ~dissolve_pattern : dissolve_pattern)}<(offset>>5);
        5:use_new={1'b0,offset}>=(WIDTH_U>>1);
        default:use_new=0;
    endcase
    delta=0; subtract_delta=0;
    if(enabled && effect==0) begin
        if(!move_right) begin
            use_new={1'b0,xpos}>=split;
            delta=use_new ? split : {1'b0,offset};
            subtract_delta=use_new;
        end else begin
            use_new=xpos<offset;
            delta=use_new ? split : {1'b0,offset};
            subtract_delta=!use_new;
        end
    end
    selected_base=use_new ? new_base : old_base;
    local_column={3'b0,xpos}+({2'b0,delta}^{14{subtract_delta}})+subtract_delta;
end
endmodule
