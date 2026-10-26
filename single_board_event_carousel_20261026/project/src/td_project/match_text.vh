function [7:0] team_char;input [5:0] sel,p;begin team_char=0;case(sel)
0:case(p)0:team_char=8'd11;1:team_char=8'd12;default:team_char=0;endcase
1:case(p)0:team_char=8'd13;1:team_char=8'd12;default:team_char=0;endcase
2:case(p)0:team_char=8'd14;1:team_char=8'd15;default:team_char=0;endcase
3:case(p)0:team_char=8'd16;1:team_char=8'd17;default:team_char=0;endcase
4:case(p)0:team_char=8'd18;1:team_char=8'd19;default:team_char=0;endcase
5:case(p)0:team_char=8'd20;1:team_char=8'd21;default:team_char=0;endcase
default:team_char=0;endcase end endfunction
function [7:0] state_char;input [5:0] sel,p;begin state_char=0;case(sel)
0:case(p)0:state_char=8'd22;1:state_char=8'd23;2:state_char=8'd24;3:state_char=8'd25;default:state_char=0;endcase
1:case(p)0:state_char=8'd23;1:state_char=8'd26;2:state_char=8'd27;3:state_char=8'd28;default:state_char=0;endcase
2:case(p)0:state_char=8'd22;1:state_char=8'd29;2:state_char=8'd30;3:state_char=8'd31;default:state_char=0;endcase
3:case(p)0:state_char=8'd22;1:state_char=8'd23;2:state_char=8'd32;3:state_char=8'd33;default:state_char=0;endcase
4:case(p)0:state_char=8'd34;1:state_char=8'd35;2:state_char=8'd36;3:state_char=8'd37;default:state_char=0;endcase
default:state_char=0;endcase end endfunction
function [7:0] page_char;input [5:0] sel,p;begin page_char=0;case(sel)
0:case(p)0:page_char=8'd23;1:page_char=8'd38;2:page_char=8'd39;3:page_char=8'd40;default:page_char=0;endcase
1:case(p)0:page_char=8'd41;1:page_char=8'd42;2:page_char=8'd43;3:page_char=8'd44;default:page_char=0;endcase
2:case(p)0:page_char=8'd23;1:page_char=8'd45;2:page_char=8'd46;3:page_char=8'd47;default:page_char=0;endcase
3:case(p)0:page_char=8'd48;1:page_char=8'd49;2:page_char=8'd50;3:page_char=8'd51;default:page_char=0;endcase
default:page_char=0;endcase end endfunction
function [7:0] text_char;input [5:0] sel,p;begin text_char=0;case(sel)
0:case(p)0:text_char=8'd23;1:text_char=8'd52;2:text_char=8'd0;3:text_char=8'd53;4:text_char=8'd0;5:text_char=8'd23;6:text_char=8'd38;7:text_char=8'd52;8:text_char=8'd54;default:text_char=0;endcase
1:case(p)0:text_char=8'd55;1:text_char=8'd56;2:text_char=8'd57;3:text_char=8'd58;4:text_char=8'd59;5:text_char=8'd60;6:text_char=8'd23;default:text_char=0;endcase
2:case(p)0:text_char=8'd61;1:text_char=8'd12;default:text_char=0;endcase
3:case(p)0:text_char=8'd62;1:text_char=8'd12;default:text_char=0;endcase
4:case(p)0:text_char=8'd63;1:text_char=8'd64;2:text_char=8'd65;3:text_char=8'd66;default:text_char=0;endcase
5:case(p)0:text_char=8'd22;1:text_char=8'd23;2:text_char=8'd65;3:text_char=8'd67;default:text_char=0;endcase
6:case(p)0:text_char=8'd68;1:text_char=8'd69;2:text_char=8'd70;3:text_char=8'd71;default:text_char=0;endcase
7:case(p)0:text_char=8'd23;1:text_char=8'd26;2:text_char=8'd43;3:text_char=8'd44;4:text_char=8'd0;5:text_char=8'd22;6:text_char=8'd29;7:text_char=8'd30;8:text_char=8'd31;9:text_char=8'd0;10:text_char=8'd23;11:text_char=8'd69;12:text_char=8'd34;13:text_char=8'd35;default:text_char=0;endcase
8:case(p)0:text_char=8'd23;1:text_char=8'd38;2:text_char=8'd72;3:text_char=8'd31;default:text_char=0;endcase
9:case(p)0:text_char=8'd27;1:text_char=8'd73;2:text_char=8'd65;3:text_char=8'd0;4:text_char=8'd53;5:text_char=8'd0;6:text_char=8'd41;7:text_char=8'd42;8:text_char=8'd22;9:text_char=8'd29;default:text_char=0;endcase
10:case(p)0:text_char=8'd74;1:text_char=8'd75;2:text_char=8'd76;3:text_char=8'd49;4:text_char=8'd77;5:text_char=8'd78;6:text_char=8'd23;7:text_char=8'd38;default:text_char=0;endcase
11:case(p)0:text_char=8'd79;1:text_char=8'd49;2:text_char=8'd80;3:text_char=8'd81;default:text_char=0;endcase
12:case(p)0:text_char=8'd82;1:text_char=8'd83;2:text_char=8'd84;3:text_char=8'd41;4:text_char=8'd42;5:text_char=8'd85;6:text_char=8'd74;7:text_char=8'd75;8:text_char=8'd22;9:text_char=8'd23;default:text_char=0;endcase
13:case(p)0:text_char=8'd86;1:text_char=8'd26;2:text_char=8'd49;3:text_char=8'd87;default:text_char=0;endcase
14:case(p)0:text_char=8'd86;1:text_char=8'd26;2:text_char=8'd80;3:text_char=8'd81;default:text_char=0;endcase
15:case(p)0:text_char=8'd88;1:text_char=8'd76;2:text_char=8'd49;3:text_char=8'd87;default:text_char=0;endcase
16:case(p)0:text_char=8'd89;1:text_char=8'd46;2:text_char=8'd47;3:text_char=8'd0;4:text_char=8'd90;5:text_char=8'd49;6:text_char=8'd91;7:text_char=8'd92;default:text_char=0;endcase
17:case(p)0:text_char=8'd82;1:text_char=8'd41;2:text_char=8'd42;3:text_char=8'd93;4:text_char=8'd94;5:text_char=8'd95;6:text_char=8'd49;7:text_char=8'd24;8:text_char=8'd25;default:text_char=0;endcase
18:case(p)0:text_char=8'd23;1:text_char=8'd38;2:text_char=8'd96;3:text_char=8'd97;4:text_char=8'd98;5:text_char=8'd22;6:text_char=8'd23;7:text_char=8'd22;8:text_char=8'd29;9:text_char=8'd99;10:text_char=8'd100;11:text_char=8'd101;12:text_char=8'd102;default:text_char=0;endcase
19:case(p)0:text_char=8'd103;1:text_char=8'd104;2:text_char=8'd22;3:text_char=8'd23;4:text_char=8'd50;5:text_char=8'd51;default:text_char=0;endcase
20:case(p)0:text_char=8'd77;1:text_char=8'd105;2:text_char=8'd76;3:text_char=8'd49;4:text_char=8'd22;5:text_char=8'd23;6:text_char=8'd69;7:text_char=8'd99;8:text_char=8'd100;9:text_char=8'd106;10:text_char=8'd107;default:text_char=0;endcase
21:case(p)0:text_char=8'd68;1:text_char=8'd108;2:text_char=8'd105;3:text_char=8'd109;default:text_char=0;endcase
22:case(p)0:text_char=8'd110;1:text_char=8'd111;2:text_char=8'd0;3:text_char=8'd41;4:text_char=8'd42;5:text_char=8'd112;6:text_char=8'd113;default:text_char=0;endcase
23:case(p)0:text_char=8'd114;1:text_char=8'd115;default:text_char=0;endcase
24:case(p)0:text_char=8'd79;1:text_char=8'd49;2:text_char=8'd50;3:text_char=8'd51;4:text_char=8'd116;5:text_char=8'd117;6:text_char=8'd118;default:text_char=0;endcase
25:case(p)0:text_char=8'd48;1:text_char=8'd49;2:text_char=8'd50;3:text_char=8'd51;4:text_char=8'd116;5:text_char=8'd99;6:text_char=8'd100;7:text_char=8'd106;8:text_char=8'd107;default:text_char=0;endcase
26:case(p)0:text_char=8'd105;1:text_char=8'd109;2:text_char=8'd119;3:text_char=8'd120;default:text_char=0;endcase
27:case(p)0:text_char=8'd83;1:text_char=8'd84;2:text_char=8'd41;3:text_char=8'd42;4:text_char=8'd121;5:text_char=8'd22;6:text_char=8'd23;7:text_char=8'd65;8:text_char=8'd67;default:text_char=0;endcase
28:case(p)0:text_char=8'd24;1:text_char=8'd25;2:text_char=8'd74;3:text_char=8'd75;default:text_char=0;endcase
29:case(p)0:text_char=8'd22;1:text_char=8'd23;2:text_char=8'd122;3:text_char=8'd123;4:text_char=8'd124;default:text_char=0;endcase
30:case(p)0:text_char=8'd32;1:text_char=8'd33;2:text_char=8'd124;3:text_char=8'd0;4:text_char=8'd125;5:text_char=8'd126;6:text_char=8'd127;7:text_char=8'd22;8:text_char=8'd29;default:text_char=0;endcase
31:case(p)0:text_char=8'd128;1:text_char=8'd2;2:text_char=8'd0;3:text_char=8'd61;4:text_char=8'd12;5:text_char=8'd0;6:text_char=8'd0;7:text_char=8'd128;8:text_char=8'd3;9:text_char=8'd0;10:text_char=8'd62;11:text_char=8'd12;12:text_char=8'd0;13:text_char=8'd0;14:text_char=8'd128;15:text_char=8'd4;16:text_char=8'd0;17:text_char=8'd65;18:text_char=8'd67;19:text_char=8'd0;20:text_char=8'd0;21:text_char=8'd128;22:text_char=8'd5;23:text_char=8'd0;24:text_char=8'd74;25:text_char=8'd75;default:text_char=0;endcase
32:case(p)0:text_char=8'd67;1:text_char=8'd129;2:text_char=8'd128;3:text_char=8'd5;4:text_char=8'd130;5:text_char=8'd131;6:text_char=8'd23;7:text_char=8'd38;8:text_char=8'd72;9:text_char=8'd31;default:text_char=0;endcase
33:case(p)0:text_char=8'd128;1:text_char=8'd2;2:text_char=8'd132;3:text_char=8'd128;4:text_char=8'd3;5:text_char=8'd0;6:text_char=8'd133;7:text_char=8'd129;8:text_char=8'd134;9:text_char=8'd29;10:text_char=8'd0;11:text_char=8'd67;12:text_char=8'd129;13:text_char=8'd135;14:text_char=8'd29;default:text_char=0;endcase
34:case(p)0:text_char=8'd128;1:text_char=8'd4;2:text_char=8'd0;3:text_char=8'd32;4:text_char=8'd33;5:text_char=8'd136;6:text_char=8'd137;7:text_char=8'd138;8:text_char=8'd0;9:text_char=8'd0;10:text_char=8'd67;11:text_char=8'd129;12:text_char=8'd128;13:text_char=8'd5;14:text_char=8'd139;15:text_char=8'd26;16:text_char=8'd50;17:text_char=8'd140;default:text_char=0;endcase
35:case(p)0:text_char=8'd4;1:text_char=8'd0;2:text_char=8'd3;3:text_char=8'd0;4:text_char=8'd2;5:text_char=8'd0;6:text_char=8'd69;7:text_char=8'd99;8:text_char=8'd100;9:text_char=8'd74;10:text_char=8'd75;11:text_char=8'd22;12:text_char=8'd23;default:text_char=0;endcase
36:case(p)0:text_char=8'd67;1:text_char=8'd129;2:text_char=8'd128;3:text_char=8'd5;4:text_char=8'd141;5:text_char=8'd142;6:text_char=8'd0;7:text_char=8'd130;8:text_char=8'd131;9:text_char=8'd22;10:text_char=8'd23;11:text_char=8'd24;12:text_char=8'd25;default:text_char=0;endcase
37:case(p)0:text_char=8'd34;1:text_char=8'd35;2:text_char=8'd69;3:text_char=8'd99;4:text_char=8'd100;5:text_char=8'd119;6:text_char=8'd120;7:text_char=8'd105;8:text_char=8'd109;9:text_char=8'd112;10:text_char=8'd131;11:text_char=8'd95;12:text_char=8'd72;13:text_char=8'd31;default:text_char=0;endcase
38:case(p)0:text_char=8'd128;1:text_char=8'd5;2:text_char=8'd143;3:text_char=8'd144;4:text_char=8'd130;5:text_char=8'd131;6:text_char=8'd72;7:text_char=8'd31;8:text_char=8'd0;9:text_char=8'd50;10:text_char=8'd51;11:text_char=8'd145;12:text_char=8'd106;13:text_char=8'd146;default:text_char=0;endcase
39:case(p)0:text_char=8'd147;1:text_char=8'd40;2:text_char=8'd148;3:text_char=8'd71;4:text_char=8'd0;5:text_char=8'd128;6:text_char=8'd2;7:text_char=8'd48;8:text_char=8'd76;9:text_char=8'd40;10:text_char=8'd0;11:text_char=8'd128;12:text_char=8'd3;13:text_char=8'd88;14:text_char=8'd76;15:text_char=8'd40;default:text_char=0;endcase
40:case(p)0:text_char=8'd128;1:text_char=8'd4;2:text_char=8'd22;3:text_char=8'd23;4:text_char=8'd24;5:text_char=8'd25;6:text_char=8'd0;7:text_char=8'd128;8:text_char=8'd5;9:text_char=8'd30;10:text_char=8'd102;11:text_char=8'd74;12:text_char=8'd23;default:text_char=0;endcase
41:case(p)0:text_char=8'd1;1:text_char=8'd2;2:text_char=8'd3;3:text_char=8'd4;4:text_char=8'd5;5:text_char=8'd6;6:text_char=8'd7;7:text_char=8'd8;8:text_char=8'd9;9:text_char=8'd10;10:text_char=8'd149;11:text_char=8'd0;12:text_char=8'd132;default:text_char=0;endcase
42:case(p)0:text_char=8'd150;default:text_char=0;endcase
43:case(p)0:text_char=8'd49;default:text_char=0;endcase
44:case(p)0:text_char=8'd151;1:text_char=8'd152;default:text_char=0;endcase
default:text_char=0;endcase end endfunction
function [7:0] cell_glyph;input [5:0] col;input [4:0] row;reg [2:0] winner;begin cell_glyph=0;winner=sa>sb ? fa:fb;
case(row)
1:begin if(col>=2 && col<11)cell_glyph=text_char(0,col-2);if(col>=30)begin if(fs==4 && summary)cell_glyph=text_char(26,col-30);else cell_glyph=fs==5 ? page_char(pg,col-30):state_char(fs,col-30);end end
3:begin if(col>=2 && col<9)cell_glyph=text_char(1,col-2);case(col)30:cell_glyph=8'd150;31:cell_glyph=8'd1+round_tens;32:cell_glyph=8'd1+round_units;33:cell_glyph=8'd49;default:;endcase end
default:;endcase
if(fs==5)begin case(pg)
0:case(row)
5:begin if(col>=4 && col<18)cell_glyph=text_char(7,col-4); end
9:begin if(col>=6 && col<10)cell_glyph=text_char(8,col-6); end
11:begin if(col>=6 && col<16)cell_glyph=text_char(9,col-6); end
14:begin if(col>=6 && col<14)cell_glyph=text_char(10,col-6); end
default:;endcase
1:case(row)
4:begin if(col>=4 && col<6)cell_glyph=text_char(2,col-4);if(col>=29 && col<31)cell_glyph=text_char(3,col-29); end
5:begin if(col>=4 && col<6)cell_glyph=team_char(fa,col-4);if(col>=29 && col<31)cell_glyph=team_char(fb,col-29); end
7:begin if(col>=16 && col<20)cell_glyph=text_char(11,col-16); end
10:begin if(col>=19 && col<21)cell_glyph=text_char(44,col-19); end
14:begin if(col>=12 && col<22)cell_glyph=text_char(12,col-12); end
default:;endcase
2:case(row)
6:begin if(col>=4 && col<8)cell_glyph=text_char(13,col-4);if(col>=14 && col<18)cell_glyph=text_char(14,col-14); end
8:begin if(col>=14 && col<16)cell_glyph=team_char(fa,col-14);if(col>=18 && col<20)cell_glyph=text_char(44,col-18);if(col>=22 && col<24)cell_glyph=team_char(fb,col-22); end
10:begin if(col>=4 && col<8)cell_glyph=text_char(15,col-4);if(col>=14 && col<22)cell_glyph=text_char(16,col-14); end
12:begin if(col>=4 && col<13)cell_glyph=text_char(17,col-4); end
14:begin if(col>=4 && col<17)cell_glyph=text_char(18,col-4); end
default:;endcase
3:begin if(lv)begin case(row)
4:begin if(col>=4 && col<6)cell_glyph=text_char(2,col-4);if(col>=29 && col<31)cell_glyph=text_char(3,col-29); end
5:begin if(col>=4 && col<6)cell_glyph=team_char(fa,col-4);if(col>=29 && col<31)cell_glyph=team_char(fb,col-29); end
7:begin if(col>=17 && col<21)cell_glyph=text_char(21,col-17); end
14:begin if(sa==sb)begin if(col>=15 && col<22)cell_glyph=text_char(22,col-15);end else begin if(col>=16 && col<18)cell_glyph=team_char(winner,col-16);if(col>=19 && col<21)cell_glyph=text_char(23,col-19);end end
16:begin if(col>=13 && col<22)cell_glyph=text_char(25,col-13); end
default:;endcase end else begin case(row)
9:begin if(col>=16 && col<22)cell_glyph=text_char(19,col-16); end
13:begin if(col>=12 && col<23)cell_glyph=text_char(20,col-12); end
default:;endcase end end
endcase
case(row)
18:begin if(col>=2 && col<18)cell_glyph=text_char(39,col-2); end
20:begin if(col>=2 && col<15)cell_glyph=text_char(40,col-2); end
default:;endcase end else begin
case(row)
4:begin if(col>=4 && col<6)cell_glyph=text_char(2,col-4);if(col>=29 && col<31)cell_glyph=text_char(3,col-29); end
5:begin if(col>=4 && col<6)cell_glyph=team_char(fa,col-4);if(col>=29 && col<31)cell_glyph=team_char(fb,col-29); end
7:begin if(fs==0 || fs==2 || fs==3)begin if(col>=16 && col<20)cell_glyph=text_char(4,col-16);end else if(fs==4 && summary)begin if(col>=17 && col<21)cell_glyph=text_char(21,col-17);end end
14:begin if(fs==0)begin if(col>=12 && col<21)cell_glyph=text_char(27,col-12);end else if(fs==1)begin if(col>=17 && col<21)cell_glyph=text_char(28,col-17);end else if(fs==2)begin if(col>=16 && col<21)cell_glyph=text_char(29,col-16);end else if(fs==3)begin if(col>=14 && col<23)cell_glyph=text_char(30,col-14);end else if(fs==4 && summary)begin if(sa==sb)begin if(col>=15 && col<22)cell_glyph=text_char(22,col-15);end else begin if(col>=16 && col<18)cell_glyph=team_char(winner,col-16);if(col>=19 && col<21)cell_glyph=text_char(23,col-19);end end end
17:begin if(fs==4 && !summary)begin if(sa==sb)begin if(col>=15 && col<22)cell_glyph=text_char(22,col-15);end else begin if(col>=16 && col<18)cell_glyph=team_char(winner,col-16);if(col>=19 && col<21)cell_glyph=text_char(23,col-19);end end end
16:begin if(fs==0)begin if(col>=13 && col<17)cell_glyph=text_char(5,col-13);case(col)18:cell_glyph=8'd1;19:cell_glyph=8'd1+(dur==2 ? 3:dur==3 ? 5:dur==1 ? 1:0);20:cell_glyph=8'd149;21:cell_glyph=8'd1+(dur==0 ? 3:0);22:cell_glyph=8'd1;default:;endcase end else if(fs==2 && sec<=10)begin if(col>=16 && col<20)cell_glyph=text_char(6,col-16);end end
18,20:begin if(fs==0)begin if(row==18)begin if(col>=2 && col<28)cell_glyph=text_char(31,col-2);end else begin if(col>=2 && col<12)cell_glyph=text_char(32,col-2);end end
else if(fs==1)begin if(row==18)begin if(col>=2 && col<15)cell_glyph=text_char(35,col-2);end else begin if(col>=2 && col<15)cell_glyph=text_char(36,col-2);end end
else if(fs==4)begin if(row==18)begin if(col>=2 && col<16)cell_glyph=text_char(37,col-2);end else begin if(col>=2 && col<16)cell_glyph=text_char(38,col-2);end end
else begin if(row==18)begin if(col>=2 && col<17)cell_glyph=text_char(33,col-2);end else begin if(col>=2 && col<20)cell_glyph=text_char(34,col-2);end end end
default:;endcase end
end endfunction
