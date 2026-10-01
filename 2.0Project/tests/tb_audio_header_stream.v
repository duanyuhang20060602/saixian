`timescale 1ns/1ps

// Exercise the production scanner with a valid AUD header and one corrupt
// fixed byte at a time. The length field is independent of the format check.
module tb_audio_header_stream;
reg clk=0;
always #5 clk=~clk;
reg rst=1, data_valid=0;
reg [7:0] data=0;
reg [7:0] header [0:19];
integer bad, i;

bmp_read dut(
    .clk(clk), .rst(rst), .op_abort(1'b0),
    .scan_start(1'b0), .scan_stop(1'b0),
    .scan_start_sector(32'd0), .scan_max_sector(32'd0),
    .scan_target_count(3'd0), .load_start(1'b0), .load_sector(32'd0),
    .sd_init_done(1'b1), .bmp_width(16'd1280), .bmp_height(16'd720),
    .write_req_ack(1'b0), .sd_sec_read_data(data),
    .sd_sec_read_data_valid(data_valid), .sd_sec_read_end(1'b0)
);

initial begin
    header[0]=8'h53; header[1]=8'h58; header[2]=8'h41; header[3]=8'h55;
    header[4]=8'h44; header[5]=8'h30; header[6]=8'h30; header[7]=8'h31;
    header[8]=8'h04; header[9]=0; header[10]=0; header[11]=0;
    header[12]=8'h80; header[13]=8'hbb; header[14]=0; header[15]=0;
    header[16]=8'h10; header[17]=0; header[18]=8'h02; header[19]=0;
    // -1 is valid. All other cases corrupt one of the fixed-format bytes.
    for (bad=-1; bad<20; bad=bad+1) begin
        rst=1; data_valid=0;
        repeat(2) @(negedge clk);
        rst=0;
        force dut.state=3'd1;
        for (i=0; i<20; i=i+1) begin
            data=header[i];
            if (i==bad && (i<8 || i>=12)) data=data^8'h01;
            data_valid=1;
            @(negedge clk);
        end
        data_valid=0;
        if (bad==-1 && dut.audio_header_ok!==1'b1)
            $fatal(1,"valid AUD header rejected");
        if (bad>=0 && (bad<8 || bad>=12) && dut.audio_header_ok!==1'b0)
            $fatal(1,"corrupt AUD byte %0d accepted",bad);
        release dut.state;
        @(negedge clk);
    end
    $display("PASS streaming AUD header: valid format and all 16 fixed-byte corruptions");
    $finish;
end
endmodule
