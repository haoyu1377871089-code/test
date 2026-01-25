// IS66WVS4M8ALL PSRAM 仿真行为模型
// 支持 QSPI 和 QPI 模式
// 存储容量: 4MB (IS66WVS4M8ALL 实际大小)
//
// 协议说明:
// QSPI模式 (1-4-4):
// - EBh (Quad IO Read):  CMD(8 bits, 1-bit SPI) + ADDR(24 bits, 4-bit) + Wait(6 cycles) + DATA(4-bit)
// - 38h (Quad IO Write): CMD(8 bits, 1-bit SPI) + ADDR(24 bits, 4-bit) + DATA(4-bit)
// - 35h (Enter QPI):     CMD(8 bits, 1-bit SPI)
//
// QPI模式 (4-4-4):
// - EBh (Quad IO Read):  CMD(8 bits, 4-bit) + ADDR(24 bits, 4-bit) + Wait(6 cycles) + DATA(4-bit)
// - 38h (Quad IO Write): CMD(8 bits, 4-bit) + ADDR(24 bits, 4-bit) + DATA(4-bit)
// - F5h (Exit QPI):      CMD(8 bits, 4-bit)

/* verilator lint_off WIDTHTRUNC */

module psram(
  input sck,
  input ce_n,
  inout [3:0] dio
);

  // 4MB 内存大小 (IS66WVS4M8ALL 实际大小)
  reg [7:0] mem [0:4*1024*1024-1];  // 4MB = 4194304 bytes

  // 计数器和寄存器
  reg [7:0] counter;      // SCK 计数器
  reg [7:0] cmd_reg;      // 命令寄存器
  reg [23:0] addr_reg;    // 地址寄存器
  reg [21:0] mem_addr;    // 内存写地址 (22 bits for 4MB)
  reg [7:0] byte_buf;     // 字节缓冲（写入用）
  reg [21:0] read_addr;   // 读取地址 (22 bits for 4MB)
  
  // QPI模式标志 - 持久状态，不随ce_n复位
  reg qpi_mode;
  
  // 输入采样寄存器 - 在posedge采样输入
  reg [3:0] dio_sampled;
  
  // 命令定义
  localparam CMD_READ      = 8'hEB;
  localparam CMD_WRITE     = 8'h38;
  localparam CMD_ENTER_QPI = 8'h35;
  localparam CMD_EXIT_QPI  = 8'hF5;

  wire is_read      = (cmd_reg == CMD_READ);
  wire is_write     = (cmd_reg == CMD_WRITE);
  wire is_enter_qpi = (cmd_reg == CMD_ENTER_QPI);
  wire is_exit_qpi  = (cmd_reg == CMD_EXIT_QPI);
  
  // QPI模式下的命令长度：2个周期（vs SPI模式下8个周期）
  wire [7:0] cmd_end_cnt = qpi_mode ? 8'd2 : 8'd8;
  // QPI模式下地址结束计数：2+6=8 (vs SPI模式下8+6=14)
  wire [7:0] addr_end_cnt = qpi_mode ? 8'd8 : 8'd14;
  // QPI模式下读数据开始计数：8+6(wait)=14 (vs SPI模式下14+6=20)
  wire [7:0] read_start_cnt = qpi_mode ? 8'd14 : 8'd20;
  // QPI模式下写数据开始计数：8 (vs SPI模式下14)
  wire [7:0] write_start_cnt = qpi_mode ? 8'd8 : 8'd14;
  
  // 输出数据 - 纯组合逻辑
  wire [3:0] dout_hi = mem[read_addr][7:4];
  wire [3:0] dout_lo = mem[read_addr][3:0];
  
  // 偶数counter输出高nibble，奇数counter输出低nibble
  wire [3:0] dout_comb = (counter[0] == 0) ? dout_hi : dout_lo;
  
  // 读数据输出使能
  wire dout_en = (counter >= read_start_cnt) && is_read && !ce_n;
  
  // 三态逻辑
  assign dio = dout_en ? dout_comb : 4'bz;

  wire do_reset = ce_n;

  // QPI模式标志 - 独立的always块，不受ce_n复位影响
  // 只在初始复位时清零
  initial begin
    qpi_mode = 1'b0;
  end

  // 在 posedge sck 采样输入
  always @(posedge sck or posedge do_reset) begin
    if (do_reset) begin
      dio_sampled <= 4'b0;
    end else begin
      dio_sampled <= dio;
      // 调试：只显示QPI模式初始化期间
      // if (counter < 10)
      //   $display("[PSRAM] posedge sck: counter=%0d, dio=0x%x, ce_n=%b", counter, dio, ce_n);
    end
  end

  // 主逻辑 - 在 negedge sck 更新状态
  // 这样在下一个 posedge sck 时数据稳定，控制器可以采样
  always @(negedge sck or posedge do_reset) begin
    if (do_reset) begin
      counter <= 0;
      cmd_reg <= 0;
      addr_reg <= 0;
      mem_addr <= 0;
      byte_buf <= 0;
      read_addr <= 0;
    end else begin
      counter <= counter + 1;
      
      // 接收命令阶段
      if (counter < cmd_end_cnt) begin
        if (qpi_mode) begin
          // QPI模式: 4-bit并行，2个周期
          cmd_reg <= {cmd_reg[3:0], dio_sampled};
        end else begin
          // SPI模式: 1-bit串行，8个周期
          cmd_reg <= {cmd_reg[6:0], dio_sampled[0]};
        end
      end
      
      // 接收地址阶段 (总是4-bit QSPI)
      if (counter >= cmd_end_cnt && counter < addr_end_cnt) begin
        addr_reg <= {addr_reg[19:0], dio_sampled};
      end
      
      // 地址接收完毕，保存地址 (使用低22位寻址4MB)
      if (counter == addr_end_cnt - 1) begin
        mem_addr <= {addr_reg[17:0], dio_sampled};   // 22 bits for 4MB
        read_addr <= {addr_reg[17:0], dio_sampled};  // 22 bits for 4MB
      end
      
      // 处理Enter/Exit QPI命令
      // 注意：命令检测需要在命令寄存器更新后进行
      if (qpi_mode) begin
        // QPI模式下，命令在counter=2完成（0,1两个周期后）
        if (counter == 2 && is_exit_qpi) begin
          qpi_mode <= 1'b0;
          $display("[PSRAM] Exit QPI mode");
        end
      end else begin
        // SPI模式下，命令在counter=8完成（0-7共8个周期后）
        if (counter == 8) begin
          // $display("[PSRAM] negedge sck counter=8, cmd_reg=0x%02x, is_enter_qpi=%b, qpi_mode=%b", cmd_reg, is_enter_qpi, qpi_mode);
          if (is_enter_qpi) begin
            // $display("[PSRAM] >>> Setting qpi_mode to 1 <<<");
            qpi_mode <= 1'b1;
            $display("[PSRAM] Enter QPI mode");
          end
        end
      end
      
      // 读数据阶段 - 地址递增
      if (counter >= read_start_cnt && is_read) begin
        if (counter[0] == 1) begin  // 奇数 counter
          read_addr <= read_addr + 1;
        end
      end
      
      // 写数据阶段
      if (counter >= write_start_cnt && is_write) begin
        if (counter[0] == 0) begin
          // 偶数 counter: 接收高 4 位
          byte_buf[7:4] <= dio_sampled;
        end else begin
          // 奇数 counter: 接收低 4 位并写入内存
          mem[mem_addr] <= {byte_buf[7:4], dio_sampled};
          mem_addr <= mem_addr + 1;
        end
      end
    end
  end

endmodule

/* verilator lint_on WIDTHTRUNC */
