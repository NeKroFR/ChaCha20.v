module quarter_round (
    input wire clk,             // Clock signal
    input wire rst_n,           // Active-low reset
    input wire [31:0] a_in,     // 32-bit input a
    input wire [31:0] b_in,     // 32-bit input b
    input wire [31:0] c_in,     // 32-bit input c
    input wire [31:0] d_in,     // 32-bit input d
    output reg [31:0] a_out,    // 32-bit output a
    output reg [31:0] b_out,    // 32-bit output b
    output reg [31:0] c_out,    // 32-bit output c
    output reg [31:0] d_out     // 32-bit output d
);
    // Perform ChaCha20 quarter round
    reg [31:0] a1_reg, d1_rotated_reg, c2_reg, b2_rotated_reg;

    wire [31:0] a1 = a_in + b_in;
    wire [31:0] d1 = d_in ^ a1;
    wire [31:0] d1_rotated = {d1[15:0], d1[31:16]};
    
    wire [31:0] c2 = c_in + d1_rotated;
    wire [31:0] b2 = b_in ^ c2;
    wire [31:0] b2_rotated = {b2[19:0], b2[31:20]};

    wire [31:0] a3 = a1_reg + b2_rotated_reg;
    wire [31:0] d3 = d1_rotated_reg ^ a3;
    wire [31:0] d3_rotated = {d3[23:0], d3[31:24]};
    
    wire [31:0] c4 = c2_reg + d3_rotated;
    wire [31:0] b4 = b2_rotated_reg ^ c4;
    wire [31:0] b4_rotated = {b4[24:0], b4[31:25]};

    // Pipeline registers to store intermediate results
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all registers
            a1_reg <= 32'd0;
            d1_rotated_reg <= 32'd0;
            c2_reg <= 32'd0;
            b2_rotated_reg <= 32'd0;
            a_out <= 32'd0;
            b_out <= 32'd0;
            c_out <= 32'd0;
            d_out <= 32'd0;
        end else begin
            // Store intermediate results in pipeline registers
            a1_reg <= a1;
            d1_rotated_reg <= d1_rotated;
            c2_reg <= c2;
            b2_rotated_reg <= b2_rotated;
            
            // Store final results in output registers
            a_out <= a3;
            b_out <= b4_rotated;
            c_out <= c4;
            d_out <= d3_rotated;
        end
    end
endmodule
