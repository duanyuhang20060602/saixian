function [23:0] trophy_color;input [3:0] i;begin case(i)
0:trophy_color=24'h000000;
1:trophy_color=24'hdacab7;
2:trophy_color=24'hcab497;
3:trophy_color=24'hc3a173;
4:trophy_color=24'hb49a76;
5:trophy_color=24'hb18a51;
6:trophy_color=24'hab7b34;
7:trophy_color=24'h9f7e4d;
8:trophy_color=24'h9a7232;
9:trophy_color=24'h966921;
10:trophy_color=24'h905f12;
11:trophy_color=24'h805d20;
12:trophy_color=24'h795211;
13:trophy_color=24'h724808;
14:trophy_color=24'h5f410e;
15:trophy_color=24'h3f2704;
default:trophy_color=0;endcase end endfunction
