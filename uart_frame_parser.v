 module uart_frame_parser (
    input clk,
    input rst_n,
    input rx_done,
    input [7:0] rx_data_byte,
    input uart_tx_state,
    input [31:0] rd_data,
    output reg send_en,
    output reg [7:0] tx_data_byte,
    output reg wr_en,
    output reg [7:0] wr_addr,
    output reg [31:0] wr_data,
    output reg rd_en,
    output reg [7:0] rd_addr,
    output reg wdi_uart
 );

//FSM nhận
localparam S_IDLE = 3'd0, S_CMD  = 3'd1,
           S_ADDR = 3'd2, S_LEN  = 3'd3,
           S_DATA = 3'd4, S_CHK  = 3'd5;

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
reg [1:0] tx_state;        // R_IDLE=0, R_SEND=1, R_WAIT=2

// Frame registers
reg [7:0] r_cmd;
reg [7:0] r_addr;
reg [7:0] r_len;
reg [7:0] r_data_cnt;
reg [31:0] r_data_acc;
reg [7:0] chk_acc;

// Response buffer
reg [7:0] resp_buf [0:5];  // Buffer chứa bytes cần gửi về PC, Tối đa 6 bytes: [0xAA][D0][D1][D2][D3][CHK]
reg [2:0] resp_len;
reg [2:0] resp_idx;

reg       do_resp_fsm;   // từ FSM nhận
reg       do_resp_read;  // từ READ delay
wire do_resp = do_resp_fsm | do_resp_read;

// READ delay
reg rd_en_d;

integer i;

