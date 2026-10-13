module photo_auto_advance #(
    parameter integer CLK_FREQ_HZ=75000000,
    parameter integer HOLD_SECONDS=5
)(
    input wire clk,rst,enable,display_valid,transition_active,busy,enough_images,
    input wire settings_mode,manual_event,
    output reg next_pulse
);
localparam integer HOLD_CYCLES=CLK_FREQ_HZ*HOLD_SECONDS;
reg [31:0] hold_count;
always @(posedge clk or posedge rst) begin
    if(rst) begin hold_count<=0;next_pulse<=0;end
    else begin
        next_pulse<=0;
        if(!enable || !display_valid || transition_active || busy || !enough_images ||
           settings_mode || manual_event) hold_count<=0;
        else if(hold_count>=HOLD_CYCLES-1) begin hold_count<=0;next_pulse<=1;end
        else hold_count<=hold_count+1'b1;
    end
end
endmodule
