`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,lv=0,ack=0;always #5 clk=~clk;
reg[255:0] line=0;wire lr,req,pending,ready,fault;wire[31:0] address,data;
wire[7:0] generation,index;wire[4:0] length;wire[15:0] mask;
reg bv=0,be=0;reg[7:0] bd=0;
photo_text_font_b loader(.clk(clk),.rst(rst),.line_valid(lv),.line(line),.line_ready(lr),
 .card_ready(1'b1),.fs_error(4'd0),.request(req),.address(address),.byte_valid(bv),.byte_data(bd),.sector_end(be),
 .word_pending(pending),.generation(generation),.index(index),.length(length),.data(data),.mask(mask),.word_ack(ack),
 .session(32'd1),.font_ready(ready),.fault(fault),.tick(1'b0));
function[15:0] pattern;input integer code,row;begin pattern=16'ha53c^(code*16'h0137)^(row*16'h0421);end endfunction
function[7:0] header;input integer pos;begin case(pos)
 0:header="S";1:header="X";2:header="F";3:header="O";4:header="N";5:header="T";6:header="0";7:header="1";default:header=0;
endcase end endfunction
reg[31:0] base;reg busy=0;integer pos=0,offset;reg[15:0] sample_word;
// Assert sector_end with the last data byte: this exercises the queued-write
// transition even when the selected glyph ends exactly at the sector end.
always @(negedge clk)begin
 bv=0;be=0;
 if(rst)begin busy=0;pos=0;end
 else if(!busy && req)begin base=(address-2209)*512;pos=0;busy=1;end
 else if(busy)begin
  bv=1;offset=base+pos;
  if(offset<512)bd=header(offset);
  else begin sample_word=pattern((offset-512)/32,((offset-512)%32)/2);bd=offset%2 ? sample_word[7:0]:sample_word[15:8];end
  if(pos==511)begin be=1;busy=0;end else pos=pos+1;
 end
end
integer expected_code[0:15];integer i,w,g,r;reg[31:0] wanted;
task publish;input integer n,start_code;
 begin
  wait(lr);@(negedge clk);line=0;line[253:249]=n;
  for(i=0;i<16;i=i+1)begin expected_code[i]=start_code+i;line[i*14+:14]=expected_code[i];end
  lv=1;@(negedge clk);lv=0;
  wait(pending);repeat(4)@(negedge clk);
  for(w=0;w<128;w=w+1)begin
   g=w/8;r=(w%8)*2;wanted=g<n ? {pattern(expected_code[g],r),pattern(expected_code[g],r+1)}:32'd0;
   if(index!=w || length!=n || data!==wanted || fault)$fatal(1,"physical RAM mismatch n=%d word=%d index=%d data=%h expected=%h",n,w,index,data,wanted);
   ack=1;@(negedge clk);ack=0;repeat(3)@(negedge clk);
  end
  wait(lr);
 end
endtask
initial begin
 repeat(6)@(negedge clk);rst=0;wait(ready);
 publish(1,64);publish(16,64);publish(3,96);publish(0,0);
 $display("PASS actual vendor DP RAM: all 512 words, nonzero first rows, full 16-character cache, final-sector-byte writes, shortened/deleted tail clearing");$finish;
end
initial begin #5000000;$fatal(1,"vendor cache timeout state=%d",loader.state);end
endmodule
