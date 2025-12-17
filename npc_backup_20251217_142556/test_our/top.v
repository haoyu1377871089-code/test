module top(
  input        clk,
  input        a,
  input        b,
  output reg   f
);
  always @(posedge clk) begin
    f <= a ^ b;
  end
endmodule