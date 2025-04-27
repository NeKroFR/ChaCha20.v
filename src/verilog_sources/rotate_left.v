module rotate_left (
    input [31:0] v,       // 32-bit unsigned integer to rotate
    input [4:0] c,        // Number of bits to rotate (0-31)
    output [31:0] result  // Result of the rotation
);
    // Rotate a 32-bit unsigned integer left by c bits
    assign result = (v << c) | (v >> (32 - c));
endmodule
