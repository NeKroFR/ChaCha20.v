// Top-level module for the simulation
module chacha20_top (
    input wire clk,
    input wire rst_n,
    input wire [7:0] data_in,
    input wire data_valid,
    output wire [7:0] data_out,
    output wire busy
);
    // Parameters
    parameter [255:0] DEFAULT_KEY = {
        8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07,
        8'h08, 8'h09, 8'h0a, 8'h0b, 8'h0c, 8'h0d, 8'h0e, 8'h0f,
        8'h10, 8'h11, 8'h12, 8'h13, 8'h14, 8'h15, 8'h16, 8'h17,
        8'h18, 8'h19, 8'h1a, 8'h1b, 8'h1c, 8'h1d, 8'h1e, 8'h1f
    };
    parameter [95:0] DEFAULT_NONCE = {
        8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
        8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h01
    };
    parameter [31:0] DEFAULT_COUNTER = 32'h00000001;
    
    // State machine states
    localparam IDLE = 2'b00;
    localparam ENCRYPTING = 2'b01;
    localparam ENCRYPTED = 2'b10;
    
    // Internal signals
    reg [1:0] state;
    reg start_encrypt;
    reg [7:0] plaintext_byte;
    reg plaintext_valid;
    reg plaintext_last;
    wire plaintext_ready;
    wire [7:0] ciphertext_byte;
    wire ciphertext_valid;
    wire ciphertext_last;
    reg ciphertext_ready;
    wire encrypt_done;
    
    // Instantiate encryption module
    chacha20_encrypt encrypt_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_encrypt),
        .key(DEFAULT_KEY),
        .counter(DEFAULT_COUNTER),
        .nonce(DEFAULT_NONCE),
        .plaintext_data(plaintext_byte),
        .plaintext_valid(plaintext_valid),
        .plaintext_last(plaintext_last),
        .plaintext_ready(plaintext_ready),
        .ciphertext_data(ciphertext_byte),
        .ciphertext_valid(ciphertext_valid),
        .ciphertext_last(ciphertext_last),
        .ciphertext_ready(ciphertext_ready),
        .done(encrypt_done)
    );
    
    // Output assignments
    assign data_out = ciphertext_byte;
    assign busy = (state != IDLE);
    
    // Encryption state machine 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            start_encrypt <= 1'b0;
            plaintext_byte <= 8'h00;
            plaintext_valid <= 1'b0;
            plaintext_last <= 1'b0;
            ciphertext_ready <= 1'b1;
        end else begin
            case (state)
                IDLE: begin
                    if (data_valid) begin
                        start_encrypt <= 1'b1;
                        plaintext_byte <= data_in;
                        plaintext_valid <= 1'b1;
                        plaintext_last <= 1'b1;
                        state <= ENCRYPTING;
                    end
                end
                
                ENCRYPTING: begin
                    start_encrypt <= 1'b0;
                    
                    if (plaintext_ready) begin
                        plaintext_valid <= 1'b0;
                    end
                    
                    if (encrypt_done) begin
                        state <= ENCRYPTED;
                    end
                end
                
                ENCRYPTED: begin
                    if (!data_valid) begin
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule
