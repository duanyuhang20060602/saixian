module tb;
reg clk=0;always #5 clk=~clk;reg rst=1,tick=0,transition=0,manual=0;
wire[76:0] cfg;
water_scene d(.clk(clk),.rst(rst),.frame_tick(tick),.display_valid(1'b1),.transition_active(transition),
 .wave_enable(1'b1),.manual_drop(manual),.progress(9'd0),.cfg(cfg));
integer f,age0=0,age1=0,last0=0,last1=0,complete0=0,complete1=0,max_count=0;real far0,far1,dx,dy,v;
function real farthest;input integer cx,cy;real a,b,c,e;begin
 a=$sqrt(cx*cx+cy*cy);b=$sqrt((1279-cx)*(1279-cx)+cy*cy);
 c=$sqrt(cx*cx+(719-cy)*(719-cy));e=$sqrt((1279-cx)*(1279-cx)+(719-cy)*(719-cy));
 farthest=a;if(b>farthest)farthest=b;if(c>farthest)farthest=c;if(e>farthest)farthest=e;
end endfunction
initial begin
 repeat(4)@(negedge clk);rst=0;
 for(f=0;f<500;f=f+1)begin
  @(negedge clk);transition=f>=200&&f<204;manual=f==350;tick=1;
  @(negedge clk);tick=0;manual=0;
  if(cfg[76]+{1'b0,cfg[75]}>max_count)max_count=cfg[76]+{1'b0,cfg[75]};
  if(cfg[76])begin age0=age0+1;last0=cfg[32:21];far0=farthest(cfg[74:64],cfg[52:43]);end
  else if(age0>0)begin
   if(!transition)begin if(age0!=85||last0<far0)$fatal(1,"drop0 stopped before corners: age%0d radius%0d far%f",age0,last0,far0);complete0=complete0+1;end
   age0=0;
  end
  if(cfg[75])begin age1=age1+1;last1=cfg[20:9];far1=farthest(cfg[63:53],cfg[42:33]);end
  else if(age1>0)begin if(age1!=85||last1<far1)$fatal(1,"drop1 stopped before corners");complete1=complete1+1;age1=0;end
 end
 if(complete0<3||complete1<1||max_count!=2)$fatal(1,"wave coverage incomplete");
 $display("PASS 85-frame dwell waves, farthest-corner coverage, manual trigger, max two sources");$finish;
end
endmodule
