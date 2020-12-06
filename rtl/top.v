`default_nettype none

module top
#(
    // Clock divider for time counting, half a second for 25MHz:
    parameter TIME_CLK_DIV_RATE = 12_500_000,
    parameter TIME_CLK_DIV_WIDTH = 24
)(
    input   wire    clk_25mhz,

    // LED counter output signals
    output  wire                oled_clk,
    output  wire                oled_mosi,
    output  wire                oled_dc,
    output  wire                oled_resn,

    output  reg                 wifi_gpio0
);

    // Reset handling
    reg i_reset_n;

    reset RESET_CNT(
        .i_clk      (clk_25mhz),
        .o_reset_n  (i_reset_n)
    );

    // We'll be using clock/reset signals from one of the shifter generators, as they're both the same
    reg o_shifter_b_cp;    
    reg o_shifter_b_mr_n;
    led_display_counter #(.TIME_CLK_DIV_RATE(TIME_CLK_DIV_RATE), .TIME_CLK_DIV_WIDTH(TIME_CLK_DIV_WIDTH)) DISPLAY(
        .i_clk              (clk_25mhz),
        .i_reset_n          (i_reset_n),
        .o_shifter_a_ds     (oled_dc),
        .o_shifter_b_ds     (oled_mosi),
        .o_shifter_a_cp     (oled_clk),
        .o_shifter_b_cp     (o_shifter_b_cp),
        .o_shifter_a_mr_n   (oled_resn),
        .o_shifter_b_mr_n   (o_shifter_b_mr_n)
    );

    always @(*) begin
        // Tie GPIO0, keep board from rebooting:
        wifi_gpio0 = 1'b1;
    end

endmodule