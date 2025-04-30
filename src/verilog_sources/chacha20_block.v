`include "src/verilog_headers/chacha20_defs.vh"

module chacha20_block #(
    parameter MAX_PARALLEL_BLOCKS = `CHACHA20_PARALLEL_BLOCKS,
    parameter PIPELINE_STAGES = `CHACHA20_PIPELINE_STAGES,
    parameter RESOURCE_OPTIMIZE = `CHACHA20_RESOURCE_OPTIMIZE,
    parameter ENDIANNESS = `CHACHA20_ENDIANNESS
)(
    input clk,                              // Clock signal
    input rst_n,                            // Active low reset
    input start,                            // Start signal
    input [255:0] key,                      // 32 bytes key
    input [31:0] counter,                   // 4 bytes counter
    input [95:0] nonce,                     // 12 bytes nonce
    input [1:0] parallel_blocks,            // Number of blocks to process in parallel (0=1, 1=2, 2=4)
    output reg [2047:0] keystream_blocks,   // Up to 4 keystream blocks (4 x 512 bits)
    output reg done                         // Operation complete
);
    // Define constants
    localparam [31:0] CONST_0 = `CHACHA20_CONST_0;
    localparam [31:0] CONST_1 = `CHACHA20_CONST_1;
    localparam [31:0] CONST_2 = `CHACHA20_CONST_2;
    localparam [31:0] CONST_3 = `CHACHA20_CONST_3;

    // Define states
    localparam IDLE = 3'b000;
    localparam INIT = 3'b001;
    localparam ROUNDS_1_TO_10 = 3'b010;   // First 10 rounds (5 double-rounds)
    localparam ROUNDS_11_TO_20 = 3'b011;  // Second 10 rounds (5 double-rounds)
    localparam FINALIZE = 3'b100;         // Add initial state to working state
    
    // Column indices (4 quarter rounds x 4 elements each)
    localparam [4:0] COL_IDX_0_0 = 0;  localparam [4:0] COL_IDX_0_1 = 4;  localparam [4:0] COL_IDX_0_2 = 8;  localparam [4:0] COL_IDX_0_3 = 12;
    localparam [4:0] COL_IDX_1_0 = 1;  localparam [4:0] COL_IDX_1_1 = 5;  localparam [4:0] COL_IDX_1_2 = 9;  localparam [4:0] COL_IDX_1_3 = 13;
    localparam [4:0] COL_IDX_2_0 = 2;  localparam [4:0] COL_IDX_2_1 = 6;  localparam [4:0] COL_IDX_2_2 = 10; localparam [4:0] COL_IDX_2_3 = 14;
    localparam [4:0] COL_IDX_3_0 = 3;  localparam [4:0] COL_IDX_3_1 = 7;  localparam [4:0] COL_IDX_3_2 = 11; localparam [4:0] COL_IDX_3_3 = 15;
    
    // Diagonal indices (4 quarter rounds x 4 elements each)
    localparam [4:0] DIAG_IDX_0_0 = 0;  localparam [4:0] DIAG_IDX_0_1 = 5;  localparam [4:0] DIAG_IDX_0_2 = 10; localparam [4:0] DIAG_IDX_0_3 = 15;
    localparam [4:0] DIAG_IDX_1_0 = 1;  localparam [4:0] DIAG_IDX_1_1 = 6;  localparam [4:0] DIAG_IDX_1_2 = 11; localparam [4:0] DIAG_IDX_1_3 = 12;
    localparam [4:0] DIAG_IDX_2_0 = 2;  localparam [4:0] DIAG_IDX_2_1 = 7;  localparam [4:0] DIAG_IDX_2_2 = 8;  localparam [4:0] DIAG_IDX_2_3 = 13;
    localparam [4:0] DIAG_IDX_3_0 = 3;  localparam [4:0] DIAG_IDX_3_1 = 4;  localparam [4:0] DIAG_IDX_3_2 = 9;  localparam [4:0] DIAG_IDX_3_3 = 14;
    
    reg [2:0] state;
    reg [4:0] double_round_counter;     // Up to 10 double rounds (20 rounds)
    reg process_column_round;           // 0 for column round, 1 for diagonal round
    
    // Number of parallel blocks to process (1, 2, or 4)
    reg [3:0] num_blocks;
    
    // State for up to 4 parallel blocks
    reg [31:0] initial_state [0:MAX_PARALLEL_BLOCKS-1][0:15];
    reg [31:0] working_state [0:MAX_PARALLEL_BLOCKS-1][0:15];
    
    // Pipeline tracking
    reg [2:0] pipeline_stage;
    
    // =====================================================================
    // HIGH PERFORMANCE MODE - Multiple Quarter Round Instances for parallelism
    // =====================================================================
    
    // Array-based connection wires for quarter rounds
    wire [31:0] col_qr_in [0:MAX_PARALLEL_BLOCKS-1][0:3][0:3];
    wire [31:0] col_qr_out [0:MAX_PARALLEL_BLOCKS-1][0:3][0:3];
    wire [31:0] diag_qr_in [0:MAX_PARALLEL_BLOCKS-1][0:3][0:3];
    wire [31:0] diag_qr_out [0:MAX_PARALLEL_BLOCKS-1][0:3][0:3];
    
    // Resource-optimized mode
    reg [31:0] qr_inputs [0:3];
    wire [31:0] qr_outputs [0:3];
    
    // Resource-optimized tracking
    reg [4:0] qr_index;
    reg [2:0] qr_block_index;
    reg qr_is_diagonal;
    
    // Instantiate quarter rounds based on resource optimization parameter
    generate
        if (RESOURCE_OPTIMIZE == 0) begin: high_perf_impl
            // High-performance mode: Instantiate parallel QR modules
            genvar block_idx, qr_idx, i;
            
            for (block_idx = 0; block_idx < MAX_PARALLEL_BLOCKS; block_idx = block_idx + 1) begin : block_gen
                // Column round connections for this block
                for (i = 0; i < 4; i = i + 1) begin : col_qr_inputs
                    assign col_qr_in[block_idx][i][0] = working_state[block_idx][i == 0 ? COL_IDX_0_0 : i == 1 ? COL_IDX_1_0 : i == 2 ? COL_IDX_2_0 : COL_IDX_3_0];
                    assign col_qr_in[block_idx][i][1] = working_state[block_idx][i == 0 ? COL_IDX_0_1 : i == 1 ? COL_IDX_1_1 : i == 2 ? COL_IDX_2_1 : COL_IDX_3_1];
                    assign col_qr_in[block_idx][i][2] = working_state[block_idx][i == 0 ? COL_IDX_0_2 : i == 1 ? COL_IDX_1_2 : i == 2 ? COL_IDX_2_2 : COL_IDX_3_2];
                    assign col_qr_in[block_idx][i][3] = working_state[block_idx][i == 0 ? COL_IDX_0_3 : i == 1 ? COL_IDX_1_3 : i == 2 ? COL_IDX_2_3 : COL_IDX_3_3];
                end
            
                // Diagonal round connections for this block
                for (i = 0; i < 4; i = i + 1) begin : diag_qr_inputs
                    assign diag_qr_in[block_idx][i][0] = working_state[block_idx][i == 0 ? DIAG_IDX_0_0 : i == 1 ? DIAG_IDX_1_0 : i == 2 ? DIAG_IDX_2_0 : DIAG_IDX_3_0];
                    assign diag_qr_in[block_idx][i][1] = working_state[block_idx][i == 0 ? DIAG_IDX_0_1 : i == 1 ? DIAG_IDX_1_1 : i == 2 ? DIAG_IDX_2_1 : DIAG_IDX_3_1];
                    assign diag_qr_in[block_idx][i][2] = working_state[block_idx][i == 0 ? DIAG_IDX_0_2 : i == 1 ? DIAG_IDX_1_2 : i == 2 ? DIAG_IDX_2_2 : DIAG_IDX_3_2];
                    assign diag_qr_in[block_idx][i][3] = working_state[block_idx][i == 0 ? DIAG_IDX_0_3 : i == 1 ? DIAG_IDX_1_3 : i == 2 ? DIAG_IDX_2_3 : DIAG_IDX_3_3];
                end
                
                // Instantiate quarter round modules for each block
                for (qr_idx = 0; qr_idx < 4; qr_idx = qr_idx + 1) begin : qr_modules
                    quarter_round #(
                        .PIPELINE_STAGES(PIPELINE_STAGES)
                    ) col_qr (
                        .clk(clk),
                        .rst_n(rst_n),
                        .a_in(col_qr_in[block_idx][qr_idx][0]),
                        .b_in(col_qr_in[block_idx][qr_idx][1]),
                        .c_in(col_qr_in[block_idx][qr_idx][2]),
                        .d_in(col_qr_in[block_idx][qr_idx][3]),
                        .a_out(col_qr_out[block_idx][qr_idx][0]),
                        .b_out(col_qr_out[block_idx][qr_idx][1]),
                        .c_out(col_qr_out[block_idx][qr_idx][2]),
                        .d_out(col_qr_out[block_idx][qr_idx][3])
                    );
                    
                    quarter_round #(
                        .PIPELINE_STAGES(PIPELINE_STAGES)
                    ) diag_qr (
                        .clk(clk),
                        .rst_n(rst_n),
                        .a_in(diag_qr_in[block_idx][qr_idx][0]),
                        .b_in(diag_qr_in[block_idx][qr_idx][1]),
                        .c_in(diag_qr_in[block_idx][qr_idx][2]),
                        .d_in(diag_qr_in[block_idx][qr_idx][3]),
                        .a_out(diag_qr_out[block_idx][qr_idx][0]),
                        .b_out(diag_qr_out[block_idx][qr_idx][1]),
                        .c_out(diag_qr_out[block_idx][qr_idx][2]),
                        .d_out(diag_qr_out[block_idx][qr_idx][3])
                    );
                end
            end
        end
        else begin: resource_opt_impl
            // Resource-optimized mode: Single shared QR module
            quarter_round #(
                .PIPELINE_STAGES(PIPELINE_STAGES)
            ) shared_qr (
                .clk(clk),
                .rst_n(rst_n),
                .a_in(qr_inputs[0]),
                .b_in(qr_inputs[1]),
                .c_in(qr_inputs[2]),
                .d_in(qr_inputs[3]),
                .a_out(qr_outputs[0]),
                .b_out(qr_outputs[1]),
                .c_out(qr_outputs[2]),
                .d_out(qr_outputs[3])
            );
        end
    endgenerate
    
    // Endianness conversion function
    function [31:0] adjust_endianness;
        input [31:0] word;
        begin
            if (ENDIANNESS == 0) begin 
                // Little endian - convert to big endian
                adjust_endianness = {word[7:0], word[15:8], word[23:16], word[31:24]};
            end else begin
                // Big endian - no conversion needed
                adjust_endianness = word;
            end
        end
    endfunction
    
    // Main state machine
    always @(posedge clk or negedge rst_n) begin
        integer blk, qr, out_idx, word_idx;
        
        if (!rst_n) begin
            state <= IDLE;
            done <= 1'b0;
            double_round_counter <= 5'd0;
            process_column_round <= 1'b1;
            pipeline_stage <= 3'd0;
            num_blocks <= 4'd1;
            qr_index <= 5'd0;
            qr_block_index <= 3'd0;
            qr_is_diagonal <= 1'b0;
            keystream_blocks <= 2048'd0;
            
            // Initialize input arrays 
            for (word_idx = 0; word_idx < 4; word_idx = word_idx + 1) begin
                qr_inputs[word_idx] <= 32'd0;
            end
            
            // Initialize all state arrays to 0
            for (blk = 0; blk < MAX_PARALLEL_BLOCKS; blk = blk + 1) begin
                for (word_idx = 0; word_idx < 16; word_idx = word_idx + 1) begin
                    initial_state[blk][word_idx] <= 32'd0;
                    working_state[blk][word_idx] <= 32'd0;
                end
            end
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    
                    if (start) begin
                        // Determine number of blocks to process
                        case (parallel_blocks)
                            2'b00: num_blocks <= 4'd1;
                            2'b01: num_blocks <= 4'd2;
                            2'b10: num_blocks <= 4'd4;
                            default: num_blocks <= 4'd1;
                        endcase
                        
                        state <= INIT;
                    end
                end
                
                INIT: begin
                    // Initialize state for requested number of blocks in parallel
                    for (blk = 0; blk < MAX_PARALLEL_BLOCKS; blk = blk + 1) begin
                        if (blk < num_blocks) begin
                            // Initialize constants
                            initial_state[blk][0] <= CONST_0;
                            initial_state[blk][1] <= CONST_1;
                            initial_state[blk][2] <= CONST_2;
                            initial_state[blk][3] <= CONST_3;
                            
                            // Initialize key (8 words) with consistent endianness
                            initial_state[blk][4] <= adjust_endianness(key[31:0]);
                            initial_state[blk][5] <= adjust_endianness(key[63:32]);
                            initial_state[blk][6] <= adjust_endianness(key[95:64]);
                            initial_state[blk][7] <= adjust_endianness(key[127:96]);
                            initial_state[blk][8] <= adjust_endianness(key[159:128]);
                            initial_state[blk][9] <= adjust_endianness(key[191:160]);
                            initial_state[blk][10] <= adjust_endianness(key[223:192]);
                            initial_state[blk][11] <= adjust_endianness(key[255:224]);
                            
                            // Initialize counter (incremented for each block)
                            initial_state[blk][12] <= counter + blk;
                            
                            // Initialize nonce (3 words) with consistent endianness
                            initial_state[blk][13] <= adjust_endianness(nonce[31:0]);
                            initial_state[blk][14] <= adjust_endianness(nonce[63:32]);
                            initial_state[blk][15] <= adjust_endianness(nonce[95:64]);
                            
                            // Copy to working state
                            working_state[blk][0] <= CONST_0;
                            working_state[blk][1] <= CONST_1;
                            working_state[blk][2] <= CONST_2;
                            working_state[blk][3] <= CONST_3;
                            working_state[blk][4] <= adjust_endianness(key[31:0]);
                            working_state[blk][5] <= adjust_endianness(key[63:32]);
                            working_state[blk][6] <= adjust_endianness(key[95:64]);
                            working_state[blk][7] <= adjust_endianness(key[127:96]);
                            working_state[blk][8] <= adjust_endianness(key[159:128]);
                            working_state[blk][9] <= adjust_endianness(key[191:160]);
                            working_state[blk][10] <= adjust_endianness(key[223:192]);
                            working_state[blk][11] <= adjust_endianness(key[255:224]);
                            working_state[blk][12] <= counter + blk;
                            working_state[blk][13] <= adjust_endianness(nonce[31:0]);
                            working_state[blk][14] <= adjust_endianness(nonce[63:32]);
                            working_state[blk][15] <= adjust_endianness(nonce[95:64]);
                        end
                    end
                    
                    // Setup for first half of rounds
                    double_round_counter <= 5'd0;
                    process_column_round <= 1'b1;
                    pipeline_stage <= 3'd0;
                    qr_index <= 5'd0;
                    qr_block_index <= 3'd0;
                    qr_is_diagonal <= 1'b0;
                    state <= ROUNDS_1_TO_10;
                end
                
                ROUNDS_1_TO_10, ROUNDS_11_TO_20: begin
                    if (RESOURCE_OPTIMIZE == 0) begin
                        // HIGH PERFORMANCE MODE
                        // Original high-performance implementation
                        pipeline_stage <= pipeline_stage + 1;
                        
                        // Wait for pipeline stages to complete
                        if (pipeline_stage >= PIPELINE_STAGES) begin
                            pipeline_stage <= 3'd0;
                            
                            // Process all active blocks in parallel
                            for (blk = 0; blk < MAX_PARALLEL_BLOCKS; blk = blk + 1) begin
                                if (blk < num_blocks) begin
                                    if (process_column_round) begin
                                        // Column round results
                                        for (qr = 0; qr < 4; qr = qr + 1) begin
                                            for (out_idx = 0; out_idx < 4; out_idx = out_idx + 1) begin
                                                if (qr == 0) begin
                                                    working_state[blk][out_idx == 0 ? COL_IDX_0_0 : out_idx == 1 ? COL_IDX_0_1 : out_idx == 2 ? COL_IDX_0_2 : COL_IDX_0_3] <= col_qr_out[blk][qr][out_idx];
                                                end else if (qr == 1) begin
                                                    working_state[blk][out_idx == 0 ? COL_IDX_1_0 : out_idx == 1 ? COL_IDX_1_1 : out_idx == 2 ? COL_IDX_1_2 : COL_IDX_1_3] <= col_qr_out[blk][qr][out_idx];
                                                end else if (qr == 2) begin
                                                    working_state[blk][out_idx == 0 ? COL_IDX_2_0 : out_idx == 1 ? COL_IDX_2_1 : out_idx == 2 ? COL_IDX_2_2 : COL_IDX_2_3] <= col_qr_out[blk][qr][out_idx];
                                                end else begin
                                                    working_state[blk][out_idx == 0 ? COL_IDX_3_0 : out_idx == 1 ? COL_IDX_3_1 : out_idx == 2 ? COL_IDX_3_2 : COL_IDX_3_3] <= col_qr_out[blk][qr][out_idx];
                                                end
                                            end
                                        end
                                    end else begin
                                        // Diagonal round results
                                        for (qr = 0; qr < 4; qr = qr + 1) begin
                                            for (out_idx = 0; out_idx < 4; out_idx = out_idx + 1) begin
                                                if (qr == 0) begin
                                                    working_state[blk][out_idx == 0 ? DIAG_IDX_0_0 : out_idx == 1 ? DIAG_IDX_0_1 : out_idx == 2 ? DIAG_IDX_0_2 : DIAG_IDX_0_3] <= diag_qr_out[blk][qr][out_idx];
                                                end else if (qr == 1) begin
                                                    working_state[blk][out_idx == 0 ? DIAG_IDX_1_0 : out_idx == 1 ? DIAG_IDX_1_1 : out_idx == 2 ? DIAG_IDX_1_2 : DIAG_IDX_1_3] <= diag_qr_out[blk][qr][out_idx];
                                                end else if (qr == 2) begin
                                                    working_state[blk][out_idx == 0 ? DIAG_IDX_2_0 : out_idx == 1 ? DIAG_IDX_2_1 : out_idx == 2 ? DIAG_IDX_2_2 : DIAG_IDX_2_3] <= diag_qr_out[blk][qr][out_idx];
                                                end else begin
                                                    working_state[blk][out_idx == 0 ? DIAG_IDX_3_0 : out_idx == 1 ? DIAG_IDX_3_1 : out_idx == 2 ? DIAG_IDX_3_2 : DIAG_IDX_3_3] <= diag_qr_out[blk][qr][out_idx];
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                            
                            // Toggle between column and diagonal rounds
                            if (!process_column_round) begin
                                // Increment double round counter after diagonal round
                                double_round_counter <= double_round_counter + 5'd1;
                            end
                            process_column_round <= ~process_column_round;
                            
                            // Check for round completion
                            if (state == ROUNDS_1_TO_10 && !process_column_round && double_round_counter == 5'd4) begin
                                // Move to second half
                                state <= ROUNDS_11_TO_20;
                                double_round_counter <= 5'd0;
                            end else if (state == ROUNDS_11_TO_20 && !process_column_round && double_round_counter == 5'd4) begin
                                // All 20 rounds complete
                                state <= FINALIZE;
                            end
                        end
                    end
                    else begin
                        // RESOURCE OPTIMIZED MODE
                        // Select inputs for the shared quarter round module
                        if (process_column_round) begin
                            // Column round inputs
                            if (qr_index == 0) begin
                                qr_inputs[0] <= working_state[qr_block_index][COL_IDX_0_0];
                                qr_inputs[1] <= working_state[qr_block_index][COL_IDX_0_1];
                                qr_inputs[2] <= working_state[qr_block_index][COL_IDX_0_2];
                                qr_inputs[3] <= working_state[qr_block_index][COL_IDX_0_3];
                            end else if (qr_index == 1) begin
                                qr_inputs[0] <= working_state[qr_block_index][COL_IDX_1_0];
                                qr_inputs[1] <= working_state[qr_block_index][COL_IDX_1_1];
                                qr_inputs[2] <= working_state[qr_block_index][COL_IDX_1_2];
                                qr_inputs[3] <= working_state[qr_block_index][COL_IDX_1_3];
                            end else if (qr_index == 2) begin
                                qr_inputs[0] <= working_state[qr_block_index][COL_IDX_2_0];
                                qr_inputs[1] <= working_state[qr_block_index][COL_IDX_2_1];
                                qr_inputs[2] <= working_state[qr_block_index][COL_IDX_2_2];
                                qr_inputs[3] <= working_state[qr_block_index][COL_IDX_2_3];
                            end else begin
                                qr_inputs[0] <= working_state[qr_block_index][COL_IDX_3_0];
                                qr_inputs[1] <= working_state[qr_block_index][COL_IDX_3_1];
                                qr_inputs[2] <= working_state[qr_block_index][COL_IDX_3_2];
                                qr_inputs[3] <= working_state[qr_block_index][COL_IDX_3_3];
                            end
                            qr_is_diagonal <= 1'b0;
                        end else begin
                            // Diagonal round inputs
                            if (qr_index == 0) begin
                                qr_inputs[0] <= working_state[qr_block_index][DIAG_IDX_0_0];
                                qr_inputs[1] <= working_state[qr_block_index][DIAG_IDX_0_1];
                                qr_inputs[2] <= working_state[qr_block_index][DIAG_IDX_0_2];
                                qr_inputs[3] <= working_state[qr_block_index][DIAG_IDX_0_3];
                            end else if (qr_index == 1) begin
                                qr_inputs[0] <= working_state[qr_block_index][DIAG_IDX_1_0];
                                qr_inputs[1] <= working_state[qr_block_index][DIAG_IDX_1_1];
                                qr_inputs[2] <= working_state[qr_block_index][DIAG_IDX_1_2];
                                qr_inputs[3] <= working_state[qr_block_index][DIAG_IDX_1_3];
                            end else if (qr_index == 2) begin
                                qr_inputs[0] <= working_state[qr_block_index][DIAG_IDX_2_0];
                                qr_inputs[1] <= working_state[qr_block_index][DIAG_IDX_2_1];
                                qr_inputs[2] <= working_state[qr_block_index][DIAG_IDX_2_2];
                                qr_inputs[3] <= working_state[qr_block_index][DIAG_IDX_2_3];
                            end else begin
                                qr_inputs[0] <= working_state[qr_block_index][DIAG_IDX_3_0];
                                qr_inputs[1] <= working_state[qr_block_index][DIAG_IDX_3_1];
                                qr_inputs[2] <= working_state[qr_block_index][DIAG_IDX_3_2];
                                qr_inputs[3] <= working_state[qr_block_index][DIAG_IDX_3_3];
                            end
                            qr_is_diagonal <= 1'b1;
                        end
                        
                        // Manage pipeline stages
                        pipeline_stage <= pipeline_stage + 1;
                        
                        // Wait for pipeline to complete, then update state
                        if (pipeline_stage >= PIPELINE_STAGES) begin
                            pipeline_stage <= 3'd0;
                            
                            // Store quarter round results
                            if (qr_is_diagonal) begin
                                // Update diagonal round results
                                if (qr_index == 0) begin
                                    working_state[qr_block_index][DIAG_IDX_0_0] <= qr_outputs[0];
                                    working_state[qr_block_index][DIAG_IDX_0_1] <= qr_outputs[1];
                                    working_state[qr_block_index][DIAG_IDX_0_2] <= qr_outputs[2];
                                    working_state[qr_block_index][DIAG_IDX_0_3] <= qr_outputs[3];
                                end else if (qr_index == 1) begin
                                    working_state[qr_block_index][DIAG_IDX_1_0] <= qr_outputs[0];
                                    working_state[qr_block_index][DIAG_IDX_1_1] <= qr_outputs[1];
                                    working_state[qr_block_index][DIAG_IDX_1_2] <= qr_outputs[2];
                                    working_state[qr_block_index][DIAG_IDX_1_3] <= qr_outputs[3];
                                end else if (qr_index == 2) begin
                                    working_state[qr_block_index][DIAG_IDX_2_0] <= qr_outputs[0];
                                    working_state[qr_block_index][DIAG_IDX_2_1] <= qr_outputs[1];
                                    working_state[qr_block_index][DIAG_IDX_2_2] <= qr_outputs[2];
                                    working_state[qr_block_index][DIAG_IDX_2_3] <= qr_outputs[3];
                                end else begin
                                    working_state[qr_block_index][DIAG_IDX_3_0] <= qr_outputs[0];
                                    working_state[qr_block_index][DIAG_IDX_3_1] <= qr_outputs[1];
                                    working_state[qr_block_index][DIAG_IDX_3_2] <= qr_outputs[2];
                                    working_state[qr_block_index][DIAG_IDX_3_3] <= qr_outputs[3];
                                end
                            end else begin
                                // Update column round results
                                if (qr_index == 0) begin
                                    working_state[qr_block_index][COL_IDX_0_0] <= qr_outputs[0];
                                    working_state[qr_block_index][COL_IDX_0_1] <= qr_outputs[1];
                                    working_state[qr_block_index][COL_IDX_0_2] <= qr_outputs[2];
                                    working_state[qr_block_index][COL_IDX_0_3] <= qr_outputs[3];
                                end else if (qr_index == 1) begin
                                    working_state[qr_block_index][COL_IDX_1_0] <= qr_outputs[0];
                                    working_state[qr_block_index][COL_IDX_1_1] <= qr_outputs[1];
                                    working_state[qr_block_index][COL_IDX_1_2] <= qr_outputs[2];
                                    working_state[qr_block_index][COL_IDX_1_3] <= qr_outputs[3];
                                end else if (qr_index == 2) begin
                                    working_state[qr_block_index][COL_IDX_2_0] <= qr_outputs[0];
                                    working_state[qr_block_index][COL_IDX_2_1] <= qr_outputs[1];
                                    working_state[qr_block_index][COL_IDX_2_2] <= qr_outputs[2];
                                    working_state[qr_block_index][COL_IDX_2_3] <= qr_outputs[3];
                                end else begin
                                    working_state[qr_block_index][COL_IDX_3_0] <= qr_outputs[0];
                                    working_state[qr_block_index][COL_IDX_3_1] <= qr_outputs[1];
                                    working_state[qr_block_index][COL_IDX_3_2] <= qr_outputs[2];
                                    working_state[qr_block_index][COL_IDX_3_3] <= qr_outputs[3];
                                end
                            end
                            
                            // Move to the next quarter round
                            qr_index <= qr_index + 1;
                            
                            if (qr_index == 3) begin
                                qr_index <= 0;
                                qr_block_index <= qr_block_index + 1;
                                
                                if (qr_block_index == num_blocks - 1) begin
                                    qr_block_index <= 0;
                                    
                                    // Toggle between column and diagonal rounds
                                    process_column_round <= ~process_column_round;
                                    
                                    if (!process_column_round) begin
                                        // Increment double round counter after diagonal round
                                        double_round_counter <= double_round_counter + 1;
                                        
                                        // Check for round completion
                                        if (state == ROUNDS_1_TO_10 && double_round_counter == 4) begin
                                            // Move to second half
                                            state <= ROUNDS_11_TO_20;
                                            double_round_counter <= 0;
                                        end else if (state == ROUNDS_11_TO_20 && double_round_counter == 4) begin
                                            // All 20 rounds complete
                                            state <= FINALIZE;
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                
                FINALIZE: begin
                    // Calculate final keystream blocks for all active blocks
                    keystream_blocks <= 2048'd0; // Clear first
                    
                    for (blk = 0; blk < MAX_PARALLEL_BLOCKS; blk = blk + 1) begin
                        if (blk < num_blocks) begin
                            for (word_idx = 0; word_idx < 16; word_idx = word_idx + 1) begin
                                keystream_blocks[blk*512 + word_idx*32 +: 32] <= 
                                    initial_state[blk][word_idx] + working_state[blk][word_idx];
                            end
                        end
                    end

                    done <= 1'b1;
                    state <= IDLE;
                end
                
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
