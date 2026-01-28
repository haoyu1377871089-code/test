// D-Cache: Parameterized, 2-way set-associative with burst support
// Default: 4KB, 2-way, 16-byte cache line (4 words per line)
// Write Policy: Write-through + No-write-allocate
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
//
// Write Policy:
//   - Write-through: All writes go to memory immediately
//   - No-write-allocate: Write misses don't fill cache, just write to memory
//   - Write hits also update cache data
//
// Cacheable Address Regions (ysyxSoC):
//   - PSRAM:  0x80000000 - 0x80400000 (4MB)
//   - SDRAM:  0xa0000000 - 0xa2000000 (32MB)
// Non-cacheable (I/O devices) are bypassed directly to memory

module DCache #(
    parameter CACHE_SIZE    = 4096,     // Total cache size (bytes)
    parameter LINE_SIZE     = 16,       // Cache line size (bytes): 4, 8, 16, 32
    parameter NUM_WAYS      = 2,        // Associativity
    parameter ADDR_WIDTH    = 32
) (
    input clk,
    input rst,
    
    // Upstream interface (to CPU/EXU)
    input               cpu_req,        // Memory request
    input               cpu_wen,        // Write enable (0=read, 1=write)
    input  [31:0]       cpu_addr,       // Memory address
    input  [31:0]       cpu_wdata,      // Write data
    input  [3:0]        cpu_wmask,      // Write byte mask
    output reg          cpu_rvalid,     // Data valid (for both read and write completion)
    output reg [31:0]   cpu_rdata,      // Read data
    
    // Downstream interface (to memory/LSU_AXI4) - with burst support
    output reg          mem_req,        // Memory request
    output reg          mem_wen,        // Memory write enable
    output reg [31:0]   mem_addr,       // Memory address
    output reg [31:0]   mem_wdata,      // Memory write data
    output reg [3:0]    mem_wmask,      // Memory write mask
    output reg [7:0]    mem_len,        // Burst length (0=1 beat, N-1=N beats)
    input               mem_rvalid,     // Memory data valid
    input      [31:0]   mem_rdata,      // Memory read data
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
reg [31:0] req_wdata_reg;       // Captured write data
reg [3:0]  req_wmask_reg;       // Captured write mask
reg        req_wen_reg;         // Captured write enable

wire [TAG_WIDTH-1:0]    req_tag   = req_addr_reg[ADDR_WIDTH-1 -: TAG_WIDTH];
wire [INDEX_WIDTH-1:0]  req_index = req_addr_reg[OFFSET_WIDTH +: INDEX_WIDTH];
wire [WORD_OFFSET-1:0]  req_word  = req_addr_reg[2 +: WORD_OFFSET];  // Word selector within line

// ============================================================
// Cacheable Address Detection (ysyxSoC memory map)
// ============================================================
// Only cache PSRAM (0x80000000 - 0x803FFFFF) and SDRAM (0xa0000000 - 0xa1FFFFFF)
// All other addresses (I/O devices) bypass cache directly
wire is_psram_region = (req_addr_reg[31:22] == 10'b10_0000_0000);  // 0x80000000 - 0x803FFFFF
wire is_sdram_region = (req_addr_reg[31:25] == 7'b101_0000);       // 0xa0000000 - 0xa1FFFFFF
wire is_cacheable = is_psram_region || is_sdram_region;

// For input address (before capture) - used for quick bypass decision
wire [31:0] input_addr = cpu_addr;
wire input_is_psram = (input_addr[31:22] == 10'b10_0000_0000);
wire input_is_sdram = (input_addr[31:25] == 7'b101_0000);
wire input_is_cacheable = input_is_psram || input_is_sdram;

// ============================================================
// State Machine
// ============================================================
localparam S_IDLE        = 4'd0;
localparam S_LOOKUP      = 4'd1;
localparam S_REFILL_REQ  = 4'd2;  // Send burst request (read miss)
localparam S_REFILL_DATA = 4'd3;  // Receive burst data (read miss)
localparam S_WRITE_REQ   = 4'd4;  // Send write request (write-through)
localparam S_WRITE_RESP  = 4'd5;  // Wait for write response
localparam S_BYPASS_REQ  = 4'd6;  // Bypass: send request for non-cacheable address
localparam S_BYPASS_RESP = 4'd7;  // Bypass: wait for response

reg [3:0] state;
reg [INDEX_WIDTH-1:0] refill_index;
reg [TAG_WIDTH-1:0]   refill_tag;
reg                   refill_way;                 // Which way to fill (from LRU)
reg [WORD_OFFSET-1:0] refill_word_cnt;            // Current word being filled

// ============================================================
// Tag Comparison (combinational)
// ============================================================
wire hit_way0 = valid[0][req_index] && (tags[0][req_index] == req_tag);
wire hit_way1 = valid[1][req_index] && (tags[1][req_index] == req_tag);
wire cache_hit = hit_way0 || hit_way1;
wire hit_way = hit_way1;  // 0 = way0 hit, 1 = way1 hit

// Hit data selection
wire [31:0] hit_data_way0 = data[0][req_index][req_word];
wire [31:0] hit_data_way1 = data[1][req_index][req_word];

// ============================================================
// Performance Counters (simulation only)
// ============================================================
`ifdef SIMULATION
    // Basic counters
    reg [63:0] perf_dcache_read_hit_cnt;
    reg [63:0] perf_dcache_read_miss_cnt;
    reg [63:0] perf_dcache_write_hit_cnt;
    reg [63:0] perf_dcache_write_miss_cnt;
    reg [63:0] perf_dcache_refill_cycles;
    reg [63:0] perf_dcache_write_cycles;
    reg [31:0] refill_cycle_counter;
    reg [31:0] write_cycle_counter;
    
    // AMAT statistics
    reg [63:0] perf_dcache_total_cycles;   // Total access cycles
    reg [63:0] perf_dcache_access_cnt;     // Total access count
    reg [31:0] access_cycle_counter;       // Per-access cycle counter
`endif

// ============================================================
// Byte-masked write helper function
// ============================================================
function [31:0] apply_write_mask;
    input [31:0] old_data;
    input [31:0] new_data;
    input [3:0]  mask;
    begin
        apply_write_mask[7:0]   = mask[0] ? new_data[7:0]   : old_data[7:0];
        apply_write_mask[15:8]  = mask[1] ? new_data[15:8]  : old_data[15:8];
        apply_write_mask[23:16] = mask[2] ? new_data[23:16] : old_data[23:16];
        apply_write_mask[31:24] = mask[3] ? new_data[31:24] : old_data[31:24];
    end
endfunction

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
        mem_wen <= 1'b0;
        mem_addr <= 32'h0;
        mem_wdata <= 32'h0;
        mem_wmask <= 4'h0;
        mem_len <= 8'h0;
        req_addr_reg <= 32'h0;
        req_wdata_reg <= 32'h0;
        req_wmask_reg <= 4'h0;
        req_wen_reg <= 1'b0;
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
        perf_dcache_read_hit_cnt <= 64'd0;
        perf_dcache_read_miss_cnt <= 64'd0;
        perf_dcache_write_hit_cnt <= 64'd0;
        perf_dcache_write_miss_cnt <= 64'd0;
        perf_dcache_refill_cycles <= 64'd0;
        perf_dcache_write_cycles <= 64'd0;
        refill_cycle_counter <= 32'd0;
        write_cycle_counter <= 32'd0;
        perf_dcache_total_cycles <= 64'd0;
        perf_dcache_access_cnt <= 64'd0;
        access_cycle_counter <= 32'd0;
`endif
    end else begin
        // Default: clear request signals
        cpu_rvalid <= 1'b0;
        
        case (state)
            S_IDLE: begin
                mem_req <= 1'b0;
                mem_wen <= 1'b0;
                if (cpu_req) begin
                    req_addr_reg <= cpu_addr;      // Capture address
                    req_wdata_reg <= cpu_wdata;    // Capture write data
                    req_wmask_reg <= cpu_wmask;    // Capture write mask
                    req_wen_reg <= cpu_wen;        // Capture write enable
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
                // Check if address is cacheable
                if (!is_cacheable) begin
                    // ========== NON-CACHEABLE ACCESS (BYPASS) ==========
                    // I/O devices: bypass cache entirely
                    state <= S_BYPASS_REQ;
`ifdef SIMULATION
                    write_cycle_counter <= 32'd1;
`endif
                end else if (req_wen_reg) begin
                    // ========== CACHEABLE WRITE OPERATION ==========
                    // Write-through: always write to memory
                    // Also update cache if hit (write-allocate on hit)
                    
                    if (cache_hit) begin
                        // Write hit: update cache data with byte mask
                        if (hit_way0) begin
                            data[0][req_index][req_word] <= apply_write_mask(
                                data[0][req_index][req_word], req_wdata_reg, req_wmask_reg);
                            lru[req_index] <= 1'b1;  // Way 0 was used
                        end else begin
                            data[1][req_index][req_word] <= apply_write_mask(
                                data[1][req_index][req_word], req_wdata_reg, req_wmask_reg);
                            lru[req_index] <= 1'b0;  // Way 1 was used
                        end
`ifdef SIMULATION
                        perf_dcache_write_hit_cnt <= perf_dcache_write_hit_cnt + 1;
`endif
                    end else begin
`ifdef SIMULATION
                        perf_dcache_write_miss_cnt <= perf_dcache_write_miss_cnt + 1;
`endif
                    end
                    
                    // Write-through: send write to memory
                    state <= S_WRITE_REQ;
`ifdef SIMULATION
                    write_cycle_counter <= 32'd1;
`endif
                    
                end else begin
                    // ========== CACHEABLE READ OPERATION ==========
                    if (cache_hit) begin
                        // Read hit - return data immediately
                        cpu_rvalid <= 1'b1;
                        // Select hit data and align based on byte offset
                        // EXU expects aligned data (LSU_AXI4 does this for bypass)
                        if (hit_way0) begin
                            case (req_addr_reg[1:0])
                                2'b00: cpu_rdata <= hit_data_way0;
                                2'b01: cpu_rdata <= {8'b0, hit_data_way0[31:8]};
                                2'b10: cpu_rdata <= {16'b0, hit_data_way0[31:16]};
                                2'b11: cpu_rdata <= {24'b0, hit_data_way0[31:24]};
                            endcase
                            lru[req_index] <= 1'b1;  // Way 0 was used, way 1 is now LRU
                        end else begin
                            case (req_addr_reg[1:0])
                                2'b00: cpu_rdata <= hit_data_way1;
                                2'b01: cpu_rdata <= {8'b0, hit_data_way1[31:8]};
                                2'b10: cpu_rdata <= {16'b0, hit_data_way1[31:16]};
                                2'b11: cpu_rdata <= {24'b0, hit_data_way1[31:24]};
                            endcase
                            lru[req_index] <= 1'b0;  // Way 1 was used, way 0 is now LRU
                        end
                        state <= S_IDLE;
`ifdef SIMULATION
                        perf_dcache_read_hit_cnt <= perf_dcache_read_hit_cnt + 1;
                        perf_dcache_total_cycles <= perf_dcache_total_cycles + {32'b0, access_cycle_counter} + 1;
                        perf_dcache_access_cnt <= perf_dcache_access_cnt + 1;
`endif
                    end else begin
                        // Read miss - start refill
                        refill_index <= req_index;
                        refill_tag <= req_tag;
                        refill_way <= lru[req_index];  // Replace LRU way
                        refill_word_cnt <= {WORD_OFFSET{1'b0}};
                        state <= S_REFILL_REQ;
`ifdef SIMULATION
                        perf_dcache_read_miss_cnt <= perf_dcache_read_miss_cnt + 1;
                        refill_cycle_counter <= 32'd1;
`endif
                    end
                end
            end
            
            S_REFILL_REQ: begin
`ifdef SIMULATION
                refill_cycle_counter <= refill_cycle_counter + 1;
                access_cycle_counter <= access_cycle_counter + 1;
`endif
                // Send burst read request
                mem_req <= 1'b1;
                mem_wen <= 1'b0;
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
                        
                        // Return the requested word with byte alignment
                        // For the word that arrived in the current beat, use mem_rdata directly
                        // For words received in earlier beats, read from cache (already written)
                        begin
                            reg [31:0] raw_word;
                            if (refill_word_cnt == req_word) begin
                                // Current beat contains the requested word
                                raw_word = mem_rdata;
                            end else begin
                                // Word was received in an earlier beat, read from cache
                                raw_word = data[refill_way][refill_index][req_word];
                            end
                            // Align data based on byte offset (same as LSU_AXI4)
                            case (req_addr_reg[1:0])
                                2'b00: cpu_rdata <= raw_word;
                                2'b01: cpu_rdata <= {8'b0, raw_word[31:8]};
                                2'b10: cpu_rdata <= {16'b0, raw_word[31:16]};
                                2'b11: cpu_rdata <= {24'b0, raw_word[31:24]};
                            endcase
                        end
                        cpu_rvalid <= 1'b1;
                        
                        state <= S_IDLE;
`ifdef SIMULATION
                        perf_dcache_refill_cycles <= perf_dcache_refill_cycles + {32'b0, refill_cycle_counter};
                        perf_dcache_total_cycles <= perf_dcache_total_cycles + {32'b0, access_cycle_counter} + 1;
                        perf_dcache_access_cnt <= perf_dcache_access_cnt + 1;
`endif
                    end
                end
            end
            
            S_WRITE_REQ: begin
`ifdef SIMULATION
                write_cycle_counter <= write_cycle_counter + 1;
                access_cycle_counter <= access_cycle_counter + 1;
`endif
                // Send single-beat write request
                mem_req <= 1'b1;
                mem_wen <= 1'b1;
                mem_addr <= req_addr_reg;
                mem_wdata <= req_wdata_reg;
                mem_wmask <= req_wmask_reg;
                mem_len <= 8'h0;  // Single beat
                state <= S_WRITE_RESP;
            end
            
            S_WRITE_RESP: begin
                mem_req <= 1'b0;  // Clear request after one cycle
`ifdef SIMULATION
                write_cycle_counter <= write_cycle_counter + 1;
                access_cycle_counter <= access_cycle_counter + 1;
`endif
                if (mem_rvalid) begin
                    // Write complete
                    cpu_rvalid <= 1'b1;
                    state <= S_IDLE;
`ifdef SIMULATION
                    perf_dcache_write_cycles <= perf_dcache_write_cycles + {32'b0, write_cycle_counter};
                    perf_dcache_total_cycles <= perf_dcache_total_cycles + {32'b0, access_cycle_counter} + 1;
                    perf_dcache_access_cnt <= perf_dcache_access_cnt + 1;
`endif
                end
            end
            
            // ============================================================
            // BYPASS states for non-cacheable I/O devices
            // ============================================================
            S_BYPASS_REQ: begin
`ifdef SIMULATION
                write_cycle_counter <= write_cycle_counter + 1;
                access_cycle_counter <= access_cycle_counter + 1;
`endif
                // Send single-beat request directly to memory (no caching)
                mem_req <= 1'b1;
                mem_wen <= req_wen_reg;
                mem_addr <= req_addr_reg;
                mem_wdata <= req_wdata_reg;
                mem_wmask <= req_wmask_reg;
                mem_len <= 8'h0;  // Single beat, no burst for I/O
                state <= S_BYPASS_RESP;
            end
            
            S_BYPASS_RESP: begin
                mem_req <= 1'b0;  // Clear request after one cycle
`ifdef SIMULATION
                write_cycle_counter <= write_cycle_counter + 1;
                access_cycle_counter <= access_cycle_counter + 1;
`endif
                if (mem_rvalid) begin
                    // Bypass complete
                    cpu_rvalid <= 1'b1;
                    cpu_rdata <= mem_rdata;  // Return read data (ignored for writes)
                    state <= S_IDLE;
`ifdef SIMULATION
                    perf_dcache_total_cycles <= perf_dcache_total_cycles + {32'b0, access_cycle_counter} + 1;
                    perf_dcache_access_cnt <= perf_dcache_access_cnt + 1;
`endif
                end
            end
            
            default: begin
                state <= S_IDLE;
            end
        endcase
    end
end

// ============================================================
// Debug Output (simulation only)
// ============================================================
`ifdef SIMULATION
reg [31:0] dcache_dbg_cycle_cnt;
always @(posedge clk or posedge rst) begin
    if (rst)
        dcache_dbg_cycle_cnt <= 32'd0;
    else
        dcache_dbg_cycle_cnt <= dcache_dbg_cycle_cnt + 1;
end

`ifdef DCACHE_DEBUG
always @(posedge clk) begin
    if (!rst) begin
        if (state == S_LOOKUP && !is_cacheable)
            $display("[DCache @%0d] BYPASS addr=%h wen=%b cpu_req=%b", dcache_dbg_cycle_cnt, req_addr_reg, req_wen_reg, cpu_req);
        if (state == S_LOOKUP && is_cacheable && cache_hit && !req_wen_reg)
            $display("[DCache @%0d] READ HIT addr=%h data=%h", dcache_dbg_cycle_cnt, req_addr_reg, 
                     hit_way0 ? hit_data_way0 : hit_data_way1);
        if (state == S_LOOKUP && is_cacheable && !cache_hit && !req_wen_reg)
            $display("[DCache @%0d] READ MISS addr=%h", dcache_dbg_cycle_cnt, req_addr_reg);
        if (state == S_LOOKUP && is_cacheable && req_wen_reg)
            $display("[DCache @%0d] WRITE addr=%h data=%h hit=%b", dcache_dbg_cycle_cnt, 
                     req_addr_reg, req_wdata_reg, cache_hit);
    end
end
`endif
`endif

endmodule