//FSM nhan frame
always @(posedge clk or negedge rst_n) begin
   if(!rst_n) begin
      rx_state <= S_IDLE;
      r_cmd      <= 8'd0;
      r_addr     <= 8'd0;
      r_len      <= 8'd0;
      r_data_cnt <= 8'd0;
      r_data_acc <= 32'd0;
      chk_acc    <= 8'd0;
      wr_en      <= 1'b0;
      wr_addr    <= 8'd0;
      wr_data    <= 32'd0;
      rd_en      <= 1'b0;
      rd_addr    <= 8'd0;
      wdi_uart   <= 1'b0;
      do_resp_fsm    <= 1'b0;
      resp_len   <= 3'd0;
      for (i = 0; i < 6; i = i + 1) begin
         resp_buf[i] <= 8'd0;
      end
   end
   else begin
      wr_en        <= 1'b0;
      rd_en        <= 1'b0;
      wdi_uart     <= 1'b0;
      do_resp_fsm  <= 1'b0;

      case (rx_state)
         // ── S_IDLE: đợi sync byte 0x55 ──
         S_IDLE: begin
            if(rx_done) begin
               if(rx_data_byte == 8'h55) begin
                  rx_state <= S_CMD;
                  chk_acc <= 8'd0;
                  r_data_acc <= 32'd0;
                  r_data_cnt <= 8'd0;
               end
               else begin
                  rx_state <= S_IDLE;   // khác 0x55 => ở lại
               end
            end
            else begin
               rx_state <= S_IDLE;      // chưa có byte => ở lại
            end
         end
         
         // ── S_CMD: nhận CMD byte ──
         S_CMD: begin
            if(rx_done) begin
               r_cmd    <= rx_data_byte;
               chk_acc  <= rx_data_byte;
               rx_state <= S_ADDR;
            end
            else begin
               rx_state <= S_CMD;
            end
         end
         
         // ── S_ADDR: nhận ADDR byte ──
         S_ADDR: begin
            if(rx_done) begin
               r_addr    <= rx_data_byte;
               chk_acc  <= chk_acc ^ rx_data_byte;
               rx_state <= S_LEN; 
            end
            else begin
               rx_state <= S_ADDR;
            end
         end

         // ── S_LEN: nhận LEN byte ──
         S_LEN:  begin
            if(rx_done) begin
               r_len    <= rx_data_byte;
               chk_acc  <= chk_acc ^ rx_data_byte;
               r_data_cnt <= 8'd0;
               r_data_acc <= 32'd0;
               if(rx_data_byte == 8'h00) begin
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
            if(rx_done) begin
               r_data_acc <= r_data_acc |
                                      ({{24{1'b0}}, rx_data_byte}
                                       << (r_data_cnt * 8));
               chk_acc    <= chk_acc ^ rx_data_byte;
               r_data_cnt <= r_data_cnt + 1'b1;
               if(r_data_cnt + 1 >= r_len) begin
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
            if(rx_done) begin
               rx_state <= S_IDLE;
               if(rx_data_byte == chk_acc) begin
                  //CHK đúng => thực thi lệnh
                  case (r_cmd)
                     CMD_WRITE: begin
                        wr_en <= 1'b1;
                        wr_addr <= r_addr;
                        wr_data <= r_data_acc;
                        resp_buf[0] <= 8'hAA;   
                        resp_buf[1] <= 8'hAA;  
                        resp_len    <= 3'd2;
                        do_resp_fsm     <= 1'b1;
                     end

                     CMD_READ: begin
                        rd_en   <= 1'b1;
                        rd_addr <= r_addr;
                     end

                     CMD_KICK: begin
                        wdi_uart    <= 1'b1;
                        resp_buf[0] <= 8'hAA;   
                        resp_buf[1] <= 8'hAA;  
                        resp_len    <= 3'd2;
                        do_resp_fsm <= 1'b1;
                     end

                     CMD_STATUS: begin
                        rd_en   <= 1'b1;
                        rd_addr <= 8'h10;
                     end

                     default: begin
                        // CMD không hợp lệ => NACK
                        resp_buf[0] <= 8'hFF;
                        resp_buf[1] <= 8'hFF;
                        resp_len    <= 3'd2;
                        do_resp_fsm <= 1'b1;
                     end
                  endcase
               end
               else begin
                  //CHK sai => NACK
                  resp_buf[0] <= 8'hFF;
                  resp_buf[1] <= 8'hFF;
                  resp_len    <= 3'd2;
                  do_resp_fsm <= 1'b1;
               end
            end
            else begin
               rx_state <= S_CHK;
            end
         end

         default: rx_state <= S_IDLE;
      endcase
   end
end

// Xử lý READ delay 1 cycle:
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rd_en_d     <= 1'b0;
        resp_len    <= 3'd0;
        do_resp_read     <= 1'b0;
        resp_buf[0] <= 8'd0;
        resp_buf[1] <= 8'd0;
        resp_buf[2] <= 8'd0;
        resp_buf[3] <= 8'd0;
        resp_buf[4] <= 8'd0;
        resp_buf[5] <= 8'd0;
    end else begin
        rd_en_d <= rd_en;  // delay 1 cycle

        if (rd_en_d) begin
            // rd_data đã có giá trị → build response
            resp_buf[0] <= 8'hAA;
            resp_buf[1] <= rd_data[7:0];
            resp_buf[2] <= rd_data[15:8];
            resp_buf[3] <= rd_data[23:16];
            resp_buf[4] <= rd_data[31:24];
            resp_buf[5] <= 8'hAA
                         ^ rd_data[7:0]
                         ^ rd_data[15:8]
                         ^ rd_data[23:16]
                         ^ rd_data[31:24];
            resp_len    <= 3'd6;
            do_resp_read     <= 1'b1;
        end else begin
            // rd_en_d=0 → không có gì → giữ nguyên
            do_resp_read  <= 1'b0;
        end
    end
end


//FSM gửi response:
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_state     <= R_IDLE;
        send_en      <= 1'b0;
        tx_data_byte <= 8'd0;
        resp_idx     <= 3'd0;
    end else begin
        send_en <= 1'b0;  // default

        case (tx_state)

            R_IDLE: begin
                if (do_resp) begin
                    resp_idx <= 3'd0;
                    tx_state <= R_SEND;
                end else begin
                    tx_state <= R_IDLE;
                end
            end

            R_SEND: begin
                if (!uart_tx_state) begin
                    // uart_tx rảnh → gửi byte
                    tx_data_byte <= resp_buf[resp_idx];
                    send_en      <= 1'b1;
                    tx_state     <= R_WAIT;
                end else begin
                    // uart_tx bận → đứng yên
                    tx_state <= R_SEND;
                end
            end

            R_WAIT: begin
                if (!uart_tx_state) begin
                    if (resp_idx + 1 >= resp_len) begin
                        // Hết byte → về R_IDLE
                        tx_state <= R_IDLE;
                    end else begin
                        // Còn byte → gửi tiếp
                        resp_idx <= resp_idx + 1'b1;
                        tx_state <= R_SEND;
                    end
                end else begin
                    // send_en vẫn còn cao → đợi
                    tx_state <= R_WAIT;
                end
            end

            default: begin
                tx_state <= R_IDLE;
            end

        endcase
    end
end

endmodule