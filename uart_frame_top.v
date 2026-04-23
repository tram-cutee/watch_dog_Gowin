module uart_frame_top (
    input clk,
    input rst_n,
/////////// uart rx
    input rx_done,
    input [7:0] rx_data_byte,
////////// uart tx
    input tx_done,
    output [7:0] tx_data_byte,
    output send_en,
////// regfile
    input [31:0] rd_data,
    output wr_en,
    output [7:0] wr_addr,
    output [31:0] wr_data,
    output rd_en,
    output [7:0] rd_addr,
////////////////// watchdog core
    output wdi_uart
);
wire send_uart_valid;
wire [7:0] send_uart_data;
wire recv_uart_valid;
wire recv_uart_ready;
wire [7:0] recv_uart_data;
uart_frame_parser uart_frame_parser_i(
    .clk(clk),
    .rst_n(rst_n),
    .recv_uart_valid(recv_uart_valid),
    .recv_uart_data(recv_uart_data),
    .recv_uart_ready(recv_uart_ready),
    .send_uart_data(send_uart_data),
    .send_uart_valid(send_uart_valid),
    .rd_data(rd_data),
    .wr_en(wr_en),
    .wr_addr(wr_addr),
    .wr_data(wr_data),
    .rd_en(rd_en),
    .rd_addr(rd_addr),
    .wdi_uart(wdi_uart)
);
uart_buffer recv_buffer_i(
    .clk(clk),
    .rst_n(rst_n),
    .master_valid(rx_done),
    .master_data_byte(rx_data_byte),
    .slave_ready(recv_uart_ready),
    .slave_valid(recv_uart_valid),
    .slave_data_byte(recv_uart_data)
);
uart_buffer resp_buffer_i(
    .clk(clk),
    .rst_n(rst_n),
    .master_valid(send_uart_valid),
    .master_data_byte(send_uart_data),
    .slave_ready(tx_done),
    .slave_valid(send_en),
    .slave_data_byte(tx_data_byte)
);
endmodule

module uart_frame_parser (
    input clk,
    input rst_n,
/////////// uart rx
    input recv_uart_valid,
    input [7:0] recv_uart_data,
    output reg recv_uart_ready,
////////// uart tx
    output reg [7:0] send_uart_data,
    output reg send_uart_valid,
////// regfile
    input [31:0] rd_data,
    output reg wr_en,
    output reg [7:0] wr_addr,
    output reg [31:0] wr_data,
    output reg rd_en,
    output reg [7:0] rd_addr,
////////////////// watchdog core
    output reg wdi_uart
);
//FSM nhận
localparam S_IDLE = 3'd0, S_CMD  = 3'd1,
           S_ADDR = 3'd2, S_LEN  = 3'd3,
           S_DATA = 3'd4, S_CHK  = 3'd5,
           S_EXEC = 3'd6, S_RESP = 3'd7;

// CMD codes
localparam CMD_WRITE  = 8'h01,
           CMD_READ   = 8'h02,
           CMD_KICK   = 8'h03,
           CMD_STATUS = 8'h04;

// FSM state
reg [2:0] rx_state;        // S_IDLE=0, S_CMD=1, S_ADDR=2, S_LEN=3, S_DATA=4, S_CHK=5

// Frame registers
reg [7:0]   r_cmd;
reg [7:0]   r_addr;
reg [7:0]   r_len;
reg [7:0]   r_data_cnt;
reg [31:0]  r_data_acc;
reg [7:0]   chk_acc;

// Response buffer
/*
    WRITE thành công → [0xAA][0xAA]  
    KICK  thành công → [0xBB][0xBB]   
    READ/STATUS      → [0xAA][D0][D1][D2][D3][CHK], CHK = 0xAA ^ D0 ^ D1 ^ D2 ^ D3
    CHK sai          → [0xFF][0xFF]   
*/ 

