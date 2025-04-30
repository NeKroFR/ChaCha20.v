`include "src/verilog_headers/chacha20_defs.vh"

module quarter_round #(
    parameter PIPELINE_STAGES = `CHACHA20_PIPELINE_STAGES,
    parameter ROT_16 = 16,
    parameter ROT_12 = 12,
    parameter ROT_8 = 8,
    parameter ROT_7 = 7
) (
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

    // Calculate intermediate values (first half of the quarter round)
    wire [31:0] a1 = a_in + b_in;
    wire [31:0] d1 = d_in ^ a1;
    wire [31:0] d1_rotated = {d1[ROT_16-1:0], d1[31:ROT_16]};
    
    wire [31:0] c2 = c_in + d1_rotated;
    wire [31:0] b2 = b_in ^ c2;
    wire [31:0] b2_rotated = {b2[ROT_12-1:0], b2[31:ROT_12]};

    // Generate appropriate implementation based on pipeline stages
    generate
        if (PIPELINE_STAGES == 0) begin : no_pipeline
            // No pipeline
            wire [31:0] a3 = a1 + b2_rotated;
            wire [31:0] d3 = d1_rotated ^ a3;
            wire [31:0] d3_rotated = {d3[ROT_8-1:0], d3[31:ROT_8]};
            
            wire [31:0] c4 = c2 + d3_rotated;
            wire [31:0] b4 = b2_rotated ^ c4;
            wire [31:0] b4_rotated = {b4[ROT_7-1:0], b4[31:ROT_7]};
            
            // Assign outputs directly (no registers)
            always @(*) begin
                a_out = a3;
                b_out = b4_rotated;
                c_out = c4;
                d_out = d3_rotated;
            end
        end
        else if (PIPELINE_STAGES == 1) begin : single_pipeline
            // Single pipeline stage
            
            reg [31:0] a1_reg, d1_rotated_reg, c2_reg, b2_rotated_reg;
            
            wire [31:0] a3_next;
            wire [31:0] d3_next;
            wire [31:0] d3_rotated_next;
            wire [31:0] c4_next;
            wire [31:0] b4_next;
            wire [31:0] b4_rotated_next;
            
            // First half registers
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    a1_reg <= 32'd0;
                    d1_rotated_reg <= 32'd0;
                    c2_reg <= 32'd0;
                    b2_rotated_reg <= 32'd0;
                end else begin
                    a1_reg <= a1;
                    d1_rotated_reg <= d1_rotated;
                    c2_reg <= c2;
                    b2_rotated_reg <= b2_rotated;
                end
            end
            
            // Second half calculations (using registered first half results)
            assign a3_next = a1_reg + b2_rotated_reg;
            assign d3_next = d1_rotated_reg ^ a3_next;
            assign d3_rotated_next = {d3_next[ROT_8-1:0], d3_next[31:ROT_8]};
            assign c4_next = c2_reg + d3_rotated_next;
            assign b4_next = b2_rotated_reg ^ c4_next;
            assign b4_rotated_next = {b4_next[ROT_7-1:0], b4_next[31:ROT_7]};
            
            // Output assignments (direct from second half calculations)
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    a_out <= 32'd0;
                    b_out <= 32'd0;
                    c_out <= 32'd0;
                    d_out <= 32'd0;
                end else begin
                    a_out <= a3_next;
                    b_out <= b4_rotated_next;
                    c_out <= c4_next;
                    d_out <= d3_rotated_next;
                end
            end
        end
        else begin : two_stage_pipeline
            // Two-stage pipeline
            
            reg [31:0] a1_reg, d1_rotated_reg, c2_reg, b2_rotated_reg;
            
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    a1_reg <= 32'd0;
                    d1_rotated_reg <= 32'd0;
                    c2_reg <= 32'd0;
                    b2_rotated_reg <= 32'd0;
                end else begin
                    a1_reg <= a1;
                    d1_rotated_reg <= d1_rotated;
                    c2_reg <= c2;
                    b2_rotated_reg <= b2_rotated;
                end
            end
            
            // Calculate second half with registered inputs
            wire [31:0] a3 = a1_reg + b2_rotated_reg;
            wire [31:0] d3 = d1_rotated_reg ^ a3;
            wire [31:0] d3_rotated = {d3[ROT_8-1:0], d3[31:ROT_8]};
            
            wire [31:0] c4 = c2_reg + d3_rotated;
            wire [31:0] b4 = b2_rotated_reg ^ c4;
            wire [31:0] b4_rotated = {b4[ROT_7-1:0], b4[31:ROT_7]};
            
            // Second stage output registers
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    a_out <= 32'd0;
                    b_out <= 32'd0;
                    c_out <= 32'd0;
                    d_out <= 32'd0;
                end else begin
                    a_out <= a3;
                    b_out <= b4_rotated;
                    c_out <= c4;
                    d_out <= d3_rotated;
                end
            end
        end
    endgenerate
endmodule
