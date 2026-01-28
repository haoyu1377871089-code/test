// AXI4 Delayer Module with Timing Calibration
//
// This module implements timing calibration for AXI4 transactions between
// different clock domains (CPU and memory device).
//
// Calibration Principle:
//   Let CPU frequency = f_cpu, Device frequency = f_dev
//   Frequency ratio r = f_cpu / f_dev
//
//   For read transaction beat i:
//   - Device returns at time t_i (relative to transaction start t_0)
//   - CPU perceives at time t_i' = t_0 + (t_i - t_0) * r
//
// Parameters:
//   R_TIMES_S: r * s, where s = 2^S_SHIFT (fixed-point representation)
//   S_SHIFT:   Shift amount for fixed-point (s = 256 by default)
//   MAX_BURST: Maximum burst length supported
//
// When R_TIMES_S = S_SHIFT (i.e., r = 1), the module acts as pass-through

module axi4_delayer #(
    parameter R_TIMES_S = 256,    // r * s, default r=1.0 (pass-through)
    parameter S_SHIFT   = 8,      // s = 256 (fixed-point scaling)
    parameter MAX_BURST = 8       // Maximum burst length
)(
    input         clock,
    input         reset,

    // ============================================================
    // Upstream Interface (to CPU)
    // ============================================================
    // Read Address Channel
    output reg    in_arready,
    input         in_arvalid,
    input  [3:0]  in_arid,
    input  [31:0] in_araddr,
    input  [7:0]  in_arlen,
    input  [2:0]  in_arsize,
    input  [1:0]  in_arburst,
    input         in_arlock,
    input  [3:0]  in_arcache,
    input  [2:0]  in_arprot,
    
    // Read Data Channel
    input         in_rready,
    output reg    in_rvalid,
    output [3:0]  in_rid,
    output [31:0] in_rdata,
    output [1:0]  in_rresp,
    output        in_rlast,
    
    // Write Address Channel
    output reg    in_awready,
    input         in_awvalid,
    input  [3:0]  in_awid,
    input  [31:0] in_awaddr,
    input  [7:0]  in_awlen,
    input  [2:0]  in_awsize,
    input  [1:0]  in_awburst,
    input         in_awlock,
    input  [3:0]  in_awcache,
    input  [2:0]  in_awprot,
    
    // Write Data Channel
    output reg    in_wready,
    input         in_wvalid,
    input  [31:0] in_wdata,
    input  [3:0]  in_wstrb,
    input         in_wlast,
    
    // Write Response Channel
    input         in_bready,
    output reg    in_bvalid,
    output [3:0]  in_bid,
    output [1:0]  in_bresp,

    // ============================================================
    // Downstream Interface (to Device)
    // ============================================================
    // Read Address Channel
    input         out_arready,
    output reg    out_arvalid,
    output [3:0]  out_arid,
    output [31:0] out_araddr,
    output [7:0]  out_arlen,
    output [2:0]  out_arsize,
    output [1:0]  out_arburst,
    output        out_arlock,
    output [3:0]  out_arcache,
    output [2:0]  out_arprot,
    
    // Read Data Channel
    output reg    out_rready,
    input         out_rvalid,
    input  [3:0]  out_rid,
    input  [31:0] out_rdata,
    input  [1:0]  out_rresp,
    input         out_rlast,
    
    // Write Address Channel
    input         out_awready,
    output reg    out_awvalid,
    output [3:0]  out_awid,
    output [31:0] out_awaddr,
    output [7:0]  out_awlen,
    output [2:0]  out_awsize,
    output [1:0]  out_awburst,
    output        out_awlock,
    output [3:0]  out_awcache,
    output [2:0]  out_awprot,
    
    // Write Data Channel
    input         out_wready,
    output reg    out_wvalid,
    output [31:0] out_wdata,
    output [3:0]  out_wstrb,
    output        out_wlast,
    
    // Write Response Channel
    output reg    out_bready,
    input         out_bvalid,
    input  [3:0]  out_bid,
    input  [1:0]  out_bresp
);

