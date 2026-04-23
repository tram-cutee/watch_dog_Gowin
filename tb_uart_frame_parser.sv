`timescale 1ns/1ps
`define CLK_PERIOD 100
module tb_uart_frame_parser ();
    reg clk;
    reg rst_n;
    reg rx_done = 0;
    reg [7:0] rx_data_byte =0;
    reg uart_tx_state = 0;
    wire [7:0] tx_data_byte;
    wire send_en;
    reg [31:0] rd_data;
    wire wr_en;
    wire [7:0] wr_addr;
    wire [31:0] wr_data;
    wire rd_en;
    wire [7:0] rd_addr;
    wire wdi_uart;

    uart_frame_parser_new uart_frame_parser_new_i(
        .clk(clk),
        .rst_n(rst_n),
        .rx_done(rx_done),
        .rx_data_byte(rx_data_byte),
        .uart_tx_state(uart_tx_state),
        .tx_data_byte(tx_data_byte),
        .send_en(send_en),
        .rd_data(rd_data),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .rd_en(rd_en),
        .rd_addr(rd_addr),
        .wdi_uart(wdi_uart)
    );
    
    initial clk = 1'b1;
    always #(`CLK_PERIOD / 2) clk =~clk;

    task send_byte(input [7:0] data);
    begin
        @(posedge clk);
        #1;                    // thêm 1ns để tránh race
        rx_data_byte = data;
        rx_done = 1'b1;
        @(posedge clk);
        #1;
        rx_done = 1'b0;
        repeat(0) @(posedge clk);  // gap giữa các byte
    end
    endtask

    initial begin
    rst_n = 1'b0;
    rx_data_byte = 8'd0;
    rx_done = 1'd0;
    #(`CLK_PERIOD*5);
    rst_n = 1'b1;
    #(`CLK_PERIOD*10);
    //command 1
    send_byte(8'h55);  // Sync
    send_byte(8'h01);  // CMD WRITE
    send_byte(8'h04);  // ADDR
    send_byte(8'h04);  // LEN = 4
    send_byte(8'hD0);  // Data[0]
    send_byte(8'h07);  // Data[1]
    send_byte(8'h00);  // Data[2]
    send_byte(8'h00);  // Data[3]
    send_byte(8'hD6);  // CHK
    
    //command 2
    send_byte(8'h11);  // trash
    send_byte(8'h55);  // Sync
    send_byte(8'h01);  // CMD WRITE
    send_byte(8'h03);  // ADDR
    send_byte(8'h03);  // LEN = 3
    send_byte(8'hD0);  // Data[0]
    send_byte(8'h07);  // Data[1]
    send_byte(8'ha2);  // Data[2]
    send_byte(8'h74);  // CHK

    //command 3
    send_byte(8'h11);  // trash
    send_byte(8'h55);  // Sync
    send_byte(8'h02);  // CMD READ
    send_byte(8'h01);  // ADDR
    send_byte(8'h0);  // LEN = 0
    send_byte(8'h03);  // CHK

    //command 4
    send_byte(8'h11);  // trash
    send_byte(8'h55);  // Sync
    send_byte(8'h04);  // CMD STATUS
    send_byte(8'h00);  // ADDR
    send_byte(8'h0);  // LEN = 0
    send_byte(8'h04);  // CHK

    //command 5
    send_byte(8'h11);  // trash
    send_byte(8'h55);  // Sync
    send_byte(8'h03);  // CMD KICK 
    send_byte(8'h00);  // ADDR
    send_byte(8'h00);  // LEN = 0
    send_byte(8'h03);  // CHK
    #(`CLK_PERIOD*50);
    $finish;
end

endmodule