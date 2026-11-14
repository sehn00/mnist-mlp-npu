
`timescale 1ns / 1ps

module memory_controller_tb;

    reg clk = 0;
    reg rst = 1;

    // ========================================
    // WMEM
    // ========================================
    reg weight_req = 0;
    reg [14:0] weight_addr = 0;
    wire [31:0] weight_data0, weight_data1, weight_data2, weight_data3;
    wire weight_valid;

    // ========================================
    // BMEM
    // ========================================
    reg bias_req = 0;
    reg [7:0] bias_addr = 0;
    wire [127:0] bias_data;
    wire bias_valid;

    // ========================================
    // ACT_A: 32bit x 128
    // ========================================
    reg act_a_req = 0;
    reg act_a_we = 0;
    reg [6:0] act_a_addr = 0;
    reg [31:0] act_a_din = 0;
    wire [31:0] act_a_dout;
    wire act_a_valid;

    // ========================================
    // ACT_B: 32bit x 32
    // ========================================
    reg act_b_req = 0;
    reg act_b_we = 0;
    reg [4:0] act_b_addr = 0;
    reg [31:0] act_b_din = 0;
    wire [31:0] act_b_dout;
    wire act_b_valid;

    // ========================================
    // IMEM_A: 32bit x 196
    // ========================================
    reg imem_a_req = 0;
    reg imem_a_we = 0;
    reg [7:0] imem_a_addr = 0;
    reg [31:0] imem_a_din = 0;
    wire [31:0] imem_a_dout;
    wire imem_a_valid;

    // ========================================
    // IMEM_B: 32bit x 196
    // ========================================
    reg imem_b_req = 0;
    reg imem_b_we = 0;
    reg [7:0] imem_b_addr = 0;
    reg [31:0] imem_b_din = 0;
    wire [31:0] imem_b_dout;
    wire imem_b_valid;

    // ========================================
    // OMEM: 32bit x 10
    // ========================================
    reg omem_req = 0;
    reg omem_we = 0;
    reg [3:0] omem_addr = 0;
    reg [31:0] omem_din = 0;
    wire [31:0] omem_dout;
    wire omem_valid;

    integer errors = 0;
    integer wmem_i;
    integer wmem_checks;
    integer wmem_bank;
    integer wmem_addr_test;
    integer wmem_layer;
    integer wmem_group;
    integer wmem_words_per_neuron;
    integer wmem_layer_base;
    integer wmem_layer_bank_base;
    integer wmem_neuron;
    integer wmem_original_addr;
    reg [31:0] wmem_expected;
    reg [31:0] wmem_actual;

    reg [31:0] expected_wmem [0:117055];
    
    // BMEM expected data: 128bit x 163
    reg [127:0] expected_bmem [0:162];

    integer bmem_i;
    integer bmem_checks;

    initial begin
        $readmemh(
            "D:/NPU_MEMORY/hex/bias_128bit.hex",
            expected_bmem
        );
    end

// ========================================
// MNIST Input Data (784 pixels = 196 words)
// ========================================
reg [31:0] mnist_input [0:195];
integer mnist_i;
integer mnist_checks;

initial begin
    $readmemh(
        "D:/NPU_MEMORY/hex/input_0000.hex",
        mnist_input
    );
end
    // Load golden weight data
    initial begin
        $readmemh(
            "D:/NPU_MEMORY/hex/weight.hex",
            expected_wmem
        );
    end

    // 100 MHz clock
    always #5 clk = ~clk;

    // ========================================
    // DUT: Memory Controller
    // ========================================
    memory_controller uut (
        .clk(clk),
        .rst(rst),

        .weight_req(weight_req),
        .weight_addr(weight_addr),
        .weight_data0(weight_data0),
        .weight_data1(weight_data1),
        .weight_data2(weight_data2),
        .weight_data3(weight_data3),
        .weight_valid(weight_valid),

        .bias_req(bias_req),
        .bias_addr(bias_addr),
        .bias_data(bias_data),
        .bias_valid(bias_valid),

        .act_a_req(act_a_req),
        .act_a_we(act_a_we),
        .act_a_addr(act_a_addr),
        .act_a_din(act_a_din),
        .act_a_dout(act_a_dout),
        .act_a_valid(act_a_valid),

        .act_b_req(act_b_req),
        .act_b_we(act_b_we),
        .act_b_addr(act_b_addr),
        .act_b_din(act_b_din),
        .act_b_dout(act_b_dout),
        .act_b_valid(act_b_valid),

        .imem_a_req(imem_a_req),
        .imem_a_we(imem_a_we),
        .imem_a_addr(imem_a_addr),
        .imem_a_din(imem_a_din),
        .imem_a_dout(imem_a_dout),
        .imem_a_valid(imem_a_valid),

        .imem_b_req(imem_b_req),
        .imem_b_we(imem_b_we),
        .imem_b_addr(imem_b_addr),
        .imem_b_din(imem_b_din),
        .imem_b_dout(imem_b_dout),
        .imem_b_valid(imem_b_valid),

        .omem_req(omem_req),
        .omem_we(omem_we),
        .omem_addr(omem_addr),
        .omem_din(omem_din),
        .omem_dout(omem_dout),
        .omem_valid(omem_valid)
    );

    // ========================================
    // IMEM_A/B Test Task
    // ========================================
    task check_imem;
        input ar, aw;
        input [7:0] aa;
        input [31:0] ad;

        input br, bw;
        input [7:0] ba;
        input [31:0] bd;

        input check_a;
        input [31:0] expected_a;
        input check_b;
        input [31:0] expected_b;

        begin
            @(negedge clk);

            imem_a_req = ar;
            imem_a_we = aw;
            imem_a_addr = aa;
            imem_a_din = ad;

            imem_b_req = br;
            imem_b_we = bw;
            imem_b_addr = ba;
            imem_b_din = bd;

            @(posedge clk);
            #1;

            if (imem_a_valid !== (ar && !aw)) begin
                $display("FAIL: IMEM_A valid");
                errors = errors + 1;
            end

            if (imem_b_valid !== (br && !bw)) begin
                $display("FAIL: IMEM_B valid");
                errors = errors + 1;
            end

            if (check_a) begin
                if (imem_a_dout !== expected_a) begin
                    $display(
                        "FAIL: IMEM_A addr=%0d expected=%08h actual=%08h",
                        aa, expected_a, imem_a_dout
                    );
                    errors = errors + 1;
                end
                else
                    $display(
                        "PASS: IMEM_A addr=%0d data=%08h",
                        aa, imem_a_dout
                    );
            end

            if (check_b) begin
                if (imem_b_dout !== expected_b) begin
                    $display(
                        "FAIL: IMEM_B addr=%0d expected=%08h actual=%08h",
                        ba, expected_b, imem_b_dout
                    );
                    errors = errors + 1;
                end
                else
                    $display(
                        "PASS: IMEM_B addr=%0d data=%08h",
                        ba, imem_b_dout
                    );
            end
        end
    endtask

    // ========================================
    // WMEM 4-Bank verification task
    // Layer bases in original weight.hex: 0, 100352, 116736
    // Bank bases: 0, 25088, 29184
    // Per-neuron words: 196, 128, 32
    // Note: FC3 bank2/3 only have 2 neurons; remaining 32 words padded.
    // ========================================
    task check_wmem4;
        input [14:0] addr;
        input integer layer;
        begin
            @(negedge clk);
            weight_req = 1'b1;
            weight_addr = addr;
            // Hold request/address for two rising edges to accommodate
            // the optional primitive output register.
            @(posedge clk); #1;
            @(posedge clk); #1;
            // Wait for registered WMEM output and valid
            if (weight_valid !== 1'b1) begin
                $display("FAIL: WMEM valid not asserted at addr=%0d", addr);
                errors = errors + 1;
            end
            
            case (layer)
                0: begin
                    wmem_layer_base = 0;
                    wmem_layer_bank_base = 0;
                    wmem_words_per_neuron = 196;
                end
                1: begin
                    wmem_layer_base = 100352;
                    wmem_layer_bank_base = 25088;
                    wmem_words_per_neuron = 128;
                end
                default: begin
                    wmem_layer_base = 116736;
                    wmem_layer_bank_base = 29184;
                    wmem_words_per_neuron = 32;
                end
            endcase
            wmem_group = (addr - wmem_layer_bank_base) / wmem_words_per_neuron;
            for (wmem_bank = 0; wmem_bank < 4; wmem_bank = wmem_bank + 1) begin
                wmem_neuron = wmem_group * 4 + wmem_bank;
                wmem_original_addr = wmem_layer_base
                    + wmem_neuron * wmem_words_per_neuron
                    + ((addr - wmem_layer_bank_base) % wmem_words_per_neuron);
                case (wmem_bank)
                    0: wmem_actual = weight_data0;
                    1: wmem_actual = weight_data1;
                    2: wmem_actual = weight_data2;
                    3: wmem_actual = weight_data3;
                endcase
                if (layer == 2 && wmem_neuron >= 10) begin
                    // Bank2/3 padding is not part of the original weights.
                    // COE generator padded unused words with zero.
                    wmem_expected = 32'h00000000;
                end else begin
                    wmem_expected = expected_wmem[wmem_original_addr];
                end
                if (wmem_actual !== wmem_expected) begin
                    $display("FAIL: WMEM L%0d bank=%0d addr=%0d neuron=%0d expected=%08h actual=%08h",
                        layer+1, wmem_bank, addr, wmem_neuron, wmem_expected, wmem_actual);
                    errors = errors + 1;
                end else begin
                    wmem_checks = wmem_checks + 1;
                end
            end
        end
    endtask

    // ========================================
    // Main Test
    // ========================================
    initial begin

        #1;
        if (^expected_wmem[0] === 1'bx || ^mnist_input[0] === 1'bx) begin
            $display("FAIL: weight.hex or input_0000.hex not loaded");
            errors = errors + 1;
        end
        repeat (2) @(negedge clk);
        rst = 0;

        // ====================================
        // TEST 1: IMEM_A/B Address 0 Write
        // ====================================
        check_imem(
            1, 1, 8'd0, 32'h01020304,
            1, 1, 8'd0, 32'hA1B2C3D4,
            0, 0, 0, 0
        );

        // ====================================
        // TEST 2: IMEM_A/B Address 0 Read
        // ====================================
        check_imem(
            1, 0, 8'd0, 0,
            1, 0, 8'd0, 0,
            1, 32'h01020304,
            1, 32'hA1B2C3D4
        );

        // ====================================
        // TEST 3: IMEM_B Address 195 Write
        // ====================================
        check_imem(
            1, 0, 8'd0, 0,
            1, 1, 8'd195, 32'h11223344,
            1, 32'h01020304,
            0, 0
        );

        // ====================================
        // TEST 4: IMEM_A Address 195 Write
        // ====================================
        check_imem(
            1, 1, 8'd195, 32'h55667788,
            1, 0, 8'd195, 0,
            0, 0,
            1, 32'h11223344
        );

        // ====================================
        // TEST 5: IMEM_A/B Address 195 Read
        // ====================================
        check_imem(
            1, 0, 8'd195, 0,
            1, 0, 8'd195, 0,
            1, 32'h55667788,
            1, 32'h11223344
        );

        // ====================================
        // TEST 6: ACT_A/B Write
        // ====================================
        @(negedge clk);

        imem_a_req = 0;
        imem_b_req = 0;

        act_a_req = 1;
        act_a_we = 1;
        act_a_addr = 7'd127;
        act_a_din = 32'h12345678;

        act_b_req = 1;
        act_b_we = 1;
        act_b_addr = 5'd31;
        act_b_din = 32'hAABBCCDD;

        @(posedge clk);
        #1;

        // ====================================
        // TEST 7: ACT_A/B Read
        // ====================================
        @(negedge clk);

        act_a_we = 0;
        act_b_we = 0;

        @(posedge clk);
        #1;

        if (act_a_valid !== 1'b1 ||
            act_a_dout !== 32'h12345678) begin
            $display("FAIL: ACT_A");
            errors = errors + 1;
        end
        else
            $display("PASS: ACT_A");

        if (act_b_valid !== 1'b1 ||
            act_b_dout !== 32'hAABBCCDD) begin
            $display("FAIL: ACT_B");
            errors = errors + 1;
        end
        else
            $display("PASS: ACT_B");

        // ====================================
        // TEST 8: WMEM 4-Bank / BMEM Read
        // ====================================
        @(negedge clk);
        act_a_req = 0;
        act_b_req = 0;
        bias_req = 1;
        bias_addr = 8'd128;  // FC2 first 4 biases

        @(posedge clk); #1;
        @(posedge clk); #1;

        $display(
            "BMEM addr=128 data=%032h valid=%b",
            bias_data,
            bias_valid
        );
        if (bias_valid !== 1'b1 ||
        bias_data !== 128'hFFFFFFE9FFFFFFFAFFFFFFF2FFFFFFFF) begin

        $display("FAIL: BMEM expected=%032h actual=%032h valid=%b",
    128'hFFFFFFE9FFFFFFFAFFFFFFF2FFFFFFFF,
    bias_data,
    bias_valid);
        errors = errors + 1;

    end else begin
        $display("PASS: BMEM 128bit data verified");
    end
        wmem_checks = 0;
        check_wmem4(15'd25088, 1); // FC2 first word for PE0~3
        $display("TEST 8: WMEM 4-Bank %0d/4 PASSED", wmem_checks);

        // ====================================
        // ====================================
        // TEST 9: OMEM Address 0 Write
        // ====================================
        @(negedge clk);

        weight_req = 0;
        bias_req = 0;

        omem_req = 1;
        omem_we = 1;
        omem_addr = 4'd0;
        omem_din = 32'h12345678;

        @(posedge clk);
        #1;

        // ====================================
        // TEST 10: OMEM Address 9 Write
        // ====================================
        @(negedge clk);

        omem_addr = 4'd9;
        omem_din = 32'hAABBCCDD;

        @(posedge clk);
        #1;

        // ====================================
        // TEST 11: OMEM Address 0 Read
        // ====================================
        @(negedge clk);

        omem_we = 0;
        omem_addr = 4'd0;

        @(posedge clk);
        #1;

        if (omem_valid !== 1'b1 ||
            omem_dout !== 32'h12345678) begin
            $display(
                "FAIL: OMEM addr=0 expected=12345678 actual=%08h",
                omem_dout
            );
            errors = errors + 1;
        end
        else
            $display(
                "PASS: OMEM addr=0 data=%08h",
                omem_dout
            );

        // ====================================
        // TEST 12: OMEM Address 9 Read
        // ====================================
        @(negedge clk);

        omem_addr = 4'd9;

        @(posedge clk);
        #1;

        if (omem_valid !== 1'b1 ||
            omem_dout !== 32'hAABBCCDD) begin
            $display(
                "FAIL: OMEM addr=9 expected=aabbccdd actual=%08h",
                omem_dout
            );
            errors = errors + 1;
        end
        else
            $display(
                "PASS: OMEM addr=9 data=%08h",
                omem_dout
            );

        // ====================================
        // TEST 13: All Valid Signals Clear
        // ====================================
        @(negedge clk);

        weight_req = 0;
        bias_req = 0;
        act_a_req = 0;
        act_b_req = 0;
        imem_a_req = 0;
        imem_b_req = 0;
        omem_req = 0;

        @(posedge clk);
        #1;

        if (weight_valid !== 1'b0 ||
            bias_valid !== 1'b0 ||
            act_a_valid !== 1'b0 ||
            act_b_valid !== 1'b0 ||
            imem_a_valid !== 1'b0 ||
            imem_b_valid !== 1'b0 ||
            omem_valid !== 1'b0) begin

            $display("FAIL: valid signals");
            errors = errors + 1;
        end
        else
            $display("PASS: all valid signals cleared");

        // ====================================
        // TEST 14: FC1 first 4 neurons, all 196 input groups
        // ====================================
        $display("TEST 14: WMEM 4-Bank FC1 Sequential Read");
        wmem_checks = 0;
        for (wmem_i = 0; wmem_i < 196; wmem_i = wmem_i + 1)
            check_wmem4(wmem_i, 0);
        $display("WMEM FC1 Sequential Read: %0d/784 PASSED", wmem_checks);

        // ====================================
        // TEST 15: FC1/FC2/FC3 boundary reads
        // ====================================
        $display("TEST 15: WMEM 4-Bank Boundary Read");
        wmem_checks = 0;
        check_wmem4(15'd0, 0);
        check_wmem4(15'd25087, 0);
        check_wmem4(15'd25088, 1);
        check_wmem4(15'd29183, 1);
        check_wmem4(15'd29184, 2);
        check_wmem4(15'd29247, 2); // FC3 last valid neuron in all banks
        check_wmem4(15'd29248, 2); // FC3 Bank0/1 valid, Bank2/3 padding
        check_wmem4(15'd29279, 2);
        $display("WMEM Boundary Read: %0d/32 PASSED", wmem_checks);

        // ====================================
        // ====================================
        // TEST 16: WMEM Valid Clear
        // ====================================
        @(negedge clk);
        weight_req = 1'b0;

        @(posedge clk);
        #1;
        @(posedge clk);
        #1;

        if (weight_valid !== 1'b0) begin
            $display("FAIL: WMEM valid clear");
            errors = errors + 1;
        end
        else
            $display("PASS: WMEM valid clear");
// ========================================
// TEST 17: MNIST Input Load to IMEM_A
// ========================================
$display("TEST 17: MNIST Input Load");

for (mnist_i = 0; mnist_i < 196;
     mnist_i = mnist_i + 1) begin

    @(negedge clk);

    imem_a_req  = 1'b1;
    imem_a_we   = 1'b1;
    imem_a_addr = mnist_i;
    imem_a_din  = mnist_input[mnist_i];

end

@(negedge clk);
imem_a_req = 1'b0;
imem_a_we  = 1'b0;

$display("MNIST 196 words written to IMEM_A");
// ========================================
// TEST 18: MNIST Input Readback
// ========================================
$display("TEST 18: MNIST Input Readback");

mnist_checks = 0;

for (mnist_i = 0; mnist_i < 196;
     mnist_i = mnist_i + 1) begin

    @(negedge clk);

    imem_a_req  = 1'b1;
    imem_a_we   = 1'b0;
    imem_a_addr = mnist_i;

    @(posedge clk);
    #1;

    if (imem_a_valid !== 1'b1 ||
        imem_a_dout !== mnist_input[mnist_i]) begin

        $display(
            "FAIL: MNIST addr=%0d expected=%08h actual=%08h",
            mnist_i,
            mnist_input[mnist_i],
            imem_a_dout
        );

        errors = errors + 1;
    end
    else begin
        mnist_checks = mnist_checks + 1;
    end
end

$display(
    "MNIST Input Readback: %0d/196 PASSED",
    mnist_checks
);

@(negedge clk);
imem_a_req = 1'b0;


        // ====================================
        // TEST 19: WMEM Back-to-Back Read
        // ====================================
        $display("TEST 19: WMEM Back-to-Back Read");

        // Clear previous requests and valid pipeline
        @(negedge clk);
        weight_req = 1'b0;
        repeat (3) @(posedge clk);
        #1;

        // 10 consecutive read requests
        for (wmem_i = 0; wmem_i < 10;
             wmem_i = wmem_i + 1) begin

            @(negedge clk);
            weight_req  = 1'b1;
            weight_addr = wmem_i;

            @(posedge clk);
            #1;

            if (wmem_i == 0) begin
                if (weight_valid !== 1'b0) begin
                    $display("FAIL: WMEM valid asserted too early");
                    errors = errors + 1;
                end
            end
            else begin
                if (weight_valid !== 1'b1 ||
                    weight_data0 !== expected_wmem[wmem_i - 1]) begin

                    $display(
                        "FAIL: cycle=%0d expected=%08h actual=%08h valid=%b",
                        wmem_i,
                        expected_wmem[wmem_i - 1],
                        weight_data0,
                        weight_valid
                    );
                    errors = errors + 1;
                end
                else begin
                    $display("PASS: WMEM cycle=%0d", wmem_i);
                end
            end
        end

        // Drain final response
        @(negedge clk);
        weight_req = 1'b0;

        @(posedge clk);
        #1;
            if (weight_valid !== 1'b1 ||
            weight_data0 !== expected_wmem[9]) begin
            $display(
            "FAIL: WMEM final response expected=%08h actual=%08h valid=%b",
            expected_wmem[9],
            weight_data0,
            weight_valid
            );
            errors = errors + 1;
        end
        else begin
            $display("PASS: WMEM final response");
        end

        // Valid must clear after pipeline drains
        @(posedge clk);
        #1;

        if (weight_valid !== 1'b0) begin
            $display("FAIL: WMEM valid did not clear");
            errors = errors + 1;
        end
        else begin
            $display("PASS: WMEM valid cleared");
        end


        // ====================================
        // TEST 20: BMEM Full Read Verification
        // ====================================
        $display("TEST 20: BMEM Full Read Verification");

        bmem_checks = 0;

        for (bmem_i = 0; bmem_i < 163;
             bmem_i = bmem_i + 1) begin

            @(negedge clk);
            bias_req  = 1'b1;
            bias_addr = bmem_i;

            // Wait for BRAM registered output
            @(posedge clk); #1;
            @(posedge clk); #1;

            if (bias_valid !== 1'b1 ||
                bias_data !== expected_bmem[bmem_i]) begin

                $display(
                    "FAIL: BMEM addr=%0d expected=%032h actual=%032h valid=%b",
                    bmem_i,
                    expected_bmem[bmem_i],
                    bias_data,
                    bias_valid
                );

                errors = errors + 1;
            end
            else begin
                bmem_checks = bmem_checks + 1;
            end
        end

        @(negedge clk);
        bias_req = 1'b0;

        $display(
            "BMEM Full Read: %0d/163 PASSED",
            bmem_checks
        );


        // ====================================
        // TEST 21: BMEM Back-to-Back Read
        // ====================================
        $display("TEST 21: BMEM Back-to-Back Read");

        // Clear previous request
        @(negedge clk);
        bias_req = 1'b0;

        repeat (3) @(posedge clk);
        #1;

        // Read 10 consecutive addresses
        for (bmem_i = 0; bmem_i < 10;
             bmem_i = bmem_i + 1) begin

            @(negedge clk);
            bias_req  = 1'b1;
            bias_addr = bmem_i;

            @(posedge clk);
            #1;

            if (bmem_i == 0) begin
                if (bias_valid !== 1'b0) begin
                    $display("FAIL: BMEM valid asserted too early");
                    errors = errors + 1;
                end
            end
            else begin
                if (bias_valid !== 1'b1 ||
                    bias_data !== expected_bmem[bmem_i-1]) begin

                    $display(
                        "FAIL: BMEM cycle=%0d expected=%032h actual=%032h valid=%b",
                        bmem_i,
                        expected_bmem[bmem_i-1],
                        bias_data,
                        bias_valid
                    );
                    errors = errors + 1;
                end
                else begin
                    $display("PASS: BMEM cycle=%0d", bmem_i);
                end
            end
        end

        // Check final response
        @(negedge clk);
        bias_req = 1'b0;

        @(posedge clk);
        #1;

        if (bias_valid !== 1'b1 ||
            bias_data !== expected_bmem[9]) begin

            $display(
                "FAIL: BMEM final response expected=%032h actual=%032h valid=%b",
                expected_bmem[9],
                bias_data,
                bias_valid
            );
            errors = errors + 1;
        end
        else begin
            $display("PASS: BMEM final response");
        end

        // Check valid clear
        @(posedge clk);
        #1;

        if (bias_valid !== 1'b0) begin
            $display("FAIL: BMEM valid did not clear");
            errors = errors + 1;
        end
        else begin
            $display("PASS: BMEM valid cleared");
        end


        // ====================================
        // Final Result
        // ====================================
        if (errors == 0)
            $display("MEMORY CONTROLLER 4-BANK ALL TESTS PASSED");
        else
            $display(
                "MEMORY CONTROLLER TEST FAILED: %0d errors",
                errors
            );

        $finish;
    end

endmodule
