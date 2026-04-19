`timescale 1ns/1ps

module ad4080_spi_master #(
    parameter int ADDR_W  = 15,
    parameter int DATA_W  = 8,
    parameter int CLK_DIV = 10
)(
    input  logic               clk,
    input  logic               rst_n,

    input  logic               start,
    input  logic               rw,          // 1: read, 0: write
    input  logic [ADDR_W-1:0]  reg_addr,
    input  logic [DATA_W-1:0]  wr_data,

    input  logic               spi_sdo,     // ADC -> FPGA

    output logic               spi_sclk,
    output logic               spi_cs_n,
    output logic               spi_sdi,     // FPGA -> ADC

    output logic [DATA_W-1:0]  rd_data,
    output logic               rd_valid,
    output logic               done,
    output logic               busy
);

    typedef enum logic [1:0] {
        IDLE,
        INST,
        DATA,
        DONE
    } state_t;

    state_t state, next_state;

    localparam int INST_W = 1 + ADDR_W;
    localparam int DELAY_DONE = 1;

    localparam int CLK_CNT_W  = (CLK_DIV    <= 1) ? 1 : $clog2(CLK_DIV);
    localparam int DONE_CNT_W = (DELAY_DONE <= 1) ? 1 : $clog2(DELAY_DONE);

    logic [INST_W-1:0]             inst_shift_reg;
    logic [INST_W-1:0]             inst_word;
    logic [DATA_W-1:0]             data_shift_reg;

    logic [$clog2(INST_W+1)-1:0]   inst_bit_cnt;
    logic [$clog2(DATA_W+1)-1:0]   data_bit_cnt;
    logic [CLK_CNT_W-1:0]          clk_cnt;
    logic                          sclk_int;

    logic                          inst_started;
    logic                          data_started;

    logic                          done_flag;
    logic [DONE_CNT_W-1:0]         done_cnt;

    assign inst_word = {rw, reg_addr};

    //------------------------------------------------
    // done delay counter
    //------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done_cnt  <= '0;
            done_flag <= 1'b0;
        end
        else if (state == DONE) begin
            if (done_cnt == DELAY_DONE - 1) begin
                done_cnt  <= '0;
                done_flag <= 1'b1;
            end
            else begin
                done_cnt  <= done_cnt + 1'b1;
                done_flag <= 1'b0;
            end
        end
        else begin
            done_cnt  <= '0;
            done_flag <= 1'b0;
        end
    end

    //------------------------------------------------
    // SPI clock output
    // idle high
    //------------------------------------------------
    assign spi_sclk = ((state == INST) || (state == DATA)) ? sclk_int : 1'b1;

    //------------------------------------------------
    // 1) State register
    //------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    //------------------------------------------------
    // 2) Next-state logic
    //------------------------------------------------
    always_comb begin
        next_state = state;

        case (state)
            IDLE: begin
                if (start)
                    next_state = INST;
            end

            INST: begin
                if ((clk_cnt == CLK_DIV-1) &&
                    (sclk_int == 1'b0) &&
                    (inst_bit_cnt == 1) &&
                    inst_started) begin
                    next_state = DATA;
                end
            end

            DATA: begin
                if ((clk_cnt == CLK_DIV-1) &&
                    (sclk_int == 1'b0) &&
                    (data_bit_cnt == 1) &&
                    data_started) begin
                    next_state = DONE;
                end
            end

            DONE: begin
                next_state = done_flag ? IDLE : DONE;
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    //------------------------------------------------
    // 3) Datapath and output registers
    //------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inst_shift_reg <= '0;
            data_shift_reg <= '0;
            inst_bit_cnt   <= '0;
            data_bit_cnt   <= '0;
            clk_cnt        <= '0;
            sclk_int       <= 1'b1;
            inst_started   <= 1'b0;
            data_started   <= 1'b0;

            spi_cs_n       <= 1'b1;
            spi_sdi        <= 1'b0;

            rd_data        <= '0;
            rd_valid       <= 1'b0;
            done           <= 1'b0;
            busy           <= 1'b0;
        end
        else begin
            done     <= 1'b0;
            rd_valid <= 1'b0;

            case (state)

                //----------------------------------------
                // IDLE
                //----------------------------------------
                IDLE: begin
                    spi_cs_n     <= 1'b1;
                    spi_sdi      <= 1'b0;
                    sclk_int     <= 1'b1;
                    clk_cnt      <= '0;
                    inst_bit_cnt <= '0;
                    data_bit_cnt <= '0;
                    inst_started <= 1'b0;
                    data_started <= 1'b0;
                    busy         <= 1'b0;

                    if (start) begin
                        inst_shift_reg <= inst_word;
                        data_shift_reg <= wr_data;

                        spi_cs_n       <= 1'b0;
                        spi_sdi        <= rw;      // first instruction bit
                        sclk_int       <= 1'b1;
                        clk_cnt        <= '0;
                        inst_bit_cnt   <= INST_W;
                        data_bit_cnt   <= DATA_W;
                        inst_started   <= 1'b0;
                        data_started   <= 1'b0;
                        busy           <= 1'b1;
                    end
                end

                //----------------------------------------
                // INST
                // falling edge: after first sample, drive next bit
                // rising  edge: consume one bit
                //----------------------------------------
                INST: begin
                    spi_cs_n <= 1'b0;
                    busy     <= 1'b1;

                    if (clk_cnt == CLK_DIV-1) begin
                        clk_cnt  <= '0;
                        sclk_int <= ~sclk_int;

                        //--------------------------------
                        // Falling edge: 1 -> 0
                        //--------------------------------
                        if (sclk_int == 1'b1) begin
                            if (inst_started) begin
                                if (inst_bit_cnt > 1) begin
                                    inst_shift_reg <= {inst_shift_reg[INST_W-2:0], 1'b0};
                                    spi_sdi        <= inst_shift_reg[INST_W-2];
                                end
                                else begin
                                    if (!rw)
                                        spi_sdi <= data_shift_reg[DATA_W-1];
                                    else
                                        spi_sdi <= 1'b0;
                                end
                            end
                        end
                        else begin
                            if (inst_bit_cnt != 0)
                                inst_bit_cnt <= inst_bit_cnt - 1'b1;

                            if (!inst_started)
                                inst_started <= 1'b1;
                        end
                    end
                    else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end


                DATA: begin
                    spi_cs_n <= 1'b0;
                    busy     <= 1'b1;

                    if (clk_cnt == CLK_DIV-1) begin
                        clk_cnt  <= '0;
                        sclk_int <= ~sclk_int;

                        //--------------------------------
                        // Falling edge: 1 -> 0
                        //--------------------------------
                        if (sclk_int == 1'b1) begin
                            // Same idea: don't advance on first falling edge
                            if (data_started) begin
                                if (!rw) begin
                                    if (data_bit_cnt > 1) begin
                                        data_shift_reg <= {data_shift_reg[DATA_W-2:0], 1'b0};
                                        spi_sdi        <= data_shift_reg[DATA_W-2];
                                    end
                                    else begin
                                        spi_sdi <= 1'b0;
                                    end
                                end
                                else begin
                                    spi_sdi <= 1'b0;
                                end
                            end
                        end
                        //--------------------------------
                        // Rising edge: 0 -> 1
                        //--------------------------------
                        else begin
                            if (rw) begin
                                if (data_bit_cnt != 0) begin
                                    data_shift_reg <= {data_shift_reg[DATA_W-2:0], spi_sdo};
                                    data_bit_cnt   <= data_bit_cnt - 1'b1;
                                end
                            end
                            else begin
                                if (data_bit_cnt != 0)
                                    data_bit_cnt <= data_bit_cnt - 1'b1;
                            end

                            if (!data_started)
                                data_started <= 1'b1;
                        end
                    end
                    else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                //----------------------------------------
                // DONE
                //----------------------------------------
                DONE: begin
                    spi_cs_n <= 1'b1;
                    spi_sdi  <= 1'b0;
                    sclk_int <= 1'b1;
                    clk_cnt  <= '0;
                    inst_started <= 1'b0;
                    data_started <= 1'b0;
                    busy     <= done_flag ? 1'b0 : 1'b1;
                    done     <= done_flag ? 1'b1 : 1'b0;

                    if (done_flag && rw) begin
                        rd_data  <= data_shift_reg;
                        rd_valid <= 1'b1;
                    end
                end

                default: begin
                    spi_cs_n     <= 1'b1;
                    spi_sdi      <= 1'b0;
                    sclk_int     <= 1'b1;
                    busy         <= 1'b0;
                    done         <= 1'b0;
                    rd_valid     <= 1'b0;
                    clk_cnt      <= '0;
                    inst_bit_cnt <= '0;
                    data_bit_cnt <= '0;
                    inst_started <= 1'b0;
                    data_started <= 1'b0;
                end
            endcase
        end
    end

endmodule