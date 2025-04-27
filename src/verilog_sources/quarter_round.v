module quarter_round (
    input [31:0] a_in,      // 32-bits input a
    input [31:0] b_in,      // 32-bits input b
    input [31:0] c_in,      // 32-bits input c
    input [31:0] d_in,      // 32-bits input d
    output [31:0] a_out,    // 32-bits output a
    output [31:0] b_out,    // 32-bits output b
    output [31:0] c_out,    // 32-bits output c
    output [31:0] d_out     // 32-bits output d
);
    // Perform ChaCha20 quarter round
    wire [31:0] a1, d1, c2, b2, a3, d3, c4, b4;
    wire [31:0] d1_rotated, b2_rotated, d3_rotated, b4_rotated;
    
    assign a1 = a_in + b_in;
    assign d1 = d_in ^ a1;
    rotate_left rl1(.v(d1), .c(5'd16), .result(d1_rotated));
    
    assign c2 = c_in + d1_rotated;
    assign b2 = b_in ^ c2;
    rotate_left rl2(.v(b2), .c(5'd12), .result(b2_rotated));
    
    assign a3 = a1 + b2_rotated;
    assign d3 = d1_rotated ^ a3;
    rotate_left rl3(.v(d3), .c(5'd8), .result(d3_rotated));
    
    assign c4 = c2 + d3_rotated;
    assign b4 = b2_rotated ^ c4;
    rotate_left rl4(.v(b4), .c(5'd7), .result(b4_rotated));
    
    assign a_out = a3;
    assign b_out = b4_rotated;
    assign c_out = c4;
    assign d_out = d3_rotated;
endmodule
