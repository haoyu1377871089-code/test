// SPI APB Wrapper with XIP (eXecute In Place) support
// - SPI register space: 0x10001000~0x10001fff -> normal access
// - Flash XIP space: 0x30000000~0x3fffffff -> XIP state machine

// define this macro to enable fast behavior simulation
// for flash by skipping SPI transfers
// `define FAST_FLASH

module spi_top_apb #(
  parameter flash_addr_start = 32'h30000000,
  parameter flash_addr_end   = 32'h3fffffff,
  parameter spi_ss_num       = 8
) (
  input         clock,
  input         reset,
  input  [31:0] in_paddr,
  input         in_psel,
  input         in_penable,
  input  [2:0]  in_pprot,
  input         in_pwrite,
  input  [31:0] in_pwdata,
  input  [3:0]  in_pstrb,
  output        in_pready,
  output [31:0] in_prdata,
  output        in_pslverr,

  output                  spi_sck,
  output [spi_ss_num-1:0] spi_ss,
  output                  spi_mosi,
  input                   spi_miso,
  output                  spi_irq_out
);

`ifdef FAST_FLASH

wire [31:0] data;
parameter invalid_cmd = 8'h0;
flash_cmd flash_cmd_i(
  .clock(clock),
  .valid(in_psel && !in_penable),
  .cmd(in_pwrite ? invalid_cmd : 8'h03),
  .addr({8'b0, in_paddr[23:2], 2'b0}),
  .data(data)
);
assign spi_sck    = 1'b0;
assign spi_ss     = 8'b0;
assign spi_mosi   = 1'b1;
assign spi_irq_out= 1'b0;
assign in_pslverr = 1'b0;
assign in_pready  = in_penable && in_psel && !in_pwrite;
assign in_prdata  = data[31:0];

`else

// ============================================================
// Address decode
// ============================================================
wire is_xip_addr = (in_paddr >= flash_addr_start) && (in_paddr <= flash_addr_end);
wire is_spi_addr = !is_xip_addr;

// ============================================================
// XIP State Machine
// ============================================================
// 使用更细粒度的状态来处理每次 SPI 访问的请求-等待周期
localparam XIP_IDLE       = 4'd0;
localparam XIP_TX1_REQ    = 4'd1;
localparam XIP_TX1_WAIT   = 4'd2;
localparam XIP_TX0_REQ    = 4'd3;
localparam XIP_TX0_WAIT   = 4'd4;
localparam XIP_SS_REQ     = 4'd5;
localparam XIP_SS_WAIT    = 4'd6;
localparam XIP_CTRL_REQ   = 4'd7;
localparam XIP_CTRL_WAIT  = 4'd8;
localparam XIP_POLL_REQ   = 4'd9;
localparam XIP_POLL_WAIT  = 4'd10;
localparam XIP_RX_REQ     = 4'd11;
localparam XIP_RX_WAIT    = 4'd12;
localparam XIP_DONE       = 4'd13;

reg [3:0] xip_state;
reg [31:0] xip_rdata;
reg xip_ready;
reg xip_error;

// XIP 控制 SPI 的信号
reg        xip_spi_stb;
reg        xip_spi_we;
reg [4:0]  xip_spi_addr;
reg [31:0] xip_spi_wdata;

// SPI master 信号
wire        spi_stb;
wire        spi_cyc;
wire        spi_we;
wire [4:0]  spi_addr;
wire [31:0] spi_wdata;
wire [3:0]  spi_sel;
wire [31:0] spi_rdata;
wire        spi_ack;
wire        spi_err;

// 当处于 XIP 模式时，使用 XIP 状态机的信号；否则使用 APB 直通
wire xip_active = (xip_state != XIP_IDLE) && (xip_state != XIP_DONE);

assign spi_stb   = xip_active ? xip_spi_stb : (is_spi_addr & in_psel);
assign spi_cyc   = xip_active ? xip_spi_stb : (is_spi_addr & in_penable);
assign spi_we    = xip_active ? xip_spi_we  : in_pwrite;
assign spi_addr  = xip_active ? xip_spi_addr : in_paddr[4:0];
assign spi_wdata = xip_active ? xip_spi_wdata : in_pwdata;
assign spi_sel   = 4'b1111;

// Flash 读命令: 0x03
localparam FLASH_CMD_READ = 8'h03;

// 保存 XIP 请求地址
reg [31:0] xip_req_addr;

