// GPIO Controller with APB Interface
// Address Map:
//   0x0: LED output (16-bit, drives 16 LEDs)
//   0x4: Switch input (16-bit, reads 16 switches state)
//   0x8: 7-segment display output (32-bit, 4 bits per digit)
//   0xc: Reserved
module gpio_top_apb(
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

  output [15:0] gpio_out,
  input  [15:0] gpio_in,
  output [7:0]  gpio_seg_0,
  output [7:0]  gpio_seg_1,
  output [7:0]  gpio_seg_2,
  output [7:0]  gpio_seg_3,
  output [7:0]  gpio_seg_4,
  output [7:0]  gpio_seg_5,
  output [7:0]  gpio_seg_6,
  output [7:0]  gpio_seg_7
);

  // Register definitions
  reg [15:0] led_reg;       // 0x0: LED output register
  reg [31:0] seg_reg;       // 0x8: 7-segment display register
  
  // APB interface - always ready, no errors
  assign in_pready = 1'b1;
  assign in_pslverr = 1'b0;
  
  // Address decoding (use lower 4 bits)
  wire [3:0] addr = in_paddr[3:0];
  
  // Read logic
  reg [31:0] rdata;
  always @(*) begin
    case (addr)
      4'h0: rdata = {16'b0, led_reg};      // LED register
      4'h4: rdata = {16'b0, gpio_in};      // Switch input
      4'h8: rdata = seg_reg;               // 7-segment register
      default: rdata = 32'b0;
    endcase
  end
  assign in_prdata = rdata;
  
  // Write logic
  wire wr_en = in_psel && in_penable && in_pwrite;
  
  always @(posedge clock) begin
    if (reset) begin
      led_reg <= 16'b0;
      seg_reg <= 32'b0;
    end else if (wr_en) begin
      case (addr)
        4'h0: begin
          // Write to LED register with byte strobes
          if (in_pstrb[0]) led_reg[7:0]  <= in_pwdata[7:0];
          if (in_pstrb[1]) led_reg[15:8] <= in_pwdata[15:8];
        end
        4'h8: begin
          // Write to 7-segment register with byte strobes
          if (in_pstrb[0]) seg_reg[7:0]   <= in_pwdata[7:0];
          if (in_pstrb[1]) seg_reg[15:8]  <= in_pwdata[15:8];
          if (in_pstrb[2]) seg_reg[23:16] <= in_pwdata[23:16];
          if (in_pstrb[3]) seg_reg[31:24] <= in_pwdata[31:24];
        end
        default: ;
      endcase
    end
  end
  
  // Output assignments
  assign gpio_out = led_reg;
  
  // 7-segment decoder: convert 4-bit value to 8-bit segment pattern
  // NVBoard format: seg[7:0] = {A, B, C, D, E, F, G, DP}
  // Active high encoding (will be inverted for common anode display)
  function [7:0] seg_decode;
    input [3:0] val;
    begin
      case (val)
        //                    ABCDEFG.
        4'h0: seg_decode = 8'b11111100; // 0: A,B,C,D,E,F on
        4'h1: seg_decode = 8'b01100000; // 1: B,C on
        4'h2: seg_decode = 8'b11011010; // 2: A,B,D,E,G on
        4'h3: seg_decode = 8'b11110010; // 3: A,B,C,D,G on
        4'h4: seg_decode = 8'b01100110; // 4: B,C,F,G on
        4'h5: seg_decode = 8'b10110110; // 5: A,C,D,F,G on
        4'h6: seg_decode = 8'b10111110; // 6: A,C,D,E,F,G on
        4'h7: seg_decode = 8'b11100000; // 7: A,B,C on
        4'h8: seg_decode = 8'b11111110; // 8: all on
        4'h9: seg_decode = 8'b11110110; // 9: A,B,C,D,F,G on
        4'hA: seg_decode = 8'b11101110; // A: A,B,C,E,F,G on
        4'hB: seg_decode = 8'b00111110; // b: C,D,E,F,G on
        4'hC: seg_decode = 8'b10011100; // C: A,D,E,F on
        4'hD: seg_decode = 8'b01111010; // d: B,C,D,E,G on
        4'hE: seg_decode = 8'b10011110; // E: A,D,E,F,G on
        4'hF: seg_decode = 8'b10001110; // F: A,E,F,G on
        default: seg_decode = 8'b00000000;
      endcase
    end
  endfunction
  
  // Assign decoded segment outputs (active low for common anode display)
  assign gpio_seg_0 = ~seg_decode(seg_reg[3:0]);
  assign gpio_seg_1 = ~seg_decode(seg_reg[7:4]);
  assign gpio_seg_2 = ~seg_decode(seg_reg[11:8]);
  assign gpio_seg_3 = ~seg_decode(seg_reg[15:12]);
  assign gpio_seg_4 = ~seg_decode(seg_reg[19:16]);
  assign gpio_seg_5 = ~seg_decode(seg_reg[23:20]);
  assign gpio_seg_6 = ~seg_decode(seg_reg[27:24]);
  assign gpio_seg_7 = ~seg_decode(seg_reg[31:28]);

endmodule
