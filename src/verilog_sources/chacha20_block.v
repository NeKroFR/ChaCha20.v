module chacha20_block (
    input clk,                          // Clock signal
    input rst_n,                        // Active low reset
    input start,                        // Start signal
    input [255:0] key,                  // 32 bytes key
    input [31:0] counter,               // 4 bytes counter
    input [95:0] nonce,                 // 12 bytes nonce
    output reg [511:0] keystream_block, // 64 bytes keystream block
    output reg done
);
    // Define constants
    localparam [31:0] CONST_0 = 32'h61707865; // "expa"
    localparam [31:0] CONST_1 = 32'h3320646e; // "nd 3"
    localparam [31:0] CONST_2 = 32'h79622d32; // "2-by"
    localparam [31:0] CONST_3 = 32'h6b206574; // "te k"

    // Define states
    localparam IDLE = 2'b00;
    localparam PROCESSING = 2'b01;
    localparam FINALIZE = 2'b10;
    reg [1:0] state;

    
    // Pipeline control
    reg [4:0] round_counter;
    reg round_type; // 0 = column round, 1 = diagonal round
    
    // Track pipeline progress
    reg processing_active;
    reg [5:0] pipeline_position;
    
    // State arrays (16 x 32-bits words)
    reg [31:0] initial_state [0:15];
    reg [31:0] working_state [0:15];
    
    // Column Round Quarter Round Instances (4 parallel units)
    // QR1: State[0, 4, 8, 12]
    wire [31:0] col_qr0_a_in, col_qr0_b_in, col_qr0_c_in, col_qr0_d_in;
    wire [31:0] col_qr0_a_out, col_qr0_b_out, col_qr0_c_out, col_qr0_d_out;
    
    // QR2: State[1, 5, 9, 13]
    wire [31:0] col_qr1_a_in, col_qr1_b_in, col_qr1_c_in, col_qr1_d_in;
    wire [31:0] col_qr1_a_out, col_qr1_b_out, col_qr1_c_out, col_qr1_d_out;
    
    // QR3: State[2, 6, 10, 14]
    wire [31:0] col_qr2_a_in, col_qr2_b_in, col_qr2_c_in, col_qr2_d_in;
    wire [31:0] col_qr2_a_out, col_qr2_b_out, col_qr2_c_out, col_qr2_d_out;
    
    // QR4: State[3, 7, 11, 15]
    wire [31:0] col_qr3_a_in, col_qr3_b_in, col_qr3_c_in, col_qr3_d_in;
    wire [31:0] col_qr3_a_out, col_qr3_b_out, col_qr3_c_out, col_qr3_d_out;


    // Column round input connections
    assign col_qr0_a_in = working_state[0];
    assign col_qr0_b_in = working_state[4];
    assign col_qr0_c_in = working_state[8];
    assign col_qr0_d_in = working_state[12];
    
    assign col_qr1_a_in = working_state[1];
    assign col_qr1_b_in = working_state[5];
    assign col_qr1_c_in = working_state[9];
    assign col_qr1_d_in = working_state[13];
    
    assign col_qr2_a_in = working_state[2];
    assign col_qr2_b_in = working_state[6];
    assign col_qr2_c_in = working_state[10];
    assign col_qr2_d_in = working_state[14];
    
    assign col_qr3_a_in = working_state[3];
    assign col_qr3_b_in = working_state[7];
    assign col_qr3_c_in = working_state[11];
    assign col_qr3_d_in = working_state[15];


    // Diagonal Round Quarter Round Instances (4 parallel units)
    // QR1: State[0, 5, 10, 15]
    wire [31:0] diag_qr0_a_in, diag_qr0_b_in, diag_qr0_c_in, diag_qr0_d_in;
    wire [31:0] diag_qr0_a_out, diag_qr0_b_out, diag_qr0_c_out, diag_qr0_d_out;
    
    // QR2: State[1, 6, 11, 12]
    wire [31:0] diag_qr1_a_in, diag_qr1_b_in, diag_qr1_c_in, diag_qr1_d_in;
    wire [31:0] diag_qr1_a_out, diag_qr1_b_out, diag_qr1_c_out, diag_qr1_d_out;
    
    // QR3: State[2, 7, 8, 13]
    wire [31:0] diag_qr2_a_in, diag_qr2_b_in, diag_qr2_c_in, diag_qr2_d_in;
    wire [31:0] diag_qr2_a_out, diag_qr2_b_out, diag_qr2_c_out, diag_qr2_d_out;
    
    // QR4: State[3, 4, 9, 14]
    wire [31:0] diag_qr3_a_in, diag_qr3_b_in, diag_qr3_c_in, diag_qr3_d_in;
    wire [31:0] diag_qr3_a_out, diag_qr3_b_out, diag_qr3_c_out, diag_qr3_d_out;
    

    // Diagonal round input connections
    assign diag_qr0_a_in = working_state[0];
    assign diag_qr0_b_in = working_state[5];
    assign diag_qr0_c_in = working_state[10];
    assign diag_qr0_d_in = working_state[15];
    
    assign diag_qr1_a_in = working_state[1];
    assign diag_qr1_b_in = working_state[6];
    assign diag_qr1_c_in = working_state[11];
    assign diag_qr1_d_in = working_state[12];
    
    assign diag_qr2_a_in = working_state[2];
    assign diag_qr2_b_in = working_state[7];
    assign diag_qr2_c_in = working_state[8];
    assign diag_qr2_d_in = working_state[13];
    
    assign diag_qr3_a_in = working_state[3];
    assign diag_qr3_b_in = working_state[4];
    assign diag_qr3_c_in = working_state[9];
    assign diag_qr3_d_in = working_state[14];
    

    // Output selection based on round type
    wire [31:0] qr0_a_out = round_type ? diag_qr0_a_out : col_qr0_a_out;
    wire [31:0] qr0_b_out = round_type ? diag_qr0_b_out : col_qr0_b_out;
    wire [31:0] qr0_c_out = round_type ? diag_qr0_c_out : col_qr0_c_out;
    wire [31:0] qr0_d_out = round_type ? diag_qr0_d_out : col_qr0_d_out;
    
    wire [31:0] qr1_a_out = round_type ? diag_qr1_a_out : col_qr1_a_out;
    wire [31:0] qr1_b_out = round_type ? diag_qr1_b_out : col_qr1_b_out;
    wire [31:0] qr1_c_out = round_type ? diag_qr1_c_out : col_qr1_c_out;
    wire [31:0] qr1_d_out = round_type ? diag_qr1_d_out : col_qr1_d_out;
    
    wire [31:0] qr2_a_out = round_type ? diag_qr2_a_out : col_qr2_a_out;
    wire [31:0] qr2_b_out = round_type ? diag_qr2_b_out : col_qr2_b_out;
    wire [31:0] qr2_c_out = round_type ? diag_qr2_c_out : col_qr2_c_out;
    wire [31:0] qr2_d_out = round_type ? diag_qr2_d_out : col_qr2_d_out;
    
    wire [31:0] qr3_a_out = round_type ? diag_qr3_a_out : col_qr3_a_out;
    wire [31:0] qr3_b_out = round_type ? diag_qr3_b_out : col_qr3_b_out;
    wire [31:0] qr3_c_out = round_type ? diag_qr3_c_out : col_qr3_c_out;
    wire [31:0] qr3_d_out = round_type ? diag_qr3_d_out : col_qr3_d_out;
    
    // Instantiate column round quarter round modules
    quarter_round col_qr0 (
        .clk(clk),
        .rst_n(rst_n),
        .a_in(col_qr0_a_in),
        .b_in(col_qr0_b_in),
        .c_in(col_qr0_c_in),
        .d_in(col_qr0_d_in),
        .a_out(col_qr0_a_out),
        .b_out(col_qr0_b_out),
        .c_out(col_qr0_c_out),
        .d_out(col_qr0_d_out)
    );
    
    quarter_round col_qr1 (
        .clk(clk),
        .rst_n(rst_n),
        .a_in(col_qr1_a_in),
        .b_in(col_qr1_b_in),
        .c_in(col_qr1_c_in),
        .d_in(col_qr1_d_in),
        .a_out(col_qr1_a_out),
        .b_out(col_qr1_b_out),
        .c_out(col_qr1_c_out),
        .d_out(col_qr1_d_out)
    );
    
    quarter_round col_qr2 (
        .clk(clk),
        .rst_n(rst_n),
        .a_in(col_qr2_a_in),
        .b_in(col_qr2_b_in),
        .c_in(col_qr2_c_in),
        .d_in(col_qr2_d_in),
        .a_out(col_qr2_a_out),
        .b_out(col_qr2_b_out),
        .c_out(col_qr2_c_out),
        .d_out(col_qr2_d_out)
    );
    
    quarter_round col_qr3 (
        .clk(clk),
        .rst_n(rst_n),
        .a_in(col_qr3_a_in),
        .b_in(col_qr3_b_in),
        .c_in(col_qr3_c_in),
        .d_in(col_qr3_d_in),
        .a_out(col_qr3_a_out),
        .b_out(col_qr3_b_out),
        .c_out(col_qr3_c_out),
        .d_out(col_qr3_d_out)
    );
    
    // Instantiate diagonal round quarter round modules
    quarter_round diag_qr0 (
        .clk(clk),
        .rst_n(rst_n),
        .a_in(diag_qr0_a_in),
        .b_in(diag_qr0_b_in),
        .c_in(diag_qr0_c_in),
        .d_in(diag_qr0_d_in),
        .a_out(diag_qr0_a_out),
        .b_out(diag_qr0_b_out),
        .c_out(diag_qr0_c_out),
        .d_out(diag_qr0_d_out)
    );
    
    quarter_round diag_qr1 (
        .clk(clk),
        .rst_n(rst_n),
        .a_in(diag_qr1_a_in),
        .b_in(diag_qr1_b_in),
        .c_in(diag_qr1_c_in),
        .d_in(diag_qr1_d_in),
        .a_out(diag_qr1_a_out),
        .b_out(diag_qr1_b_out),
        .c_out(diag_qr1_c_out),
        .d_out(diag_qr1_d_out)
    );
    
    quarter_round diag_qr2 (
        .clk(clk),
        .rst_n(rst_n),
        .a_in(diag_qr2_a_in),
        .b_in(diag_qr2_b_in),
        .c_in(diag_qr2_c_in),
        .d_in(diag_qr2_d_in),
        .a_out(diag_qr2_a_out),
        .b_out(diag_qr2_b_out),
        .c_out(diag_qr2_c_out),
        .d_out(diag_qr2_d_out)
    );
    
    quarter_round diag_qr3 (
        .clk(clk),
        .rst_n(rst_n),
        .a_in(diag_qr3_a_in),
        .b_in(diag_qr3_b_in),
        .c_in(diag_qr3_c_in),
        .d_in(diag_qr3_d_in),
        .a_out(diag_qr3_a_out),
        .b_out(diag_qr3_b_out),
        .c_out(diag_qr3_c_out),
        .d_out(diag_qr3_d_out)
    );
    
    // Pipeline delay calculation (2 cycles for QR)
    localparam QR_DELAY = 2;
    
    // State machine for ChaCha20 block function
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 1'b0;
            round_counter <= 5'd0;
            round_type <= 1'b0; // Column round
            processing_active <= 1'b0;
            pipeline_position <= 6'd0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    
                    if (start) begin
                        // Initialize state
                        initial_state[0] <= CONST_0;
                        initial_state[1] <= CONST_1;
                        initial_state[2] <= CONST_2;
                        initial_state[3] <= CONST_3;
                        
                        // Key (8 words)
                        initial_state[4] <= {key[7:0], key[15:8], key[23:16], key[31:24]};
                        initial_state[5] <= {key[39:32], key[47:40], key[55:48], key[63:56]};
                        initial_state[6] <= {key[71:64], key[79:72], key[87:80], key[95:88]};
                        initial_state[7] <= {key[103:96], key[111:104], key[119:112], key[127:120]};
                        initial_state[8] <= {key[135:128], key[143:136], key[151:144], key[159:152]};
                        initial_state[9] <= {key[167:160], key[175:168], key[183:176], key[191:184]};
                        initial_state[10] <= {key[199:192], key[207:200], key[215:208], key[223:216]};
                        initial_state[11] <= {key[231:224], key[239:232], key[247:240], key[255:248]};
                        
                        // Counter (1 word)
                        initial_state[12] <= counter;
                        
                        // Nonce (3 words)
                        initial_state[13] <= {nonce[7:0], nonce[15:8], nonce[23:16], nonce[31:24]};
                        initial_state[14] <= {nonce[39:32], nonce[47:40], nonce[55:48], nonce[63:56]};
                        initial_state[15] <= {nonce[71:64], nonce[79:72], nonce[87:80], nonce[95:88]};
                        
                        // Copy initial state to working state
                        working_state[0] <= CONST_0;
                        working_state[1] <= CONST_1;
                        working_state[2] <= CONST_2;
                        working_state[3] <= CONST_3;
                        working_state[4] <= {key[7:0], key[15:8], key[23:16], key[31:24]};
                        working_state[5] <= {key[39:32], key[47:40], key[55:48], key[63:56]};
                        working_state[6] <= {key[71:64], key[79:72], key[87:80], key[95:88]};
                        working_state[7] <= {key[103:96], key[111:104], key[119:112], key[127:120]};
                        working_state[8] <= {key[135:128], key[143:136], key[151:144], key[159:152]};
                        working_state[9] <= {key[167:160], key[175:168], key[183:176], key[191:184]};
                        working_state[10] <= {key[199:192], key[207:200], key[215:208], key[223:216]};
                        working_state[11] <= {key[231:224], key[239:232], key[247:240], key[255:248]};
                        working_state[12] <= counter;
                        working_state[13] <= {nonce[7:0], nonce[15:8], nonce[23:16], nonce[31:24]};
                        working_state[14] <= {nonce[39:32], nonce[47:40], nonce[55:48], nonce[63:56]};
                        working_state[15] <= {nonce[71:64], nonce[79:72], nonce[87:80], nonce[95:88]};
                        
                        round_counter <= 5'd0;
                        round_type <= 1'b0; // Column round
                        processing_active <= 1'b1;
                        pipeline_position <= 6'd0;
                        state <= PROCESSING;
                    end
                end
                
                PROCESSING: begin
                    if (processing_active) begin
                        pipeline_position <= pipeline_position + 6'd1;

                        if (pipeline_position >= QR_DELAY) begin
                            if (round_type == 1'b0) begin // Column round results
                                working_state[0] <= qr0_a_out;
                                working_state[4] <= qr0_b_out;
                                working_state[8] <= qr0_c_out;
                                working_state[12] <= qr0_d_out;
                                
                                working_state[1] <= qr1_a_out;
                                working_state[5] <= qr1_b_out;
                                working_state[9] <= qr1_c_out;
                                working_state[13] <= qr1_d_out;
                                
                                working_state[2] <= qr2_a_out;
                                working_state[6] <= qr2_b_out;
                                working_state[10] <= qr2_c_out;
                                working_state[14] <= qr2_d_out;
                                
                                working_state[3] <= qr3_a_out;
                                working_state[7] <= qr3_b_out;
                                working_state[11] <= qr3_c_out;
                                working_state[15] <= qr3_d_out;
                            end
                            else begin // Diagonal round results
                                working_state[0] <= qr0_a_out;
                                working_state[5] <= qr0_b_out;
                                working_state[10] <= qr0_c_out;
                                working_state[15] <= qr0_d_out;
                                
                                working_state[1] <= qr1_a_out;
                                working_state[6] <= qr1_b_out;
                                working_state[11] <= qr1_c_out;
                                working_state[12] <= qr1_d_out;
                                
                                working_state[2] <= qr2_a_out;
                                working_state[7] <= qr2_b_out;
                                working_state[8] <= qr2_c_out;
                                working_state[13] <= qr2_d_out;
                                
                                working_state[3] <= qr3_a_out;
                                working_state[4] <= qr3_b_out;
                                working_state[9] <= qr3_c_out;
                                working_state[14] <= qr3_d_out;
                                
                                round_counter <= round_counter + 5'd1;
                            end
                            
                            // Toggle round type for next iteration
                            round_type <= ~round_type;
                            
                            // Reset pipeline position for next round
                            pipeline_position <= 6'd0;
                            
                            // Check if we've completed all rounds
                            if (round_counter == 5'd9 && round_type == 1'b1) begin
                                processing_active <= 1'b0;
                                state <= FINALIZE;
                            end
                        end
                    end
                end
                
                FINALIZE: begin
                    // Add initial state to working state for final output
                    keystream_block[31:0] <= initial_state[0] + working_state[0];
                    keystream_block[63:32] <= initial_state[1] + working_state[1];
                    keystream_block[95:64] <= initial_state[2] + working_state[2];
                    keystream_block[127:96] <= initial_state[3] + working_state[3];
                    keystream_block[159:128] <= initial_state[4] + working_state[4];
                    keystream_block[191:160] <= initial_state[5] + working_state[5];
                    keystream_block[223:192] <= initial_state[6] + working_state[6];
                    keystream_block[255:224] <= initial_state[7] + working_state[7];
                    keystream_block[287:256] <= initial_state[8] + working_state[8];
                    keystream_block[319:288] <= initial_state[9] + working_state[9];
                    keystream_block[351:320] <= initial_state[10] + working_state[10];
                    keystream_block[383:352] <= initial_state[11] + working_state[11];
                    keystream_block[415:384] <= initial_state[12] + working_state[12];
                    keystream_block[447:416] <= initial_state[13] + working_state[13];
                    keystream_block[479:448] <= initial_state[14] + working_state[14];
                    keystream_block[511:480] <= initial_state[15] + working_state[15];
                    
                    done <= 1'b1;
                    state <= IDLE;
                end
                
                default: begin
                    state <= IDLE;  // reset IDLE if in an unknown state
                end
            endcase
        end
    end
endmodule
