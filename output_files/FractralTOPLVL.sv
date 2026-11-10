// Define the complex type globally so it's accessible everywhere
typedef struct packed {
    logic signed [31:0] real_part;
    logic signed [31:0] imag_part;
} complex_t;

module FractralTOPLVL (
    input  logic       clk,          // 50 MHz board clock
    input  logic       rst,
    output logic       VGA_HS,       // Horizontal Sync
    output logic       VGA_VS,       // Vertical Sync
    output logic [7:0] VGA_R,        // Red Color Channel (8-bit)
    output logic [7:0] VGA_G,        // Green Color Channel (8-bit)
    output logic [7:0] VGA_B,        // Blue Color Channel (8-bit)
    output logic       frame_done,
    
    // VGA DAC Control Pins
    output logic       VGA_CLK,      // Drives the physical DAC clock
    output logic       VGA_BLANK_N,  // Tells the DAC when to output color
    output logic       VGA_SYNC_N    // Sync on green (usually tied to 0)
);

    // Screen Resolution Constants (VGA 640x480 @ 60Hz timing parameters)
    localparam int HD   = 640;  // Horizontal Display Width
    localparam int HFP  = 16;   // Front Porch
    localparam int HSP  = 96;   // Sync Pulse
    localparam int HBP  = 48;   // Back Porch
    localparam int HTOT = 800;  // Total Horizontal Pixels

    localparam int VD   = 480;  // Vertical Display Height
    localparam int VFP  = 10;   // Front Porch
    localparam int VSP  = 2;    // Sync Pulse
    localparam int VBP  = 33;   // Back Porch
    localparam int VTOT = 525;  // Total Vertical Lines

    // Pixel clock divider (50MHz down to 25MHz for standard VGA)
    logic pixel_clk_en;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) pixel_clk_en <= 1'b0;
        else     pixel_clk_en <= ~pixel_clk_en;
    end

    // VGA Timing Counters
    logic [9:0] h_count;
    logic [9:0] v_count;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            h_count <= '0;
            v_count <= '0;
        end else if (pixel_clk_en) begin
            if (h_count == HTOT - 1) begin
                h_count <= '0;
                if (v_count == VTOT - 1) begin
                    v_count <= '0;
                end else begin
                    v_count <= v_count + 1;
                end
            end else begin
                h_count <= h_count + 1;
            end
        end
    end

    // Generate active-low VGA Sync Pulses
    assign VGA_HS = ~((h_count >= (HD + HFP)) && (h_count < (HD + HFP + HSP)));
    assign VGA_VS = ~((v_count >= (VD + VFP)) && (v_count < (VD + VFP + VSP)));

    // Active video region flag (high only when scanning inside 640x480)
    logic video_on;
    assign video_on = (h_count < HD) && (v_count < VD);

    // Map scan counters to pixel coordinates during active display region
    logic [9:0] x_pixel;
    logic [8:0] y_pixel;
    assign x_pixel = h_count[9:0];
    assign y_pixel = v_count[8:0];

    // Zoom and Center Registers (Stored in Q4.28 format)
    logic signed [31:0] center_x = 32'shFFF38000; // Approx -0.75 in Q4.28
    logic signed [31:0] center_y = 32'sh0019999A; // Approx +0.1 in Q4.28
    
    // Scale factor register: controls zoom level.
    logic signed [63:0] scale = 64'sh0000000010000000; 

    // Frame completion and infinite zoom handler
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            frame_done <= 1'b0;
            scale      <= 64'sh0000000010000000; 
        end else begin
            frame_done <= 1'b0;
            if (pixel_clk_en && (h_count == HTOT - 1) && (v_count == VTOT - 1)) begin
                frame_done <= 1'b1; // Finished a full frame!
                scale <= scale - (scale >>> 7); // Infinite zoom step
            end
        end
    end

    complex_t c_coord;
    logic [7:0] core_iter_out;

    // Coordinate Translator: Maps screen (X, Y) pixels to complex plane coordinates (c)
    always_comb begin
        logic signed [31:0] x_offset;
        logic signed [31:0] y_offset;

        x_offset = $signed({1'b0, x_pixel}) - (HD / 2);
        y_offset = $signed({1'b0, y_pixel}) - (VD / 2);

        // Map screen coordinates relative to center, scaled by the current zoom factor
        c_coord.real_part = center_x + $signed((x_offset * scale) >>> 28);
        c_coord.imag_part = center_y + $signed((y_offset * scale) >>> 28);
    end

    // Instantiate your core math engine
    MandralFractralGen math_engine (
        .clk(clk),
        .rst(rst),
        .c_in(c_coord),
        .iter_out(core_iter_out)
    );

    // Drive RGB Color Outputs (Black during blanking intervals, fractal color during active video)
    always_comb begin
        if (video_on) begin
            VGA_R = core_iter_out;
            VGA_G = core_iter_out;
            VGA_B = core_iter_out;
        end else begin
            VGA_R = 8'h00;
            VGA_G = 8'h00;
            VGA_B = 8'h00;
        end
    end

    // Drive the physical VGA DAC chip
    assign VGA_CLK = pixel_clk_en;    
    assign VGA_BLANK_N = video_on;    
    assign VGA_SYNC_N = 1'b0;         

endmodule