// ============================================================
// Read Channel Delay Processing
// ============================================================
localparam R_IDLE      = 2'd0;
localparam R_WAIT_DEV  = 2'd1;  // Waiting for device response
localparam R_DELAY     = 2'd2;  // Delay countdown

reg [1:0] r_state;

// Transaction information saved
reg [3:0]  saved_arid;
reg [31:0] saved_araddr;
reg [7:0]  saved_arlen;
reg [2:0]  saved_arsize;
reg [1:0]  saved_arburst;
reg        saved_arlock;
reg [3:0]  saved_arcache;
reg [2:0]  saved_arprot;

// Per-beat information buffer
reg [31:0] beat_data   [0:MAX_BURST-1];
reg [1:0]  beat_resp   [0:MAX_BURST-1];
reg        beat_last   [0:MAX_BURST-1];
reg [31:0] beat_target [0:MAX_BURST-1];  // Target delay time (CPU cycles)

reg [2:0]  beat_recv_cnt;   // Beats received (3-bit for MAX_BURST=8)
reg [2:0]  beat_send_cnt;   // Beats sent (3-bit for MAX_BURST=8)
reg [31:0] dev_cycle_cnt;   // Device cycle counter
reg [31:0] cpu_cycle_cnt;   // CPU cycle counter

// Pass-through signals for read address
assign out_arid    = saved_arid;
assign out_araddr  = saved_araddr;
assign out_arlen   = saved_arlen;
assign out_arsize  = saved_arsize;
assign out_arburst = saved_arburst;
assign out_arlock  = saved_arlock;
assign out_arcache = saved_arcache;
assign out_arprot  = saved_arprot;

// Output read data from buffer
assign in_rid   = saved_arid;
assign in_rdata = beat_data[beat_send_cnt];
assign in_rresp = beat_resp[beat_send_cnt];
assign in_rlast = beat_last[beat_send_cnt];

// Delay calculation function
// target_cpu_time = dev_time * r = dev_time * R_TIMES_S / s
function [31:0] calc_delay;
    input [31:0] dev_time;
    begin
        calc_delay = (dev_time * R_TIMES_S) >> S_SHIFT;
    end
endfunction

