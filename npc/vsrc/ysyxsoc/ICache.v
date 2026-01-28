// I-Cache: Parameterized, 2-way set-associative with burst support
// Default: 4KB, 2-way, 16-byte cache line (4 words per line)
//
// Parameters:
//   - CACHE_SIZE: Total cache size in bytes (default: 4096)
//   - LINE_SIZE:  Cache line size in bytes (default: 16, must be power of 2, >= 4)
//   - NUM_WAYS:   Associativity (default: 2)
//   - ADDR_WIDTH: Address width (default: 32)
//
// Address breakdown (for 16B line, 4KB cache, 2-way):
//   Tag[31:9] Index[8:4] Offset[3:0]
//   - Offset: selects byte within line (4 bits for 16B)
//   - Index:  selects cache set (5 bits for 128 sets = 4KB / 16B / 2)
//   - Tag:    identifies the memory block

module ICache #(
    parameter CACHE_SIZE    = 4096,     // Total cache size (bytes)
    parameter LINE_SIZE     = 16,       // Cache line size (bytes): 4, 8, 16, 32
    parameter NUM_WAYS      = 2,        // Associativity
    parameter ADDR_WIDTH    = 32
) (
    input clk,
    input rst,
    
    // Upstream interface (to CPU/EXU)
    input               cpu_req,        // Fetch request
    input  [31:0]       cpu_addr,       // Fetch address
    input               cpu_flush,      // Flush: cancel current operation
    output reg          cpu_rvalid,     // Data valid
    output reg [31:0]   cpu_rdata,      // Instruction data
    
    // Downstream interface (to memory/IFU_AXI4) - with burst support
    output reg          mem_req,        // Memory read request
    output reg [31:0]   mem_addr,       // Memory address (line-aligned)
    output reg [7:0]    mem_len,        // Burst length (0=1 beat, N-1=N beats)
    input               mem_rvalid,     // Memory data valid
    input      [31:0]   mem_rdata,      // Memory data
    input               mem_rlast       // Last beat of burst
);

// ============================================================
// Derived Parameters
// ============================================================
localparam OFFSET_WIDTH   = $clog2(LINE_SIZE);              // Bits for byte offset
localparam WORD_OFFSET    = $clog2(LINE_SIZE / 4);          // Bits for word offset within line
localparam NUM_SETS       = CACHE_SIZE / LINE_SIZE / NUM_WAYS;
localparam INDEX_WIDTH    = $clog2(NUM_SETS);
localparam TAG_WIDTH      = ADDR_WIDTH - INDEX_WIDTH - OFFSET_WIDTH;
localparam WORDS_PER_LINE = LINE_SIZE / 4;                  // Words per cache line

// ============================================================
// Cache Storage
// ============================================================
// Valid bits: [way][set]
reg valid [0:NUM_WAYS-1][0:NUM_SETS-1];

// Tags: [way][set]
reg [TAG_WIDTH-1:0] tags [0:NUM_WAYS-1][0:NUM_SETS-1];

// Data: [way][set][word] - multi-word cache line
reg [31:0] data [0:NUM_WAYS-1][0:NUM_SETS-1][0:WORDS_PER_LINE-1];

// LRU bits: 1 bit per set (0 = way0 is LRU, 1 = way1 is LRU)
// Note: For NUM_WAYS > 2, would need tree-based LRU
reg lru [0:NUM_SETS-1];

// ============================================================
// Address Decomposition (using captured address)
// ============================================================
reg [31:0] req_addr_reg;        // Captured request address

wire [TAG_WIDTH-1:0]    req_tag   = req_addr_reg[ADDR_WIDTH-1 -: TAG_WIDTH];
wire [INDEX_WIDTH-1:0]  req_index = req_addr_reg[OFFSET_WIDTH +: INDEX_WIDTH];
wire [WORD_OFFSET-1:0]  req_word  = req_addr_reg[2 +: WORD_OFFSET];  // Word selector within line

// ============================================================
// State Machine
// ============================================================
localparam S_IDLE       = 3'd0;
localparam S_LOOKUP     = 3'd1;
localparam S_REFILL_REQ = 3'd2;  // Send burst request
localparam S_REFILL_DATA= 3'd3;  // Receive burst data

