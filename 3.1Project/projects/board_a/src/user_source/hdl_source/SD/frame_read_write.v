`timescale 1ns/1ps
module frame_read_write
#
(
	parameter MEM_DATA_BITS          = 32,
	parameter READ_DATA_BITS         = 32,
	parameter WRITE_DATA_BITS        = 32,
	parameter ADDR_BITS              = 21,
	parameter BURST_BITS             = 9,//
	parameter BURST_SIZE             = 256,
	parameter WRITE_V_FLIP           = 1,      // 1: vertical flip when writing TF/BMP frame into SDRAM
	parameter FRAME_WIDTH            = 640,
	parameter FRAME_HEIGHT           = 480
) 
(
	input high_color,fluid_mode,input [8:0] fluid_progress,
	input                            rst,                  
	input                            mem_clk,                    // external memory controller user interface clock
	input							 Sdr_init_done,
	input							 Sdr_init_ref_vld,
    input							 Sdr_busy,
	
    /*
    output                           rd_burst_req,               // to external memory controller,send out a burst read request
	output[BURST_BITS - 1:0]         rd_burst_len,               // to external memory controller,data length of the burst read request, not bytes
	output[ADDR_BITS - 1:0]          rd_burst_addr,              // to external memory controller,base address of the burst read request 
	input                            rd_burst_data_valid,        // from external memory controller,read data valid 
	input[MEM_DATA_BITS - 1:0]       rd_burst_data,              // from external memory controller,read request data
	input                            rd_burst_finish,            // from external memory controller,burst read finish
	*/
	output							 App_rd_en,
	output[ADDR_BITS - 1:0]			 App_rd_addr,
	input							 Sdr_rd_en,					 //read_data_valid
	input[MEM_DATA_BITS - 1:0]		 Sdr_rd_dout,
	
	input                            read_clk,                   // data read module clock
	input                            read_req,                   // data read module read request,keep '1' until read_req_ack = '1'
	output                           read_req_ack,               // data read module read request response
	output                           read_finish,                // data read module read request finish
	input[ADDR_BITS - 1:0]           read_addr_0,                // data read module read request base address 0, used when read_addr_index = 0
	input[ADDR_BITS - 1:0]           read_addr_1,                // data read module read request base address 1, used when read_addr_index = 1
	input[ADDR_BITS - 1:0]           read_addr_2,                // data read module read request base address 1, used when read_addr_index = 2
	input[ADDR_BITS - 1:0]           read_addr_3,                // data read module read request base address 1, used when read_addr_index = 3
	input[1:0]                       read_addr_index,            // select valid base address from read_addr_0 read_addr_1 read_addr_2 read_addr_3
	input[ADDR_BITS - 1:0]           read_len,                   // data read module read request data length
	input                            read_en,                    // data read module read request for one data, read_data valid next clock
	output[READ_DATA_BITS  - 1:0]    read_data,                  // read data
	output                           read_fifo_empty,            // no pixel available in read_clk domain
    input                            slide_active,
    input[1:0]                       slide_old_index,
    input[1:0]                       slide_new_index,
    input[10:0]                      slide_offset,
    input                            slide_right,
    input[4:0]                       transition_mode,
    input                            buffer0_vga,
    input                            buffer1_vga,
	/*
	output                           wr_burst_req,               // to external memory controller,send out a burst write request
	output[BURST_BITS - 1:0]         wr_burst_len,               // to external memory controller,data length of the burst write request, not bytes
	output[ADDR_BITS - 1:0]          wr_burst_addr,              // to external memory controller,base address of the burst write request 
	input                            wr_burst_data_req,          // from external memory controller,write data request ,before data 1 clock
	output[MEM_DATA_BITS - 1:0]      wr_burst_data,              // to external memory controller,write data
	input                            wr_burst_finish,            // from external memory controller,burst write finish
	*/
	output							 App_wr_en,
	output[ADDR_BITS - 1:0]			 App_wr_addr,
	output[MEM_DATA_BITS - 1:0]	 App_wr_din,
	output[3:0]						 App_wr_dm,
	
	//
	input                            write_clk,                  // data write module clock
	input                            write_req,                  // data write module write request,keep '1' until read_req_ack = '1'
	output                           write_req_ack,              // data write module write request response
	output                           write_finish,               // data write module write request finish
	input[ADDR_BITS - 1:0]           write_addr_0,               // data write module write request base address 0, used when write_addr_index = 0
	input[ADDR_BITS - 1:0]           write_addr_1,               // data write module write request base address 1, used when write_addr_index = 1
	input[ADDR_BITS - 1:0]           write_addr_2,               // data write module write request base address 1, used when write_addr_index = 2
	input[ADDR_BITS - 1:0]           write_addr_3,               // data write module write request base address 1, used when write_addr_index = 3
	input[1:0]                       write_addr_index,           // select valid base address from write_addr_0 write_addr_1 write_addr_2 write_addr_3
	input[ADDR_BITS - 1:0]           write_len,                  // data write module write request data length
    input                            write_vga,
	input                            write_en,                   // data write module write request for one data
	input[WRITE_DATA_BITS - 1:0]     write_data,                // write data
	output                           write_fifo_full             // write-side overflow diagnostic

);
// Synchronize the frame selector before presenting a delayed request to either
// reader. Selection remains fixed throughout a frame and owns the shared FIFO.
(* async_reg="true" *)reg fluid_mode_meta,fluid_mode_sync;
reg [4:0] read_request_pipe;reg fluid_selected;
always @(posedge mem_clk or posedge rst)
 if(rst)begin fluid_mode_meta<=0;fluid_mode_sync<=0;read_request_pipe<=0;fluid_selected<=0;end
 else begin
  fluid_mode_meta<=fluid_mode;fluid_mode_sync<=fluid_mode_meta;
  read_request_pipe<={read_request_pipe[3:0],read_req};
  if(read_request_pipe[3]&&!read_request_pipe[4])fluid_selected<=fluid_mode_sync;
 end
wire selected_request=read_request_pipe[4];
wire legacy_busy,legacy_urgent,legacy_rd,legacy_ack,legacy_finish,legacy_clear;
wire [ADDR_BITS-1:0] legacy_address,fluid_address;
wire fluid_busy,fluid_rd,fluid_ack,fluid_finish,fluid_clear,fluid_we;
wire [31:0] fluid_data;
// Use the frame-owned phase directly; avoid half-word/offset re-quantization.
wire [76:0] fluid_configuration={68'd0,fluid_progress};
wire [31:0] fluid_timeouts;
assign App_rd_en=fluid_selected ? fluid_rd:legacy_rd;
assign App_rd_addr=fluid_selected ? fluid_address:legacy_address;
assign read_req_ack=fluid_selected ? fluid_ack:legacy_ack;
assign read_finish=fluid_selected ? fluid_finish:legacy_finish;
assign read_fifo_aclr=fluid_selected ? fluid_clear:legacy_clear;
assign O_rd_busy=fluid_selected ? fluid_busy:legacy_busy;
assign read_urgent=fluid_selected ? (wrusedw<768 && !fluid_finish):legacy_urgent;
water_reader #(.FIFO_DEPTH(1024)) fluid_reader(
 .rst(rst || !fluid_selected),.mem_clk(mem_clk),.Sdr_init_done(Sdr_init_done),
 .Sdr_init_ref_vld(Sdr_init_ref_vld),.Sdr_busy(Sdr_busy),.Sdr_rd_en(Sdr_rd_en),
 .App_wr_busy(App_wr_busy),.Sdr_rd_dout(Sdr_rd_dout),.O_rd_busy(fluid_busy),
 .App_rd_en(fluid_rd),.App_rd_addr(fluid_address),.read_req(selected_request),
 .read_req_ack(fluid_ack),.read_finish(fluid_finish),.read_addr_0(read_addr_0),
 .read_addr_1(read_addr_1),.read_addr_2(read_addr_2),.read_addr_3(read_addr_3),
 .read_addr_index(read_addr_index),.slide_old_index(slide_old_index),.slide_new_index(slide_new_index),
 .read_len(read_len),.slide_active(slide_active),.slide_right(slide_right),
 .transition_mode(transition_mode==7 ? 4'd5:transition_mode==8 ? 4'd0:transition_mode==9 ? 4'd3:transition_mode==10 ? 4'd1:transition_mode==11 ? 4'd4:transition_mode==12 ? 4'd2:4'd6),.slide_offset(slide_offset),.water_cfg(fluid_configuration),
 .force_effect_plane(1'b0),.fifo_aclr(fluid_clear),.wrusedw({1'b0,wrusedw}),
 .fifo_we(fluid_we),.fifo_data(fluid_data),.read_timeouts(fluid_timeouts));
localparam READ_FIFO_BITS=10;
wire [READ_FIFO_BITS-1:0] wrusedw;
wire read_urgent;
// Display reserve uses a separate width from write burst counters.
wire[BURST_BITS - 1:0]                           rdusedw;                    // read used words

wire 								 App_rd_busy;
wire								 App_wr_busy;

wire                                 read_fifo_aclr;             // fifo Asynchronous clear
wire                                 write_fifo_aclr;            // fifo Asynchronous clear

wire O_wr_busy;
wire O_rd_busy;

assign App_wr_busy = O_wr_busy;//下个时钟写指令拉高
assign App_rd_busy = O_rd_busy;//读指令还没有过去十个时钟;因为写指令优先，不需要在意下个时钟是否是读指令
assign App_wr_dm = 4'b0000;

//instantiate an asynchronous FIFO 
wfifo_32_32_512 write_buf
	(
	.clkr                      	(mem_clk                  ),          // Read side clock
	.clkw                      	(write_clk                ),          // Write side clock
	.rst                       	(rst | write_fifo_aclr    ),          // Reset also before first request
	.we                      	(write_en                 ),          // Write Request
	.re                      	(App_wr_en        		  ),          // Read Request
	.di                       	(write_data               ),          // Input Data
	.empty_flag                 (                         ),          // Read side Empty flag
	.full_flag                  (write_fifo_full          ),          // Write side Full flag
	.wrusedw                	(              	  		  ),          // Read Used Words
	.rdusedw                	(rdusedw                  ),          // Write Used Words
	.dout                       (App_wr_din		          )
);

frame_fifo_write
#
(
	.MEM_DATA_BITS              (MEM_DATA_BITS            ),
	.ADDR_BITS                  (ADDR_BITS                ),
	.BURST_BITS                 (BURST_BITS               ),
	.BURST_SIZE                 (BURST_SIZE               ),
	.WRITE_V_FLIP               (WRITE_V_FLIP             ),
	.FRAME_WIDTH                (FRAME_WIDTH              ),
	.FRAME_HEIGHT               (FRAME_HEIGHT             )
) 
frame_fifo_write_m0              
(  
 .high_color(high_color),
	.rst                        (rst                      ),
	.mem_clk                    (mem_clk                  ),
    .Sdr_init_done				(Sdr_init_done),
	.Sdr_init_ref_vld			(Sdr_init_ref_vld),
    .Sdr_busy					(Sdr_busy),
	.App_rd_busy				(App_rd_busy),
    .read_urgent(read_urgent),
    .O_wr_busy					(O_wr_busy),
	
	.App_wr_en					(App_wr_en),
    .App_wr_addr				(App_wr_addr),
	.write_req                  (write_req                ),
	.write_req_ack              (write_req_ack            ),
	.write_finish               (write_finish             ),
	.write_addr_0               (write_addr_0             ),
	.write_addr_1               (write_addr_1             ),
	.write_addr_2               (write_addr_2             ),
	.write_addr_3               (write_addr_3             ),
	.write_addr_index           (write_addr_index         ),    
	.write_len                  (write_len                ),
    .write_vga                 (write_vga               ),
	.fifo_aclr                  (write_fifo_aclr          ),
	.rdusedw                 	(rdusedw                  )
);

//instantiate an asynchronous FIFO 
rfifo_32_32_512 #(.ADDR_WIDTH_W(READ_FIFO_BITS),.ADDR_WIDTH_R(READ_FIFO_BITS),.AL_FULL_NUM(1021)) read_buf
	(
	.clkr                     	(read_clk                   ),          // Read side clock
	.clkw                     	(mem_clk                    ),          // Write side clock
	.rst                      	(rst | read_fifo_aclr       ),          // Reset also before first request
	.we                     	(fluid_selected ? fluid_we:Sdr_rd_en),          // Write Request
	.re                     	(read_en && !read_fifo_empty),          // Never pop an empty FIFO
	.di                      	(fluid_selected ? fluid_data:Sdr_rd_dout),          // Input Data
	.empty_flag					(read_fifo_empty            ),          // Read side Empty flag
	.full_flag					(                           ),          // Write side Full flag
	.wrusedw                	(wrusedw         	  	  		 ),          // Read Used Words
	.rdusedw                	(                  			 ),          // Write Used Words
	.dout						(read_data                  )
);

frame_fifo_read
#
(
	.MEM_DATA_BITS              (MEM_DATA_BITS            ),
	.ADDR_BITS                  (ADDR_BITS                ),
	.BURST_BITS                 (READ_FIFO_BITS           ),
	.BURST_SIZE                 (BURST_SIZE               ),
    .FIFO_DEPTH(1024),
    .FRAME_WIDTH                (FRAME_WIDTH              )
)
frame_fifo_read_m0
(
 .high_color(high_color),
	.rst                        (rst || fluid_selected    ),
	.mem_clk                    (mem_clk                  ),
    .Sdr_init_done				(Sdr_init_done),
	.Sdr_init_ref_vld			(Sdr_init_ref_vld),
    .Sdr_busy					(Sdr_busy),
    .Sdr_rd_en					(Sdr_rd_en),
	.App_wr_busy				(App_wr_busy),
    .O_rd_busy					(legacy_busy),
    .read_urgent(legacy_urgent),
	
    .App_rd_en					(legacy_rd),
    .App_rd_addr				(legacy_address),
	.read_req                   (selected_request         ),
	.read_req_ack               (legacy_ack             ),
	.read_finish                (legacy_finish              ),
	.read_addr_0                (read_addr_0              ),
	.read_addr_1                (read_addr_1              ),
	.read_addr_2                (read_addr_2              ),
	.read_addr_3                (read_addr_3              ),
	.read_addr_index            (read_addr_index          ),    
	.read_len                   (read_len                 ),
    .slide_active               (slide_active             ),
    .slide_old_index            (slide_old_index          ),
    .slide_new_index            (slide_new_index          ),
    .slide_offset               (slide_offset             ),
    .slide_right                (slide_right              ),
    .transition_mode            (transition_mode[2:0]     ),
    .buffer0_vga                (buffer0_vga              ),
    .buffer1_vga                (buffer1_vga              ),
	.fifo_aclr                  (legacy_clear           ),
	.wrusedw                	(wrusedw                  )
);

endmodule
