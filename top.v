`include "axi_master.v"
module top;

    parameter ADDR_WIDTH   = 32;
    parameter DATA_WIDTH   = 32;
    parameter DATA_DEPTH   = 32;
    parameter BURST_LENGTH = 4;
    parameter STRB_SIZE    = DATA_WIDTH/8;
    parameter BURST_SIZE   = $clog2(STRB_SIZE);
    parameter ID_SIZE      = $clog2(ADDR_WIDTH);

    reg aclk;
    reg arst;

    wire [ID_SIZE-1:0] awid;
    wire [ADDR_WIDTH-1:0] awaddr;
    wire [7:0] awburst_length;
    wire [3:0] awburst_size;
    wire [1:0] awburst_type;
    wire awvalid;
    reg awready;

    wire [ID_SIZE-1:0] wid;
    wire [DATA_WIDTH-1:0] wdata;
    wire [STRB_SIZE-1:0] wstrb;
    wire wlast;
    wire wvalid;
    reg wready;

    reg [ID_SIZE-1:0] bid;
    reg [1:0] bresp;
    reg bvalid;
    wire bready;

    wire [ID_SIZE-1:0] arid;
    wire [ADDR_WIDTH-1:0] araddr;
    wire [7:0] arburst_length;
    wire [3:0] arburst_size;
    wire [1:0] arburst_type;
    wire arvalid;
    reg arready;

    reg [ID_SIZE-1:0] rid;
    reg [DATA_WIDTH-1:0] rdata;
    reg rlast;
    reg [1:0] rresp;
    reg rvalid;
    wire rready;

    reg [8*30:1] test_name;

    reg [DATA_WIDTH-1:0] mem [0:DATA_DEPTH-1];

    integer i;
    integer wr_index;
    integer rd_index;
    integer rd_count;

    integer write_beats_done;
    integer read_beats_done;
    integer write_response_done;

    // DUT
    axi_master dut (
        .aclk(aclk),
        .arst(arst),

        .awid(awid),
        .awaddr(awaddr),
        .awburst_length(awburst_length),
        .awburst_size(awburst_size),
        .awburst_type(awburst_type),
        .awvalid(awvalid),
        .awready(awready),

        .wid(wid),
        .wdata(wdata),
        .wstrb(wstrb),
        .wlast(wlast),
        .wvalid(wvalid),
        .wready(wready),

        .bid(bid),
        .bresp(bresp),
        .bvalid(bvalid),
        .bready(bready),

        .arid(arid),
        .araddr(araddr),
        .arburst_length(arburst_length),
        .arburst_size(arburst_size),
        .arburst_type(arburst_type),
        .arvalid(arvalid),
        .arready(arready),

        .rid(rid),
        .rdata(rdata),
        .rlast(rlast),
        .rresp(rresp),
        .rvalid(rvalid),
        .rready(rready)
    );

    // Clock generation
    initial begin
        aclk = 0;
        forever #5 aclk = ~aclk;
    end

    //========================================
    // WRITE TASK
    // Waits for a write burst and its response
    //========================================
    task axi_write;
        input integer start_addr;
        input integer beats;
        begin
            $display("WRITE TEST: address=%h, beats=%0d",
                     start_addr, beats);

            wait(write_beats_done >= beats);
            wait(write_response_done == 1);

            $display("WRITE TEST COMPLETED");
        end
    endtask

    //========================================
    // READ TASK
    // Waits for read data beats
    //========================================
    task axi_read;
        input integer start_addr;
        input integer beats;
        begin
            $display("READ TEST: address=%h, beats=%0d",
                     start_addr, beats);

            wait(read_beats_done >= beats);

            $display("READ TEST COMPLETED");
        end
    endtask

    //========================================
    // SIMPLE AXI SLAVE MODEL
    //========================================
    always @(posedge aclk) begin

        if (arst) begin
            awready <= 0;
            wready  <= 0;
            arready <= 0;

            bid     <= 0;
            bresp   <= 0;
            bvalid  <= 0;

            rid     <= 0;
            rdata   <= 0;
            rlast   <= 0;
            rresp   <= 0;
            rvalid  <= 0;

            wr_index <= 0;
            rd_index <= 0;
            rd_count <= 0;

            write_beats_done    <= 0;
            read_beats_done     <= 0;
            write_response_done <= 0;
        end

        else begin
            // Slave ready signals
            awready <= 1;
            wready  <= 1;
            arready <= 1;

            // WRITE ADDRESS HANDSHAKE
            if (awvalid && awready) begin
                wr_index <= awaddr >> 2;

                $display("AW: address=%h, length=%0d",
                         awaddr, awburst_length);
            end

            // WRITE DATA HANDSHAKE
            if (wvalid && wready) begin
                mem[wr_index] <= wdata;
                $display("W: address=%h, data=%h, last=%b",
                         wr_index * 4, wdata, wlast);

                wr_index <= wr_index + 1;
                write_beats_done <= write_beats_done + 1;

                if (wlast) begin
                    bvalid <= 1;
                    bid    <= wid;
                    bresp  <= 2'b00;
                end
            end

            // WRITE RESPONSE HANDSHAKE
            if (bvalid && bready) begin
                bvalid <= 0;
                write_response_done <= 1;
                $display("B: response accepted");
            end

            // READ ADDRESS HANDSHAKE
            if (arvalid && arready) begin
                rd_index <= araddr >> 2;
                rd_count <= 0;

                rid    <= arid;
                rdata  <= mem[araddr >> 2];
                rresp  <= 2'b00;
                rvalid <= 1;
                rlast  <= (arburst_length == 0);

                $display("AR: address=%h, length=%0d",
                         araddr, arburst_length);
            end

            // READ DATA HANDSHAKE
            else if (rvalid && rready) begin
                $display("R: beat=%0d, data=%h, last=%b",
                         rd_count, rdata, rlast);

                read_beats_done <= read_beats_done + 1;

                if (rlast) begin
                    rvalid <= 0;
                    rlast  <= 0;
                end

                else begin
                    rd_index <= rd_index + 1;
                    rd_count <= rd_count + 1;
                    rdata <= mem[rd_index + 1];
                    rlast <= (rd_count + 1 == arburst_length);
                end
            end
        end
    end

    //========================================
    // TEST INITIALIZATION AND TESTCASES
    //========================================
    initial begin
        arst = 1;

        test_name = "test_nwr_nrd";
        if ($value$plusargs("test_name=%s", test_name))
            $display("Selected test: %0s", test_name);
        else
            $display("Default test: %0s", test_name);

        for (i = 0; i < DATA_DEPTH; i = i + 1)
            mem[i] = 0;

        repeat (3) @(negedge aclk);
        arst = 0;

        case (test_name)

            // Test 1: Write burst
            "test_write": begin
                axi_write('h10, BURST_LENGTH);
            end

            // Test 2: Write followed by read
            "test_read": begin
                axi_write('h10, BURST_LENGTH);
                axi_read('h10, BURST_LENGTH);
            end

            // Test 3: Four-beat burst
            "test_4beat": begin
                axi_write('h10, 4);
                axi_read('h10, 4);
            end

            // Test 4: Write and read sequence
            "test_nwr_nrd": begin
                axi_write('h10, BURST_LENGTH);
                axi_read('h10, BURST_LENGTH);
            end

            default: begin
                $display("ERROR: Unknown test name");
            end

        endcase

        $display("TESTCASE FINISHED: %0s", test_name);
        #30;
        $finish;
    end

    // Timeout protection
    initial begin
        #2000;
        $display("ERROR: Simulation timeout");
        $finish;
    end
  initial begin
    $dumpfile("1.vcd");
    $dumpvars;
  end

endmodule












