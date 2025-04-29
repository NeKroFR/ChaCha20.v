module tb_chacha20;
    parameter CLK_PERIOD = 10; // 10ns clock period (100MHz)
    
    // Test signals
    reg clk;
    reg rst_n;
    reg start;
    reg [255:0] key;
    reg [31:0] counter;
    reg [95:0] nonce;
    
    // Encryption signals
    reg [31:0] plaintext_data;
    reg plaintext_valid;
    reg plaintext_last;
    wire plaintext_ready;
    wire [31:0] ciphertext_data;
    wire ciphertext_valid;
    wire ciphertext_last;
    reg ciphertext_ready;
    wire encrypt_done;
    
    // Decryption signals
    reg [31:0] dec_ciphertext_data;
    reg dec_ciphertext_valid;
    reg dec_ciphertext_last;
    wire dec_ciphertext_ready;
    wire [31:0] dec_plaintext_data;
    wire dec_plaintext_valid;
    wire dec_plaintext_last;
    reg dec_plaintext_ready;
    wire decrypt_done;
    
    // Test message "Very very secret message"
    localparam integer MESSAGE_WORDS = 6; // 24 bytes (6 words)
    reg [31:0] message [0:MESSAGE_WORDS-1];
    reg [31:0] encrypted [0:MESSAGE_WORDS-1];
    reg [31:0] decrypted [0:MESSAGE_WORDS-1];
    integer i;
    
    // DUT instantiation - encryption
    chacha20_encrypt encrypt_dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .key(key),
        .counter(counter),
        .nonce(nonce),
        .plaintext_data(plaintext_data),
        .plaintext_valid(plaintext_valid),
        .plaintext_last(plaintext_last),
        .plaintext_ready(plaintext_ready),
        .ciphertext_data(ciphertext_data),
        .ciphertext_valid(ciphertext_valid),
        .ciphertext_last(ciphertext_last),
        .ciphertext_ready(ciphertext_ready),
        .done(encrypt_done)
    );
    
    // DUT instantiation - decryption
    chacha20_decrypt decrypt_dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .key(key),
        .counter(counter),
        .nonce(nonce),
        .ciphertext_data(dec_ciphertext_data),
        .ciphertext_valid(dec_ciphertext_valid),
        .ciphertext_last(dec_ciphertext_last),
        .ciphertext_ready(dec_ciphertext_ready),
        .plaintext_data(dec_plaintext_data),
        .plaintext_valid(dec_plaintext_valid),
        .plaintext_last(dec_plaintext_last),
        .plaintext_ready(dec_plaintext_ready),
        .done(decrypt_done)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Test sequence
    initial begin
        // Initialize test message in 32-bit words
        // "Very very secret message" (24 bytes)
        message[0] = {8'd'V', 8'd'e', 8'd'r', 8'd'y'}; // "Very"
        message[1] = {8'd' ', 8'd'v', 8'd'e', 8'd'r'}; // " ver"
        message[2] = {8'd'y', 8'd' ', 8'd's', 8'd'e'}; // "y se"
        message[3] = {8'd'c', 8'd'r', 8'd'e', 8'd't'}; // "cret"
        message[4] = {8'd' ', 8'd'm', 8'd'e', 8'd's'}; // " mes"
        message[5] = {8'd's', 8'd'a', 8'd'g', 8'd'e'}; // "sage"
        
        // Initialize test signals
        rst_n = 0;
        start = 0;
        plaintext_valid = 0;
        plaintext_last = 0;
        ciphertext_ready = 1;
        dec_ciphertext_valid = 0;
        dec_ciphertext_last = 0;
        dec_plaintext_ready = 1;
        
        // Generate random key and nonce for testing
        for (i = 0; i < 32; i = i + 1) begin
            key[i*8 +: 8] = $random & 8'hFF;
        end
        for (i = 0; i < 12; i = i + 1) begin
            nonce[i*8 +: 8] = $random & 8'hFF;
        end
        counter = 42; // Arbitrary counter value (beetween 0 and 2^32-1)
        
        #20 rst_n = 1; // Release reset after 20ns
        
        // Display test parameters
        $display("=== ChaCha20 Encryption/Decryption Test ===");
        $display("Message: 'Very very secret message'");
        $display("Key (hex): %h", key);
        $display("Nonce (hex): %h", nonce);
        $display("Initial counter: %d", counter);
        
        // Start encryption
        #20 start = 1;
        #10 start = 0;
        
        // Wait for encryption module to be ready
        wait(plaintext_ready);
        
        // Feed plaintext words
        for (i = 0; i < MESSAGE_WORDS; i = i + 1) begin
            plaintext_data = message[i];
            plaintext_valid = 1;
            plaintext_last = (i == MESSAGE_WORDS-1);
            
            // Wait until module is ready for next word
            wait(plaintext_ready);
            
            // Store encrypted word
            if (ciphertext_valid) begin
                encrypted[i] = ciphertext_data;
                $display("Encrypted word %0d: 0x%08x -> 0x%08x", 
                         i, message[i], ciphertext_data);
            end
            
            #10; // wait one cycle before sending next word
        end
        
        plaintext_valid = 0;
        plaintext_last = 0;
        
        wait(encrypt_done);
        #50;
        
        $display("\n=== Encryption completed ===");
        $display("Encrypted message (hex words): ");
        for (i = 0; i < MESSAGE_WORDS; i = i + 1) begin
            $display("%d: 0x%08x", i, encrypted[i]);
        end
        
        // Start decryption
        #20 start = 1;
        #10 start = 0;
        
        wait(dec_ciphertext_ready);
        
        // Load ciphertext words
        for (i = 0; i < MESSAGE_WORDS; i = i + 1) begin
            dec_ciphertext_data = encrypted[i];
            dec_ciphertext_valid = 1;
            dec_ciphertext_last = (i == MESSAGE_WORDS-1);
            
            // Wait until module is ready for next word
            wait(dec_ciphertext_ready);
            
            // Store decrypted word
            if (dec_plaintext_valid) begin
                decrypted[i] = dec_plaintext_data;
                $display("Decrypted word %0d: 0x%08x -> 0x%08x", 
                         i, encrypted[i], dec_plaintext_data);
            end
            
            #10; // wait one cycle before sending next word
        end
        
        dec_ciphertext_valid = 0;
        dec_ciphertext_last = 0;

        wait(decrypt_done);
        #50;
        
        $display("\n=== Decryption completed ===");
        $display("Decrypted message (words): ");
        for (i = 0; i < MESSAGE_WORDS; i = i + 1) begin
            $display("%d: 0x%08x ASCII: \"%c%c%c%c\"", i, decrypted[i],
                    decrypted[i][31:24], decrypted[i][23:16], 
                    decrypted[i][15:8], decrypted[i][7:0]);
        end
        
        // Verify decryption results
        reg decryption_correct = 1;
        for (i = 0; i < MESSAGE_WORDS; i = i + 1) begin
            if (message[i] != decrypted[i]) begin
                $display("ERROR at word %0d: Expected 0x%08x, Got 0x%08x", 
                         i, message[i], decrypted[i]);
                decryption_correct = 0;
            end
        end
        
        if (decryption_correct) begin
            $display("\nSUCCESS: All words correctly decrypted!");
        } else begin
            $display("\nERROR: Decryption failed!");
        end
        
        $finish;
    end
endmodule
