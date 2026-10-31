`timescale 1ns/1ps
// Application CRC protects the new sideband even on the compact control link.
module photo_text_crc(input [79:0] data,output [15:0] crc);
function [15:0] calculate;input [79:0] d;integer i;reg[15:0] c;begin
 c=16'hffff;for(i=79;i>=0;i=i-1)c={c[14:0],1'b0}^((c[15]^d[i])?16'h1021:16'd0);calculate=c;
end endfunction
assign crc=calculate(data);
endmodule

