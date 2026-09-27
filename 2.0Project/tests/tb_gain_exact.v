`timescale 1ns/1ps
module tb_gain_exact;
reg clk=0;always #5 clk=~clk;
wire [23:0] out;
saixian_picture_adjust_pipe dut(clk,1'b1,1'b0,11'd0,24'd0,4'd4,4'd4,4'd4,2'd0,out);
reg signed [10:0] value;
integer v,l,e,checks=0;
initial begin
    for(v=-383;v<=382;v=v+1) for(l=0;l<16;l=l+1) begin
        value=v;
        case(l)
            0:e=v>>>1;1:e=(v>>>1)+(v>>>3);
            2:e=(v>>>1)+(v>>>2);3:e=v-(v>>>3);
            4:e=v;5:e=v+(v>>>3);6:e=v+(v>>>2);
            7:e=v+(v>>>1);default:e=v+(v>>>1)+(v>>>2);
        endcase
        if($signed(dut.contrast_scale_pipe(value,4'(l)))!==e ||
           $signed(dut.decoded_gain(value,dut.gain_config(4'(l),1'b0)))!==e)
            $fatal(1,"contrast gain not exact v=%d l=%d",v,l);
        checks=checks+1;
    end
    for(v=-255;v<=255;v=v+1) for(l=0;l<16;l=l+1) begin
        value=v;
        case(l)
            0:e=0;1:e=v>>>2;2:e=v>>>1;3:e=v-(v>>>2);
            4:e=v;5:e=v+(v>>>3);6:e=v+(v>>>2);
            7:e=v+(v>>>1);default:e=v+(v>>>1)+(v>>>2);
        endcase
        if($signed(dut.saturation_scale_pipe(value,4'(l)))!==e ||
           $signed(dut.decoded_gain(value,dut.gain_config(4'(l),1'b1)))!==e)
            $fatal(1,"saturation gain not exact v=%d l=%d",v,l);
        checks=checks+1;
    end
    $display("PASS exact DSP gains including negative rounding: %d exhaustive cases",checks);$finish;
end
endmodule
