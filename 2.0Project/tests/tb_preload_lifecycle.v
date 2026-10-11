`timescale 1ns/1ps
module tb_preload_lifecycle;
reg sd=0,mem=0,vid=0,rst=1,prepare=0,active=0,idle=0,cache=0,initialized=1;
reg [2:0] error=0;reg valid=0,ending=0;reg [7:0] data=0;
always #5 sd=~sd;always #10 mem=~mem;always #6.667 vid=~vid;
wire owner,claim,ps,pv,mr,host_reset,pause;
saixian_tf_preload dut(.sd_clk(sd),.mem_clk(mem),.video_clk(vid),.rst_sd(rst),.rst_mem(rst),.rst_video(rst),
 .prepare(prepare),.active(active),.show(1'b0),.photo_idle(idle),.photo_bus_claim(1'b0),
 .shared_sd_initialized(initialized),.sector_valid(valid),.sector_end(ending),.sector_data(data),.observed_sector(32'd78910),
 .mode_sd(owner),.mode_mem(claim),.photo_reset_sd(ps),.photo_reset_video(pv),.memory_reset(mr),.shared_sd_reset(host_reset),.photo_pause(pause),
 .sdr_busy(1'b0),.sdr_init(1'b1),.sdr_refresh(1'b0),.rd_valid(1'b0),.rd_data(32'd0));
integer i;
initial begin
 force dut.cache_ready=cache;force dut.bus_idle=1;force dut.sd_error=error;force dut.memory_error=0;
 repeat(5)@(negedge sd);rst=0;repeat(10)@(negedge sd);
 // Learn a header encountered by the original photo scan.
 for(i=0;i<512;i=i+1)begin valid=1;data=i<8 ? dut.magic_byte(i) : 0;@(negedge sd);end
 valid=0;ending=1;@(negedge sd);ending=0;
 if(!dut.hint_valid || dut.hint_sector!=78910)$fatal(1,"boot-scan sector hint not retained");
 prepare=1;repeat(20)@(negedge sd);
 if(owner || dut.session || !pause)$fatal(1,"host stolen before photo drained");
 idle=1;wait(owner);cache=1;wait(!owner);repeat(10)@(negedge sd);
 if(host_reset || ps || pv || mr || !dut.session)$fatal(1,"successful preload reset client");
 active=1;repeat(10)@(negedge mem);active=0;wait(dut.restart_count!=0);
 prepare=0;repeat(30)@(negedge sd);
 if(owner || !dut.session || !cache || host_reset || ps || pv || mr)$fatal(1,"ordinary exit lost cached session");
 prepare=1;repeat(20)@(negedge sd);
 if(owner || !dut.session)$fatal(1,"warm reentry took SD host");
 prepare=0;cache=0;initialized=0;
 repeat(10)@(negedge mem);
 if(!ps || !pv || !mr || dut.session || dut.hint_valid)$fatal(1,"real card reset retained stale state/bus");
 initialized=1;repeat(10)@(negedge mem);
 if(ps || pv || mr)$fatal(1,"card reinitialization did not release reset");
 prepare=1;wait(owner);error=5;
 repeat(80)@(negedge sd);prepare=0;
 repeat(10)@(negedge sd);
 if(owner || dut.session || host_reset || ps || pv || mr)$fatal(1,"CRC cancellation disturbed retained photo or failed recovery");
 error=0;prepare=1;wait(owner);
 $display("PASS preload lifecycle: boot hint, drain-before-host-lease, cache survival/warm reentry, player restart, card reset invalidation, CRC failure cancellation/retry");$finish;
end
initial begin #100000;$fatal(1,"lifecycle timeout");end
endmodule
