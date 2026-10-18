`timescale 1ns / 1ps
module axi_master(
    aclk, arst,
    awid, awaddr, awburst_length, awburst_size,
    awburst_type, awvalid, awready,
    wid, wdata, wstrb, wlast, wvalid, wready,
    bid, bresp, bvalid, bready,
    arid, araddr, arburst_length, arburst_size,
    arburst_type, arvalid, arready,
    rid, rdata, rlast, rresp, rvalid, rready
);

    parameter ADDR_WIDTH   = 32;
    parameter DATA_WIDTH   = 32;
    parameter DATA_DEPTH   = 32;
    parameter BURST_LENGTH = 4;
    parameter STRB_SIZE    = DATA_WIDTH/8;
    parameter BURST_SIZE   = $clog2(STRB_SIZE);
    parameter ID_SIZE      = $clog2(ADDR_WIDTH);
    parameter OKAY    = 2'b00;
    parameter EX_OKAY = 2'b01;
    parameter FIXED   = 2'b00;
    parameter INCR    = 2'b01;
    parameter WRAP    = 2'b10;
    input aclk;
    input arst;

    // Write address channel
    output reg [ID_SIZE-1:0] awid;
    output reg [ADDR_WIDTH-1:0] awaddr;
    output reg [7:0] awburst_length;
    output reg [3:0] awburst_size;
    output reg [1:0] awburst_type;
    output reg awvalid;
    input awready;

    // Write data channel
    output reg [ID_SIZE-1:0] wid;
    output reg [DATA_WIDTH-1:0] wdata;
    output reg [STRB_SIZE-1:0] wstrb;
    output reg wlast;
    output reg wvalid;
    input wready;

    // Write response channel
    input [ID_SIZE-1:0] bid;
    input [1:0] bresp;
    input bvalid;
    output reg bready;

    // Read address channel
    output reg [ID_SIZE-1:0] arid;
    output reg [ADDR_WIDTH-1:0] araddr;
    output reg [7:0] arburst_length;
    output reg [3:0] arburst_size;
    output reg [1:0] arburst_type;
    output reg arvalid;
    input arready;

    // Read data channel
    input [ID_SIZE-1:0] rid;
    input [DATA_WIDTH-1:0] rdata;
    input rlast;
    input [1:0] rresp;
    input rvalid;
    output reg rready;

    // State declarations
    parameter ST_AW   = 3'b000;
    parameter ST_W    = 3'b001;
    parameter ST_B    = 3'b010;
    parameter ST_AR   = 3'b011;
    parameter ST_R    = 3'b100;
    parameter ST_DONE = 3'b101;

    reg [2:0] state;
    reg [7:0] wr_count;
    reg [7:0] rd_count;

    always @(posedge aclk) begin

        if (arst) begin
            awid           <= 0;
            awaddr         <= 0;
            awburst_length <= 0;
            awburst_size   <= 0;
            awburst_type   <= 0;
            awvalid        <= 0;

            wid            <= 0;
            wdata          <= 0;
            wstrb          <= 0;
            wlast          <= 0;
            wvalid         <= 0;

            bready         <= 0;

            arid           <= 0;
            araddr         <= 0;
            arburst_length <= 0;
            arburst_size   <= 0;
            arburst_type   <= 0;
            arvalid        <= 0;

            rready         <= 0;

            wr_count       <= 0;
            rd_count       <= 0;
            state          <= ST_AW;
        end

        else begin

            case (state)

                //================================
                // WRITE ADDRESS CHANNEL
                //================================
                ST_AW: begin

                    if (!awvalid) begin
                        awid           <= 1;
                        awaddr         <= 'h10;
                        awburst_length <= BURST_LENGTH - 1;
                        awburst_size   <= BURST_SIZE;
                        awburst_type   <= INCR;
                        awvalid        <= 1;
                    end

                    else if (awvalid && awready) begin
                        awvalid  <= 0;
                        wr_count <= 0;
                        state    <= ST_W;
                    end
                end

                //================================
                // WRITE DATA CHANNEL
                //================================
                ST_W: begin

                    if (!wvalid) begin
                        wid   <= awid;
                        wdata <= wr_count * 2 + 1;
                        wstrb <= {STRB_SIZE{1'b1}};
                        wlast <= (wr_count == BURST_LENGTH - 1);
                        wvalid <= 1;
                    end

                    else if (wvalid && wready) begin
                        wvalid <= 0;

                        if (wr_count == BURST_LENGTH - 1) begin
                            bready <= 1;
                            state  <= ST_B;
                        end

                        else begin
                            wr_count <= wr_count + 1;
                        end
                    end
                end

                //================================
                // WRITE RESPONSE CHANNEL
                //================================
                ST_B: begin

                    if (bvalid && bready) begin
                        bready <= 0;
                        state  <= ST_AR;
                    end
                end

                //================================
                // READ ADDRESS CHANNEL
                //================================
                ST_AR: begin

                    if (!arvalid) begin
                        arid           <= awid;
                        araddr         <= 'h10;
                        arburst_length <= BURST_LENGTH - 1;
                        arburst_size   <= BURST_SIZE;
                        arburst_type   <= INCR;
                        arvalid        <= 1;
                    end

                    else if (arvalid && arready) begin
                        arvalid  <= 0;
                        rready   <= 1;
                        rd_count <= 0;
                        state    <= ST_R;
                    end
                end

                //================================
                // READ DATA CHANNEL
                //================================
                ST_R: begin

                    if (rvalid && rready) begin

                        // Display each received data beat
                        $display("Read beat=%0d, Address=%h, Data=%h, RRESP=%b",
                                 rd_count, araddr + rd_count * STRB_SIZE,
                                 rdata, rresp);

                        if (rlast || rd_count == BURST_LENGTH - 1) begin
                            rready <= 0;
                            state  <= ST_DONE;
                        end

                        else begin
                            rd_count <= rd_count + 1;
                        end
                    end
                end

                //================================
                // TRANSACTION COMPLETE
                //================================
                ST_DONE: begin
                    awvalid <= 0;
                    wvalid  <= 0;
                    bready  <= 0;
                    arvalid <= 0;
                    rready  <= 0;
                end

                default: begin
                    state <= ST_AW;
                end

            endcase
        end
    end
endmodule