// XIP 状态机
always @(posedge clock or posedge reset) begin
    if (reset) begin
        xip_state <= XIP_IDLE;
        xip_rdata <= 32'b0;
        xip_ready <= 1'b0;
        xip_error <= 1'b0;
        xip_spi_stb <= 1'b0;
        xip_spi_we <= 1'b0;
        xip_spi_addr <= 5'b0;
        xip_spi_wdata <= 32'b0;
        xip_req_addr <= 32'b0;
    end else begin
        case (xip_state)
            XIP_IDLE: begin
                xip_ready <= 1'b0;
                xip_error <= 1'b0;
                xip_spi_stb <= 1'b0;
                
                // 检测到 XIP 地址的请求 (psel 有效时开始)
                if (in_psel && is_xip_addr) begin
                    if (in_pwrite) begin
                        // XIP 不支持写操作
                        // synthesis translate_off
                        $display("[XIP ERROR] Write to Flash XIP space not supported! addr=%h", in_paddr);
                        // synthesis translate_on
                        xip_error <= 1'b1;
                        xip_ready <= 1'b1;
                        xip_state <= XIP_DONE;
                    end else begin
                        xip_req_addr <= in_paddr;
                        xip_state <= XIP_TX1_REQ;
                    end
                end
            end
            
            // ========== TX1: cmd + addr ==========
            XIP_TX1_REQ: begin
                xip_spi_stb <= 1'b1;
                xip_spi_we <= 1'b1;
                xip_spi_addr <= 5'h04;  // TX1
                xip_spi_wdata <= {FLASH_CMD_READ, xip_req_addr[23:2], 2'b00};
                xip_state <= XIP_TX1_WAIT;
            end
            
            XIP_TX1_WAIT: begin
                if (spi_ack) begin
                    xip_spi_stb <= 1'b0;
                    xip_state <= XIP_TX0_REQ;
                end
            end
            
            // ========== TX0: dummy ==========
            XIP_TX0_REQ: begin
                xip_spi_stb <= 1'b1;
                xip_spi_we <= 1'b1;
                xip_spi_addr <= 5'h00;  // TX0
                xip_spi_wdata <= 32'h00000000;
                xip_state <= XIP_TX0_WAIT;
            end
            
            XIP_TX0_WAIT: begin
                if (spi_ack) begin
                    xip_spi_stb <= 1'b0;
                    xip_state <= XIP_SS_REQ;
                end
            end
            
            // ========== SS: select flash ==========
            XIP_SS_REQ: begin
                xip_spi_stb <= 1'b1;
                xip_spi_we <= 1'b1;
                xip_spi_addr <= 5'h18;  // SS
                xip_spi_wdata <= 32'h00000001;  // Flash = slave 0
                xip_state <= XIP_SS_WAIT;
            end
            
            XIP_SS_WAIT: begin
                if (spi_ack) begin
                    xip_spi_stb <= 1'b0;
                    xip_state <= XIP_CTRL_REQ;
                end
            end
            
            // ========== CTRL: start transfer ==========
            XIP_CTRL_REQ: begin
                xip_spi_stb <= 1'b1;
                xip_spi_we <= 1'b1;
                xip_spi_addr <= 5'h10;  // CTRL
                // CHAR_LEN=64 | ASS(1<<13) | TX_NEG(1<<10) | GO(1<<8) = 0x2540
                xip_spi_wdata <= 32'h00002540;
                xip_state <= XIP_CTRL_WAIT;
            end
            
            XIP_CTRL_WAIT: begin
                if (spi_ack) begin
                    xip_spi_stb <= 1'b0;
                    xip_state <= XIP_POLL_REQ;
                end
            end
            
            // ========== POLL: wait for transfer complete ==========
            XIP_POLL_REQ: begin
                xip_spi_stb <= 1'b1;
                xip_spi_we <= 1'b0;  // 读
                xip_spi_addr <= 5'h10;  // CTRL
                xip_state <= XIP_POLL_WAIT;
            end
            
            XIP_POLL_WAIT: begin
                if (spi_ack) begin
                    xip_spi_stb <= 1'b0;
                    // 检查 GO/BUSY 位 (bit 8)
                    if (!spi_rdata[8]) begin
                        // 传输完成
                        xip_state <= XIP_RX_REQ;
                    end else begin
                        // 继续轮询
                        xip_state <= XIP_POLL_REQ;
                    end
                end
            end
            
            // ========== RX: read data ==========
            XIP_RX_REQ: begin
                xip_spi_stb <= 1'b1;
                xip_spi_we <= 1'b0;
                xip_spi_addr <= 5'h00;  // RX0
                xip_state <= XIP_RX_WAIT;
            end
            
            XIP_RX_WAIT: begin
                if (spi_ack) begin
                    // Flash 返回的数据是大端序，需要字节交换
                    xip_rdata <= {spi_rdata[7:0], spi_rdata[15:8], 
                                  spi_rdata[23:16], spi_rdata[31:24]};
                    xip_spi_stb <= 1'b0;
                    xip_ready <= 1'b1;
                    xip_state <= XIP_DONE;
                end
            end
            
            // ========== DONE: wait for APB complete ==========
            XIP_DONE: begin
                // 等待 APB 事务完成 (penable 有效)
                if (in_penable && in_psel) begin
                    xip_state <= XIP_IDLE;
                    xip_ready <= 1'b0;
                    xip_error <= 1'b0;
                end
            end
            
            default: xip_state <= XIP_IDLE;
        endcase
    end
end

// ============================================================
// SPI Master Instance
// ============================================================
spi_top u0_spi_top (
  .wb_clk_i(clock),
  .wb_rst_i(reset),
  .wb_adr_i(spi_addr),
  .wb_dat_i(spi_wdata),
  .wb_dat_o(spi_rdata),
  .wb_sel_i(spi_sel),
  .wb_we_i (spi_we),
  .wb_stb_i(spi_stb),
  .wb_cyc_i(spi_cyc),
  .wb_ack_o(spi_ack),
  .wb_err_o(spi_err),
  .wb_int_o(spi_irq_out),

  .ss_pad_o(spi_ss),
  .sclk_pad_o(spi_sck),
  .mosi_pad_o(spi_mosi),
  .miso_pad_i(spi_miso)
);

// ============================================================
// APB Output Mux
// ============================================================
assign in_pready  = (xip_state == XIP_DONE) ? xip_ready : 
                    (is_spi_addr ? spi_ack : 1'b0);
assign in_prdata  = (xip_state == XIP_DONE) ? xip_rdata : spi_rdata;
assign in_pslverr = (xip_state == XIP_DONE) ? xip_error : spi_err;

`endif // FAST_FLASH

endmodule
