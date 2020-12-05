module reset(
    input   wire    i_clk,
    output  reg     o_reset_n
);

    always @(posedge i_clk) begin
        o_reset_n <= 1'b1;
    end

endmodule