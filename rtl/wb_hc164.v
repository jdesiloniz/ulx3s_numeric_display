`default_nettype none

module wb_hc164
#(
    // Clock divider factor, take into account that we use 4 clock cycles for each bit sent to the shifter,
    // so if your board uses 25MHz, `CLK_DIV_RATE=1` will give you roughly 6MHz.
    parameter CLK_DIV_RATE = 1,
    parameter CLK_DIV_WIDTH = 1
)(
    input       wire        i_clk,
    input       wire        i_reset_n,

    // Wishbone bus 
    input   wire                            i_wb_cyc,
    input   wire                            i_wb_stb,
    input   wire    [7:0]                   i_wb_data,
    output  reg                             o_wb_ack,
    output  reg                             o_wb_stall,

    // Output signals to the device
    output  reg                             o_shifter_ds,       // Actual bit to send
    output  reg                             o_shifter_cp = 1'b1,       // Clock signal
    output  reg                             o_shifter_mr_n      // Reset (active low)
);
    /******************
     * DATA PATH
    ******************/
    reg                             reset_clock_divider;
    reg                             start_clock_divider; 
    reg                             reset_counter;
    reg                             update_counter;
    reg                             load_shift_data;
    reg                             clear_shift_data;
    reg                             shift_data;
    reg                             raise_clock;
    reg                             lower_clock;

    // Counter handling
    reg     [2:0]                   bit_counter = 3'd7;
    always @(posedge i_clk) begin
        if (!i_reset_n)
            bit_counter <= 3'd7;
        else if (reset_counter)
            bit_counter <= 3'd7;
        else if (update_counter)
            bit_counter <= bit_counter - 1'b1;
    end

    // Bit shifter
    reg     [7:0]    o_shifter_data;
    reg     [2:0]    o_shifter_op;
    wire    [7:0]    i_shifter_data;

    shifter #(.DATA_WIDTH(8)) SHIFTER(
        .i_clk          (i_clk),
        .o_data         (i_shifter_data),
        .i_op           (o_shifter_op),
        .i_data         (o_shifter_data)
    );

    always @(*) begin
        o_shifter_op                    = 3'd3; // Shift to right, padding with 1'b1
        o_shifter_ds                    = (i_reset_n && state > STATE_IDLE) ? o_shifter_data[0] : 1'b0;
    end

    always @(posedge i_clk) begin
        if (!i_reset_n)
            o_shifter_data <= 8'b0;
        else if (clear_shift_data)
            o_shifter_data <= 8'b0;
        else if (load_shift_data)
            o_shifter_data <= i_wb_data;
        else if (shift_data)
            o_shifter_data <= i_shifter_data;
    end

    // Clock divider
    reg                             o_clk_div_start_stb;
    reg                             o_clk_div_reset_stb;
    wire                            clk_div_did_rise;
    /* verilator lint_off UNUSED */
    wire                            i_clk_div_clk;
    /* verilator lint_on UNUSED */

    clk_divider #(.CLK_DIVIDER_RATE(CLK_DIV_RATE), .CLK_DIVIDER_WIDTH(CLK_DIV_WIDTH)) CLK_DIV(
        .i_clk              (i_clk),
        .i_reset_n          (i_reset_n),

        .i_start_stb        (o_clk_div_start_stb),
        .i_reset_stb        (o_clk_div_reset_stb),
        .o_div_clk          (i_clk_div_clk),
        .o_div_clk_rose     (clk_div_did_rise)
    );

    always @(posedge i_clk) begin
        o_clk_div_start_stb <= start_clock_divider;
        o_clk_div_reset_stb <= reset_clock_divider;
    end

    // External clock
    always @(posedge i_clk) begin
        if (!i_reset_n)
            o_shifter_cp <= 1'b0;
        else if (raise_clock)
            o_shifter_cp <= 1'b1;
        else if (lower_clock)
            o_shifter_cp <= 1'b0;
    end

    /******************
     * FSM
    ******************/
    localparam STATE_IDLE           = 3'd0;
    localparam STATE_PRELOAD_1      = 3'd1;
    localparam STATE_PRELOAD_2      = 3'd2;
    localparam STATE_CLOCK_1        = 3'd3;
    localparam STATE_CLOCK_2        = 3'd4;
    localparam STATE_CLOCK_3        = 3'd5;
    localparam STATE_CLOCK_4        = 3'd6;

    reg     [2:0]   state = STATE_IDLE;

    reg transition_preload_1;        
    reg transition_preload_2;        
    reg transition_clock_1;
    reg transition_clock_2;
    reg transition_clock_3;
    reg transition_clock_4;
    reg transition_become_idle;
    reg transition_next_bit;

    // State transitions
    reg received_request;
    reg is_request_finished;

    always @(*) begin
        received_request                            = i_wb_stb && i_wb_cyc && !o_wb_stall;
        is_request_finished                         = bit_counter == 3'd7;

        if (!i_reset_n) begin
            transition_preload_1        = 1'b0;
            transition_preload_2        = 1'b0;
            transition_clock_1          = 1'b0;
            transition_clock_2          = 1'b0;
            transition_clock_3          = 1'b0;
            transition_clock_4          = 1'b0;
            transition_become_idle      = 1'b0;
            transition_next_bit         = 1'b0;
        end else begin
            transition_preload_1        = state == STATE_IDLE && i_reset_n && received_request;
            transition_preload_2        = state == STATE_PRELOAD_1 && i_reset_n && clk_div_did_rise;
            transition_clock_1          = state == STATE_PRELOAD_2 && i_reset_n && clk_div_did_rise;
            transition_clock_2          = state == STATE_CLOCK_1 && i_reset_n && clk_div_did_rise;
            transition_clock_3          = state == STATE_CLOCK_2 && i_reset_n && clk_div_did_rise;
            transition_clock_4          = state == STATE_CLOCK_3 && i_reset_n && clk_div_did_rise;
            transition_become_idle      = state == STATE_CLOCK_4 && i_reset_n && clk_div_did_rise && is_request_finished;
            transition_next_bit         = state == STATE_CLOCK_4 && i_reset_n && clk_div_did_rise && !is_request_finished;
        end        
    end

    // Applying state transitions
    always @(posedge i_clk) begin
        if (!i_reset_n) begin
            state <= STATE_IDLE;
        end else begin
            if (transition_preload_1)
                state <= STATE_PRELOAD_1;
            else if (transition_preload_2)
                state <= STATE_PRELOAD_2;
            else if (transition_clock_1)
                state <= STATE_CLOCK_1;
            else if (transition_clock_2)
                state <= STATE_CLOCK_2;
            else if (transition_clock_3)
                state <= STATE_CLOCK_3;
            else if (transition_clock_4)
                state <= STATE_CLOCK_4;
            else if (transition_become_idle)
                state <= STATE_IDLE;
            else if (transition_next_bit)
                state <= STATE_CLOCK_1;
        end
    end

    // Control signals for data path
    always @(*) begin
        reset_clock_divider         = transition_become_idle;
        start_clock_divider         = transition_preload_1;
        reset_counter               = transition_preload_1;
        update_counter              = transition_clock_4;
        load_shift_data             = transition_preload_1;
        shift_data                  = transition_clock_4 && bit_counter > 3'd0;
        clear_shift_data            = transition_become_idle;
        raise_clock                 = transition_clock_1||transition_next_bit;
        lower_clock                 = transition_clock_3;
    end

    // Other external signals
    always @(*) begin
        o_shifter_mr_n              = i_reset_n;
    end

    always @(posedge i_clk) begin
        o_wb_ack                    <= transition_preload_1;
        o_wb_stall                  <= transition_preload_1||(state != STATE_IDLE);
    end

/*********************
* Formal verification
**********************/
`ifdef FORMAL
`ifdef WB_HC164
	reg f_past_valid;
	initial f_past_valid = 0;

	always @(posedge i_clk) begin
		f_past_valid <= 1'b1;
	end

    // Assumptions
    initial assume(!i_reset_n);

    // STB and CYC are tied
    always @(*)
		if (i_wb_stb)
			assume(i_wb_cyc);

    // Strobe signals are 1-cycle long
    always @(posedge i_clk)
        if (f_past_valid && $past(i_wb_stb))
            assume(!i_wb_stb);

    // Inputs from shift register are stable if we don't perform a change to its outputs
    always @(posedge i_clk)
        if (f_past_valid && $stable(o_shifter_data && o_shifter_op))
            assume($stable(i_shifter_data));

    // Assertions

    // While IDLE, there shouldn't be changes in the outputs:
    always @(posedge i_clk)
        if (f_past_valid && state == STATE_IDLE && $past(state == STATE_IDLE) && i_reset_n && $past(i_reset_n))
            assert($stable(o_shifter_ds) && $stable(o_shifter_cp));

    // Bit counter is correctly set before the shifting process starts:
    always @(posedge i_clk)
        if (state == STATE_PRELOAD_2 && i_reset_n)
            assert(bit_counter == 3'd7);

    // Bit counter should be updated in the final clock signal:
    always @(posedge i_clk)
        if (f_past_valid && state == STATE_CLOCK_4 && i_reset_n && $past(i_reset_n) && $past(clk_div_did_rise))
            assert($past(bit_counter, CLK_DIV_RATE) != bit_counter);

    // We need to continue shifting if not all bits were submitted:
    always @(posedge i_clk)
        if (f_past_valid && $past(state == STATE_CLOCK_4 && clk_div_did_rise && bit_counter < 3'd7 && i_reset_n) && i_reset_n)
            assert(state == STATE_CLOCK_1);

    // We need to stop shifting if all bits were submitted:
    always @(posedge i_clk)
        if (f_past_valid && $past(state == STATE_CLOCK_4 && clk_div_did_rise && bit_counter == 3'd7 && i_reset_n) && i_reset_n)
            assert(state == STATE_IDLE);

    // During TX, we only change status when the clock divider tell us:
    always @(posedge i_clk)
        if (f_past_valid && $past(i_reset_n && !clk_div_did_rise) && $past(state >= STATE_PRELOAD_1 && state <= STATE_CLOCK_4))
            assert($stable(state));

    // Just before starting the clock count, we start the clock divider to keep track of time
    always @(posedge i_clk)
        if (f_past_valid && i_reset_n && $past(i_reset_n) && state == STATE_PRELOAD_1 && $past(state != STATE_PRELOAD_1))
            assert(o_clk_div_start_stb);

    // We should stop dividing clock when idle
    always @(posedge i_clk)
        if (f_past_valid && i_reset_n && $past(i_reset_n) && state == STATE_IDLE && $past(state != STATE_IDLE))
            assert(o_clk_div_reset_stb);

    // We should shift data during clock #4 of present bit:
    always @(posedge i_clk)
        if (f_past_valid && i_reset_n && $past(i_reset_n) && state == STATE_CLOCK_4 && $past(state != STATE_CLOCK_4))
            assert(o_shifter_data == $past(i_shifter_data));

    // We also need to latch the data the user wants to send:
    always @(posedge i_clk)
        if (f_past_valid && i_reset_n && $past(i_reset_n) && state == STATE_PRELOAD_1 && $past(state == STATE_IDLE))
            assert($past(i_wb_data) == o_shifter_data);

    // External clock should rise half of a CLK_DIV cycle and lower the rest of the cycle
    always @(posedge i_clk)
        if (f_past_valid && i_reset_n && $past(i_reset_n) && (state == STATE_CLOCK_1||state == STATE_CLOCK_2))
            assert(o_shifter_cp);

    always @(posedge i_clk)
        if (f_past_valid && i_reset_n && $past(i_reset_n) && (state == STATE_CLOCK_3||state == STATE_CLOCK_4))
            assert(!o_shifter_cp);

    // Ack and stall lines should work as expected

    always @(posedge i_clk)
        if (state != STATE_IDLE && i_reset_n)
            assert(o_wb_stall);

    always @(posedge i_clk)
        if (f_past_valid && state == STATE_PRELOAD_1 && $past(state == STATE_IDLE))
            assert(o_wb_ack);
`endif
`endif

endmodule