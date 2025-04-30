`include "src/verilog_headers/chacha20_defs.vh"

module chacha20_encrypt #(
    parameter MAX_PARALLEL_BLOCKS = `CHACHA20_PARALLEL_BLOCKS,
    parameter DATA_WIDTH_WORDS = 1,
    parameter PIPELINE_STAGES = `CHACHA20_PIPELINE_STAGES,
    parameter RESOURCE_OPTIMIZE = `CHACHA20_RESOURCE_OPTIMIZE,
    parameter ENDIANNESS = `CHACHA20_ENDIANNESS
)(
    input clk,                           // Clock signal
    input rst_n,                         // Active low reset signal
    input start,                         // Start signal
    input [255:0] key,                   // 32 bytes key
    input [31:0] counter,                // 4 bytes counter
    input [95:0] nonce,                  // 12 bytes nonce
    
    input [32*DATA_WIDTH_WORDS-1:0] plaintext_data,  // Input data (configurable width)
    input plaintext_valid,               // Input data valid
    input plaintext_last,                // Last chunk of plaintext
    output plaintext_ready,              // Ready to accept input
    
    output reg [32*DATA_WIDTH_WORDS-1:0] ciphertext_data, // Output data (configurable width)
    output reg ciphertext_valid,         // Output data valid
    output reg ciphertext_last,          // Last chunk of ciphertext
    input ciphertext_ready,              // Downstream is ready to accept
    
    output reg done                      // Encryption complete
);
    // Define states
    localparam IDLE = 3'b000;
    localparam GENERATE_KEYSTREAM = 3'b001;
    localparam PROCESS_DATA = 3'b010;
    localparam WAIT_OUTPUT = 3'b011;
    
    reg [2:0] state;
    reg [31:0] current_counter;
    reg [3:0] block_position;
    
    // Generate keystream blocks
    reg block_start;
    wire block_done;
    reg [1:0] parallel_blocks;       // Number of blocks to generate (1 or 2)
    wire [2047:0] keystream_blocks;  // 2 blocks of 1024 bits each
    reg [1023:0] current_keystream;  // Up to 2 blocks (1024 bits)
    reg block_active;                // Flag to track if keystream is valid
    reg [3:0] active_blocks;         // Number of valid blocks in current_keystream
    
    // Ready signal with backpressure handling
    reg plaintext_ready_reg;
    assign plaintext_ready = plaintext_ready_reg && (state == PROCESS_DATA);
    
    // Instantiate ChaCha20 block function
    chacha20_block #(
        .MAX_PARALLEL_BLOCKS(MAX_PARALLEL_BLOCKS),
        .PIPELINE_STAGES(PIPELINE_STAGES),
        .RESOURCE_OPTIMIZE(RESOURCE_OPTIMIZE),
        .ENDIANNESS(ENDIANNESS)
    ) block_gen (
        .clk(clk),
        .rst_n(rst_n),
        .start(block_start),
        .key(key),
        .counter(current_counter),
        .nonce(nonce),
        .parallel_blocks(parallel_blocks),
        .keystream_blocks(keystream_blocks),
        .done(block_done)
    );

    // State machine for encryption
    always @(posedge clk or negedge rst_n) begin
        integer i;
        if (!rst_n) begin
            state <= IDLE;
            done <= 1'b0;
            plaintext_ready_reg <= 1'b0;
            ciphertext_valid <= 1'b0;
            ciphertext_last <= 1'b0;
            ciphertext_data <= {(32*DATA_WIDTH_WORDS){1'b0}};
            block_start <= 1'b0;
            block_position <= 4'd0;
            parallel_blocks <= 2'b00;
            block_active <= 1'b0;
            active_blocks <= 4'd0;
            current_keystream <= 1024'd0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    ciphertext_valid <= 1'b0;
                    ciphertext_last <= 1'b0;
                    block_active <= 1'b0;
                    
                    if (start) begin
                        current_counter <= counter;
                        block_position <= 4'd0;
                        state <= GENERATE_KEYSTREAM;
                        block_start <= 1'b1;
                        
                        // Always generate 2 blocks at once for efficiency
                        parallel_blocks <= 2'b01;  
                        plaintext_ready_reg <= 1'b0;
                    end else begin
                        plaintext_ready_reg <= 1'b0;
                    end
                end
                
                GENERATE_KEYSTREAM: begin
                    block_start <= 1'b0;
                    
                    if (block_done) begin
                        // Store both keystream blocks
                        current_keystream <= keystream_blocks[1023:0];
                        active_blocks <= parallel_blocks + 1'b1; // Convert 2'b01 to 2
                        block_active <= 1'b1;
                        state <= PROCESS_DATA;
                        plaintext_ready_reg <= 1'b1;
                    end
                end
                
                PROCESS_DATA: begin
                    if (plaintext_valid && plaintext_ready_reg) begin
                        // Enhanced data width processing - XOR multiple words at once
                        for (i = 0; i < DATA_WIDTH_WORDS; i = i + 1) begin
                            // Check if we have enough keystream available
                            if ((block_position + i) < (16 * active_blocks)) begin
                                // plaintext ^ keystream
                                ciphertext_data[i*32 +: 32] <= 
                                    plaintext_data[i*32 +: 32] ^ 
                                    current_keystream[(block_position + i)*32 +: 32];
                            end else begin
                                // Not enough keystream, just pass plaintext through
                                // (should never happen with correct keystream generation)
                                ciphertext_data[i*32 +: 32] <= plaintext_data[i*32 +: 32];
                            end
                        end
                        
                        ciphertext_valid <= 1'b1;
                        ciphertext_last <= plaintext_last;
                        plaintext_ready_reg <= 1'b0;
                        state <= WAIT_OUTPUT;
                    end
                end
                
                WAIT_OUTPUT: begin
                    if (ciphertext_ready || !ciphertext_valid) begin
                        ciphertext_valid <= 1'b0;
                        
                        if (ciphertext_last) begin
                            // Encryption complete
                            done <= 1'b1;
                            state <= IDLE;
                        end else begin
                            // Move to next position (based on data width)
                            block_position <= block_position + DATA_WIDTH_WORDS;
                            
                            // Check if we need a new keystream block
                            if (block_position + DATA_WIDTH_WORDS >= 16) begin
                                // End of current keystream block
                                block_position <= (block_position + DATA_WIDTH_WORDS) & 4'hF; // mod 16
                                current_counter <= current_counter + 32'd1;
                                
                                if (active_blocks > 1) begin
                                    // If we have more blocks available, shift to next block
                                    current_keystream <= {512'd0, current_keystream[1023:512]};
                                    active_blocks <= active_blocks - 1'b1;
                                    state <= PROCESS_DATA;
                                    plaintext_ready_reg <= 1'b1;
                                end else begin
                                    // Generate new keystream blocks
                                    block_active <= 1'b0;
                                    state <= GENERATE_KEYSTREAM;
                                    block_start <= 1'b1;
                                end
                            end else begin
                                // Continue with current block
                                state <= PROCESS_DATA;
                                plaintext_ready_reg <= 1'b1;
                            end
                        end
                    end
                end
                
                default: begin
                    state <= IDLE;  // Reset to IDLE if in an unknown state
                end
            endcase
        end
    end
endmodule
