`include "src/verilog_headers/chacha20_defs.vh"

module chacha20_decrypt #(
    parameter MAX_PARALLEL_BLOCKS = `CHACHA20_PARALLEL_BLOCKS,
    parameter DATA_WIDTH_WORDS = 1,
    parameter PIPELINE_STAGES = `CHACHA20_PIPELINE_STAGES,
    parameter RESOURCE_OPTIMIZE = `CHACHA20_RESOURCE_OPTIMIZE,
    parameter ENDIANNESS = `CHACHA20_ENDIANNESS
)(
    input clk,                           // Clock signal
    input rst_n,                         // Active low reset
    input start,                         // Start signal
    input [255:0] key,                   // 32 bytes key
    input [31:0] counter,                // 4 bytes counter
    input [95:0] nonce,                  // 12 bytes nonce
    
    input [32*DATA_WIDTH_WORDS-1:0] ciphertext_data,  // Input data (configurable width)
    input ciphertext_valid,              // Input data valid
    input ciphertext_last,               // Last chunk of ciphertext
    output ciphertext_ready,             // Ready to accept input
    
    output [32*DATA_WIDTH_WORDS-1:0] plaintext_data,  // Output data (configurable width)
    output plaintext_valid,              // Output data valid
    output plaintext_last,               // Last chunk of plaintext
    input plaintext_ready,               // Downstream is ready to accept
    
    output done                          // Decryption complete
);
    // Since ChaCha20 is symmetric, decryption is identical to encryption
    chacha20_encrypt #(
        .MAX_PARALLEL_BLOCKS(MAX_PARALLEL_BLOCKS),
        .DATA_WIDTH_WORDS(DATA_WIDTH_WORDS),
        .PIPELINE_STAGES(PIPELINE_STAGES),
        .RESOURCE_OPTIMIZE(RESOURCE_OPTIMIZE),
        .ENDIANNESS(ENDIANNESS)
    ) encrypt_instance (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .key(key),
        .counter(counter),
        .nonce(nonce),
        .plaintext_data(ciphertext_data),
        .plaintext_valid(ciphertext_valid),
        .plaintext_last(ciphertext_last),
        .plaintext_ready(ciphertext_ready),
        .ciphertext_data(plaintext_data),
        .ciphertext_valid(plaintext_valid),
        .ciphertext_last(plaintext_last),
        .ciphertext_ready(plaintext_ready),
        .done(done)
    );
endmodule
