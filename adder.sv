
//
// 9-bit configurable arithmetic core.
//
//   mode = 00 -> ADD : data_out = data_in0 + data_in1
//   mode = 01 -> SUB : data_out = data_in0 - data_in1  (saturates at 0
//                      instead of wrapping around if data_in1 > data_in0)
//   mode = 10 -> MAX : data_out = larger of data_in0 / data_in1
//   mode = 11 -> MIN : data_out = smaller of data_in0 / data_in1
//
//   clk_en = 1 -> normal operation (core updates every clock)
//   clk_en = 0 -> core HOLDS its last output (used by the testbench to
//                 model a slower / throttled "transmission frequency"
//                 on top of the same fixed clk period)
//
//   Reset (rst_n = 0, active-low, synchronous) clears data_out/out_valid.
//   out_valid follows in_valid with exactly 1 clock cycle of latency.
//=======================================================================
module adder (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       clk_en,
    input  logic [8:0] data_in0,
    input  logic [8:0] data_in1,
    input  logic       in_valid,
    input  logic [1:0] mode,
    output logic [9:0] data_out,
    output logic       out_valid
);

    logic [9:0] result;

    // Combinational: pick the operation based on mode
    always_comb begin
        case (mode)
            2'b00:   result = data_in0 + data_in1;                                   // ADD
            2'b01:   result = (data_in0 >= data_in1) ? (data_in0 - data_in1) : 10'd0; // SUB
            2'b10:   result = (data_in0 >= data_in1) ? {1'b0,data_in0} : {1'b0,data_in1}; // MAX
            2'b11:   result = (data_in0 <= data_in1) ? {1'b0,data_in0} : {1'b0,data_in1}; // MIN
            default: result = 10'd0;
        endcase
    end

    // Sequential: registered output, reset, and clk_en hold
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            data_out  <= 10'd0;
            out_valid <= 1'b0;
        end else if (clk_en) begin
            out_valid <= in_valid;
            data_out  <= in_valid ? result : 10'd0;
        end
        // clk_en == 0 -> do nothing -> output holds its previous value
    end

endmodule
