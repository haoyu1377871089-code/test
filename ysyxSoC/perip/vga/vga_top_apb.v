// VGA 控制器 (640x480 @ 60Hz) - 简单版本
// 地址空间:
//   0x00: 控制寄存器 (读: 屏幕尺寸 [31:16]=宽度, [15:0]=高度)
//   0x04: 同步寄存器 (保留)
//   0x08+: 帧缓冲 (每像素32位: 0x00RRGGBB)

/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off WIDTHEXPAND */

module vga_top_apb(
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

  output [7:0]  vga_r,
  output [7:0]  vga_g,
  output [7:0]  vga_b,
  output        vga_hsync,
  output        vga_vsync,
  output        vga_valid
);

  // VGA 时序参数 (640x480 @ 60Hz)
  localparam h_frontporch = 96;
  localparam h_active     = 144;
  localparam h_backporch  = 784;
  localparam h_total      = 800;
  localparam v_frontporch = 2;
  localparam v_active     = 35;
  localparam v_backporch  = 515;
  localparam v_total      = 525;

  // 帧缓冲参数 (640x480 = 307200 像素)
  localparam FB_WIDTH  = 640;
  localparam FB_HEIGHT = 480;
  localparam FB_SIZE   = FB_WIDTH * FB_HEIGHT;  // 307200

  // 帧缓冲 RAM
  reg [31:0] framebuf [0:FB_SIZE-1];

  // VGA 计数器
  reg [9:0] x_cnt;
  reg [9:0] y_cnt;
  reg [18:0] pixel_counter;  // 当前像素索引

  // 有效区域信号
  wire h_valid = (x_cnt > h_active) && (x_cnt <= h_backporch);
  wire v_valid = (y_cnt > v_active) && (y_cnt <= v_backporch);
  wire pixel_valid = h_valid && v_valid;

  // 水平计数器 - 自由运行
  always @(posedge clock) begin
    if (reset) begin
      x_cnt <= 1;
    end else begin
      if (x_cnt == h_total) begin
        x_cnt <= 1;
      end else begin
        x_cnt <= x_cnt + 1;
      end
    end
  end

  // 垂直计数器
  always @(posedge clock) begin
    if (reset) begin
      y_cnt <= 1;
    end else begin
      if (x_cnt == h_total) begin
        if (y_cnt == v_total) begin
          y_cnt <= 1;
        end else begin
          y_cnt <= y_cnt + 1;
        end
      end
    end
  end

  // 像素计数器 - 用于帧缓冲读取
  always @(posedge clock) begin
    if (reset) begin
      pixel_counter <= 0;
    end else begin
      if (y_cnt == v_total && x_cnt == h_total) begin
        pixel_counter <= 0;
      end else if (pixel_valid) begin
        pixel_counter <= pixel_counter + 1;
      end
    end
  end

  // APB 接口 - 简化版，立即响应
  assign in_pready  = 1'b1;
  assign in_pslverr = 1'b0; 

  // 地址解码 (基于相对地址)
  wire [20:0] addr = in_paddr[20:0];
  wire is_ctrl_reg = (addr == 21'h0);
  wire is_framebuf = (addr >= 21'h8);
  wire [18:0] fb_word_addr = (addr - 21'h8) >> 2;

  // APB 写操作 - 写入帧缓冲
  always @(posedge clock) begin
    if (in_psel && in_penable && in_pwrite && is_framebuf && fb_word_addr < FB_SIZE) begin
      if (in_pstrb[0]) framebuf[fb_word_addr][ 7: 0] <= in_pwdata[ 7: 0];
      if (in_pstrb[1]) framebuf[fb_word_addr][15: 8] <= in_pwdata[15: 8];
      if (in_pstrb[2]) framebuf[fb_word_addr][23:16] <= in_pwdata[23:16];
      if (in_pstrb[3]) framebuf[fb_word_addr][31:24] <= in_pwdata[31:24];
    end
  end

  // APB 读操作
  reg [31:0] rdata;
  always @(*) begin
    if (is_ctrl_reg)
      rdata = {16'd640, 16'd480};  // 返回帧缓冲尺寸
    else if (is_framebuf && fb_word_addr < FB_SIZE)
      rdata = framebuf[fb_word_addr];
    else
      rdata = 32'b0;
  end
  assign in_prdata = rdata;

  // VGA 同步信号生成
  assign vga_hsync = (x_cnt > h_frontporch);
  assign vga_vsync = (y_cnt > v_frontporch);
  assign vga_valid = pixel_valid;

  // 输出 RGB (像素格式: 0x00RRGGBB)
  assign vga_r = pixel_valid ? framebuf[pixel_counter][23:16] : 8'h0;
  assign vga_g = pixel_valid ? framebuf[pixel_counter][15: 8] : 8'h0;
  assign vga_b = pixel_valid ? framebuf[pixel_counter][ 7: 0] : 8'h0;

endmodule

/* verilator lint_on WIDTHTRUNC */
/* verilator lint_on WIDTHEXPAND */
