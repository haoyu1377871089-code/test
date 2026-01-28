`timescale 1ns / 10ps

// Refer to the data sheet for the flash instructions at
// https://www.winbond.com/hq/product/code-storage-flash-memory/serial-nor-flash/?__locale=zh
//
// Supported commands:
// - 03h: Read Data (standard SPI read)
// - 05h: Read Status Register-1
// - 35h: Read Status Register-2
// - 70h: Read Flag Status Register (Micron) - returns ready status
// - 9Fh: Read JEDEC ID
// - ABh: Release Power-down / Device ID

module flash (
  input  sck,
  input  ss,
  input  mosi,
  output miso
);
  wire reset = ss;

  // States: cmd, addr, data, status (for status register reads), err
  typedef enum [2:0] { cmd_t, addr_t, data_t, status_t, err_t } state_t;
  reg [2:0]  state;
  reg [7:0]  counter;
  reg [7:0]  cmd;
  reg [23:0] addr;
  reg [31:0] data;
  reg [7:0]  status_reg;  // Status register for status commands

  wire ren = (state == addr_t) && (counter == 8'd23);
  wire [31:0] rdata;
  wire [31:0] raddr = {8'b0, addr[22:0], mosi};
  flash_cmd flash_cmd_i(
    .clock(sck),
    .valid(ren),
    .cmd(cmd),
    .addr(raddr),
    .data(rdata)
  );

  // Full command byte (when counter == 7, cmd[6:0] contains bits 7-1, mosi contains bit 0)
  wire [7:0] cmd_full = {cmd[6:0], mosi};
  
  // Command decode using full command byte
  wire cmd_is_read     = (cmd_full == 8'h03);  // Read Data
  wire cmd_is_status   = (cmd_full == 8'h05) || (cmd_full == 8'h35) || (cmd_full == 8'h70);  // Status register reads
  wire cmd_is_jedec_id = (cmd_full == 8'h9F);  // Read JEDEC ID
  wire cmd_is_release  = (cmd_full == 8'hAB);  // Release Power-down
  wire cmd_is_valid    = cmd_is_read || cmd_is_status || cmd_is_jedec_id || cmd_is_release;

  always@(posedge sck or posedge reset) begin
    if (reset) state <= cmd_t;
    else begin
      case (state)
        cmd_t: begin
          if (counter == 8'd7) begin
            // After receiving command byte, decide next state
            if (cmd_is_read)
              state <= addr_t;
            else if (cmd_is_status || cmd_is_jedec_id || cmd_is_release)
              state <= status_t;
            else
              state <= err_t;
          end
        end
        addr_t: state <= (counter == 8'd23) ? data_t : state;
        data_t: state <= state;
        status_t: state <= state;  // Stay in status state until CS goes high

        default: begin
          state <= state;
          $fwrite(32'h80000002, "Assertion failed: Unsupported command `%xh`\n", cmd);
          $fatal;
        end
      endcase
    end
  end

  always@(posedge sck or posedge reset) begin
    if (reset) counter <= 8'd0;
    else begin
      case (state)
        cmd_t:    counter <= (counter < 8'd7 ) ? counter + 8'd1 : 8'd0;
        addr_t:   counter <= (counter < 8'd23) ? counter + 8'd1 : 8'd0;
        status_t: counter <= counter + 8'd1;  // Keep counting for status bytes
        default:  counter <= counter + 8'd1;
      endcase
    end
  end

  always@(posedge sck or posedge reset) begin
    if (reset)               cmd <= 8'd0;
    else if (state == cmd_t) cmd <= { cmd[6:0], mosi };
  end

  always@(posedge sck or posedge reset) begin
    if (reset) addr <= 24'd0;
    else if (state == addr_t && counter < 8'd23)
      addr <= { addr[22:0], mosi };
  end

  // Status register initialization based on command
  always@(posedge sck or posedge reset) begin
    if (reset) begin
      status_reg <= 8'h00;
    end else if (state == cmd_t && counter == 8'd7) begin
      case ({cmd[6:0], mosi})  // Full command byte
        8'h05: status_reg <= 8'h00;  // Status Register-1: not busy, write disabled
        8'h35: status_reg <= 8'h00;  // Status Register-2
        8'h70: status_reg <= 8'h80;  // Flag Status Register: ready (bit 7 = 1)
        8'h9F: status_reg <= 8'hEF;  // JEDEC ID first byte (Winbond)
        8'hAB: status_reg <= 8'h17;  // Device ID
        default: status_reg <= 8'h00;
      endcase
    end else if (state == status_t) begin
      // Shift out status register bits
      status_reg <= {status_reg[6:0], 1'b0};
    end
  end

  wire [31:0] data_bswap = {rdata[7:0], rdata[15:8], rdata[23:16], rdata[31:24]};
  always@(posedge sck or posedge reset) begin
    if (reset) data <= 32'd0;
    else if (state == data_t) begin
      data <= { {counter == 8'd0 ? data_bswap : data}[30:0], 1'b0 };
    end
  end

  // MISO output multiplexer
  reg miso_out;
  always @(*) begin
    if (ss) begin
      miso_out = 1'b1;
    end else if (state == status_t) begin
      miso_out = status_reg[7];  // Output MSB of status register
    end else if (state == data_t) begin
      miso_out = (counter == 8'd0) ? data_bswap[31] : data[31];
    end else begin
      miso_out = 1'b1;
    end
  end
  assign miso = miso_out;

endmodule

import "DPI-C" function void flash_read(input int addr, output int data);

module flash_cmd(
  input             clock,
  input             valid,
  input       [7:0] cmd,
  input      [31:0] addr,
  output reg [31:0] data
);
  always@(posedge clock) begin
    if (valid)
      if (cmd == 8'h03) flash_read(addr, data);
      else begin
        $fwrite(32'h80000002, "Assertion failed: Unsupport command `%xh`, only support `03h` read command\n", cmd);
        $fatal;
      end
  end
endmodule