reg [2:0] state;
reg [INDEX_WIDTH-1:0] refill_index;
reg [TAG_WIDTH-1:0]   refill_tag;
reg                   refill_way;                 // Which way to fill (from LRU)
reg [WORD_OFFSET-1:0] refill_word_cnt;            // Current word being filled

// Debug: ICache state
`ifdef SIMULATION
    reg [63:0] ic_dbg_cycle;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ic_dbg_cycle <= 0;
        end else begin
            ic_dbg_cycle <= ic_dbg_cycle + 1;
            if (ic_dbg_cycle < 50 || (ic_dbg_cycle < 3000 && mem_rvalid)) begin
                $display("[IC@%0d] st=%d req=%b addr=%h flush=%b memreq=%b rv=%b rl=%b word=%d",
                         ic_dbg_cycle, state, cpu_req, cpu_addr, cpu_flush, mem_req, mem_rvalid, mem_rlast, refill_word_cnt);
            end
        end
    end
`endif

// ============================================================
// Tag Comparison (combinational)
// ============================================================
wire hit_way0 = valid[0][req_index] && (tags[0][req_index] == req_tag);
wire hit_way1 = valid[1][req_index] && (tags[1][req_index] == req_tag);
wire cache_hit = hit_way0 || hit_way1;

// Hit data selection
wire [31:0] hit_data_way0 = data[0][req_index][req_word];
wire [31:0] hit_data_way1 = data[1][req_index][req_word];

// ============================================================
// Performance Counters (simulation only)
// ============================================================
`ifdef SIMULATION
    // Basic counters
    reg [63:0] perf_icache_hit_cnt;
    reg [63:0] perf_icache_miss_cnt;
    reg [63:0] perf_icache_refill_cycles;
    reg [31:0] refill_cycle_counter;
    
    // AMAT statistics
    reg [63:0] perf_icache_total_cycles;   // Total access cycles
    reg [63:0] perf_icache_access_cnt;     // Total access count
    reg [31:0] access_cycle_counter;       // Per-access cycle counter
`endif

