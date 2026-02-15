module adc_exe (
    input  logic         clk,
    input  logic         rst_n,

    input  logic [1:0]   exe_op_type, // 1: Delay, 2: Sample
    input  logic [31:0]  exe_ticks,
    input  logic         exe_valid,
    output logic         exe_ready,

    // AD4080 
    output logic         adc_cnv,
    output logic         adc_cs_n,
    output logic         adc_sclk,
    input  logic         adc_sdo,

    output logic [19:0]  adc_raw_data,
    output logic         adc_data_valid
);

    // spi_reader
    logic        spi_start;
    logic        spi_done;
    logic [19:0] spi_data_out;

    typedef enum logic [1:0] { IDLE, DO_DELAY, DO_SAMPLE, ACK } state_e;
    state_e state;
    logic [31:0] delay_cnt;

    ad4080_spi_reader #(
        .CNV_HIG_CNT(5),
        .CONV_WAIT_CNT(60),
        .SCLK_HALF_CNT(1) 
    ) u_spi_reader (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (spi_start),
        .adc_cnv    (adc_cnv),
        .adc_cs_n   (adc_cs_n),
        .adc_sclk   (adc_sclk),
        .adc_sdo    (adc_sdo),
        .adc_data   (spi_data_out),
        .data_valid (spi_done)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            exe_ready  <= 1'b0;
            spi_start  <= 1'b0;
            delay_cnt  <= 32'd0;
            adc_data_valid <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    exe_ready <= 1'b1;
                    adc_data_valid <= 1'b0;
                    if (exe_valid) begin
                        exe_ready <= 1'b0;
                        if (exe_op_type == 2'b01) begin      // Delay 
                            delay_cnt <= 32'd0;
                            state     <= DO_DELAY;
                        end else if (exe_op_type == 2'b10) begin // Sample 
                            spi_start <= 1'b1; // reader
                            state     <= DO_SAMPLE;
                        end
                    end
                end

                DO_DELAY: begin
                    if (delay_cnt >= exe_ticks) begin
                        state <= ACK;
                    end else begin
                        delay_cnt <= delay_cnt + 1'b1;
                    end
                end

                DO_SAMPLE: begin
                    spi_start <= 1'b0; //  start 
                    if (spi_done) begin
                        adc_raw_data   <= spi_data_out;
                        adc_data_valid <= 1'b1;
                        state          <= ACK;
                    end
                end

                ACK: begin
                    adc_data_valid <= 1'b0;
                    exe_ready      <= 1'b1; 
                    state          <= IDLE;
                end
            endcase
        end
    end

endmodule