`default_nettype none

module led_display_counter
#(
    `ifdef verilator
    parameter TIME_CLK_DIV_RATE = 10000,
    parameter TIME_CLK_DIV_WIDTH = 15
    `else
    // Clock divider for time counting, half a second for 25MHz:
    parameter TIME_CLK_DIV_RATE = 12_500_000,
    parameter TIME_CLK_DIV_WIDTH = 24
    `endif    
)(
    input   wire                i_clk,
    input   wire                i_reset_n,

    `ifdef verilator
    output  wire                debug_update_leds,
    `endif

    // LED display output signals
    output  wire                o_shifter_a_ds,
    output  wire                o_shifter_b_ds,
    output  wire                o_shifter_a_cp,
    output  wire                o_shifter_b_cp,
    output  wire                o_shifter_a_mr_n,
    output  wire                o_shifter_b_mr_n
);
    /******************
     * DATA PATH
    ******************/
    reg reset_counter;
    reg update_counter;
    reg start_clk_divider;
    reg reset_clk_divider;

    // Counter
    /* verilator lint_off UNOPTFLAT */
    reg     [15:0]                   o_counter;
    /* verilator lint_on UNOPTFLAT */
    reg     [15:0]                   temp_counter_reset;
    reg     [15:0]                   temp_counter_update;
    always @(*) begin
        temp_counter_reset      = (reset_counter) ? 16'b0 : o_counter;
        temp_counter_update     = (update_counter) ? o_counter + 16'h1 : temp_counter_reset;
    end

    always @(posedge i_clk) begin
        o_counter               <= (i_reset_n) ? temp_counter_update : 16'b0;
    end

    // Clock divider for time:
    reg                             o_clk_div_time_start_stb;
    reg                             o_clk_div_time_reset_stb;
    wire                            clk_div_time_did_rise;
    /* verilator lint_off UNUSED */
    wire                            i_clk_div_time_clk;
    /* verilator lint_on UNUSED */

    clk_divider #(.CLK_DIVIDER_RATE(TIME_CLK_DIV_RATE), .CLK_DIVIDER_WIDTH(TIME_CLK_DIV_WIDTH)) CLK_DIV(
        .i_clk              (i_clk),
        .i_reset_n          (i_reset_n),

        .i_start_stb        (o_clk_div_time_start_stb),
        .i_reset_stb        (o_clk_div_time_reset_stb),
        .o_div_clk          (i_clk_div_time_clk),
        .o_div_clk_rose     (clk_div_time_did_rise)
    );

    always @(posedge i_clk) begin
        o_clk_div_time_start_stb <= start_clk_divider;
        o_clk_div_time_reset_stb <= reset_clk_divider;
    end

    // Numeric display
    numeric_led_display_controller NUM_DISPLAY(
        .i_clk              (i_clk),
        .i_reset_n          (i_reset_n),
        .i_number_to_display(o_counter),

        `ifdef verilator
        .debug_update_leds (debug_update_leds),
        `endif

        .o_shifter_a_ds     (o_shifter_a_ds),
        .o_shifter_b_ds     (o_shifter_b_ds),
        .o_shifter_a_cp     (o_shifter_a_cp),
        .o_shifter_b_cp     (o_shifter_b_cp),
        .o_shifter_a_mr_n   (o_shifter_a_mr_n),
        .o_shifter_b_mr_n   (o_shifter_b_mr_n)
    );

    /******************
     * FSM
    ******************/
    localparam STATE_RESET          = 2'd0;
    localparam STATE_INIT_COUNTER   = 2'd1;
    localparam STATE_WAIT_STARTUP   = 2'd2;
    localparam STATE_COUNT          = 2'd3;

    reg     [1:0]   state;
    /* verilator lint_off UNOPTFLAT */
    reg     [1:0]   state_next;
    /* verilator lint_on UNOPTFLAT */
      
    reg transition_init;
    reg transition_init_counter;
    reg transition_start_count;
    reg transition_update_counter;

    // State transitions
    always @(*) begin
        if (!i_reset_n) begin
            transition_init             = 1'b0;
            transition_init_counter     = 1'b0;
            transition_start_count      = 1'b0;
            transition_update_counter   = 1'b0;
        end else begin
            transition_init             = state == STATE_RESET && i_reset_n;
            transition_init_counter     = state == STATE_INIT_COUNTER && i_reset_n;
            transition_start_count      = state == STATE_WAIT_STARTUP && i_reset_n && clk_div_time_did_rise;
            transition_update_counter   = state == STATE_COUNT && i_reset_n && clk_div_time_did_rise;
        end        
    end

    // Applying state transitions
    always @(*) begin
        if (!i_reset_n) begin
            state_next = STATE_RESET;
        end else begin
            // Avoid illegal states:
            //state_next = (state > STATE_COUNT) ? STATE_RESET : state_next;

            state_next = (transition_init)              ? STATE_INIT_COUNTER : state_next;
            state_next = (transition_init_counter)      ? STATE_WAIT_STARTUP : state_next;
            state_next = (transition_start_count)       ? STATE_COUNT : state_next;
            state_next = (transition_update_counter)    ? STATE_COUNT : state_next;
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
        reset_counter               = transition_init;
        start_clk_divider           = transition_init_counter;
        reset_clk_divider           = transition_init;
        update_counter              = transition_update_counter;
    end

/*********************
* Formal verification
**********************/
`ifdef FORMAL
`ifdef LED_DISPLAY_COUNTER
	reg f_past_valid;
	initial f_past_valid = 0;

	always @(posedge i_clk) begin
		f_past_valid <= 1'b1;
	end

    // Assumptions
    initial assume(!i_reset_n);
    initial assume(!o_clk_div_time_reset_stb);
    initial assume(!o_clk_div_time_start_stb);

    // We should obey the clock divider
    always @(posedge i_clk)
        if (f_past_valid && i_reset_n && $past(i_reset_n) && $past(state == STATE_WAIT_INIT) && $past(!clk_div_time_did_rise))
            assert($stable(state));

    // Counter behaves as expected
    always @(posedge i_clk)
        if (f_past_valid && i_reset_n && $past(i_reset_n) && $past(state == STATE_COUNT) && $past(clk_div_time_did_rise))
            if ($past(o_counter < 16'hFFFF))
                assert(o_counter == $past(o_counter + 1'b1));
            else assert(o_counter == 16'b0);

    // Counter should be initialized correctly
    always @(posedge i_clk)
        if (f_past_valid && $past(!i_reset_n))
            assert(o_counter == 16'b0);

    // Clock divider should be initialized after a reset:
    always @(posedge i_clk)
        if (f_past_valid && i_reset_n && $past(i_reset_n) && $past(state == STATE_RESET))
            assert(o_clk_div_time_reset_stb);

    // Clock divider should be started before beginning to count:
    always @(posedge i_clk)
        if (f_past_valid && i_reset_n && $past(i_reset_n) && $past(state == STATE_INIT_COUNTER))
            assert(o_clk_div_time_start_stb);
`endif
`endif

endmodule