// Read Channel State Machine
integer ri;
always @(posedge clock or posedge reset) begin
    if (reset) begin
        r_state <= R_IDLE;
        in_arready <= 1'b1;
        out_arvalid <= 1'b0;
        out_rready <= 1'b0;
        in_rvalid <= 1'b0;
        beat_recv_cnt <= 3'd0;
        beat_send_cnt <= 3'd0;
        dev_cycle_cnt <= 32'd0;
        cpu_cycle_cnt <= 32'd0;
        saved_arid <= 4'b0;
        saved_araddr <= 32'b0;
        saved_arlen <= 8'b0;
        saved_arsize <= 3'b0;
        saved_arburst <= 2'b0;
        saved_arlock <= 1'b0;
        saved_arcache <= 4'b0;
        saved_arprot <= 3'b0;
        
        for (ri = 0; ri < MAX_BURST; ri = ri + 1) begin
            beat_data[ri] = 32'b0;
            beat_resp[ri] = 2'b0;
            beat_last[ri] = 1'b0;
            beat_target[ri] = 32'b0;
        end
    end else begin
        case (r_state)
            R_IDLE: begin
                in_rvalid <= 1'b0;
                if (in_arvalid && in_arready) begin
                    // Accept AR request
                    saved_arid    <= in_arid;
                    saved_araddr  <= in_araddr;
                    saved_arlen   <= in_arlen;
                    saved_arsize  <= in_arsize;
                    saved_arburst <= in_arburst;
                    saved_arlock  <= in_arlock;
                    saved_arcache <= in_arcache;
                    saved_arprot  <= in_arprot;
                    
                    in_arready <= 1'b0;
                    out_arvalid <= 1'b1;
                    
                    beat_recv_cnt <= 3'd0;
                    beat_send_cnt <= 3'd0;
                    dev_cycle_cnt <= 32'd1;  // Start counting from AR valid
                    cpu_cycle_cnt <= 32'd1;
                    
                    r_state <= R_WAIT_DEV;
                end
            end
            
            R_WAIT_DEV: begin
                // AR channel handshake
                if (out_arvalid && out_arready) begin
                    out_arvalid <= 1'b0;
                    out_rready <= 1'b1;
                end
                
                // Device cycle counter
                dev_cycle_cnt <= dev_cycle_cnt + 1;
                cpu_cycle_cnt <= cpu_cycle_cnt + 1;
                
                // Receive data from device
                if (out_rvalid && out_rready) begin
                    beat_data[beat_recv_cnt] <= out_rdata;
                    beat_resp[beat_recv_cnt] <= out_rresp;
                    beat_last[beat_recv_cnt] <= out_rlast;
                    beat_target[beat_recv_cnt] <= calc_delay(dev_cycle_cnt);
                    beat_recv_cnt <= beat_recv_cnt + 1;
                    
                    if (out_rlast) begin
                        out_rready <= 1'b0;
                        // Start returning data to CPU
                        r_state <= R_DELAY;
                    end
                end
            end
            
            R_DELAY: begin
                cpu_cycle_cnt <= cpu_cycle_cnt + 1;
                
                // Check if target time reached
                if (cpu_cycle_cnt >= beat_target[beat_send_cnt]) begin
                    if (!in_rvalid || in_rready) begin
                        in_rvalid <= 1'b1;
                        
                        if (in_rready && in_rvalid) begin
                            // Handshake complete
                            if (beat_last[beat_send_cnt]) begin
                                // Transaction complete
                                in_rvalid <= 1'b0;
                                in_arready <= 1'b1;
                                r_state <= R_IDLE;
                            end else begin
                                beat_send_cnt <= beat_send_cnt + 1;
                            end
                        end
                    end
                end
            end
            
            default: r_state <= R_IDLE;
        endcase
    end
end

// ============================================================
// Write Channel Delay Processing
// ============================================================
localparam W_IDLE      = 2'd0;
localparam W_ADDR      = 2'd1;  // Write address phase
localparam W_DATA      = 2'd2;  // Write data phase
localparam W_RESP      = 2'd3;  // Write response phase

reg [1:0] w_state;

// Write transaction saved info
reg [3:0]  saved_awid;
reg [31:0] saved_awaddr;
reg [7:0]  saved_awlen;
reg [2:0]  saved_awsize;
reg [1:0]  saved_awburst;
reg        saved_awlock;
reg [3:0]  saved_awcache;
reg [2:0]  saved_awprot;
reg [31:0] saved_wdata;
reg [3:0]  saved_wstrb;
reg        saved_wlast;
reg [3:0]  saved_bid;
reg [1:0]  saved_bresp;

reg [31:0] w_dev_cycle_cnt;
reg [31:0] w_cpu_cycle_cnt;
reg [31:0] w_target_time;

// Pass-through signals for write address
assign out_awid    = saved_awid;
assign out_awaddr  = saved_awaddr;
assign out_awlen   = saved_awlen;
assign out_awsize  = saved_awsize;
assign out_awburst = saved_awburst;
assign out_awlock  = saved_awlock;
assign out_awcache = saved_awcache;
assign out_awprot  = saved_awprot;

// Pass-through signals for write data
assign out_wdata = saved_wdata;
assign out_wstrb = saved_wstrb;
assign out_wlast = saved_wlast;

// Output write response
assign in_bid   = saved_bid;
assign in_bresp = saved_bresp;

