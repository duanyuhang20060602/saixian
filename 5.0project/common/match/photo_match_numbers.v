// One shared blanking-time arithmetic engine; no pixel-rate dividers or DSPs.
module photo_match_numbers(input clk,rst,start,input[9:0] score_a,score_b,
 input[8:0] seconds,input[1:0] duration_index,
 output reg[3:0] a0,a1,a2,b0,b1,b2,m0,m1,s0,s1,output reg[9:0] progress);
reg[3:0] phase,hundreds,tens,minutes;
reg[9:0] remainder;
reg[15:0] product;
always @(posedge clk or posedge rst)
 if(rst)begin
  phase<=0;hundreds<=0;tens<=0;minutes<=0;remainder<=0;product<=0;
  a0<=0;a1<=0;a2<=0;b0<=0;b1<=0;b2<=0;m0<=0;m1<=0;s0<=3;s1<=0;progress<=510;
 end else if(start)phase<=1;
 else case(phase)
  1:begin remainder<=score_a;hundreds<=0;tens<=0;phase<=2;end
  2:if(remainder>=100)begin remainder<=remainder-10'd100;hundreds<=hundreds+1'b1;end else phase<=3;
  3:if(remainder>=10)begin remainder<=remainder-10'd10;tens<=tens+1'b1;end else phase<=4;
  4:begin a0<=hundreds;a1<=tens;a2<=remainder[3:0];remainder<=score_b;hundreds<=0;tens<=0;phase<=5;end
  5:if(remainder>=100)begin remainder<=remainder-10'd100;hundreds<=hundreds+1'b1;end else phase<=6;
  6:if(remainder>=10)begin remainder<=remainder-10'd10;tens<=tens+1'b1;end else phase<=7;
  7:begin b0<=hundreds;b1<=tens;b2<=remainder[3:0];remainder<={1'b0,seconds};minutes<=0;tens<=0;phase<=8;end
  8:if(remainder>=60)begin remainder<=remainder-10'd60;minutes<=minutes+1'b1;end else phase<=9;
  9:if(remainder>=10)begin remainder<=remainder-10'd10;tens<=tens+1'b1;end else phase<=10;
  10:begin m0<=0;m1<=minutes;s0<=tens;s1<=remainder[3:0];phase<=11;end
  // Vertical blanking provides over49,000 clocks. Accumulate a small
  // constant per second with the already-shared remainder, saving the
  // separate16-bit shift register, coefficient and bit-step registers.
  11:begin remainder<={1'b0,seconds};product<=0;phase<=12;end
  12:if(remainder==0)phase<=13;else begin
   remainder<=remainder-1'b1;
   case(duration_index)
    0,1:product<=product+16'd17;
    2:product<=product+16'd91;
    default:product<=product+16'd109;
   endcase
  end
  13:begin
   case(duration_index)0:progress<=product[9:0];1:progress<=product[10:1];
    2:progress<=product[14:5];default:progress<=product[15:6];endcase
   phase<=0;
  end
 endcase
endmodule