wire done_resp;
reg [2:0] resp_cnt;
reg [2:0] resp_len;
reg [31:0] r_rd_data;
reg [47:0] resp_data_r;  // 6 byte response đã chuẩn bị

assign done_resp = (resp_cnt == resp_len - 1);




/*
 FSM controll
*/
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        rx_state <= S_IDLE;
    end
    else begin
        case (rx_state)
        // ── S_IDLE: đợi sync byte 0x55 ──
        S_IDLE: begin
            if(recv_uart_valid) begin
                if(recv_uart_data == 8'h55) begin
                    rx_state <= S_CMD;
                end else begin
                    rx_state <= S_IDLE;   // khác 0x55 => ở lại
                end
            end
            else begin
                rx_state <= S_IDLE;      // chưa có byte => ở lại
            end
        end
        // ── S_CMD: nhận CMD byte ──
        S_CMD: begin
            if(recv_uart_valid) begin
                rx_state <= S_ADDR;
            end
            else begin
                rx_state <= S_CMD;
            end
        end
        // ── S_ADDR: nhận ADDR byte ──
        S_ADDR: begin
            if(recv_uart_valid) begin
                rx_state <= S_LEN; 
            end
            else begin
                rx_state <= S_ADDR;
            end
        end
        // ── S_LEN: nhận LEN byte ──
        S_LEN:  begin
            if(recv_uart_valid) begin
                if(recv_uart_data == 8'h00) begin
                    rx_state <= S_CHK;   // len = 0 => không có data
                end
                else begin
                    rx_state <= S_DATA;  // len > 0 => nhận data
                end
            end
            else begin
                rx_state <= S_LEN;      // chưa có byte => ở lại
            end
        end
        // ── S_DATA: nhận LEN bytes data ──
        S_DATA: begin
            if(recv_uart_valid) begin
                if(r_data_cnt == r_len - 1) begin
                    rx_state <= S_CHK;  // đủ LEN bytes => sang CHK
                end
                else begin
                    rx_state <= S_DATA; // chưa đủ => ở lại
                end
            end
            else begin
                rx_state <= S_DATA;    // chưa có byte => ở lại
            end
        end
        // ── S_CHK: kiểm tra checksum và thực thi lệnh ──
        S_CHK: begin
            if(recv_uart_valid) begin
                if(recv_uart_data == chk_acc) begin
                    rx_state <= S_EXEC;
                end else begin
                    rx_state <= S_IDLE;
                end
            end
            else begin
                rx_state <= S_CHK;
            end
        end
        S_EXEC: begin
            rx_state <= S_RESP;
        end
        S_RESP: begin
            if(done_resp) begin
                rx_state <= S_IDLE;
            end
            else begin
                rx_state <= S_RESP;
            end
        end
        default: rx_state <= S_IDLE;
    endcase
    end
end


always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        r_cmd <= 0;
        r_addr <= 0;
        r_len <= 0;
        r_data_acc <= 0;
        chk_acc <= 0;
    end
    else begin
        case (rx_state)
            S_IDLE: begin
                r_cmd <= 0;
                r_addr <= 0;
                r_len <= 0;
                r_data_acc <= 0;
                chk_acc <= 0;
            end
            S_CMD: begin
                if(recv_uart_valid) begin
                    r_cmd       <= recv_uart_data;
                    chk_acc     <= recv_uart_data;
                end
                else begin
                    r_cmd       <= 0;
                    chk_acc     <= chk_acc;
                end
                //r_cmd       <= recv_uart_data;
                r_addr      <= 0;
                r_len       <= 0;
                r_data_acc  <= 0;
                //chk_acc     <= r_cmd;
            end
            S_ADDR: begin
                if(recv_uart_valid) begin
                    r_addr       <= recv_uart_data;
                    chk_acc     <= chk_acc ^ recv_uart_data;
                end
                else begin
                    r_addr       <= 0;
                    chk_acc     <= chk_acc;
                end
                r_cmd       <= r_cmd;
                //r_addr      <= rx_data_byte;
                r_len       <= r_len;
                r_data_acc  <= r_data_acc;
                //chk_acc     <= chk_acc ^ rx_data_byte;
            end
            S_LEN:  begin
                if(recv_uart_valid) begin
                    r_len       <= recv_uart_data;
                    chk_acc     <= chk_acc ^ recv_uart_data;
                end
                else begin
                    r_len       <= 0;
                    chk_acc     <= chk_acc;
                end
                r_cmd       <= r_cmd;
                r_addr      <= r_addr;
                //r_len       <= rx_data_byte;
                r_data_acc  <= r_data_acc;
                //chk_acc     <= chk_acc ^ rx_data_byte;
            end
            S_DATA: begin
                r_cmd   <= r_cmd;
                r_addr  <= r_addr;
                r_len   <= r_len;
                if(recv_uart_valid) begin
                    r_data_acc[r_data_cnt*8 +:8] <= recv_uart_data;
                    chk_acc <= chk_acc ^ recv_uart_data;
                end
                else begin
                    r_data_acc <= r_data_acc;
                    chk_acc <= chk_acc;
                end
                
            end
            S_CHK: begin
                r_cmd       <= r_cmd;
                r_addr      <= r_addr;
                r_len       <= r_len;
                r_data_acc  <= r_data_acc;
                chk_acc     <= chk_acc;
            end
            S_EXEC: begin
                r_cmd       <= r_cmd;
                r_addr      <= r_addr;
                r_len       <= r_len;
                r_data_acc  <= r_data_acc;
                chk_acc     <= chk_acc;
            end
            default: begin
                r_cmd       <= r_cmd;
                r_addr      <= r_addr;
                r_len       <= r_len;
                r_data_acc  <= r_data_acc;
                chk_acc     <= chk_acc;
            end
        endcase
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_data_cnt <= 0;
    end else begin
        case (rx_state)
            S_IDLE: begin
                r_data_cnt <= 0;
            end
            S_DATA: begin
                if(recv_uart_valid) begin
                    r_data_cnt <= r_data_cnt + 1;
                    if(r_data_cnt == r_len - 1) begin
                        r_data_cnt <= 0;
                    end
                end
                else begin
                    r_data_cnt <= r_data_cnt;
                end
            end 
            default: begin
                r_data_cnt <= r_data_cnt;
            end
        endcase
    end
end

/////////////////regfile & watchdog core///////////////////////
always @(*) begin
    case (rx_state)
        S_EXEC: begin
            case (r_cmd)
                CMD_WRITE:begin
                    wr_en = 1;
                    wr_addr = r_addr;
                    wr_data = r_data_acc;
                    rd_en = 0;
                    rd_addr = 0;
                    wdi_uart = 0;
                end
                CMD_READ: begin
                    wr_en = 0;
                    wr_addr = 0;
                    wr_data = 0;
                    rd_en = 1;
                    rd_addr = r_addr; 
                    wdi_uart = 0;
                end
                CMD_KICK: begin
                    wr_en = 0;
                    wr_addr = 0;
                    wr_data = 0;
                    rd_en = 0;
                    rd_addr = 0; 
                    wdi_uart = 1;
                end
                CMD_STATUS: begin
                    wr_en = 0;
                    wr_addr = 0;
                    wr_data = 0;
                    rd_en = 1;
                    rd_addr = 8'h10; 
                    wdi_uart = 0;
                end
                default: begin
                    wr_en = 0;
                    wr_addr = 0;
                    wr_data = 0;
                    rd_en = 0;
                    rd_addr = 0; 
                    wdi_uart = 0;
                end
            endcase
        end
        default: begin
            wr_en = 0;
            wr_addr = 0;
            wr_data = 0;
            rd_en = 0;
            rd_addr = 0;
            wdi_uart = 0;
        end
    endcase
end
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_rd_data <= 0;
    end else begin
        case (rx_state)
            S_EXEC: begin
                r_rd_data <= rd_data;
            end 
            S_RESP: begin
                r_rd_data <= r_rd_data;
            end
            default: begin
                r_rd_data <= 0;
            end
        endcase
    end
end
always @(*) begin
    case (rx_state)
        S_RESP: begin
            case (r_cmd)
                CMD_WRITE:begin
                    resp_data_r = {31'h0, 8'hAA, 8'hAA};
                end
                CMD_READ, CMD_STATUS: begin
                    resp_data_r = {r_rd_data[7:0] ^ r_rd_data[15:8] ^ r_rd_data[23:16] ^ r_rd_data[31:24], 
                    r_rd_data[7:0], r_rd_data[15:8], r_rd_data[23:16], r_rd_data[31:24], 8'hAA};
                end
                CMD_KICK: begin
                    resp_data_r = {31'h0, 8'hBB, 8'hBB};
                end
                default: begin
                    resp_data_r = 0;
                end
            endcase
        end
        default: begin
            resp_data_r = 0;
        end
    endcase
end
//// respone count, respone length//////
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        resp_cnt <= 0;
        resp_len <= 0;
    end else begin
        case (rx_state)
            S_RESP: begin
                case (r_cmd)
                    CMD_WRITE:begin
                        resp_len <= 3'd2;
                    end
                    CMD_READ: begin
                        resp_len <= 3'd6;
                    end
                    CMD_KICK: begin
                        resp_len <= 3'd2;
                    end
                    CMD_STATUS: begin
                        resp_len <= 3'd6;
                    end
                    default: begin
                        resp_len <= 0;
                    end
                endcase
                if(resp_cnt == resp_len - 1) begin
                    resp_cnt <= 0;
                end else begin
                    resp_cnt <= resp_cnt + 1;
                end
            end 
            default: begin
                resp_cnt <= 0;
                resp_len <= 0;
            end
        endcase
    end
end
//// uart tx//////
always @(*) begin
    case (rx_state)
        S_RESP: begin
            send_uart_valid = 1;
            send_uart_data = resp_data_r[resp_cnt*8 +:8];
        end 
        default: begin
            send_uart_valid = 0;
            send_uart_data = 0;
        end
    endcase
end

always @(*) begin
    case (rx_state)
        S_RESP: begin
            recv_uart_ready = 0;
        end 
        default: begin
            recv_uart_ready = 1;
        end
    endcase
end

endmodule

//=============================================================================
// Module      : resp_buffer
// Description : FIFO buffer 16 bytes
//               - Input  : send_uart_valid / send_uart_data[7:0]
//               - Output : send_en (valid) / tx_done (ack) / tx_data_byte[7:0]
//=============================================================================
module uart_buffer (
    input  wire       clk,            // Clock hệ thống
    input  wire       rst_n,          // Reset hệ thống (active low)

    // Interface đầu vào (Write side)
    input  wire       master_valid,
    input  wire [7:0] master_data_byte,

    // Interface đầu ra (Read side - Handshake Valid/Ready)
    input  wire       slave_ready,        // Đóng vai trò là "Ready" từ phía UART
    output wire       slave_valid,        // Đóng vai trò là "Valid"
    output wire [7:0] slave_data_byte    // Dữ liệu đẩy đi
);

    // Tham số và thanh ghi nội bộ
    localparam DEPTH = 16;
    reg [7:0] mem [0:DEPTH-1];        // Bộ nhớ buffer 16 byte
    reg [3:0] wr_ptr;                 // Con trỏ ghi (4-bit cho 16 vị trí)
    reg [3:0] rd_ptr;                 // Con trỏ đọc
    reg [4:0] count;                  // Đếm số byte hiện có (5-bit để chứa giá trị 16)

    // --- Logic điều khiển đầu ra (Read Interface) ---
    // Buffer có dữ liệu để gửi khi count > 0
    assign slave_valid = (count > 0);
    // Dữ liệu tại vị trí con trỏ đọc hiện tại
    assign slave_data_byte = mem[rd_ptr];
    // --- Logic cập nhật con trỏ và đếm ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 4'd0;
            rd_ptr <= 4'd0;
            count  <= 5'd0;
        end else begin
            // Trường hợp Ghi: Nếu có valid và buffer chưa đầy
            if (master_valid && (count < DEPTH)) begin
                mem[wr_ptr] <= master_data_byte;
                wr_ptr      <= wr_ptr + 1'b1;
            end

            // Trường hợp Đọc: Nếu đang có dữ liệu và bên nhận báo xong (Ready)
            if (slave_valid && slave_ready) begin
                rd_ptr <= rd_ptr + 1'b1;
            end

            // Cập nhật bộ đếm (count)
            case ({ (master_valid && (count < DEPTH)), (slave_valid && slave_ready) })
                2'b10: count <= count + 1'b1; // Chỉ ghi
                2'b01: count <= count - 1'b1; // Chỉ đọc
                default: count <= count;      // Không làm gì hoặc vừa đọc vừa ghi đồng thời
            endcase
        end
    end

endmodule
 // always @(posedge clk or negedge rst_n) begin
//     if(!rst_n) begin
//         rx_state <= S_IDLE;
//     end
//     else begin
//         rx_state <= rx_next_state;
//     end
// end

 // always @(*) begin
//     case (rx_state)
//         // ── S_IDLE: đợi sync byte 0x55 ──
//         S_IDLE: begin
//             if(rx_done) begin
//                 if(rx_data_byte == 8'h55) begin
//                     rx_next_state = S_CMD;
//                 end else begin
//                     rx_next_state = S_IDLE;   // khác 0x55 => ở lại
//                 end
//             end
//             else begin
//                 rx_next_state = S_IDLE;      // chưa có byte => ở lại
//             end
//         end
//         // ── S_CMD: nhận CMD byte ──
//         S_CMD: begin
//             if(rx_done) begin
//                 rx_next_state = S_ADDR;
//             end
//             else begin
//                 rx_next_state = S_CMD;
//             end
//         end
//         // ── S_ADDR: nhận ADDR byte ──
//         S_ADDR: begin
//             if(rx_done) begin
//                 rx_next_state = S_LEN; 
//             end
//             else begin
//                 rx_next_state = S_ADDR;
//             end
//         end
//         // ── S_LEN: nhận LEN byte ──
//         S_LEN:  begin
//             if(rx_done) begin
//                 if(rx_data_byte == 8'h00) begin
//                     rx_next_state = S_CHK;   // len = 0 => không có data
//                 end
//                 else begin
//                     rx_next_state = S_DATA;  // len > 0 => nhận data
//                 end
//             end
//             else begin
//                 rx_next_state = S_LEN;      // chưa có byte => ở lại
//             end
//         end
//         // ── S_DATA: nhận LEN bytes data ──
//         S_DATA: begin
//             if(rx_done) begin
//                 if(r_data_cnt + 1 >= r_len) begin
//                     rx_next_state = S_CHK;  // đủ LEN bytes => sang CHK
//                 end
//                 else begin
//                     rx_next_state = S_DATA; // chưa đủ => ở lại
//                 end
//             end
//             else begin
//                 rx_next_state = S_DATA;    // chưa có byte => ở lại
//             end
//         end
//         // ── S_CHK: kiểm tra checksum và thực thi lệnh ──
//         S_CHK: begin
//             if(rx_done) begin
//                 if(rx_data_byte == chk_acc) begin
//                     rx_next_state = S_EXEC;
//                 end else begin
//                     rx_next_state = S_IDLE;
//                 end
//             end
//             else begin
//                 rx_next_state = S_CHK;
//             end
//         end
//         S_EXEC: begin
//             rx_next_state = S_IDLE;
//         end
//         default: rx_next_state = S_IDLE;
//     endcase
// end