// Write Channel State Machine
always @(posedge clock or posedge reset) begin
    if (reset) begin
        w_state <= W_IDLE;
        in_awready <= 1'b1;
        in_wready <= 1'b0;
        out_awvalid <= 1'b0;
        out_wvalid <= 1'b0;
        out_bready <= 1'b0;
        in_bvalid <= 1'b0;
        saved_awid <= 4'b0;
        saved_awaddr <= 32'b0;
        saved_awlen <= 8'b0;
        saved_awsize <= 3'b0;
        saved_awburst <= 2'b0;
        saved_awlock <= 1'b0;
        saved_awcache <= 4'b0;
        saved_awprot <= 3'b0;
        saved_wdata <= 32'b0;
        saved_wstrb <= 4'b0;
        saved_wlast <= 1'b0;
        saved_bid <= 4'b0;
        saved_bresp <= 2'b0;
        w_dev_cycle_cnt <= 32'd0;
        w_cpu_cycle_cnt <= 32'd0;
        w_target_time <= 32'd0;
    end else begin
        case (w_state)
            W_IDLE: begin
                in_bvalid <= 1'b0;
                if (in_awvalid && in_awready) begin
                    // Accept AW request
                    saved_awid    <= in_awid;
                    saved_awaddr  <= in_awaddr;
                    saved_awlen   <= in_awlen;
                    saved_awsize  <= in_awsize;
                    saved_awburst <= in_awburst;
                    saved_awlock  <= in_awlock;
                    saved_awcache <= in_awcache;
                    saved_awprot  <= in_awprot;
                    
                    in_awready <= 1'b0;
                    in_wready <= 1'b1;
                    
                    w_dev_cycle_cnt <= 32'd1;
                    w_cpu_cycle_cnt <= 32'd1;
                    
                    w_state <= W_ADDR;
                end
            end
            
            W_ADDR: begin
                w_dev_cycle_cnt <= w_dev_cycle_cnt + 1;
                w_cpu_cycle_cnt <= w_cpu_cycle_cnt + 1;
                
                // Wait for write data
                if (in_wvalid && in_wready) begin
                    saved_wdata <= in_wdata;
                    saved_wstrb <= in_wstrb;
                    saved_wlast <= in_wlast;
                    
                    // Forward to device
                    out_awvalid <= 1'b1;
                    out_wvalid <= 1'b1;
                    in_wready <= 1'b0;
                    
                    w_state <= W_DATA;
                end
            end
            
            W_DATA: begin
                w_dev_cycle_cnt <= w_dev_cycle_cnt + 1;
                w_cpu_cycle_cnt <= w_cpu_cycle_cnt + 1;
                
                // AW handshake
                if (out_awvalid && out_awready) begin
                    out_awvalid <= 1'b0;
                end
                
                // W handshake
                if (out_wvalid && out_wready) begin
                    out_wvalid <= 1'b0;
                end
                
                // Both done, wait for response
                if (!out_awvalid && !out_wvalid) begin
                    out_bready <= 1'b1;
                    w_state <= W_RESP;
                end
            end
            
            W_RESP: begin
                w_dev_cycle_cnt <= w_dev_cycle_cnt + 1;
                w_cpu_cycle_cnt <= w_cpu_cycle_cnt + 1;
                
                if (out_bvalid && out_bready) begin
                    saved_bid <= out_bid;
                    saved_bresp <= out_bresp;
                    out_bready <= 1'b0;
                    
                    // Calculate target time for response
                    w_target_time <= calc_delay(w_dev_cycle_cnt);
                    
                    // For write, we can send response immediately after delay
                    // (simplified: no separate delay state for write response)
                    in_bvalid <= 1'b1;
                end
                
                // Response handshake
                if (in_bvalid && in_bready) begin
                    in_bvalid <= 1'b0;
                    in_awready <= 1'b1;
                    w_state <= W_IDLE;
                end
            end
            
            default: w_state <= W_IDLE;
        endcase
    end
end

endmodule
