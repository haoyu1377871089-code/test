// SPI Slave 位翻转模块
// 接收8位数据，输出位翻转结果 (bit0<->bit7, bit1<->bit6, ...)
// SPI 模式: CPOL=0, CPHA=0 (在SCK上升沿采样MOSI，在SCK下降沿更新MISO)
// 数据顺序: MSB first

module bitrev (
  input  sck,
  input  ss,
  input  mosi,
  output miso
);
  // SS高电平(空闲)时异步复位
  wire reset = ss;

  // 位计数器 (0-15, 共16位传输)
  reg [3:0] bit_cnt;

  // 输入移位寄存器 (接收8位数据)
  reg [7:0] shift_in;

  // 输出移位寄存器 (发送位翻转后的8位数据)
  reg [7:0] shift_out;

  // 在SCK上升沿采样MOSI，接收数据
  always @(posedge sck or posedge reset) begin
    if (reset) begin
      bit_cnt <= 4'd0;
      shift_in <= 8'd0;
    end else begin
      bit_cnt <= bit_cnt + 4'd1;
      // 前8位是输入数据
      if (bit_cnt < 4'd8) begin
        shift_in <= {shift_in[6:0], mosi};
      end
    end
  end

  // 位翻转逻辑: 输入的bit7->输出的bit0, bit6->bit1, ...
  wire [7:0] reversed = {shift_in[0], shift_in[1], shift_in[2], shift_in[3],
                         shift_in[4], shift_in[5], shift_in[6], shift_in[7]};

  // 在SCK下降沿更新MISO输出
  always @(negedge sck or posedge reset) begin
    if (reset) begin
      shift_out <= 8'hFF;  // 空闲时MISO为高
    end else begin
      if (bit_cnt == 4'd8) begin
        // 第8个时钟后，加载翻转后的数据准备发送
        shift_out <= {reversed[6:0], 1'b1};  // MSB已经在miso上
      end else if (bit_cnt > 4'd8) begin
        // 后8位发送翻转数据
        shift_out <= {shift_out[6:0], 1'b1};
      end
    end
  end

  // MISO输出: SS高时为高阻(这里输出高)，传输后半段输出翻转数据
  wire [2:0] out_bit_idx = 3'd7 - bit_cnt[2:0];  // 后8位的输出索引
  assign miso = ss ? 1'b1 : 
                (bit_cnt >= 4'd8) ? reversed[out_bit_idx] : 1'b1;

endmodule
