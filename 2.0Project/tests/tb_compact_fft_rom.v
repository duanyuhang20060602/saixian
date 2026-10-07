`timescale 1ns/1ps
module tb_compact_fft_rom;
reg clk=0,rst=1;
reg [9:0] index=0;
reg [8:0] coefficient=0;
reg [5:0] fetch_state=6;
reg [15:0] hann[0:1023];
reg [31:0] twiddle[0:511],bands[0:31];
integer i;
always #5 clk=~clk;
saixian_av_fft dut(.clk(clk),.rst(rst),.frame_tick(1'b0),.sample_valid(1'b0),
    .left(16'sd0),.right(16'sd0),.read_band(5'd0));
initial begin
    $readmemh("src/user_source/hdl_source/saixian_av_hann.hex",hann);
    $readmemh("src/user_source/hdl_source/saixian_av_twiddle.hex",twiddle);
    $readmemh("src/user_source/hdl_source/saixian_av_bands.hex",bands);
    repeat(4) @(negedge clk);rst=0;
    force dut.load_index=index;force dut.twiddle_index=coefficient;force dut.state=fetch_state;
    for(i=0;i<1024;i=i+1) begin
        index=i;@(negedge clk);
        if(dut.hann_q!==hann[i]) $fatal(1,"Hann symmetry mismatch %d",i);
    end
    for(i=0;i<512;i=i+1) begin
        coefficient=i;
        fetch_state=6;@(negedge clk); // WAIT_A: read real
        fetch_state=7;@(negedge clk); // GET_A: save real, read imaginary
        fetch_state=8;@(negedge clk); // WAIT_B
        fetch_state=9;@(negedge clk); // GET_B: save imaginary
        if({dut.wr,dut.wi}!==twiddle[i]) $fatal(1,"serial quadrant coefficient mismatch %d",i);
    end
    for(i=0;i<32;i=i+1)
        if(dut.band_descriptor(i)!==bands[i]) $fatal(1,"band descriptor mismatch %d",i);
    $display("PASS all 1024 Hann values, 512 complex twiddles including signed axes, and 32 band descriptors exactly match canonical ROMs");$finish;
end
endmodule
