module chacha20_block (
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
    localparam [31:0] CONST_0 = 32'h61707865;
    localparam [31:0] CONST_1 = 32'h3320646e; // "nd 3"
    localparam [31:0] CONST_2 = 32'h79622d32; // "2-by"
    localparam [31:0] CONST_3 = 32'h6b206574; // "te k"

    // Define states
    localparam IDLE = 3'b000;
    localparam INIT = 3'b001;
    localparam ROUNDS_1_TO_10 = 3'b010;   // First 10 rounds (5 double-rounds)
    localparam ROUNDS_11_TO_20 = 3'b011;  // Second 10 rounds (5 double-rounds)
    localparam FINALIZE = 3'b100;         // Add initial state to working state
    
    reg [2:0] state;
    reg [4:0] double_round_counter;     // Up to 10 double rounds (20 rounds)
    reg process_column_round;           // 0 for column round, 1 for diagonal round
    
    // Number of parallel blocks to process (1, 2, or 4)
    reg [3:0] num_blocks;
    
    // State for up to 4 parallel blocks
    reg [31:0] initial_state [0:3][0:15];
    reg [31:0] working_state [0:3][0:15];
    
    // Pipeline tracking
    reg [1:0] pipeline_stage;
    localparam PIPELINE_DELAY = 2; // 2 cycles for QR processing
    
    // Array-based connection wires for quarter rounds
    // Use 2D arrays for inputs and outputs: [qr_index][a/b/c/d]
    wire [31:0] col_qr_in [0:3][0:3];   // [qr_module_index][a/b/c/d]
    wire [31:0] col_qr_out [0:3][0:3];  // [qr_module_index][a/b/c/d]
    wire [31:0] diag_qr_in [0:3][0:3];  // [qr_module_index][a/b/c/d]
    wire [31:0] diag_qr_out [0:3][0:3]; // [qr_module_index][a/b/c/d]
    
    // Define lookup tables for column and diagonal indices
    // These represent the state indices that feed into each quarter round
    localparam integer COL_IDX [0:3][0:3] = '{
        '{0, 4, 8, 12},     // QR0 inputs come from these state indices
        '{1, 5, 9, 13},     // QR1 inputs come from these state indices
        '{2, 6, 10, 14},    // QR2 inputs come from these state indices
        '{3, 7, 11, 15}     // QR3 inputs come from these state indices
    };
    
    localparam integer DIAG_IDX [0:3][0:3] = '{
        '{0, 5, 10, 15},    // QR0 inputs come from these state indices
        '{1, 6, 11, 12},    // QR1 inputs come from these state indices
        '{2, 7, 8, 13},     // QR2 inputs come from these state indices
        '{3, 4, 9, 14}      // QR3 inputs come from these state indices
    };
    
    // Generate column round connections using nested loops
    genvar i, j;
    generate
        for (i = 0; i < 4; i = i + 1) begin : col_qr_inputs
            for (j = 0; j < 4; j = j + 1) begin : col_inputs
                assign col_qr_in[i][j] = working_state[0][COL_IDX[i][j]];
            end
        end
    
        // Generate diagonal round connections using nested loops
        for (i = 0; i < 4; i = i + 1) begin : diag_qr_inputs
            for (j = 0; j < 4; j = j + 1) begin : diag_inputs
                assign diag_qr_in[i][j] = working_state[0][DIAG_IDX[i][j]];
            end
        end
    endgenerate
    
    // Instantiate quarter round modules using generate statement
    genvar qr_idx;
    generate
        for (qr_idx = 0; qr_idx < 4; qr_idx = qr_idx + 1) begin : qr_modules
            quarter_round col_qr (
                .clk(clk),
                .rst_n(rst_n),
                .a_in(col_qr_in[qr_idx][0]),
                .b_in(col_qr_in[qr_idx][1]),
                .c_in(col_qr_in[qr_idx][2]),
                .d_in(col_qr_in[qr_idx][3]),
                .a_out(col_qr_out[qr_idx][0]),
                .b_out(col_qr_out[qr_idx][1]),
                .c_out(col_qr_out[qr_idx][2]),
                .d_out(col_qr_out[qr_idx][3])
            );
            
            quarter_round diag_qr (
                .clk(clk),
                .rst_n(rst_n),
                .a_in(diag_qr_in[qr_idx][0]),
                .b_in(diag_qr_in[qr_idx][1]),
                .c_in(diag_qr_in[qr_idx][2]),
                .d_in(diag_qr_in[qr_idx][3]),
                .a_out(diag_qr_out[qr_idx][0]),
                .b_out(diag_qr_out[qr_idx][1]),
                .c_out(diag_qr_out[qr_idx][2]),
                .d_out(diag_qr_out[qr_idx][3])
            );
        end
    endgenerate
    
    // Define mappings between column QR outputs and state matrix indices
    localparam integer COL_OUT_MAP [0:3][0:3] = '{
        '{0, 4, 8, 12},    // QR0 output goes to these state indices
        '{1, 5, 9, 13},    // QR1 output goes to these state indices
        '{2, 6, 10, 14},   // QR2 output goes to these state indices
        '{3, 7, 11, 15}    // QR3 output goes to these state indices
    };
    
    localparam integer DIAG_OUT_MAP [0:3][0:3] = '{
        '{0, 5, 10, 15},   // QR0 output goes to these state indices
        '{1, 6, 11, 12},   // QR1 output goes to these state indices
        '{2, 7, 8, 13},    // QR2 output goes to these state indices
        '{3, 4, 9, 14}     // QR3 output goes to these state indices
    };
    
    // Main state machine
    always @(posedge clk or negedge rst_n) begin
        // Declare all variables at the beginning of the procedural block
        integer i, qr, out_idx;
        
        if (!rst_n) begin
            state <= IDLE;
            done <= 1'b0;
            double_round_counter <= 5'd0;
            process_column_round <= 1'b1;
            pipeline_stage <= 2'd0;
            num_blocks <= 4'd1;
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
                    // Initialize state for all blocks in parallel
                    for (i = 0; i < 4; i = i + 1) begin
                        if (i < num_blocks) begin
                            // Initialize constants
                            initial_state[i][0] <= CONST_0;
                            initial_state[i][1] <= CONST_1;
                            initial_state[i][2] <= CONST_2;
                            initial_state[i][3] <= CONST_3;
                            
                            // Initialize key (8 words)
                            initial_state[i][4] <= {key[7:0], key[15:8], key[23:16], key[31:24]};
                            initial_state[i][5] <= {key[39:32], key[47:40], key[55:48], key[63:56]};
                            initial_state[i][6] <= {key[71:64], key[79:72], key[87:80], key[95:88]};
                            initial_state[i][7] <= {key[103:96], key[111:104], key[119:112], key[127:120]};
                            initial_state[i][8] <= {key[135:128], key[143:136], key[151:144], key[159:152]};
                            initial_state[i][9] <= {key[167:160], key[175:168], key[183:176], key[191:184]};
                            initial_state[i][10] <= {key[199:192], key[207:200], key[215:208], key[223:216]};
                            initial_state[i][11] <= {key[231:224], key[239:232], key[247:240], key[255:248]};
                            
                            // Initialize counter (incremented for each block)
                            initial_state[i][12] <= counter + i;
                            
                            // Initialize nonce (3 words)
                            initial_state[i][13] <= {nonce[7:0], nonce[15:8], nonce[23:16], nonce[31:24]};
                            initial_state[i][14] <= {nonce[39:32], nonce[47:40], nonce[55:48], nonce[63:56]};
                            initial_state[i][15] <= {nonce[71:64], nonce[79:72], nonce[87:80], nonce[95:88]};
                            
                            // Copy to working state
                            working_state[i][0] <= CONST_0;
                            working_state[i][1] <= CONST_1;
                            working_state[i][2] <= CONST_2;
                            working_state[i][3] <= CONST_3;
                            working_state[i][4] <= {key[7:0], key[15:8], key[23:16], key[31:24]};
                            working_state[i][5] <= {key[39:32], key[47:40], key[55:48], key[63:56]};
                            working_state[i][6] <= {key[71:64], key[79:72], key[87:80], key[95:88]};
                            working_state[i][7] <= {key[103:96], key[111:104], key[119:112], key[127:120]};
                            working_state[i][8] <= {key[135:128], key[143:136], key[151:144], key[159:152]};
                            working_state[i][9] <= {key[167:160], key[175:168], key[183:176], key[191:184]};
                            working_state[i][10] <= {key[199:192], key[207:200], key[215:208], key[223:216]};
                            working_state[i][11] <= {key[231:224], key[239:232], key[247:240], key[255:248]};
                            working_state[i][12] <= counter + i;
                            working_state[i][13] <= {nonce[7:0], nonce[15:8], nonce[23:16], nonce[31:24]};
                            working_state[i][14] <= {nonce[39:32], nonce[47:40], nonce[55:48], nonce[63:56]};
                            working_state[i][15] <= {nonce[71:64], nonce[79:72], nonce[87:80], nonce[95:88]};
                        end
                    end
                    
                    // Setup for first half of rounds
                    double_round_counter <= 5'd0;
                    process_column_round <= 1'b1;
                    pipeline_stage <= 2'd0;
                    state <= ROUNDS_1_TO_10;
                end
                
                ROUNDS_1_TO_10: begin
                    pipeline_stage <= pipeline_stage + 1;
                    
                    // Wait for pipeline stages to complete
                    if (pipeline_stage >= PIPELINE_DELAY) begin
                        pipeline_stage <= 2'd0;
                        
                        // Update block 0 using array-based indexing
                        if (process_column_round) begin
                            // Column round results
                            for (qr = 0; qr < 4; qr = qr + 1) begin
                                for (out_idx = 0; out_idx < 4; out_idx = out_idx + 1) begin
                                    working_state[0][COL_OUT_MAP[qr][out_idx]] <= col_qr_out[qr][out_idx];
                                end
                            end
                        end else begin
                            // Diagonal round results
                            for (qr = 0; qr < 4; qr = qr + 1) begin
                                for (out_idx = 0; out_idx < 4; out_idx = out_idx + 1) begin
                                    working_state[0][DIAG_OUT_MAP[qr][out_idx]] <= diag_qr_out[qr][out_idx];
                                end
                            end
                            
                            // Increment double round counter after diagonal round
                            double_round_counter <= double_round_counter + 5'd1;
                        end
                        
                        // Toggle between column and diagonal rounds
                        process_column_round <= ~process_column_round;
                        
                        // Move to second half after 5 double rounds (10 rounds total)
                        if (double_round_counter == 5'd5 && !process_column_round) begin
                            state <= ROUNDS_11_TO_20;
                            double_round_counter <= 5'd0;
                        end
                    end
                end
                
                ROUNDS_11_TO_20: begin
                    pipeline_stage <= pipeline_stage + 1;
                    
                    // Wait for pipeline stages to complete
                    if (pipeline_stage >= PIPELINE_DELAY) begin
                        pipeline_stage <= 2'd0;
                        
                        // Update block 0 using array-based indexing (same as ROUNDS_1_TO_10)
                        if (process_column_round) begin
                            // Column round results
                            for (qr = 0; qr < 4; qr = qr + 1) begin
                                for (out_idx = 0; out_idx < 4; out_idx = out_idx + 1) begin
                                    working_state[0][COL_OUT_MAP[qr][out_idx]] <= col_qr_out[qr][out_idx];
                                end
                            end
                        end else begin
                            // Diagonal round results
                            for (qr = 0; qr < 4; qr = qr + 1) begin
                                for (out_idx = 0; out_idx < 4; out_idx = out_idx + 1) begin
                                    working_state[0][DIAG_OUT_MAP[qr][out_idx]] <= diag_qr_out[qr][out_idx];
                                end
                            end
                            
                            double_round_counter <= double_round_counter + 5'd1;
                        end
                        
                        process_column_round <= ~process_column_round;
                        
                        // Finalize after all rounds completed
                        if (double_round_counter == 5'd5 && !process_column_round) begin
                            state <= FINALIZE;
                        end
                    end
                end
                
                FINALIZE: begin
                    // Calculate final keystream blocks
                    
                    // Block 0
                    for (integer w = 0; w < 16; w = w + 1) begin
                        keystream_blocks[32*w +: 32] <= initial_state[0][w] + working_state[0][w];
                    end
                    
                    // Block 1
                    if (num_blocks > 1) begin
                        for (integer w = 0; w < 16; w = w + 1) begin
                            keystream_blocks[512 + 32*w +: 32] <= initial_state[1][w] + working_state[1][w];
                        end
                    end

                    // Block 2
                    if (num_blocks > 2) begin
                        for (integer w = 0; w < 16; w = w + 1) begin
                            keystream_blocks[1024 + 32*w +: 32] <= initial_state[2][w] + working_state[2][w];
                        end
                    end

                    // Block 3
                    if (num_blocks > 3) begin
                        for (integer w = 0; w < 16; w = w + 1) begin
                            keystream_blocks[1536 + 32*w +: 32] <= initial_state[3][w] + working_state[3][w];
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
