`timescale 1ns/1ps
module tb_uart_frame_parser ();

    reg clk,
    reg rst_n,
/////////// uart rx
    reg rx_done,
    reg [7:0] rx_data_byte,
////////// uart tx
    reg uart_tx_state,
    wire [7:0] tx_data_byte,
    wire send_en,
////// regfile
    reg [31:0] rd_data,
    wire wr_en,
    wire [7:0] wr_addr,
    wire [31:0] wr_data,
    wire rd_en,
    wire [7:0] rd_addr,
////////////////// watchdog core
    wire wdi_uart    
endmodule