`default_nettype none

// Simple wrapper around `led_display_controller.v` to display hexadecimal numbers.
module numeric_led_display_controller
#(
    `ifdef verilator
    parameter LED_DISPLAY_DIV_RATE = 200,     // Reduced refresh rate for simulation
    parameter LED_DISPLAY_DIV_WIDTH = 8,
    `else
    // Clock divider rate (set for a master clock of 25MHz):
    parameter LED_DISPLAY_DIV_RATE = 62000,     // Refresh rate for LED displays: 403Hz (around 100Hz per digit)
    parameter LED_DISPLAY_DIV_WIDTH = 16,
    `endif
    parameter COMMON_ANODE = 1'b1             // Common anode LED displays need to invert the signals, use 0 if using common cathode ones
)(
    input   wire                i_clk,
    input   wire                i_reset_n,
    input   wire    [15:0]      i_number_to_display,

    `ifdef verilator
    output  wire                debug_update_leds,
    `endif
    
    // LED display output signals
    output  reg                 o_shifter_a_ds,
    output  reg                 o_shifter_b_ds,
    output  reg                 o_shifter_a_cp,
    output  reg                 o_shifter_b_cp,
    output  reg                 o_shifter_a_mr_n,
    output  reg                 o_shifter_b_mr_n
);

    // LED display controller
    reg     [7:0]   o_led_display_D0;
    reg     [7:0]   o_led_display_D1;
    reg     [7:0]   o_led_display_D2;
    reg     [7:0]   o_led_display_D3;

    led_display_controller #(.LED_DISPLAY_DIV_RATE(LED_DISPLAY_DIV_RATE), .LED_DISPLAY_DIV_WIDTH(LED_DISPLAY_DIV_WIDTH), .COMMON_ANODE(COMMON_ANODE)) LED_DISPLAY(
        .i_clk              (i_clk),
        .i_reset_n          (i_reset_n),

        `ifdef verilator
        .debug_update_leds  (debug_update_leds),
        `endif

        .i_display_D0       (o_led_display_D0),
        .i_display_D1       (o_led_display_D1),
        .i_display_D2       (o_led_display_D2),
        .i_display_D3       (o_led_display_D3),

        .o_shifter_a_ds     (o_shifter_a_ds),
        .o_shifter_b_ds     (o_shifter_b_ds),
        .o_shifter_a_cp     (o_shifter_a_cp),
        .o_shifter_b_cp     (o_shifter_b_cp),
        .o_shifter_a_mr_n   (o_shifter_a_mr_n),
        .o_shifter_b_mr_n   (o_shifter_b_mr_n)
    );

    // Data conversion for LED numbers:
    always @(*) begin
        case (i_number_to_display[3:0])
            4'h0:   o_led_display_D0 = 8'b11111100;
            4'h1:   o_led_display_D0 = 8'b01100000;
            4'h2:   o_led_display_D0 = 8'b11011010;
            4'h3:   o_led_display_D0 = 8'b11110010;
            4'h4:   o_led_display_D0 = 8'b01100110;
            4'h5:   o_led_display_D0 = 8'b10110110;
            4'h6:   o_led_display_D0 = 8'b10111110;
            4'h7:   o_led_display_D0 = 8'b11100000;
            4'h8:   o_led_display_D0 = 8'b11111110;
            4'h9:   o_led_display_D0 = 8'b11100110;
            4'hA:   o_led_display_D0 = 8'b11101110;
            4'hB:   o_led_display_D0 = 8'b00111110;
            4'hC:   o_led_display_D0 = 8'b10011100;
            4'hD:   o_led_display_D0 = 8'b01111010;
            4'hE:   o_led_display_D0 = 8'b10011110;
            4'hF:   o_led_display_D0 = 8'b10001110;
        endcase

        case (i_number_to_display[7:4])
            4'h0:   o_led_display_D1 = 8'b11111100;
            4'h1:   o_led_display_D1 = 8'b01100000;
            4'h2:   o_led_display_D1 = 8'b11011010;
            4'h3:   o_led_display_D1 = 8'b11110010;
            4'h4:   o_led_display_D1 = 8'b01100110;
            4'h5:   o_led_display_D1 = 8'b10110110;
            4'h6:   o_led_display_D1 = 8'b10111110;
            4'h7:   o_led_display_D1 = 8'b11100000;
            4'h8:   o_led_display_D1 = 8'b11111110;
            4'h9:   o_led_display_D1 = 8'b11100110;
            4'hA:   o_led_display_D1 = 8'b11101110;
            4'hB:   o_led_display_D1 = 8'b00111110;
            4'hC:   o_led_display_D1 = 8'b10011100;
            4'hD:   o_led_display_D1 = 8'b01111010;
            4'hE:   o_led_display_D1 = 8'b10011110;
            4'hF:   o_led_display_D1 = 8'b10001110;
        endcase

        case (i_number_to_display[11:8])
            4'h0:   o_led_display_D2 = 8'b11111100;
            4'h1:   o_led_display_D2 = 8'b01100000;
            4'h2:   o_led_display_D2 = 8'b11011010;
            4'h3:   o_led_display_D2 = 8'b11110010;
            4'h4:   o_led_display_D2 = 8'b01100110;
            4'h5:   o_led_display_D2 = 8'b10110110;
            4'h6:   o_led_display_D2 = 8'b10111110;
            4'h7:   o_led_display_D2 = 8'b11100000;
            4'h8:   o_led_display_D2 = 8'b11111110;
            4'h9:   o_led_display_D2 = 8'b11100110;
            4'hA:   o_led_display_D2 = 8'b11101110;
            4'hB:   o_led_display_D2 = 8'b00111110;
            4'hC:   o_led_display_D2 = 8'b10011100;
            4'hD:   o_led_display_D2 = 8'b01111010;
            4'hE:   o_led_display_D2 = 8'b10011110;
            4'hF:   o_led_display_D2 = 8'b10001110;
        endcase

        case (i_number_to_display[15:12])
            4'h0:   o_led_display_D3 = 8'b11111100;
            4'h1:   o_led_display_D3 = 8'b01100000;
            4'h2:   o_led_display_D3 = 8'b11011010;
            4'h3:   o_led_display_D3 = 8'b11110010;
            4'h4:   o_led_display_D3 = 8'b01100110;
            4'h5:   o_led_display_D3 = 8'b10110110;
            4'h6:   o_led_display_D3 = 8'b10111110;
            4'h7:   o_led_display_D3 = 8'b11100000;
            4'h8:   o_led_display_D3 = 8'b11111110;
            4'h9:   o_led_display_D3 = 8'b11100110;
            4'hA:   o_led_display_D3 = 8'b11101110;
            4'hB:   o_led_display_D3 = 8'b00111110;
            4'hC:   o_led_display_D3 = 8'b10011100;
            4'hD:   o_led_display_D3 = 8'b01111010;
            4'hE:   o_led_display_D3 = 8'b10011110;
            4'hF:   o_led_display_D3 = 8'b10001110;
        endcase
    end

endmodule