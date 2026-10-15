`timescale 1ns/1ps
// Same RTL and fixed point reference, faster scheduling than the SPI clock.
module tb_scaler_full;
wire done;
scaler_case #(.SW(640),.SH(360),.PACE(1),.PIXEL_PERIOD(12),.ROWS(360)) full_frame(done);
initial begin wait(done);$finish;end
initial begin #100000000;$fatal(1,"full scaler timeout");end
endmodule
