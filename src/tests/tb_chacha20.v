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
    reg [7:0] plaintext_data;
    reg plaintext_valid;
    reg plaintext_last;
    wire plaintext_ready;
    wire [7:0] ciphertext_data;
    wire ciphertext_valid;
    wire ciphertext_last;
    reg ciphertext_ready;
    wire encrypt_done;
    
    // Decryption signals
    reg [7:0] dec_ciphertext_data;
    reg dec_ciphertext_valid;
    reg dec_ciphertext_last;
    wire dec_ciphertext_ready;
    wire [7:0] dec_plaintext_data;
    wire dec_plaintext_valid;
    wire dec_plaintext_last;
    reg dec_plaintext_ready;
    wire decrypt_done;
    
    // Test data
    reg [7:0] message [0:23]; // "Very very secret message"
    reg [7:0] encrypted [0:23];
    reg [7:0] decrypted [0:23];
    integer message_length = 24;
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
        // Initialize test message
        message[0] = "V"; message[1] = "e"; message[2] = "r"; message[3] = "y";
        message[4] = " "; message[5] = "v"; message[6] = "e"; message[7] = "r";
        message[8] = "y"; message[9] = " "; message[10] = "s"; message[11] = "e";
        message[12] = "c"; message[13] = "r"; message[14] = "e"; message[15] = "t";
        message[16] = " "; message[17] = "m"; message[18] = "e"; message[19] = "s";
        message[20] = "s"; message[21] = "a"; message[22] = "g"; message[23] = "e";
        
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
        
        #20 rst_n = 1; // Reset deasserted after 20ns
        
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
        
        // Feed plaintext bytes
        for (i = 0; i < message_length; i = i + 1) begin
            plaintext_data = message[i];
            plaintext_valid = 1;
            plaintext_last = (i == message_length - 1);
            
            wait(plaintext_ready);
            
            // Store encrypted byte
            if (ciphertext_valid) begin
                encrypted[i] = ciphertext_data;
                $display("Encrypted byte %0d: 0x%02x (ASCII: %c) -> 0x%02x", 
                         i, message[i], message[i], ciphertext_data);
            end
            
            #10;
        end
        
        plaintext_valid = 0;
        plaintext_last = 0;
        
        wait(encrypt_done);
        #50;
        
        $display("\n=== Encryption completed ===");
        $display("Encrypted message (hex): ");
        for (i = 0; i < message_length; i = i + 1) begin
            $write("%02x ", encrypted[i]);
            if ((i+1) % 8 == 0) $write("\n");
        end
        $write("\n");
        
        // Start decryption
        #20 start = 1;
        #10 start = 0;
        
        wait(dec_ciphertext_ready);
        
        // Load ciphertext bytes
        for (i = 0; i < message_length; i = i + 1) begin
            dec_ciphertext_data = encrypted[i];
            dec_ciphertext_valid = 1;
            dec_ciphertext_last = (i == message_length - 1);
            
            wait(dec_ciphertext_ready);
            
            // Store decrypted byte
            if (dec_plaintext_valid) begin
                decrypted[i] = dec_plaintext_data;
                $display("Decrypted byte %0d: 0x%02x -> 0x%02x (ASCII: %c)", 
                         i, encrypted[i], dec_plaintext_data, dec_plaintext_data);
            end
            
            #10;
        end
        
        dec_ciphertext_valid = 0;
        dec_ciphertext_last = 0;

        wait(decrypt_done);
        #50;
        
        $display("\n=== Decryption completed ===");
        $display("Decrypted message: '");
        for (i = 0; i < message_length; i = i + 1) begin
            $write("%c", decrypted[i]);
        end
        $display("'");
    end
endmodule
