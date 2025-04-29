module chacha20_decrypt (
    input clk,                          // Clock signal
    input rst_n,                        // Active low reset
    input start,                        // Start signal
    input [255:0] key,                  // 32 bytes key
    input [31:0] counter,               // 4 bytes counter
    input [95:0] nonce,                 // 12 bytes nonce
    
    input [31:0] ciphertext_data,       // Input data word (32 bits)
    input ciphertext_valid,             // Input data valid
    input ciphertext_last,              // Last word of ciphertext
    output ciphertext_ready,            // Ready to accept input
    output [31:0] plaintext_data,       // Output data word (32 bits)
    output plaintext_valid,             // Output data valid
    output plaintext_last,              // Last word of plaintext
    input plaintext_ready,              // Downstream is ready to accept
    output done                         // Decryption complete
);
    // Since ChaCha20 is symmetric, decryption is identical to encryption
    chacha20_encrypt encrypt_instance (
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
