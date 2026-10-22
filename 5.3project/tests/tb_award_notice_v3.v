module tb_award_notice_v3;
reg [2:0] notice=0;reg [11:0] x=26;reg [10:0] y=22;wire [23:0] rgb;
photo_award_notice dut(.notice(notice),.x(x),.y(y),.rgb_in(24'h123456),.rgb_out(rgb));
integer n;
initial begin
 #1;if(rgb!==24'h123456)$fatal(1,"disabled notice modified image");
 for(n=1;n<=3;n=n+1)begin
  notice=n;x=26;y=22;#1;if(rgb!==24'hffffff)$fatal(1,"notice glyph missing");
  x=24;#1;if(rgb!==24'h202020)$fatal(1,"notice background missing");
  x=282;#1;if(rgb!==24'h123456)$fatal(1,"notice affected pixels outside banner");
 end
 notice=4;x=26;y=22;#1;if(rgb!==24'hffffff)$fatal(1,"photo error P glyph missing");
 if(dut.message!=="PHOTO ERROR    ")$fatal(1,"photo failure mislabeled as award");
 $display("PASS photo error and loading/missing/error banner glyph, background, disabled/outside image preservation");$finish;
end
endmodule
