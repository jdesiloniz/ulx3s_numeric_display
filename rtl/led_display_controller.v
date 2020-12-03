`default_nettype none

// Sends data to shifter registers that will reach the 7-segment display.
// Data to be sent is not latched. At refresh time,
// whatever is in the appropiate `i_display_x` signal (depending on the current digit to refresh)
// will be output to the shifter registers in order to be shown.
//
// Raw data expected by the shifter registers is as follows:
//
// shifter_a           | shifter_b
// D3 D2 D1 D0 x x x x | a b c d e f g DP 
//
// Dn = current digit to refresh
// a - n: segment on/off (0 = on, 1 = off) - the LED display is expected to be common anode, if it's common-cathode please update these
// DP: point marker on/off (0 = on, 1 = off)

module led_display_controller
#(
    // Clock divider rate (set for a master clock of 25MHz):
    parameter LED_DISPLAY_DIV_RATE = 62000,     // Refresh rate for LED displays: 403Hz (around 100Hz per digit)
    parameter LED_DISPLAY_DIV_WIDTH = 16
)(
    input   wire                i_clk,
    input   wire                i_reset_n,
    
    // Values to show in LEDs as an hexadecimal number (7 segments + point) for each digit (LSB = 0):
    // a b c d e f g DP
    input   wire    [7:0]       i_display_D0,
    input   wire    [7:0]       i_display_D1,
    input   wire    [7:0]       i_display_D2,
    input   wire    [7:0]       i_display_D3,

    // Output signals
    output  reg                 o_shifter_a_ds,
    output  reg                 o_shifter_b_ds,
    output  reg                 o_shifter_a_cp,
    output  reg                 o_shifter_b_cp,
    output  reg                 o_shifter_a_mr_n,
    output  reg                 o_shifter_b_mr_n
);
    /******************
     * DATA PATH
    ******************/
    reg                             reset_clock_divider_leds;
    reg                             start_clock_divider_leds;
    reg                             update_leds;
    reg                             update_counter_digits;
    reg                             reset_counter_digits;

    // Digit counter
    /* verilator lint_off UNOPTFLAT */
    reg     [1:0]                   digit_counter;
    /* verilator lint_on UNOPTFLAT */
    reg     [1:0]                   temp_digit_counter_reset;
    reg     [1:0]                   temp_digit_counter_update;
    always @(*) begin
        temp_digit_counter_reset      = (reset_counter_digits) ? 2'd3 : digit_counter;
        temp_digit_counter_update     = (update_counter_digits) ? digit_counter - 1'b1 : temp_digit_counter_reset;
    end

    always @(posedge i_clk) begin
        digit_counter                 <= (i_reset_n) ? temp_digit_counter_update : 2'd3;
    end

    // Clock divider for LEDs:
    reg                             o_clk_div_leds_start_stb;
    reg                             o_clk_div_leds_reset_stb;
    wire                            clk_div_leds_did_rise;
    /* verilator lint_off UNUSED */
    wire                            i_clk_div_leds_clk;
    /* verilator lint_on UNUSED */

    clk_divider #(.CLK_DIVIDER_RATE(LED_DISPLAY_DIV_RATE), .CLK_DIVIDER_WIDTH(LED_DISPLAY_DIV_WIDTH)) CLK_DIV(
        .i_clk              (i_clk),
        .i_reset_n          (i_reset_n),

        .i_start_stb        (o_clk_div_leds_start_stb),
        .i_reset_stb        (o_clk_div_leds_reset_stb),
        .o_div_clk          (i_clk_div_leds_clk),
        .o_div_clk_rose     (clk_div_leds_did_rise)
    );

    always @(posedge i_clk) begin
        o_clk_div_leds_start_stb <= start_clock_divider_leds;
        o_clk_div_leds_reset_stb <= reset_clock_divider_leds;
    end

    // Shift registers
    reg             o_wb_shifter_a_cyc;
    reg             o_wb_shifter_a_stb;
    reg [7:0]       o_wb_shifter_a_data;
    reg             i_wb_shifter_a_cp_redirect;
    reg             i_wb_shifter_a_ds_redirect;
    reg             i_wb_shifter_a_mr_n_redirect;
    wire            i_wb_shifter_a_ack;
    wire            i_wb_shifter_a_stall;
    reg             o_wb_shifter_b_cyc;
    reg             o_wb_shifter_b_stb;
    reg [7:0]       o_wb_shifter_b_data;
    reg             i_wb_shifter_b_cp_redirect;
    reg             i_wb_shifter_b_ds_redirect;
    reg             i_wb_shifter_b_mr_n_redirect;
    wire            i_wb_shifter_b_ack;
    wire            i_wb_shifter_b_stall;

    wb_hc164 #(.CLK_DIV_RATE(1), .CLK_DIV_WIDTH(1)) SHIFTER_A(
        .i_clk              (i_clk),
        .i_reset_n          (i_reset_n),

        .i_wb_cyc           (o_wb_shifter_a_cyc),
        .i_wb_stb           (o_wb_shifter_a_stb),
        .i_wb_data          (o_wb_shifter_a_data),
        .o_wb_ack           (i_wb_shifter_a_ack),
        .o_wb_stall         (i_wb_shifter_a_stall),

        .o_shifter_ds       (i_wb_shifter_a_ds_redirect),
        .o_shifter_cp       (i_wb_shifter_a_cp_redirect),
        .o_shifter_mr_n     (i_wb_shifter_a_mr_n_redirect)
    );

    wb_hc164 #(.CLK_DIV_RATE(1), .CLK_DIV_WIDTH(1)) SHIFTER_B(
        .i_clk              (i_clk),
        .i_reset_n          (i_reset_n),

        .i_wb_cyc           (o_wb_shifter_b_cyc),
        .i_wb_stb           (o_wb_shifter_b_stb),
        .i_wb_data          (o_wb_shifter_b_data),
        .o_wb_ack           (i_wb_shifter_b_ack),
        .o_wb_stall         (i_wb_shifter_b_stall),

        .o_shifter_ds       (i_wb_shifter_b_ds_redirect),
        .o_shifter_cp       (i_wb_shifter_b_cp_redirect),
        .o_shifter_mr_n     (i_wb_shifter_b_mr_n_redirect)
    );

    always @(posedge i_clk) begin
        o_wb_shifter_a_stb <= update_leds;
        o_wb_shifter_a_cyc <= update_leds;
        o_wb_shifter_b_stb <= update_leds;
        o_wb_shifter_b_cyc <= update_leds;
    end

    // Data conversion
    always @(*) begin
        case (digit_counter)
            2'd0: begin
                o_wb_shifter_a_data = 8'b00010000;
                o_wb_shifter_b_data = i_display_D0;                
            end
            2'd1: begin
                o_wb_shifter_a_data = 8'b00100000;
                o_wb_shifter_b_data = i_display_D1;
            end
            2'd2: begin
                o_wb_shifter_a_data = 8'b01000000;
                o_wb_shifter_b_data = i_display_D2;
            end
            2'd3: begin
                o_wb_shifter_a_data = 8'b10000000;
                o_wb_shifter_b_data = i_display_D3;
            end
            default: begin
                o_wb_shifter_a_data = 8'b00010000;
                o_wb_shifter_b_data = i_display_D0;
            end
        endcase
    end

    // Clock/reset redirections
    always @(*) begin
        o_shifter_a_cp      = i_wb_shifter_a_cp_redirect;
        o_shifter_a_ds      = i_wb_shifter_a_ds_redirect;
        o_shifter_a_mr_n    = i_wb_shifter_a_mr_n_redirect;
        o_shifter_b_cp      = i_wb_shifter_b_cp_redirect;
        o_shifter_b_ds      = i_wb_shifter_b_ds_redirect;
        o_shifter_b_mr_n    = i_wb_shifter_b_mr_n_redirect;
    end

    /******************
     * FSM
    ******************/
    localparam STATE_RESET          = 3'd0;
    localparam STATE_INIT           = 3'd1;
    localparam STATE_DIGIT_1        = 3'd2;
    localparam STATE_DIGIT_2        = 3'd3;
    localparam STATE_DIGIT_3        = 3'd4;
    localparam STATE_DIGIT_4        = 3'd5;

    reg     [2:0]   state;
    /* verilator lint_off UNOPTFLAT */
    reg     [2:0]   state_next;
    /* verilator lint_on UNOPTFLAT */

    reg transition_reset;        
    reg transition_init;        
    reg transition_digit_1;
    reg transition_digit_2;
    reg transition_digit_3;
    reg transition_digit_4;
    reg transition_digit_go_back;

    // State transitions
    always @(*) begin
        if (!i_reset_n) begin
            transition_reset            = 1'b0;
            transition_init             = 1'b0;
            transition_digit_1          = 1'b0;
            transition_digit_2          = 1'b0;
            transition_digit_3          = 1'b0;
            transition_digit_4          = 1'b0;
            transition_digit_go_back    = 1'b0;
        end else begin
            transition_reset            = !i_reset_n;
            transition_init             = state == STATE_RESET && i_reset_n;
            transition_digit_1          = state == STATE_INIT && i_reset_n;
            transition_digit_2          = state == STATE_DIGIT_1 && i_reset_n && clk_div_leds_did_rise;
            transition_digit_3          = state == STATE_DIGIT_2 && i_reset_n && clk_div_leds_did_rise;
            transition_digit_4          = state == STATE_DIGIT_3 && i_reset_n && clk_div_leds_did_rise;
            transition_digit_go_back    = state == STATE_DIGIT_4 && i_reset_n && clk_div_leds_did_rise;
        end        
    end

    // Applying state transitions
    always @(*) begin
        if (!i_reset_n) begin
            state_next = STATE_RESET;
        end else begin
            // Avoid illegal states:
            state_next = (state > STATE_DIGIT_4) ? STATE_RESET : state_next;

            state_next = (transition_reset)         ? STATE_RESET : state_next;
            state_next = (transition_init)          ? STATE_INIT : state_next;
            state_next = (transition_digit_1)       ? STATE_DIGIT_1 : state_next;
            state_next = (transition_digit_2)       ? STATE_DIGIT_2 : state_next;
            state_next = (transition_digit_3)       ? STATE_DIGIT_3 : state_next;
            state_next = (transition_digit_4)       ? STATE_DIGIT_4 : state_next;
            state_next = (transition_digit_go_back) ? STATE_DIGIT_1 : state_next;
        end
    end

    always @(posedge i_clk) begin
        if (!i_reset_n) begin
            state <= STATE_RESET;
        end else begin
            state <= state_next;
        end        
    end
    // Control signals for data path
    always @(*) begin
        reset_clock_divider_leds    = transition_reset;
        start_clock_divider_leds    = transition_init;
        update_leds                 = transition_digit_1||transition_digit_go_back;
        update_counter_digits       = transition_digit_1||transition_digit_2||transition_digit_3||transition_digit_4||transition_digit_go_back;
        reset_counter_digits        = transition_reset;
    end

/*********************
* Formal verification
**********************/
`ifdef FORMAL
`ifdef LED_DISPLAY_CONTROLLER
	reg f_past_valid;
	initial f_past_valid = 0;

	always @(posedge i_clk) begin
		f_past_valid <= 1'b1;
	end

    // Assumptions
    initial assume(!i_reset_n);
    initial assume(!o_clk_div_leds_reset_stb);
    initial assume(!o_clk_div_leds_start_stb);

    // We won't reset unless there's an actual reset
    always @(posedge i_clk)
        if (f_past_valid && $past(i_reset_n))
            assert(state != STATE_RESET);

    // We should obey the clock divider
    always @(posedge i_clk)
        if (f_past_valid && i_reset_n && $past(i_reset_n) && $past(state > STATE_INIT) && $past(!clk_div_leds_did_rise))
            assert($stable(state));

    // Digit counter behaves as expected
    always @(posedge i_clk)
        if (f_past_valid && i_reset_n && $past(i_reset_n) && $past(state > STATE_INIT) && $past(clk_div_leds_did_rise))
            if ($past(digit_counter > 2'd0))
                assert($past(digit_counter) == digit_counter + 1'b1);
            else assert(digit_counter == 2'd3);

    // Digit counter should be initialized correctly
    always @(posedge i_clk)
        if (f_past_valid && $past(!i_reset_n))
            assert(digit_counter == 2'd3);

    // We should send the data to the shift registers while redrawing a number:
    always @(posedge i_clk)
        if (f_past_valid && $past(i_reset_n) && i_reset_n && state == STATE_DIGIT_1 && $past(state != STATE_DIGIT_1))
            assert(o_wb_shifter_a_stb && o_wb_shifter_b_stb && o_wb_shifter_a_cyc && o_wb_shifter_b_cyc);

    // Sent data should be correct
    reg             f_is_digit_D0;
    reg             f_is_digit_D1;
    reg             f_is_digit_D2;
    reg             f_is_digit_D3;
    reg     [7:0]   f_segment_data;
    reg     [7:0]   f_digit_data;

    always @(*) begin
        f_is_digit_D0 = digit_counter == 2'd0;
        f_is_digit_D1 = digit_counter == 2'd1;
        f_is_digit_D2 = digit_counter == 2'd2;
        f_is_digit_D3 = digit_counter == 2'd3;

        f_segment_data = f_is_digit_D0 ? i_display_D0 : 8'd0;
        f_segment_data = f_is_digit_D1 ? i_display_D1 : f_segment_data;
        f_segment_data = f_is_digit_D2 ? i_display_D2 : f_segment_data;
        f_segment_data = f_is_digit_D3 ? i_display_D3 : f_segment_data;

        f_digit_data = {f_is_digit_D3, f_is_digit_D2, f_is_digit_D1, f_is_digit_D0, 4'b0};
    end

    always @(posedge i_clk)
        if (f_past_valid && $past(i_reset_n) && i_reset_n && o_wb_shifter_a_stb)
            assert(o_wb_shifter_a_data == f_digit_data);

    always @(posedge i_clk)
        if (f_past_valid && $past(i_reset_n) && i_reset_n && o_wb_shifter_b_stb)
            assert(o_wb_shifter_b_data == f_segment_data);

`endif
`endif

endmodule