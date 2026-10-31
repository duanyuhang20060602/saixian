// Packed strings occupy unused words of the same32K glyph ROM.
module photo_match_text_query(input[5:0] col,input[4:0] row,input[2:0] state,team_a,team_b,
 input[9:0] score_a,score_b,input[8:0] seconds,input[1:0] duration_index,
 output reg[8:0] address,output reg direct,output reg[6:0] glyph);
reg[2:0] winner,help;
task select_text;input[8:0] base;input[5:0] pos,limit;begin
 if(pos<limit)begin direct=0;address=base+{3'd0,pos};end
end endtask
always @*begin
 address=511;direct=1;glyph=0;winner=score_a>score_b ? team_a:team_b;help=0;
 case(row)
 1:begin
  if(col>=2 && col<15)select_text(448,col-6'd2,16);
  if(col>=30 && state<=4)select_text(9'd32+{3'd0,state,3'd0},col-6'd30,8);
 end
 4:case(col)4:glyph=53;5:glyph=8;29:glyph=55;30:glyph=8;endcase
 5:begin
  if(col>=4 && col<8 && team_a<6)select_text({4'd0,team_a,2'd0},col-6'd4,4);
  if(col>=29 && col<33 && team_b<6)select_text({4'd0,team_b,2'd0},col-6'd29,4);
 end
 7:if(col>=16 && col<20 && state!=1 && state!=4)select_text(464,col-6'd16,4);
 14:if(col>=12 && col<28)case(state)
  0:select_text(80,col-6'd12,16);
  1:select_text(96,col-6'd17,16);
  2:select_text(112,col-6'd16,16);
  3:select_text(128,col-6'd14,16);
  default:if(score_a==score_b)select_text(144,col-6'd15,16);
   else begin
    if(col>=16 && col<18 && winner<6)select_text({4'd0,winner,2'd0},col-6'd16,4);
    if(col>=19 && col<21)select_text(160,col-6'd19,16);
   end
 endcase
 16:begin
  if(state==0)case(col)
   13:glyph=23;14:glyph=1;15:glyph=35;16:glyph=36;
   18:glyph=100;
   19:glyph=duration_index==2 ? 56:duration_index==3 ? 101:duration_index==1 ? 52:100;
   20:glyph=106;21:glyph=duration_index==0 ? 56:100;22:glyph=100;
  endcase
  else if(state==2 && seconds<=10 && col>=16 && col<20)select_text(468,col-6'd16,4);
 end
 18,20:if(col>=2)begin
  help=state==0 ? (row==18 ? 0:1):state==1 ? (row==18 ? 4:5):
   state==4 ? (row==18 ? 6:7):(row==18 ? 2:3);
  select_text(9'd192+{1'b0,help,5'd0},col-6'd2,32);
 end
 endcase
end
endmodule
