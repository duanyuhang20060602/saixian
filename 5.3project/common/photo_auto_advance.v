module photo_auto_advance #(
    parameter integer CLK_FREQ_HZ=75000000,
    parameter integer HOLD_SECONDS=5,
    parameter integer ADJUSTABLE=0
)(
    input wire clk,rst,enable,display_valid,transition_active,busy,enough_images,
    input wire settings_mode,manual_event,
    output reg next_pulse,input [4:0] interval_seconds
);
// Count seconds separately: adjustable intervals need no variable multiplier
// and the system-clock counter is only 27 bits at 75 MHz.
localparam SECOND_BITS=($clog2(CLK_FREQ_HZ)>0) ? $clog2(CLK_FREQ_HZ):1;
localparam HOLD_BITS=($clog2(HOLD_SECONDS+1)>5) ? $clog2(HOLD_SECONDS+1):5;
wire [HOLD_BITS-1:0] seconds=ADJUSTABLE ?
    (interval_seconds==0 ? 5'd1:interval_seconds):HOLD_SECONDS;
reg [SECOND_BITS-1:0] subsecond;
reg [HOLD_BITS-1:0] elapsed,last_seconds;
always @(posedge clk or posedge rst) begin
    if(rst) begin subsecond<=0;elapsed<=0;last_seconds<=HOLD_SECONDS;next_pulse<=0;end
    else begin
        next_pulse<=0;last_seconds<=seconds;
        if(!enable || !display_valid || transition_active || busy || !enough_images ||
           settings_mode || manual_event || seconds!=last_seconds)begin subsecond<=0;elapsed<=0;end
        else if(subsecond==CLK_FREQ_HZ-1)begin
            subsecond<=0;
            if(elapsed>=seconds-1'b1)begin elapsed<=0;next_pulse<=1;end
            else elapsed<=elapsed+1'b1;
        end else subsecond<=subsecond+1'b1;
    end
end
endmodule
