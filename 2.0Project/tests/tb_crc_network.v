`timescale 1ns/1ps
module tb_crc_network;
delta_memory memory_bus();
delta_player player();
reg [31:0] old,word,expected;
integer i,k;
initial begin
for(i=0;i<10000;i=i+1)begin
 old=$random;word=$random;expected=old^word;
 for(k=0;k<32;k=k+1)expected=expected[0] ? (expected>>1)^32'hedb88320 : expected>>1;
 if(memory_bus.crc_word(old,word)!==expected || player.crc_word(old,word)!==expected ||
 player.decode.crc_word(old,word)!==expected)$fatal(1,"CRC network mismatch");
end
$display("PASS production CRC XOR sharing: loader memory, player and decoder functions match 10000 arbitrary input/state pairs");$finish;
end
endmodule
