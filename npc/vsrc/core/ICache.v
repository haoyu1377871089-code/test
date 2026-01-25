// I-Cache: 4KB, 2-way set-associative, 4-byte (1-word) cache line
// Parameters:
//   - Total size: 4KB
//   - Associativity: 2-way
//   - Line size: 4 bytes (1 word) - simplifies refill, no burst needed
//   - Number of sets: 512 (4KB / 2 / 4B)
//   - Address: Tag[31:11] Index[10:2] Offset[1:0] (word-aligned)
//   - Replacement: LRU (1 bit per set)

module ICache (
    input clk,
    input rst,
    
    // Upstream interface (to CPU/EXU)
    input               cpu_req,        // Fetch request
    input      [31:0]   cpu_addr,       // Fetch address
    output reg          cpu_rvalid,     // Data valid
    output reg [31:0]   cpu_rdata,      // Instruction data
    
    // Downstream interface (to memory/IFU_AXI)
    output reg          mem_req,        // Memory read request
    output reg [31:0]   mem_addr,       // Memory address
    input               mem_rvalid,     // Memory data valid
    input      [31:0]   mem_rdata       // Memory data
);

// ============================================================
// Parameters
// ============================================================
localparam OFFSET_WIDTH = 2;    // 4 bytes = 2^2 (word-aligned, lower 2 bits ignored)
localparam INDEX_WIDTH  = 9;    // 512 sets = 2^9
localparam TAG_WIDTH    = 21;   // 32 - 9 - 2 = 21
localparam NUM_SETS     = 512;
localparam NUM_WAYS     = 2;

// ============================================================
// Cache Storage
// ============================================================
// Valid bits: [way][set]
reg valid [0:NUM_WAYS-1][0:NUM_SETS-1];

// Tags: [way][set]
reg [TAG_WIDTH-1:0] tags [0:NUM_WAYS-1][0:NUM_SETS-1];

// Data: [way][set] - single word per line
reg [31:0] data [0:NUM_WAYS-1][0:NUM_SETS-1];

// LRU bits: 1 bit per set (0 = way0 is LRU, 1 = way1 is LRU)
reg lru [0:NUM_SETS-1];

// ============================================================
// Address Decomposition (using captured address)
// ============================================================
reg [31:0] req_addr_reg;        // Captured request address
wire [TAG_WIDTH-1:0]    req_tag   = req_addr_reg[31:11];
wire [INDEX_WIDTH-1:0]  req_index = req_addr_reg[10:2];  // Word-aligned index

// ============================================================
// State Machine
// ============================================================
localparam S_IDLE       = 2'd0;
localparam S_LOOKUP     = 2'd1;
localparam S_REFILL     = 2'd2;

reg [1:0] state;
reg [INDEX_WIDTH-1:0] refill_index;
reg [TAG_WIDTH-1:0] refill_tag;
reg refill_way;                 // Which way to fill (from LRU)
reg refill_req_sent;            // Track if request was sent

// ============================================================
// Tag Comparison (combinational)
// ============================================================
wire hit_way0 = valid[0][req_index] && (tags[0][req_index] == req_tag);
wire hit_way1 = valid[1][req_index] && (tags[1][req_index] == req_tag);
wire cache_hit = hit_way0 || hit_way1;

// ============================================================
// Performance Counters (simulation only)
// ============================================================
`ifdef SIMULATION
    reg [63:0] perf_icache_hit_cnt;
    reg [63:0] perf_icache_miss_cnt;
    reg [63:0] perf_icache_refill_cycles;
    reg [31:0] refill_cycle_counter;
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
        req_addr_reg <= 32'h0;
        refill_index <= {INDEX_WIDTH{1'b0}};
        refill_tag <= {TAG_WIDTH{1'b0}};
        refill_way <= 1'b0;
        refill_req_sent <= 1'b0;
        
        // Initialize all cache entries as invalid (use blocking for loop)
        for (i = 0; i < NUM_WAYS; i = i + 1) begin
            for (j = 0; j < NUM_SETS; j = j + 1) begin
                valid[i][j] = 1'b0;
                tags[i][j] = {TAG_WIDTH{1'b0}};
                data[i][j] = 32'h0;
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
`endif
    end else begin
        // Default: clear request signals
        cpu_rvalid <= 1'b0;
        
        case (state)
            S_IDLE: begin
                mem_req <= 1'b0;
                if (cpu_req) begin
                    req_addr_reg <= cpu_addr;  // Capture address
                    state <= S_LOOKUP;
                end
            end
            
            S_LOOKUP: begin
                if (cache_hit) begin
                    // Cache hit - return data immediately
                    cpu_rvalid <= 1'b1;
                    if (hit_way0) begin
                        cpu_rdata <= data[0][req_index];
                        lru[req_index] <= 1'b1;  // Way 0 was used, way 1 is now LRU
                    end else begin
                        cpu_rdata <= data[1][req_index];
                        lru[req_index] <= 1'b0;  // Way 1 was used, way 0 is now LRU
                    end
                    state <= S_IDLE;
`ifdef SIMULATION
                    perf_icache_hit_cnt <= perf_icache_hit_cnt + 1;
`endif
                end else begin
                    // Cache miss - start refill (single word)
                    refill_index <= req_index;
                    refill_tag <= req_tag;
                    refill_way <= lru[req_index];  // Replace LRU way
                    refill_req_sent <= 1'b0;
                    state <= S_REFILL;
`ifdef SIMULATION
                    perf_icache_miss_cnt <= perf_icache_miss_cnt + 1;
                    refill_cycle_counter <= 32'd1;
`endif
                end
            end
            
            S_REFILL: begin
`ifdef SIMULATION
                refill_cycle_counter <= refill_cycle_counter + 1;
`endif
                // Issue single memory request (1-word cache line)
                // mem_req must be a pulse (one cycle only)
                if (!refill_req_sent) begin
                    mem_req <= 1'b1;
                    mem_addr <= {req_addr_reg[31:2], 2'b0};  // Word-aligned address
                    refill_req_sent <= 1'b1;
                end else begin
                    mem_req <= 1'b0;  // Clear request after one cycle
                    if (mem_rvalid) begin
                        // Got response - update cache and return data
`ifdef SIMULATION
                        perf_icache_refill_cycles <= perf_icache_refill_cycles + {32'b0, refill_cycle_counter};
`endif
                        // Write to cache
                        valid[refill_way][refill_index] <= 1'b1;
                        tags[refill_way][refill_index] <= refill_tag;
                        data[refill_way][refill_index] <= mem_rdata;
                        
                        // Update LRU (the filled way was just used)
                        lru[refill_index] <= ~refill_way;
                        
                        // Return the data
                        cpu_rvalid <= 1'b1;
                        cpu_rdata <= mem_rdata;
                        
                        state <= S_IDLE;
                    end
                end
            end
            
            default: begin
                state <= S_IDLE;
            end
        endcase
    end
end

// ============================================================
// Debug Output (simulation only) - Disabled for performance
// ============================================================
// Debug warnings are disabled by default. Uncomment if needed for debugging.

endmodule
