`timescale 1ns/1ps

// -----------------------------------------------------------------
// INTERFACE
// -----------------------------------------------------------------
interface adder_if (input logic clk);
    logic       rst_n;
    logic       clk_en;
    logic [8:0] data_in0;
    logic [8:0] data_in1;
    logic       in_valid;
    logic [1:0] mode;
    logic [9:0] data_out;
    logic       out_valid;

    modport DRIVER  (input clk, output rst_n, clk_en, data_in0, data_in1, in_valid, mode,
                      input data_out, out_valid);
    modport MONITOR (input clk, rst_n, clk_en, data_in0, data_in1, in_valid, mode, data_out, out_valid);
endinterface


// -----------------------------------------------------------------
// TRANSACTION
// -----------------------------------------------------------------
class transaction;
    typedef enum bit [1:0] {ADD = 2'b00, SUB = 2'b01, MAX = 2'b10, MIN = 2'b11} mode_e;

    rand bit [8:0] data_in0;
    rand bit [8:0] data_in1;
    rand bit       in_valid;
    rand bit [1:0] mode;
    rand bit       clk_en;

    bit       rst_n;
    bit [9:0] data_out;
    bit       out_valid;

    constraint c_valid { in_valid dist {1 :/ 90, 0 :/ 10}; }
    constraint c_freq  { clk_en   dist {1 :/ 80, 0 :/ 20}; }
    constraint c_mode  { mode inside {[0:3]}; }
    constraint c_range { data_in0 inside {[0:511]}; data_in1 inside {[0:511]}; }
endclass


// -----------------------------------------------------------------
// GENERATOR
// -----------------------------------------------------------------
class generator;
    mailbox #(transaction) gen_to_drv_mbx;
    int num_random_tests;

    function new(mailbox #(transaction) gen_to_drv_mbx, int num_random_tests = 10000);
        this.gen_to_drv_mbx  = gen_to_drv_mbx;
        this.num_random_tests = num_random_tests;
    endfunction

    task run_random_tests();
        transaction txn;
        for (int i = 0; i < num_random_tests; i++) begin
            txn = new();
            if (!txn.randomize()) $fatal(1, "randomize failed at test %0d", i);
            gen_to_drv_mbx.put(txn);
        end
        $display("[GEN] %0d constrained-random transactions sent", num_random_tests);
    endtask

    task send(bit [8:0] a, bit [8:0] b, bit [1:0] m, bit v = 1, bit ce = 1);
        transaction txn = new();
        txn.data_in0 = a;
        txn.data_in1 = b;
        txn.mode     = m;
        txn.in_valid = v;
        txn.clk_en   = ce;
        gen_to_drv_mbx.put(txn);
    endtask
endclass


// -----------------------------------------------------------------
// DRIVER
// -----------------------------------------------------------------
class driver;
    virtual adder_if.DRIVER vif;
    mailbox #(transaction) gen_to_drv_mbx;

    function new(virtual adder_if.DRIVER vif, mailbox #(transaction) gen_to_drv_mbx);
        this.vif            = vif;
        this.gen_to_drv_mbx = gen_to_drv_mbx;
    endfunction

    task reset();
        vif.rst_n <= 0; vif.clk_en <= 1; vif.in_valid <= 0;
        vif.data_in0 <= 0; vif.data_in1 <= 0; vif.mode <= 0;
        repeat (3) @(posedge vif.clk);
        vif.rst_n <= 1;
        @(posedge vif.clk);
        $display("[DRV] Reset complete");
    endtask

    task pulse_reset();
        vif.rst_n <= 0;
        @(posedge vif.clk);
        vif.rst_n <= 1;
        @(posedge vif.clk);
    endtask

    task run();
        transaction txn;
        forever begin
            gen_to_drv_mbx.get(txn);
            @(posedge vif.clk);
            vif.clk_en   <= txn.clk_en;
            vif.in_valid <= txn.in_valid;
            vif.data_in0 <= txn.data_in0;
            vif.data_in1 <= txn.data_in1;
            vif.mode     <= txn.mode;
        end
    endtask
endclass


// -----------------------------------------------------------------
// FUNCTIONAL COVERAGE (must be declared before monitor)
// -----------------------------------------------------------------
class functional_coverage;
    transaction txn;

    covergroup cg;
        option.per_instance = 1;

        cp_mode: coverpoint txn.mode {
            bins add  = {2'b00};
            bins sub  = {2'b01};
            bins maxv = {2'b10};
            bins minv = {2'b11};
        }

        cp_freq: coverpoint txn.clk_en {
            bins throttled  = {1'b0};
            bins full_speed = {1'b1};
        }

        cp_valid: coverpoint txn.in_valid {
            bins idle   = {1'b0};
            bins active = {1'b1};
        }

        cross_mode_freq: cross cp_mode, cp_freq;
    endgroup

    function new();
        cg = new();
    endfunction

    function void sample(transaction sampled_txn);
        txn = sampled_txn;
        cg.sample();
    endfunction

    function void report();
        $display("\n=================== FUNCTIONAL COVERAGE ====================");
        $display(" mode coverage            : %0.2f %%", cg.cp_mode.get_coverage());
        $display(" frequency coverage       : %0.2f %%", cg.cp_freq.get_coverage());
        $display(" in_valid coverage        : %0.2f %%", cg.cp_valid.get_coverage());
        $display(" mode x frequency (cross) : %0.2f %%", cg.cross_mode_freq.get_coverage());
        $display(" overall covergroup       : %0.2f %%", cg.get_coverage());
        $display("==============================================================\n");
    endfunction
endclass


// -----------------------------------------------------------------
// MONITOR
// -----------------------------------------------------------------
class monitor;
    virtual adder_if.MONITOR vif;
    mailbox #(transaction) mon_to_scb_mbx;
    functional_coverage cov;

    function new(virtual adder_if.MONITOR vif, mailbox #(transaction) mon_to_scb_mbx, functional_coverage cov);
        this.vif            = vif;
        this.mon_to_scb_mbx = mon_to_scb_mbx;
        this.cov            = cov;
    endfunction

    task run();
        transaction txn;
        forever begin
            @(negedge vif.clk);
            txn = new();
            txn.rst_n     = vif.rst_n;
            txn.clk_en    = vif.clk_en;
            txn.data_in0  = vif.data_in0;
            txn.data_in1  = vif.data_in1;
            txn.in_valid  = vif.in_valid;
            txn.mode      = vif.mode;
            txn.data_out  = vif.data_out;
            txn.out_valid = vif.out_valid;
            cov.sample(txn);
            mon_to_scb_mbx.put(txn);
        end
    endtask
endclass


// -----------------------------------------------------------------
// SCOREBOARD
// -----------------------------------------------------------------
class scoreboard;
    mailbox #(transaction) mon_to_scb_mbx;
    int pass_count, fail_count, check_count;

    bit [9:0] expected_data_out;
    bit       expected_out_valid;
    bit       model_is_ready;

    int last_pass_count;
    int last_fail_count;

    function new(mailbox #(transaction) mon_to_scb_mbx);
        this.mon_to_scb_mbx = mon_to_scb_mbx;
    endfunction

    function bit [9:0] get_expected_result(bit [8:0] a, bit [8:0] b, bit [1:0] mode);
        case (mode)
            2'b00:   get_expected_result = a + b;
            2'b01:   get_expected_result = (a >= b) ? (a - b) : 10'd0;
            2'b10:   get_expected_result = (a >= b) ? {1'b0,a} : {1'b0,b};
            2'b11:   get_expected_result = (a <= b) ? {1'b0,a} : {1'b0,b};
            default: get_expected_result = 10'd0;
        endcase
    endfunction

    task run();
        transaction txn;
        forever begin
            mon_to_scb_mbx.get(txn);

            // check against prediction from previous cycle (1-cycle latency)
            if (model_is_ready) begin
                check_count++;
                if (txn.data_out !== expected_data_out || txn.out_valid !== expected_out_valid) begin
                    $error("[SCB] MISMATCH @%0t: expected out=%0d valid=%0b | got out=%0d valid=%0b (a=%0d b=%0d mode=%0d)",
                           $time, expected_data_out, expected_out_valid, txn.data_out, txn.out_valid,
                           txn.data_in0, txn.data_in1, txn.mode);
                    fail_count++;
                end else begin
                    pass_count++;
                end
            end

            if (!txn.rst_n) begin
                expected_data_out  = 0;
                expected_out_valid = 0;
            end else if (txn.clk_en) begin
                expected_out_valid = txn.in_valid;
                expected_data_out  = txn.in_valid ? get_expected_result(txn.data_in0, txn.data_in1, txn.mode) : 10'd0;
            end

            model_is_ready = 1;
        end
    endtask

    function void report();
        $display("\n==================== SCOREBOARD SUMMARY ====================");
        $display(" Checks: %0d   Passed: %0d   Failed: %0d", check_count, pass_count, fail_count);
        if (fail_count == 0) $display(" >>> ALL CHECKS PASSED <<<");
        else                 $display(" >>> %0d CHECK(S) FAILED <<<", fail_count);
        $display("==============================================================\n");
    endfunction

    function void checkpoint(string label);
        int passed_since_last = pass_count - last_pass_count;
        int failed_since_last = fail_count - last_fail_count;
        if (failed_since_last == 0)
            $display("[PASS] %s (%0d cycle check(s) verified)", label, passed_since_last);
        else
            $display("[FAIL] %s (%0d of %0d cycle check(s) failed)", label, failed_since_last, passed_since_last + failed_since_last);
        last_pass_count = pass_count;
        last_fail_count = fail_count;
    endfunction
endclass


// -----------------------------------------------------------------
// ENVIRONMENT
// -----------------------------------------------------------------
class environment;
    virtual adder_if vif;
    generator            gen;
    driver               drv;
    monitor              mon;
    scoreboard            scb;
    functional_coverage    cov;
    mailbox #(transaction) gen_to_drv_mbx;
    mailbox #(transaction) mon_to_scb_mbx;

    function new(virtual adder_if vif);
        this.vif = vif;

        gen_to_drv_mbx = new(2);   // bounded -> paces generator to driver speed
        mon_to_scb_mbx = new();

        cov = new();
        gen = new(gen_to_drv_mbx);
        drv = new(vif.DRIVER, gen_to_drv_mbx);
        mon = new(vif.MONITOR, mon_to_scb_mbx, cov);
        scb = new(mon_to_scb_mbx);
    endfunction

    task pre_test();
        drv.reset();
    endtask

    task start();
        fork
            drv.run();
            mon.run();
            scb.run();
        join_none
    endtask

    task post_test();
        repeat (3) @(posedge vif.clk);
        scb.report();
        cov.report();
    endtask
endclass


// -----------------------------------------------------------------
// TEST
// -----------------------------------------------------------------
class test;
    environment env;
    virtual adder_if vif;

    function new(virtual adder_if vif);
        this.vif = vif;
        env      = new(vif);
    endfunction

    task check_now(bit [9:0] expected_data, bit expected_valid, string name);
        if (vif.data_out !== expected_data || vif.out_valid !== expected_valid)
            $error("[FAIL] %s: expected data_out=%0d out_valid=%0b, got data_out=%0d out_valid=%0b",
                   name, expected_data, expected_valid, vif.data_out, vif.out_valid);
        else
            $display("[PASS] %s", name);
    endtask

    task run();
        $display("\n======== ADDER OOP/CRV TESTBENCH (SystemVerilog) ========\n");

        env.pre_test();
        check_now(10'd0, 1'b0, "TC-001: Reset clears outputs");
        env.start();

        env.gen.send(0,   0,   transaction::ADD);
        env.gen.send(10,  20,  transaction::ADD);
        env.gen.send(511, 511, transaction::ADD);
        env.gen.send(511, 0,   transaction::ADD);
        env.gen.send(0,   511, transaction::ADD);
        repeat (3) @(posedge vif.clk);
        env.scb.checkpoint("TC-002..006: directed ADD cases");

        env.gen.send(255, 170, transaction::ADD, 0, 1);
        repeat (2) @(posedge vif.clk);
        env.scb.checkpoint("TC-007: invalid input handling");

        for (int i = 1; i <= 25; i++)
            env.gen.send(i & 9'h7F, (i*2) & 9'h7F, transaction::ADD);
        repeat (2) @(posedge vif.clk);
        env.scb.checkpoint("TC-009: 25 back-to-back valid transactions");

        env.gen.send(100, 200, transaction::ADD);
        @(posedge vif.clk);
        env.drv.pulse_reset();
        $display("[INFO] Mid-test reset applied");
        repeat (2) @(posedge vif.clk);
        env.scb.checkpoint("TC-010: reset during active operation");

        env.gen.send(0,   1,   transaction::ADD);
        env.gen.send(1,   0,   transaction::ADD);
        env.gen.send(1,   1,   transaction::ADD);
        env.gen.send(510, 511, transaction::ADD);
        env.gen.send(511, 1,   transaction::ADD);
        repeat (2) @(posedge vif.clk);
        env.scb.checkpoint("TC-012: boundary value analysis");

        env.gen.send(80,  50,  transaction::SUB);
        env.gen.send(50,  80,  transaction::SUB);
        env.gen.send(120, 90,  transaction::MAX);
        env.gen.send(120, 90,  transaction::MIN);
        repeat (2) @(posedge vif.clk);
        $display("[INFO] SUB/MAX/MIN mode coverage sent");
        env.scb.checkpoint("TC-014: SUB/MAX/MIN mode coverage");

        env.gen.send(5, 6, transaction::ADD, 1, 0);
        repeat (3) @(posedge vif.clk);
        env.gen.send(5, 6, transaction::ADD, 1, 1);
        repeat (2) @(posedge vif.clk);
        $display("[INFO] Throttled frequency (clk_en=0) case sent");
        env.scb.checkpoint("TC-015: throttled transmission frequency");

        env.gen.send(511, 511, transaction::ADD);
        @(posedge vif.clk);
        env.drv.pulse_reset();
        $display("[INFO] Simultaneous max-value + unexpected reset case sent");
        repeat (2) @(posedge vif.clk);
        env.scb.checkpoint("TC-016: simultaneous max-value + unexpected reset");

        $display("[INFO] Starting 10,000-transaction CRV loop (random mode + frequency)...");
        env.gen.run_random_tests();
        env.scb.checkpoint("TC-011: 10,000 constrained-random transactions");

        env.post_test();
    endtask
endclass


// -----------------------------------------------------------------
// TOP MODULE
// -----------------------------------------------------------------
module tb_top;
    bit clk = 0;
    always #5 clk = ~clk;

    adder_if aif (clk);

    adder dut (
        .clk       (clk),
        .rst_n     (aif.rst_n),
        .clk_en    (aif.clk_en),
        .data_in0  (aif.data_in0),
        .data_in1  (aif.data_in1),
        .in_valid  (aif.in_valid),
        .mode      (aif.mode),
        .data_out  (aif.data_out),
        .out_valid (aif.out_valid)
    );

    test t;
    initial begin
        t = new(aif);
        t.run();
        $display("\nTESTBENCH COMPLETE - see SCOREBOARD SUMMARY above\n");
        $finish;
    end

    initial begin
        #200_000_000;
        $error("[TIMEOUT] simulation hung");
        $finish;
    end
endmodule
