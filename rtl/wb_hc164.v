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
    /* verilator lint_off UNOPTFLAT */
    output  reg                             o_shifter_cp,       // Clock signal
    /* verilator lint_on UNOPTFLAT */
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
    /* verilator lint_off UNOPTFLAT */
    reg     [2:0]                   bit_counter;
    /* verilator lint_on UNOPTFLAT */
    reg     [2:0]                   temp_bit_counter_reset;
    reg     [2:0]                   temp_bit_counter_update;
    always @(*) begin
        temp_bit_counter_reset      = (reset_counter) ? 3'd7 : bit_counter;
        temp_bit_counter_update     = (update_counter) ? bit_counter - 1'b1 : temp_bit_counter_reset;
    end

    always @(posedge i_clk) begin
        bit_counter                 <= (i_reset_n) ? temp_bit_counter_update : 3'd7;
    end

    // Bit shifter
    /* verilator lint_off UNOPTFLAT */
    reg     [7:0]    o_shifter_data;
    /* verilator lint_on UNOPTFLAT */
    reg     [2:0]    o_shifter_op;
    wire    [7:0]    i_shifter_data;

    shifter #(.DATA_WIDTH(8)) SHIFTER(
        .o_data         (i_shifter_data),
        .i_op           (o_shifter_op),
        .i_data         (o_shifter_data)
    );

    reg     [7:0]    temp_shifter_data_clear;
    reg     [7:0]    temp_shifter_data_load;

    always @(*) begin
        temp_shifter_data_clear         = clear_shift_data ? 8'b0 : o_shifter_data;
        temp_shifter_data_load          = load_shift_data ? i_wb_data : temp_shifter_data_clear;
        o_shifter_op                    = 3'd3; // Shift to right, padding with 1'b1

        // Output signal
        o_shifter_ds                    = (i_reset_n && state > STATE_IDLE) ? o_shifter_data[0] : 1'b0;
    end

    always @(posedge i_clk) begin
        o_shifter_data <= shift_data ? i_shifter_data : temp_shifter_data_load;
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
    reg temp_cp_raise;
    reg temp_cp_lower;

    always @(*) begin
        temp_cp_raise     = (raise_clock) ? 1'b1 : o_shifter_cp;
        temp_cp_lower     = (lower_clock) ? 1'b0 : temp_cp_raise;
    end

    always @(posedge i_clk) begin
        o_shifter_cp      <= (i_reset_n) ? temp_cp_lower : 1'b0;
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

    reg     [2:0]   state;
    /* verilator lint_off UNOPTFLAT */
    reg     [2:0]   state_next;
    /* verilator lint_on UNOPTFLAT */

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
    always @(*) begin
        if (!i_reset_n) begin
            state_next = STATE_IDLE;
        end else begin
            // Avoid illegal states:
            state_next = (state > STATE_CLOCK_4) ? STATE_IDLE : state_next;

            state_next = (transition_preload_1)     ? STATE_PRELOAD_1 : state_next;
            state_next = (transition_preload_2)     ? STATE_PRELOAD_2 : state_next;
            state_next = (transition_clock_1)       ? STATE_CLOCK_1 : state_next;
            state_next = (transition_clock_2)       ? STATE_CLOCK_2 : state_next;
            state_next = (transition_clock_3)       ? STATE_CLOCK_3 : state_next;
            state_next = (transition_clock_4)       ? STATE_CLOCK_4 : state_next;
            state_next = (transition_become_idle)   ? STATE_IDLE : state_next;
            state_next = (transition_next_bit)      ? STATE_CLOCK_1 : state_next;
        end
    end

    always @(posedge i_clk) begin
        if (!i_reset_n) begin
            state <= STATE_IDLE;
        end else begin
            state <= state_next;
        end        
    end

    // Control signals for data path
    always @(*) begin
        reset_clock_divider         = transition_become_idle;
        start_clock_divider         = transition_preload_1;
        reset_counter               = transition_preload_1;
        update_counter              = transition_clock_4;
        load_shift_data             = transition_preload_1;
        shift_data                  = transition_clock_4;
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