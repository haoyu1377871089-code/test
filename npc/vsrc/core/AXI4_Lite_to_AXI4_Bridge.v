module AXI4_Lite_to_AXI4_Bridge (
    input clk,
    input rst,

    // AXI4-Lite Slave Interface (Connected to your Arbiter)
    input  [31:0] s_awaddr,
    input         s_awvalid,
    output        s_awready,
    input  [31:0] s_wdata,
    input  [3:0]  s_wstrb,
    input         s_wvalid,
    output        s_wready,
    output [1:0]  s_bresp,
    output        s_bvalid,
    input         s_bready,
    input  [31:0] s_araddr,
    input         s_arvalid,
    output        s_arready,
    output [31:0] s_rdata,
    output [1:0]  s_rresp,
    output        s_rvalid,
    input         s_rready,

    // AXI4 Master Interface (Connected to ysyxSoC)
    // Write Address
    output [3:0]  m_axi_awid,
    output [31:0] m_axi_awaddr,
    output [7:0]  m_axi_awlen,  // Burst length: 0 for single transfer
    output [2:0]  m_axi_awsize, // Burst size: 2 for 4 bytes
    output [1:0]  m_axi_awburst,// Burst type: 01 (INCR)
    output        m_axi_awlock,
    output [3:0]  m_axi_awcache,
    output [2:0]  m_axi_awprot,
    output        m_axi_awvalid,
    input         m_axi_awready,
    // Write Data
    output [31:0] m_axi_wdata,
    output [3:0]  m_axi_wstrb,
    output        m_axi_wlast,  // Always 1 for single transfer
    output        m_axi_wvalid,
    input         m_axi_wready,
    // Write Response
    input  [3:0]  m_axi_bid,
    input  [1:0]  m_axi_bresp,
    input         m_axi_bvalid,
    output        m_axi_bready,
    // Read Address
    output [3:0]  m_axi_arid,
    output [31:0] m_axi_araddr,
    output [7:0]  m_axi_arlen,
    output [2:0]  m_axi_arsize,
    output [1:0]  m_axi_arburst,
    output        m_axi_arlock,
    output [3:0]  m_axi_arcache,
    output [2:0]  m_axi_arprot,
    output        m_axi_arvalid,
    input         m_axi_arready,
    // Read Data
    input  [3:0]  m_axi_rid,
    input  [31:0] m_axi_rdata,
    input  [1:0]  m_axi_rresp,
    input         m_axi_rlast,
    input         m_axi_rvalid,
    output        m_axi_rready
);

    // ------------------------------------------------------
    // Write Address Channel
    // ------------------------------------------------------
    assign m_axi_awid    = 4'b0;
    assign m_axi_awaddr  = s_awaddr;
    assign m_axi_awlen   = 8'b0;       // Single transfer
    assign m_axi_awsize  = 3'b010;     // 4 bytes
    assign m_axi_awburst = 2'b01;      // INCR
    assign m_axi_awlock  = 1'b0;
    assign m_axi_awcache = 4'b0;
    assign m_axi_awprot  = 3'b0;
    assign m_axi_awvalid = s_awvalid;
    assign s_awready     = m_axi_awready;

    // ------------------------------------------------------
    // Write Data Channel
    // ------------------------------------------------------
    assign m_axi_wdata   = s_wdata;
    assign m_axi_wstrb   = s_wstrb;
    assign m_axi_wlast   = 1'b1;       // Always last for single transfer
    assign m_axi_wvalid  = s_wvalid;
    assign s_wready      = m_axi_wready;

    // ------------------------------------------------------
    // Write Response Channel
    // ------------------------------------------------------
    assign s_bresp       = m_axi_bresp;
    assign s_bvalid      = m_axi_bvalid;
    assign m_axi_bready  = s_bready;

    // ------------------------------------------------------
    // Read Address Channel
    // ------------------------------------------------------
    assign m_axi_arid    = 4'b0;
    assign m_axi_araddr  = s_araddr;
    assign m_axi_arlen   = 8'b0;       // Single transfer
    assign m_axi_arsize  = 3'b010;     // 4 bytes
    assign m_axi_arburst = 2'b01;      // INCR
    assign m_axi_arlock  = 1'b0;
    assign m_axi_arcache = 4'b0;
    assign m_axi_arprot  = 3'b0;
    assign m_axi_arvalid = s_arvalid;
    assign s_arready     = m_axi_arready;

    // ------------------------------------------------------
    // Read Data Channel
    // ------------------------------------------------------
    assign s_rdata       = m_axi_rdata;
    assign s_rresp       = m_axi_rresp;
    assign s_rvalid      = m_axi_rvalid;
    assign m_axi_rready  = s_rready;

endmodule