// ============================================================
// Main State Machine
// ============================================================
integer i, j, k;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state <= S_IDLE;
        cpu_rvalid <= 1'b0;
        cpu_rdata <= 32'h0;
        mem_req <= 1'b0;
        mem_addr <= 32'h0;
        mem_len <= 8'h0;
        req_addr_reg <= 32'h0;
        refill_index <= {INDEX_WIDTH{1'b0}};
        refill_tag <= {TAG_WIDTH{1'b0}};
        refill_way <= 1'b0;
        refill_word_cnt <= {WORD_OFFSET{1'b0}};
        
        // Initialize all cache entries as invalid
        for (i = 0; i < NUM_WAYS; i = i + 1) begin
            for (j = 0; j < NUM_SETS; j = j + 1) begin
                valid[i][j] = 1'b0;
                tags[i][j] = {TAG_WIDTH{1'b0}};
                for (k = 0; k < WORDS_PER_LINE; k = k + 1) begin
                    data[i][j][k] = 32'h0;
                end
            end
        end
        
        for (j = 0; j < NUM_SETS; j = j + 1) begin
            lru[j] = 1'b0;
        end
        
`ifdef SIMULATION
        perf_icache_hit_cnt <= 64'd0;
        perf_icache_miss_cnt <= 64'd0;
        perf_icache_refill_cycles <= 64'd0;
        refill_cycle_counter <= 32'd0;
        perf_icache_total_cycles <= 64'd0;
        perf_icache_access_cnt <= 64'd0;
        access_cycle_counter <= 32'd0;
`endif
    end else begin
        // Default: clear request signals
        cpu_rvalid <= 1'b0;
        
        // Flush handling: cancel current operation and return to IDLE
        if (cpu_flush && state != S_IDLE) begin
            state <= S_IDLE;
            mem_req <= 1'b0;
        end else begin
        
        case (state)
            S_IDLE: begin
                mem_req <= 1'b0;
                if (cpu_req && !cpu_flush) begin
                    req_addr_reg <= cpu_addr;  // Capture address
                    state <= S_LOOKUP;
`ifdef SIMULATION
                    access_cycle_counter <= 32'd1;  // Start counting from 1
`endif
                end
            end
            
            S_LOOKUP: begin
`ifdef SIMULATION
                access_cycle_counter <= access_cycle_counter + 1;
`endif
                if (cache_hit) begin
                    // Cache hit - return data immediately
                    cpu_rvalid <= 1'b1;
                    if (hit_way0) begin
                        cpu_rdata <= hit_data_way0;
                        lru[req_index] <= 1'b1;  // Way 0 was used, way 1 is now LRU
                    end else begin
                        cpu_rdata <= hit_data_way1;
                        lru[req_index] <= 1'b0;  // Way 1 was used, way 0 is now LRU
                    end
                    state <= S_IDLE;
`ifdef SIMULATION
                    perf_icache_hit_cnt <= perf_icache_hit_cnt + 1;
                    perf_icache_total_cycles <= perf_icache_total_cycles + {32'b0, access_cycle_counter} + 1;
                    perf_icache_access_cnt <= perf_icache_access_cnt + 1;
`endif
                end else begin
                    // Cache miss - start refill
                    refill_index <= req_index;
                    refill_tag <= req_tag;
                    refill_way <= lru[req_index];  // Replace LRU way
                    refill_word_cnt <= {WORD_OFFSET{1'b0}};
                    state <= S_REFILL_REQ;
`ifdef SIMULATION
                    perf_icache_miss_cnt <= perf_icache_miss_cnt + 1;
                    refill_cycle_counter <= 32'd1;
`endif
                end
            end
            
            S_REFILL_REQ: begin
`ifdef SIMULATION
                refill_cycle_counter <= refill_cycle_counter + 1;
                access_cycle_counter <= access_cycle_counter + 1;
`endif
                // Send burst read request
                mem_req <= 1'b1;
                // Align address to cache line boundary
                mem_addr <= {req_addr_reg[31:OFFSET_WIDTH], {OFFSET_WIDTH{1'b0}}};
                mem_len <= WORDS_PER_LINE - 1;  // Burst length (0 = 1 beat)
                state <= S_REFILL_DATA;
            end
            
            S_REFILL_DATA: begin
                mem_req <= 1'b0;  // Clear request after one cycle
`ifdef SIMULATION
                refill_cycle_counter <= refill_cycle_counter + 1;
                access_cycle_counter <= access_cycle_counter + 1;
`endif
                if (mem_rvalid) begin
                    // Write received data to cache line
                    data[refill_way][refill_index][refill_word_cnt] <= mem_rdata;
                    refill_word_cnt <= refill_word_cnt + 1;
                    
                    if (mem_rlast) begin
                        // Burst transfer complete
                        valid[refill_way][refill_index] <= 1'b1;
                        tags[refill_way][refill_index] <= refill_tag;
                        
                        // Update LRU (the filled way was just used)
                        lru[refill_index] <= ~refill_way;
                        
                        // Return the requested word
                        // Check if current beat contains the requested word
                        if (refill_word_cnt == req_word) begin
                            cpu_rdata <= mem_rdata;
                        end else begin
                            // Word was received in an earlier beat
                            cpu_rdata <= data[refill_way][refill_index][req_word];
                        end
                        cpu_rvalid <= 1'b1;
                        
                        state <= S_IDLE;
`ifdef SIMULATION
                        perf_icache_refill_cycles <= perf_icache_refill_cycles + {32'b0, refill_cycle_counter};
                        perf_icache_total_cycles <= perf_icache_total_cycles + {32'b0, access_cycle_counter} + 1;
                        perf_icache_access_cnt <= perf_icache_access_cnt + 1;
`endif
                    end
                end
            end
            
            default: begin
                state <= S_IDLE;
            end
        endcase
        end  // end of flush else
    end
end

// ============================================================
// Debug Output (simulation only) - Disabled for performance
// ============================================================
// Debug warnings are disabled by default. Uncomment if needed for debugging.
// `ifdef SIMULATION
// always @(posedge clk) begin
//     if (!rst) begin
//         if (state == S_LOOKUP && cache_hit)
//             $display("[ICache @%0t] HIT addr=%h data=%h", $time, req_addr_reg, 
//                      hit_way0 ? hit_data_way0 : hit_data_way1);
//         if (state == S_LOOKUP && !cache_hit)
//             $display("[ICache @%0t] MISS addr=%h", $time, req_addr_reg);
//     end
// end
// `endif

// Debug disabled

endmodule
