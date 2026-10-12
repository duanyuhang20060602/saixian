# 720p 源码对照

A/B SDRAM 三个模块以及 A 视频 PLL 与 d23efef 原文件一致（换行统一后比较）。BMP 差异只有缩放故障输出及显式指定原输出尺寸，缩放算法与尺寸均为原版。

```diff
--- photo_d23efef/bmp_read.v
+++ 720_compare/bmp_read.v
@@ -41,7 +41,8 @@
     input                       sd_sec_read_end,
 
     output                      bmp_data_wr_en,
-    output [23:0]               bmp_data
+    output [23:0]               bmp_data,
+    output                     scaler_fault_o
 );
 
 localparam ST_IDLE      = 3'd0;
@@ -126,12 +127,13 @@
 reg raw_pixel_valid;
 reg [23:0] raw_pixel;
 wire scaler_busy, scaler_fault;
+assign scaler_fault_o=scaler_fault;
 reg write_req_previous;
 always @(posedge clk or posedge rst) begin
     if (rst) write_req_previous <= 1'b0;
     else write_req_previous <= write_req;
 end
-saixian_load_scaler u_scaler(
+saixian_load_scaler #(.OUT_WIDTH(1280),.OUT_HEIGHT(720)) u_scaler(
     .clk(clk), .rst(rst | op_abort), .start(write_req && !write_req_previous),
     .source_width(width[15:0]), .source_height(height[15:0]),
     .pixel_valid(raw_pixel_valid), .pixel_in(raw_pixel),
```
