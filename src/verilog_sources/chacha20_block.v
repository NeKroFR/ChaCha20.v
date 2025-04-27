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
    localparam IDLE = 3'b000;
    localparam INIT = 3'b001;
    localparam ROUND = 3'b010;
    localparam FINALIZE = 3'b011;
    
    // Registers
    reg [2:0] state;
    reg [4:0] round_counter;
    reg [2:0] qr_counter;
    
    // State arrays (16 x 32-bits words)
    reg [31:0] initial_state [0:15];
    reg [31:0] working_state [0:15];
    
    // Quarter round connections
    reg [3:0] qr_a_idx, qr_b_idx, qr_c_idx, qr_d_idx;
    wire [31:0] qr_a_in, qr_b_in, qr_c_in, qr_d_in;
    wire [31:0] qr_a_out, qr_b_out, qr_c_out, qr_d_out;
    
    // Connect quarter round inputs
    assign qr_a_in = working_state[qr_a_idx];
    assign qr_b_in = working_state[qr_b_idx];
    assign qr_c_in = working_state[qr_c_idx];
    assign qr_d_in = working_state[qr_d_idx];
    
    // Instantiate quarter round
    quarter_round qr (
        .a_in(qr_a_in),
        .b_in(qr_b_in),
        .c_in(qr_c_in),
        .d_in(qr_d_in),
        .a_out(qr_a_out),
        .b_out(qr_b_out),
        .c_out(qr_c_out),
        .d_out(qr_d_out)
    );
    
    // State machine for ChaCha20 block function
    // The state machine handles the initialization, rounds, and finalization
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 1'b0;
            round_counter <= 5'd0;
            qr_counter <= 3'd0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        state <= INIT;
                    end
                end
                
                INIT: begin
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
                    qr_counter <= 3'd0;
                    state <= ROUND;
                end
                
                ROUND: begin
                    if (round_counter < 5'd20) begin
                        if (round_counter[0] == 1'b0) begin // Even -> Column round
                            case (qr_counter)
                                3'd0: begin
                                    // Column 1
                                    qr_a_idx <= 4'd0;
                                    qr_b_idx <= 4'd4;
                                    qr_c_idx <= 4'd8;
                                    qr_d_idx <= 4'd12;
                                    qr_counter <= qr_counter + 3'd1;
                                end
                                3'd1: begin
                                    // Update from previous quarter round
                                    working_state[qr_a_idx] <= qr_a_out;
                                    working_state[qr_b_idx] <= qr_b_out;
                                    working_state[qr_c_idx] <= qr_c_out;
                                    working_state[qr_d_idx] <= qr_d_out;
                                    
                                    // Column 2
                                    qr_a_idx <= 4'd1;
                                    qr_b_idx <= 4'd5;
                                    qr_c_idx <= 4'd9;
                                    qr_d_idx <= 4'd13;
                                    qr_counter <= qr_counter + 3'd1;
                                end
                                3'd2: begin
                                    // Update from previous quarter round
                                    working_state[qr_a_idx] <= qr_a_out;
                                    working_state[qr_b_idx] <= qr_b_out;
                                    working_state[qr_c_idx] <= qr_c_out;
                                    working_state[qr_d_idx] <= qr_d_out;
                                    
                                    // Column 3
                                    qr_a_idx <= 4'd2;
                                    qr_b_idx <= 4'd6;
                                    qr_c_idx <= 4'd10;
                                    qr_d_idx <= 4'd14;
                                    qr_counter <= qr_counter + 3'd1;
                                end
                                3'd3: begin
                                    // Update from previous quarter round
                                    working_state[qr_a_idx] <= qr_a_out;
                                    working_state[qr_b_idx] <= qr_b_out;
                                    working_state[qr_c_idx] <= qr_c_out;
                                    working_state[qr_d_idx] <= qr_d_out;
                                    
                                    // Column 4
                                    qr_a_idx <= 4'd3;
                                    qr_b_idx <= 4'd7;
                                    qr_c_idx <= 4'd11;
                                    qr_d_idx <= 4'd15;
                                    qr_counter <= qr_counter + 3'd1;
                                end
                                3'd4: begin
                                    // Update from previous quarter round
                                    working_state[qr_a_idx] <= qr_a_out;
                                    working_state[qr_b_idx] <= qr_b_out;
                                    working_state[qr_c_idx] <= qr_c_out;
                                    working_state[qr_d_idx] <= qr_d_out;
                                    
                                    // Move to next round
                                    round_counter <= round_counter + 5'd1;
                                    qr_counter <= 3'd0;
                                end
                                default: qr_counter <= 3'd0;
                            endcase
                        end
                        else begin // Odd -> Diagonal round
                            case (qr_counter)
                                3'd0: begin
                                    // Diagonal 1
                                    qr_a_idx <= 4'd0;
                                    qr_b_idx <= 4'd5;
                                    qr_c_idx <= 4'd10;
                                    qr_d_idx <= 4'd15;
                                    qr_counter <= qr_counter + 3'd1;
                                end
                                3'd1: begin
                                    // Update from previous quarter round
                                    working_state[qr_a_idx] <= qr_a_out;
                                    working_state[qr_b_idx] <= qr_b_out;
                                    working_state[qr_c_idx] <= qr_c_out;
                                    working_state[qr_d_idx] <= qr_d_out;
                                    
                                    // Diagonal 2
                                    qr_a_idx <= 4'd1;
                                    qr_b_idx <= 4'd6;
                                    qr_c_idx <= 4'd11;
                                    qr_d_idx <= 4'd12;
                                    qr_counter <= qr_counter + 3'd1;
                                end
                                3'd2: begin
                                    // Update from previous quarter round
                                    working_state[qr_a_idx] <= qr_a_out;
                                    working_state[qr_b_idx] <= qr_b_out;
                                    working_state[qr_c_idx] <= qr_c_out;
                                    working_state[qr_d_idx] <= qr_d_out;
                                    
                                    // Diagonal 3
                                    qr_a_idx <= 4'd2;
                                    qr_b_idx <= 4'd7;
                                    qr_c_idx <= 4'd8;
                                    qr_d_idx <= 4'd13;
                                    qr_counter <= qr_counter + 3'd1;
                                end
                                3'd3: begin
                                    // Update from previous quarter round
                                    working_state[qr_a_idx] <= qr_a_out;
                                    working_state[qr_b_idx] <= qr_b_out;
                                    working_state[qr_c_idx] <= qr_c_out;
                                    working_state[qr_d_idx] <= qr_d_out;
                                    
                                    // Diagonal 4
                                    qr_a_idx <= 4'd3;
                                    qr_b_idx <= 4'd4;
                                    qr_c_idx <= 4'd9;
                                    qr_d_idx <= 4'd14;
                                    qr_counter <= qr_counter + 3'd1;
                                end
                                3'd4: begin
                                    // Update from previous quarter round
                                    working_state[qr_a_idx] <= qr_a_out;
                                    working_state[qr_b_idx] <= qr_b_out;
                                    working_state[qr_c_idx] <= qr_c_out;
                                    working_state[qr_d_idx] <= qr_d_out;
                                    
                                    // Move to next round
                                    round_counter <= round_counter + 5'd1;
                                    qr_counter <= 3'd0;
                                end
                                default: qr_counter <= 3'd0;
                            endcase
                        end
                    end else begin
                        state <= FINALIZE;
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
