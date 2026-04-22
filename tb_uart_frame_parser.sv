`timescale 1ns/1ps
`define CLK_PERIOD 37.037
module tb_uart_frame_parser ();

    reg clk;
    reg rst_n;
/////////// uart rx
    reg rx_done = 0;
    reg [7:0] rx_data_byte =0;
////////// uart tx
    reg uart_tx_state = 0;
    wire [7:0] tx_data_byte;
    wire send_en;
////// regfile
    reg [31:0] rd_data;
    wire wr_en;
    wire [7:0] wr_addr;
    wire [31:0] wr_data;
    wire rd_en;
    wire [7:0] rd_addr;
////////////////// watchdog core
    wire wdi_uart;

    initial clk = 1'b1;
    always #(`CLK_PERIOD / 2) clk =~clk;

    initial begin
        rst_n = 1'b0;
        data_byte_tx = 8'd0;
        send_en = 1'd0;

        #(`CLK_PERIOD*20 + 1 );
        rst_n = 1'b1;
        #(`CLK_PERIOD*50);

        //Byte 1: 0x55
        data_byte_tx = 8'h55;
        send_en = 1'd1;
        #`CLK_PERIOD;
        send_en = 1'd0;
        @(posedge tx_done);
        #(`CLK_PERIOD*50);

        //Byte 2: 0x01
        data_byte_tx = 8'h01;
        send_en = 1'd1;
        #`CLK_PERIOD;
        send_en = 1'd0;
        @(posedge tx_done);
        #(`CLK_PERIOD*50);

        //Byte 3: 0x04
        data_byte_tx = 8'h04;
        send_en = 1'd1;
        #`CLK_PERIOD;
        send_en = 1'd0;
        @(posedge tx_done);
        #(`CLK_PERIOD*50);

        //Byte 4: 0x04
        data_byte_tx = 8'h04;
        send_en = 1'd1;
        #`CLK_PERIOD;
        send_en = 1'd0;
        @(posedge tx_done);
        #(`CLK_PERIOD*50);

        //Byte 4: 0xd0
        data_byte_tx = 8'hd0;
        send_en = 1'd1;
        #`CLK_PERIOD;
        send_en = 1'd0;
        @(posedge tx_done);
        #(`CLK_PERIOD*50);

        //Byte 5: 0xd0
        data_byte_tx = 8'h07;
        send_en = 1'd1;
        #`CLK_PERIOD;
        send_en = 1'd0;
        @(posedge tx_done);
        #(`CLK_PERIOD*50);

         //Byte 6: 0xd0
        data_byte_tx = 8'h00;
        send_en = 1'd1;
        #`CLK_PERIOD;
        send_en = 1'd0;
        @(posedge tx_done);
        #(`CLK_PERIOD*50);

         //Byte 7: 0xd0
        data_byte_tx = 8'h00;
        send_en = 1'd1;
        #`CLK_PERIOD;
        send_en = 1'd0;
        @(posedge tx_done);
        #(`CLK_PERIOD*50);

         //Byte 8: 0xd0
        data_byte_tx = 8'hd2;
        send_en = 1'd1;
        #`CLK_PERIOD;
        send_en = 1'd0;
        @(posedge tx_done);
        #(`CLK_PERIOD*50);
    end
endmodule