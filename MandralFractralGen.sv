// Global complex type definition
typedef struct packed {
    logic signed [31:0] real_part;
    logic signed [31:0] imag_part;
} complex_t;

module MandralFractralGen (
    input  logic     clk,
    input  logic     rst,
    input  complex_t c_in,       
    output logic [7:0] iter_out  
);

    complex_t z;
    logic [7:0] iter_count;

    // 4.0 in Q8.56 format (since multiplying two Q4.28 numbers results in Q8.56)
    localparam logic signed [63:0] ESCAPE_RADIUS_SQ = 64'sh0000000400000000; 

    // Intermediate 64-bit wires for fixed-point multiplication expansion (Q8.56)
    logic signed [63:0] z_real_sq;
    logic signed [63:0] z_imag_sq;
    logic signed [63:0] z_real_imag;
    logic signed [63:0] mag_sq;

    // Combinational logic: Calculate z^2 components on the fly
    assign z_real_sq   = z.real_part * z.real_part; // Q4.28 * Q4.28 = Q8.56
    assign z_imag_sq   = z.imag_part * z.imag_part; // Q4.28 * Q4.28 = Q8.56
    assign z_real_imag = z.real_part * z.imag_part; // Q4.28 * Q4.28 = Q8.56
    assign mag_sq      = z_real_sq + z_imag_sq;     // Q8.56

    // Sequential logic: Update z and iteration count every clock cycle
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            z          <= '0;
            iter_count <= '0;
            iter_out   <= '0;
        end else begin
            // Check if point has escaped (|z|^2 > 4.0 in Q8.56) or hit max iterations (255)
            if ((mag_sq > ESCAPE_RADIUS_SQ) || (iter_count == 8'hFF)) begin
                iter_out   <= iter_count;  // Send final count to output
                z          <= '0;          // Reset z for the next pixel
                iter_count <= '0;          // Reset counter
            end else begin
                // Apply z = z^2 + c using Q4.28 fixed-point scaling
                // (z_real_sq - z_imag_sq) is Q8.56 -> shifting right by 28 brings it back to Q4.28
                z.real_part <= $signed((z_real_sq - z_imag_sq) >>> 28) + c_in.real_part;
                
                // 2 * z_real * z_imag -> (z_real_imag << 1) is Q8.56 -> shift right by 28 to Q4.28
                z.imag_part <= $signed((z_real_imag <<< 1) >>> 28) + c_in.imag_part;
                
                iter_count  <= iter_count + 1;
            end
        end
    end

endmodule