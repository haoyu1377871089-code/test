`include "axi4_lite_interface.vh"

module AXI4_Lite_Arbiter (
    input clk,
    input rst,
    
    // Master 0: IFU接口
    input [31:0]  m0_awaddr,
    input         m0_awvalid,
    output reg    m0_awready,
    
    input [31:0]  m0_wdata,
    input [3:0]   m0_wstrb,
    input         m0_wvalid,
    output reg    m0_wready,
    
    output reg [1:0]  m0_bresp,
    output reg        m0_bvalid,
    input         m0_bready,
    
    input [31:0]  m0_araddr,
    input         m0_arvalid,
    output reg    m0_arready,
    
    output reg [31:0] m0_rdata,
    output reg [1:0]  m0_rresp,
    output reg        m0_rvalid,
    input         m0_rready,
    
    // Master 1: LSU接口
    input [31:0]  m1_awaddr,
    input         m1_awvalid,
    output reg    m1_awready,
    
    input [31:0]  m1_wdata,
    input [3:0]   m1_wstrb,
    input         m1_wvalid,
    output reg    m1_wready,
    
    output reg [1:0]  m1_bresp,
    output reg        m1_bvalid,
    input         m1_bready,
    
    input [31:0]  m1_araddr,
    input         m1_arvalid,
    output reg    m1_arready,
    
    output reg [31:0] m1_rdata,
    output reg [1:0]  m1_rresp,
    output reg        m1_rvalid,
    input         m1_rready,
    
    // Slave: SRAM接口
    output reg [31:0] s_awaddr,
    output reg        s_awvalid,
    input             s_awready,
    
    output reg [31:0] s_wdata,
    output reg [3:0]  s_wstrb,
    output reg        s_wvalid,
    input             s_wready,
    
    input [1:0]       s_bresp,
    input             s_bvalid,
    output reg        s_bready,
    
    output reg [31:0] s_araddr,
    output reg        s_arvalid,
    input             s_arready,
    
    input [31:0]      s_rdata,
    input [1:0]       s_rresp,
    input             s_rvalid,
    output reg        s_rready
);

// 仲裁器状态定义
localparam ARB_IDLE   = 2'b00;
localparam ARB_IFU    = 2'b01;  // IFU获得总线
localparam ARB_LSU    = 2'b10;  // LSU获得总线

reg [1:0] arb_state, arb_state_next;
reg [1:0] granted_master;  // 当前获得总线使用权的master

// 请求信号
wire ifu_req = m0_arvalid || m0_awvalid;  // IFU请求（读或写）
wire lsu_req = m1_arvalid || m1_awvalid;  // LSU请求（读或写）

// 状态机：仲裁逻辑
always @(*) begin
    arb_state_next = arb_state;
    granted_master = 2'b00;
    
    case (arb_state)
        ARB_IDLE: begin
            // 空闲状态：根据优先级选择master
            if (ifu_req && lsu_req) begin
                // 两者都有请求，IFU优先（指令获取通常更紧急）
                arb_state_next = ARB_IFU;
                granted_master = 2'b00;
            end else if (ifu_req) begin
                arb_state_next = ARB_IFU;
                granted_master = 2'b00;
            end else if (lsu_req) begin
                arb_state_next = ARB_LSU;
                granted_master = 2'b01;
            end else begin
                arb_state_next = ARB_IDLE;
                granted_master = 2'b00;
            end
        end
        
        ARB_IFU: begin
            // IFU获得总线使用权
            granted_master = 2'b00;
            // 检查当前事务是否完成
            // 注意：必须等待整个事务完成（数据/响应握手），不能只看地址握手
            if ((m0_rvalid && m0_rready) ||    // 读数据通道完成
                (m0_bvalid && m0_bready)) begin // 写响应通道完成
                // IFU事务完成，返回空闲状态
                arb_state_next = ARB_IDLE;
            end else begin
                // 保持IFU状态
                arb_state_next = ARB_IFU;
            end
        end
        
        ARB_LSU: begin
            // LSU获得总线使用权
            granted_master = 2'b01;
            // 检查当前事务是否完成
            // 注意：必须等待整个事务完成（数据/响应握手），不能只看地址握手
            if ((m1_rvalid && m1_rready) ||    // 读数据通道完成
                (m1_bvalid && m1_bready)) begin // 写响应完成
                // LSU事务完成，返回空闲状态
                arb_state_next = ARB_IDLE;
            end else begin
                // 保持LSU状态
                arb_state_next = ARB_LSU;
            end
        end
        
        default: begin
            arb_state_next = ARB_IDLE;
            granted_master = 2'b00;
        end
    endcase
end

// 状态寄存器
always @(posedge clk or posedge rst) begin
    if (rst) begin
        arb_state <= ARB_IDLE;
    end else begin
        arb_state <= arb_state_next;
    end
end

// 输出信号初始化（组合逻辑）
always @(*) begin
    // 默认所有ready信号为0（阻塞）
    m0_awready = 1'b0;
    m0_wready = 1'b0;
    m0_bvalid = 1'b0;
    m0_arready = 1'b0;
    m0_rvalid = 1'b0;
    m0_bresp = `AXI4_RESP_OKAY;
    m0_rresp = `AXI4_RESP_OKAY;
    m0_rdata = 32'h0;
    
    m1_awready = 1'b0;
    m1_wready = 1'b0;
    m1_bvalid = 1'b0;
    m1_arready = 1'b0;
    m1_rvalid = 1'b0;
    m1_bresp = `AXI4_RESP_OKAY;
    m1_rresp = `AXI4_RESP_OKAY;
    m1_rdata = 32'h0;
    
    // 默认slave输入为0
    s_awaddr = 32'h0;
    s_awvalid = 1'b0;
    s_wdata = 32'h0;
    s_wstrb = 4'h0;
    s_wvalid = 1'b0;
    s_bready = 1'b0;
    s_araddr = 32'h0;
    s_arvalid = 1'b0;
    s_rready = 1'b0;
    
    case (granted_master)
        2'b00: begin  // IFU获得总线
            // 将IFU信号连接到slave
            s_awaddr = m0_awaddr;
            s_awvalid = m0_awvalid;
            s_wdata = m0_wdata;
            s_wstrb = m0_wstrb;
            s_wvalid = m0_wvalid;
            s_bready = m0_bready;
            s_araddr = m0_araddr;
            s_arvalid = m0_arvalid;
            s_rready = m0_rready;
            
            // 将slave响应传回IFU
            m0_awready = s_awready;
            m0_wready = s_wready;
            m0_bvalid = s_bvalid;
            m0_bresp = s_bresp;
            m0_arready = s_arready;
            m0_rvalid = s_rvalid;
            m0_rresp = s_rresp;
            m0_rdata = s_rdata;
        end
        
        2'b01: begin  // LSU获得总线
            // 将LSU信号连接到slave
            s_awaddr = m1_awaddr;
            s_awvalid = m1_awvalid;
            s_wdata = m1_wdata;
            s_wstrb = m1_wstrb;
            s_wvalid = m1_wvalid;
            s_bready = m1_bready;
            s_araddr = m1_araddr;
            s_arvalid = m1_arvalid;
            s_rready = m1_rready;
            
            // 将slave响应传回LSU
            m1_awready = s_awready;
            m1_wready = s_wready;
            m1_bvalid = s_bvalid;
            m1_bresp = s_bresp;
            m1_arready = s_arready;
            m1_rvalid = s_rvalid;
            m1_rresp = s_rresp;
            m1_rdata = s_rdata;
        end
        
        default: begin
            // 保持默认阻塞状态
        end
    endcase
end

// ========== Debug Output (simulation only) - Disabled for performance ==========
// Debug warnings are disabled by default. Uncomment if needed for debugging.

endmodule