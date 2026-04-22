 module uart_frame_parser (
    input clk,
    input rst_n,
/////////// uart rx
    input rx_done,
    input [7:0] rx_data_byte,
////////// uart tx
    input uart_tx_state,
    output reg [7:0] tx_data_byte,
    output reg send_en,
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
           S_EXEC = 3'd6;

//FSM gửi
localparam R_IDLE = 2'd0, R_SEND = 2'd1,
           R_WAIT = 2'd2;

// CMD codes
localparam CMD_WRITE  = 8'h01,
           CMD_READ   = 8'h02,
           CMD_KICK   = 8'h03,
           CMD_STATUS = 8'h04;

// FSM state
reg [2:0] rx_state;        // S_IDLE=0, S_CMD=1, S_ADDR=2, S_LEN=3, S_DATA=4, S_CHK=5
reg [2:0] rx_next_state;

// Frame registers
reg [7:0]   r_cmd;
reg [7:0]   r_addr;
reg [7:0]   r_len;
reg [7:0]   r_data_cnt;
reg [31:0]  r_data_acc;
reg [7:0]   chk_acc;

// Response buffer
reg [7:0] resp_buf [0:5];  // Buffer chứa bytes cần gửi về PC, Tối đa 6 bytes: [0xAA][D0][D1][D2][D3][CHK]
reg [2:0] resp_len;
reg [2:0] resp_idx;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        rx_state <= IDLE;
    end
    else begin
        rx_state <= rx_next_state;
    end
end

/*
 FSM controll
*/
always @(*) begin
    case (rx_state)
        // ── S_IDLE: đợi sync byte 0x55 ──
        S_IDLE: begin
            if(rx_done) begin
                if(rx_data_byte == 8'h55) begin
                    rx_next_state = S_CMD;
                end else begin
                    rx_next_state = S_IDLE;   // khác 0x55 => ở lại
                end
            end
            else begin
                rx_next_state = S_IDLE;      // chưa có byte => ở lại
            end
        end
        // ── S_CMD: nhận CMD byte ──
        S_CMD: begin
            if(rx_done) begin
                rx_next_state = S_ADDR;
            end
            else begin
                rx_next_state = S_CMD;
            end
        end
        // ── S_ADDR: nhận ADDR byte ──
        S_ADDR: begin
            if(rx_done) begin
                rx_next_state = S_LEN; 
            end
            else begin
                rx_next_state = S_ADDR;
            end
        end
        // ── S_LEN: nhận LEN byte ──
        S_LEN:  begin
            if(rx_done) begin
                if(rx_data_byte == 8'h00) begin
                    rx_next_state = S_CHK;   // len = 0 => không có data
                end
                else begin
                    rx_next_state = S_DATA;  // len > 0 => nhận data
                end
            end
            else begin
                rx_next_state = S_LEN;      // chưa có byte => ở lại
            end
        end
        // ── S_DATA: nhận LEN bytes data ──
        S_DATA: begin
            if(rx_done) begin
                if(r_data_cnt + 1 >= r_len) begin
                    rx_next_state = S_CHK;  // đủ LEN bytes => sang CHK
                end
                else begin
                    rx_next_state = S_DATA; // chưa đủ => ở lại
                end
            end
            else begin
                rx_next_state = S_DATA;    // chưa có byte => ở lại
            end
        end
        // ── S_CHK: kiểm tra checksum và thực thi lệnh ──
        S_CHK: begin
            if(rx_done) begin
                if(rx_data_byte == chk_acc) begin
                    rx_next_state = S_EXEC;
                end else begin
                    rx_next_state = IDLE;
                end
            end
            else begin
                rx_next_state = S_CHK;
            end
        end
        S_EXEC: begin
            rx_next_state = IDLE;
        end
        default: rx_next_state = S_IDLE;
    endcase
end

always @(*) begin
    case (rx_state)
        // ── S_IDLE: đợi sync byte 0x55 ──
        S_IDLE: begin
            r_cmd = 0;
            r_addr = 0;
            r_len = 0;
            r_data_acc = 0;
            chk_acc = 0;
        end
        
        // ── S_CMD: nhận CMD byte ──
        S_CMD: begin
            r_cmd = rx_data_byte;
            r_addr = r_addr;
            r_len = r_len;
            r_data_acc = r_data_acc;
            chk_acc = rx_data_byte;
        end
        
        // ── S_ADDR: nhận ADDR byte ──
        S_ADDR: begin
            r_cmd = r_cmd;
            r_addr = rx_data_byte;
            r_len = r_len;
            r_data_acc = r_data_acc;
            chk_acc = chk_acc ^ rx_data_byte;
        end

        // ── S_LEN: nhận LEN byte ──
        S_LEN:  begin
            r_cmd = r_cmd;
            r_addr = r_addr;
            r_len = rx_data_byte;
            r_data_acc = r_data_acc;
            chk_acc = chk_acc ^ rx_data_byte;
        end

        // ── S_DATA: nhận LEN bytes data ──
        S_DATA: begin
            r_cmd = r_cmd;
            r_addr = r_addr;
            r_len = r_len;
            if(rx_done) begin
                r_data_acc[(r_data_cnt+1)*8 - 1:r_data_cnt*8] = rx_data_byte;
                chk_acc = chk_acc ^ rx_data_byte;
            end
            else begin
                r_data_acc = r_data_acc;
            end
            
        end

        // ── S_CHK: kiểm tra checksum và thực thi lệnh ──
        S_CHK: begin
            r_cmd = r_cmd;
            r_addr = r_addr;
            r_len = r_len;
            r_data_acc = r_data_acc;
            chk_acc = chk_acc;
        end
        S_EXEC: begin
            r_cmd = r_cmd;
            r_addr = r_addr;
            r_len = r_len;
            r_data_acc = r_data_acc;
            chk_acc = chk_acc;
        end
        default: begin
            r_cmd = r_cmd;
            r_addr = r_addr;
            r_len = r_len;
            r_data_acc = r_data_acc;
            chk_acc = chk_acc;
        end
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_data_cnt <= 0;
    end else begin
        case (rx_state)
            S_DATA: begin
                if(rx_done) begin
                    r_data_cnt <= r_data_cnt + 1;
                    if(r_data_cnt == r_len) begin
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
        end
    endcase
end
 endmodule