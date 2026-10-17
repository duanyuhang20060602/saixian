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
	parameter FRAME_WIDTH            = 320,
	parameter FRAME_HEIGHT           = 720
) 
(
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
    input[3:0]                       transition_mode,
    input                            buffer0_vga,
    input                            buffer1_vga,
    input [76:0] water_cfg,input force_effect_plane,output [31:0] read_timeouts,
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
	input small_write_en,input[31:0] small_write_data,
	output                           write_fifo_full             // write-side overflow diagnostic

);
wire[9:0] wrusedw;
wire App_rd_busy,App_wr_busy,read_fifo_aclr,write_fifo_aclr;
wire water_fifo_we;wire[31:0] water_fifo_data;
wire[8:0] full_used,small_used;wire full_flag,small_flag,small_select;
wire[31:0] full_data,small_data;
assign App_wr_dm=0;
assign write_fifo_full=full_flag||small_flag;
assign App_wr_din=small_select ? small_data:full_data;
wfifo_32_32_512 write_buf(.clkr(mem_clk),.clkw(write_clk),.rst(rst||write_fifo_aclr),
 .we(write_en),.di(write_data),.re(App_wr_en&&!small_select),.dout(full_data),.full_flag(full_flag),.rdusedw(full_used));
wfifo_32_32_512 small_buf(.clkr(mem_clk),.clkw(write_clk),.rst(rst||write_fifo_aclr),
 .we(small_write_en),.di(small_write_data),.re(App_wr_en&&small_select),.dout(small_data),.full_flag(small_flag),.rdusedw(small_used));
reg[20:0] write_base;
always @* case(write_addr_index)
 0:write_base=write_addr_0;1:write_base=write_addr_1;2:write_base=write_addr_2;default:write_base=write_addr_3;
endcase
water_image_writer #(.HEIGHT(FRAME_HEIGHT)) writer(.clk(mem_clk),.rst(rst),.initialized(Sdr_init_done),.refresh(Sdr_init_ref_vld),.sdr_busy(Sdr_busy),
 .reader_busy(App_rd_busy),.request(write_req),.base(write_base),.full_used(full_used),.small_used(small_used),
 .ack(write_req_ack),.finish(write_finish),.clear(write_fifo_aclr),.busy(App_wr_busy),.write_en(App_wr_en),.small_select(small_select),.address(App_wr_addr));
rfifo_32_32_512 #(.ADDR_WIDTH_W(10),.ADDR_WIDTH_R(10),.AL_FULL_NUM(1021)) read_buf(
 .clkr(read_clk),.clkw(mem_clk),.rst(rst||read_fifo_aclr),.we(water_fifo_we),.di(water_fifo_data),
 .re(read_en&&!read_fifo_empty),.dout(read_data),.empty_flag(read_fifo_empty),.wrusedw(wrusedw));
water_reader #(.ADDR_BITS(ADDR_BITS),.HEIGHT(FRAME_HEIGHT)) frame_fifo_read_m0(
 .rst(rst),.mem_clk(mem_clk),.Sdr_init_done(Sdr_init_done),.Sdr_init_ref_vld(Sdr_init_ref_vld),.Sdr_busy(Sdr_busy),
 .Sdr_rd_en(Sdr_rd_en),.Sdr_rd_dout(Sdr_rd_dout),.water_cfg(water_cfg),.force_effect_plane(force_effect_plane),.fifo_we(water_fifo_we),.fifo_data(water_fifo_data),.read_timeouts(read_timeouts),
 .App_wr_busy(App_wr_busy),.O_rd_busy(App_rd_busy),.App_rd_en(App_rd_en),.App_rd_addr(App_rd_addr),
 .read_req(read_req),.read_req_ack(read_req_ack),.read_finish(read_finish),
 .read_addr_0(read_addr_0),.read_addr_1(read_addr_1),.read_addr_2(read_addr_2),.read_addr_3(read_addr_3),.read_addr_index(read_addr_index),.read_len(read_len),
 .slide_active(slide_active),.slide_old_index(slide_old_index),.slide_new_index(slide_new_index),.slide_offset(slide_offset),.slide_right(slide_right),.transition_mode(transition_mode),
 .fifo_aclr(read_fifo_aclr),.wrusedw({1'b0,wrusedw}));
endmodule
