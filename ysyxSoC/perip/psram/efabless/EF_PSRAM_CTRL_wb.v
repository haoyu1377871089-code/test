/*
	Copyright 2020 Efabless Corp.

	Author: Mohamed Shalan (mshalan@efabless.com)
	
	Modified: 2024 - Added Read-Modify-Write support for partial writes

	Licensed under the Apache License, Version 2.0 (the "License");
	you may not use this file except in compliance with the License.
	You may obtain a copy of the License at:
	http://www.apache.org/licenses/LICENSE-2.0
	Unless required by applicable law or agreed to in writing, software
	distributed under the License is distributed on an "AS IS" BASIS,
	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
	See the License for the specific language governing permissions and
	limitations under the License.
*/

`timescale              1ns/1ps
`default_nettype        none

// Using EBH Command - with Read-Modify-Write support for partial writes
module EF_PSRAM_CTRL_wb (
    // WB bus Interface
    input   wire        clk_i,
    input   wire        rst_i,
    input   wire [31:0] adr_i,
    input   wire [31:0] dat_i,
    output  wire [31:0] dat_o,
    input   wire [3:0]  sel_i,
    input   wire        cyc_i,
    input   wire        stb_i,
    output  wire        ack_o,
    input   wire        we_i,

    // External Interface to Quad I/O
    output  wire            sck,
    output  wire            ce_n,
    input   wire [3:0]      din,
    output  wire [3:0]      dout,
    output  wire [3:0]      douten
);

    // 状态机状态
    localparam  ST_INIT      = 3'b000,    // QPI初始化状态
                ST_IDLE      = 3'b001,    // 空闲状态
                ST_READ      = 3'b010,    // 读取状态
                ST_RMW_READ  = 3'b011,    // RMW: 读取阶段
                ST_RMW_WRITE = 3'b100,    // RMW: 写入阶段
                ST_WRITE     = 3'b101;    // 完整写入状态

    // QPI初始化模块信号
    wire        init_start;
    wire        init_done;
    wire        qpi_mode;
    wire        init_sck;
    wire        init_ce_n;
    wire [3:0]  init_dout;
    wire        init_douten;

    wire        mr_sck;
    wire        mr_ce_n;
    wire [3:0]  mr_din;
    wire [3:0]  mr_dout;
    wire        mr_doe;

    wire        mw_sck;
    wire        mw_ce_n;
    wire [3:0]  mw_din;
    wire [3:0]  mw_dout;
    wire        mw_doe;

    // PSRAM Reader and Writer wires
    wire        mr_rd;
    wire        mr_done;
    wire        mw_wr;
    wire        mw_done;

    // WB Control Signals
    wire        wb_valid        =   cyc_i & stb_i;
    wire        wb_we           =   we_i & wb_valid;
    wire        wb_re           =   ~we_i & wb_valid;
    
    // 检测是否需要RMW（部分写入）
    wire        need_rmw        =   wb_we && (sel_i != 4'b1111);
    wire        full_write      =   wb_we && (sel_i == 4'b1111);

    // 寄存器保存请求信息（用于RMW）
    reg  [31:0] saved_addr;
    reg  [31:0] saved_data;
    reg  [3:0]  saved_sel;
    reg  [31:0] read_data;      // RMW读取的数据（保存的）
    
    // RMW合并后的写入数据：
    // 在 ST_RMW_READ 状态且 mr_done 时，使用 dat_o（当前读取结果）
    // 在 ST_RMW_WRITE 状态时，使用 read_data（已保存的读取结果）
    wire [31:0] rmw_read_src = (state == ST_RMW_READ && mr_done) ? dat_o : read_data;
    wire [31:0] rmw_wdata;
    assign rmw_wdata[7:0]   = saved_sel[0] ? saved_data[7:0]   : rmw_read_src[7:0];
    assign rmw_wdata[15:8]  = saved_sel[1] ? saved_data[15:8]  : rmw_read_src[15:8];
    assign rmw_wdata[23:16] = saved_sel[2] ? saved_data[23:16] : rmw_read_src[23:16];
    assign rmw_wdata[31:24] = saved_sel[3] ? saved_data[31:24] : rmw_read_src[31:24];

    // The FSM
    reg  [2:0]  state, nstate;
    always @ (posedge clk_i or posedge rst_i)
        if(rst_i)
            state <= ST_INIT;
        else
            state <= nstate;

    // 启动初始化信号
    assign init_start = (state == ST_INIT) && !init_done;
    
    // 保存请求信息（在 ST_IDLE 时保存，用于后续 RMW）
    always @ (posedge clk_i or posedge rst_i)
        if (rst_i) begin
            saved_addr <= 32'b0;
            saved_data <= 32'b0;
            saved_sel  <= 4'b0;
        end else if (state == ST_IDLE && wb_valid) begin
            saved_addr <= adr_i;
            saved_data <= dat_i;
            saved_sel  <= sel_i;
        end
    
    // 保存读取的数据（用于RMW，在读取完成时保存）
    always @ (posedge clk_i or posedge rst_i)
        if (rst_i)
            read_data <= 32'b0;
        else if (state == ST_RMW_READ && mr_done)
            read_data <= dat_o;

    // 状态转换逻辑
    always @* begin
        case(state)
            ST_INIT :
                if(init_done)
                    nstate = ST_IDLE;
                else
                    nstate = ST_INIT;
                    
            ST_IDLE :
                if(wb_re)
                    nstate = ST_READ;
                else if(need_rmw)
                    nstate = ST_RMW_READ;   // 部分写入：先读
                else if(full_write)
                    nstate = ST_WRITE;      // 完整写入：直接写
                else
                    nstate = ST_IDLE;

            ST_READ :
                if(mr_done)
                    nstate = ST_IDLE;
                else
                    nstate = ST_READ;

            ST_WRITE :
                if(mw_done)
                    nstate = ST_IDLE;
                else
                    nstate = ST_WRITE;
                    
            ST_RMW_READ :
                if(mr_done)
                    nstate = ST_RMW_WRITE;  // 读完后进入写阶段
                else
                    nstate = ST_RMW_READ;
                    
            ST_RMW_WRITE :
                if(mw_done)
                    nstate = ST_IDLE;
                else
                    nstate = ST_RMW_WRITE;
                    
            default: nstate = ST_INIT;
        endcase
    end

    // Reader控制信号：只在 ST_IDLE 时启动
    assign mr_rd = (state == ST_IDLE) && (wb_re || need_rmw);
    
    // Writer控制信号：
    // - 完整写入：在 ST_IDLE 时启动
    // - RMW写入：在 ST_RMW_READ 读取完成时启动
    assign mw_wr = ((state == ST_IDLE) && full_write) ||
                   ((state == ST_RMW_READ) && mr_done);
    
    // 写入数据选择：
    // - 完整写入：直接使用 dat_i
    // - RMW写入：使用合并后的 rmw_wdata
    wire [31:0] final_wdata = (state == ST_RMW_READ || state == ST_RMW_WRITE) 
                              ? rmw_wdata : dat_i;

    // QPI初始化模块
    PSRAM_QPI_INIT INIT (
        .clk(clk_i),
        .rst_n(~rst_i),
        .start(init_start),
        .done(init_done),
        .qpi_mode(qpi_mode),
        .sck(init_sck),
        .ce_n(init_ce_n),
        .dout(init_dout),
        .douten(init_douten)
    );

    // 读取地址：总是对齐到4字节边界
    // - 普通读取/RMW读取：使用当前地址或保存的地址
    wire [31:0] read_addr = (state == ST_RMW_READ) 
                            ? {saved_addr[31:2], 2'b0} 
                            : {adr_i[31:2], 2'b0};
    
    PSRAM_READER MR (
        .clk(clk_i),
        .rst_n(~rst_i),
        .addr(read_addr[23:0]),
        .rd(mr_rd),
        .size(3'd4),    // Always read a word
        .qpi_mode(qpi_mode),
        .done(mr_done),
        .line(dat_o),
        .sck(mr_sck),
        .ce_n(mr_ce_n),
        .din(mr_din),
        .dout(mr_dout),
        .douten(mr_doe)
    );

    // 写入地址：
    // - 完整写入：直接使用 adr_i
    // - RMW写入：使用保存的 saved_addr
    wire [31:0] write_addr = (state == ST_RMW_READ || state == ST_RMW_WRITE)
                             ? {saved_addr[31:2], 2'b0}
                             : {adr_i[31:2], 2'b0};
    
    PSRAM_WRITER MW (
        .clk(clk_i),
        .rst_n(~rst_i),
        .addr(write_addr[23:0]),
        .wr(mw_wr),
        .size(3'd4),    // Always write a word
        .qpi_mode(qpi_mode),
        .done(mw_done),
        .line(final_wdata),
        .sck(mw_sck),
        .ce_n(mw_ce_n),
        .din(mw_din),
        .dout(mw_dout),
        .douten(mw_doe)
    );

    // 根据状态选择输出信号
    wire is_writing = (state == ST_WRITE) || (state == ST_RMW_WRITE) ||
                      ((state == ST_IDLE) && full_write) ||
                      ((state == ST_RMW_READ) && mr_done);
    
    assign sck  = (state == ST_INIT) ? init_sck :
                  is_writing ? mw_sck : mr_sck;
    assign ce_n = (state == ST_INIT) ? init_ce_n :
                  is_writing ? mw_ce_n : mr_ce_n;
    assign dout = (state == ST_INIT) ? init_dout :
                  is_writing ? mw_dout : mr_dout;
    assign douten = (state == ST_INIT) ? {4{init_douten}} :
                    is_writing ? {4{mw_doe}} : {4{mr_doe}};

    assign mw_din = din;
    assign mr_din = din;
    
    // ACK信号：读取完成或写入完成
    assign ack_o = (state == ST_READ && mr_done) ||
                   (state == ST_WRITE && mw_done) ||
                   (state == ST_RMW_WRITE && mw_done);
endmodule
