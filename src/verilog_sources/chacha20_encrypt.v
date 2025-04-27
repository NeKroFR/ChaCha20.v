module chacha20_encrypt (
    input clk,                          // Clock signal
    input rst_n,                        // Active low reset signal
    input start,                        // Start signal
    input [255:0] key,                  // 32 bytes key
    input [31:0] counter,               // 4 bytes counter
    input [95:0] nonce,                 // 12 bytes nonce
    input [7:0] plaintext_data,         // Input data byte
    input plaintext_valid,              // Input data valid
    input plaintext_last,               // Last byte of plaintext
    output reg plaintext_ready,         // Ready to accept input
    output reg [7:0] ciphertext_data,   // Output data byte
    output reg ciphertext_valid,        // Output data valid
    output reg ciphertext_last,         // Last byte of ciphertext
    input ciphertext_ready,             // Downstream is ready to accept
    output reg done                     // Encryption complete
);
    // Define states
    localparam IDLE = 3'b000;   // Idle state (waiting for start)
    localparam GENERATE_KEYSTREAM = 3'b001;
    localparam PROCESS_DATA = 3'b010;
    localparam WAIT_OUTPUT = 3'b011;
    
    reg [2:0] state;
    reg [31:0] current_counter;
    reg [6:0] block_position;
    
    // Generate keystream block
    reg block_start;
    wire block_done;
    wire [511:0] keystream_block;
    reg [511:0] current_keystream;
    
    // Instantiate ChaCha20 block function
    chacha20_block block_gen (
        .clk(clk),
        .rst_n(rst_n),
        .start(block_start),
        .key(key),
        .counter(current_counter),
        .nonce(nonce),
        .keystream_block(keystream_block),
        .done(block_done)
    );

    // State machine for encryption
    // The state machine handles the keystream generation and plaintext encryption
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            done <= 1'b0;
            plaintext_ready <= 1'b0;
            ciphertext_valid <= 1'b0;
            ciphertext_last <= 1'b0;
            block_start <= 1'b0;
            block_position <= 7'd0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    ciphertext_valid <= 1'b0;
                    ciphertext_last <= 1'b0;
                    
                    if (start) begin
                        current_counter <= counter;
                        block_position <= 7'd0;
                        state <= GENERATE_KEYSTREAM;
                        block_start <= 1'b1;
                        plaintext_ready <= 1'b0;
                    end else begin
                        plaintext_ready <= 1'b0;
                    end
                end
                
                GENERATE_KEYSTREAM: begin
                    block_start <= 1'b0;
                    
                    if (block_done) begin
                        current_keystream <= keystream_block;
                        state <= PROCESS_DATA;
                        plaintext_ready <= 1'b1;
                    end
                end
                
                PROCESS_DATA: begin
                    if (plaintext_valid) begin
                        // plaintext ^ keystream
                        ciphertext_data <= plaintext_data ^ current_keystream[8*block_position +: 8];
                        ciphertext_valid <= 1'b1;
                        ciphertext_last <= plaintext_last;
                        plaintext_ready <= 1'b0;
                        state <= WAIT_OUTPUT;
                    end
                end
                
                WAIT_OUTPUT: begin
                    if (ciphertext_ready) begin
                        ciphertext_valid <= 1'b0;
                        
                        if (ciphertext_last) begin
                            // Encryption complete
                            done <= 1'b1;
                            state <= IDLE;
                        end else begin
                            // Move to next byte
                            block_position <= block_position + 7'd1;
                            
                            if (block_position == 7'd63) begin
                                // End of current keystream block, generate next block
                                current_counter <= current_counter + 32'd1;
                                block_position <= 7'd0;
                                state <= GENERATE_KEYSTREAM;
                                block_start <= 1'b1;
                            end else begin
                                // Continue in current block
                                state <= PROCESS_DATA;
                                plaintext_ready <= 1'b1;
                            end
                        end
                    end
                end
                
                default: begin
                    state <= IDLE;  // reset IDLE if in an unknown state
                end
            endcase
        end
    end
endmodule
