`timescale 1ns/1ps

module ad9833_spi_master #(
    parameter int FRAME_W = 16,
    parameter int CLK_DIV = 10
)(
    input  logic                clk,
    input  logic                rst_n,
    input  logic                start,
    input  logic [FRAME_W-1:0]  frame_data,

    output logic                spi_sclk,
    output logic                spi_fsync,
    output logic                spi_mosi,
    output logic                done,
    output logic                busy
);

    typedef enum logic [1:0] {
        IDLE,
        TRANSFER,
        DONE
    } state_t;

    state_t state, next_state;
    logic [FRAME_W-1:0] shift_reg;
    logic [$clog2(FRAME_W+1)-1:0] bit_cnt;
    logic [$clog2(CLK_DIV)-1:0]   clk_cnt;
    logic                         sclk_int;
    
    
    localparam int DELAY_DONE = 2*CLK_DIV;
    logic done_flag;
    logic [$clog2(DELAY_DONE)-1:0] done_cnt;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done_cnt <= 'd0;
            done_flag <= 'd0;
        end
        else if (done_cnt == DELAY_DONE - 1)begin
            done_cnt <= 'd0;
            done_flag <= 'd1;
        end
        else if (state == DONE)
            done_cnt <= done_cnt + 1'b1;
        else
            done_flag <= 'd0;
    end

    //------------------------------------------------
    // SPI clock output
    //------------------------------------------------
    assign spi_sclk = (state == TRANSFER) ? sclk_int : 1'b1;


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

            //----------------------------------------
            // IDLE
            //----------------------------------------
            IDLE: begin
                if (start)
                    next_state = TRANSFER;
            end

            //----------------------------------------
            // TRANSFER
            //----------------------------------------
            TRANSFER: begin
                if ((clk_cnt == CLK_DIV-1) && (sclk_int == 1'b0) && (bit_cnt == 0))
                    next_state = DONE;
            end

            //----------------------------------------
            // DONE
            //----------------------------------------
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
            shift_reg <= '0;
            bit_cnt   <= '0;
            clk_cnt   <= '0;
            sclk_int  <= 1'b1;

            spi_fsync <= 1'b1;
            spi_mosi  <= 1'b0;
            busy      <= 1'b0;
            done      <= 1'b0;
        end
        else begin
            
            done <= 1'b0;

            case (state)

                //----------------------------------------
                // IDLE
                //----------------------------------------
                IDLE: begin
                    spi_fsync <= 1'b1;
                    spi_mosi  <= 1'b0;
                    sclk_int  <= 1'b1;
                    clk_cnt   <= '0;
                    bit_cnt   <= '0;
                    busy      <= 1'b0;

                    if (start) begin
                        shift_reg <= frame_data;
                        spi_mosi  <= frame_data[FRAME_W-1];
                        bit_cnt   <= FRAME_W;
                        spi_fsync <= 1'b0;
                        busy      <= 1'b1;
                        sclk_int  <= 1'b1;
                        clk_cnt   <= '0;
                    end
                end

                //----------------------------------------
                // TRANSFER
                //----------------------------------------
                TRANSFER: begin
                    spi_fsync <= 1'b0;
                    busy      <= 1'b1;

                    if (clk_cnt == CLK_DIV-1) begin
                        clk_cnt  <= '0;
                        sclk_int <= ~sclk_int;

                        //--------------------------------
                        // Falling edge: consume one bit
                        //--------------------------------
                        if (sclk_int == 1'b1) begin
                            if (bit_cnt != 0)
                                bit_cnt <= bit_cnt - 1'b1;
                        end
                        //--------------------------------
                        // Rising edge: prepare next bit
                        //--------------------------------
                        else begin
                            if (bit_cnt >= 1) begin
                                shift_reg <= {shift_reg[FRAME_W-2:0], 1'b0};
                                spi_mosi  <= shift_reg[FRAME_W-2];
                            end
                            else begin
                                spi_mosi <= 1'b0;
                            end
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
                    spi_fsync <= 1'b1;
                    spi_mosi  <= 1'b0;
                    sclk_int  <= 1'b1;
                    busy      <= done_flag ? 1'b0 : 1'b1;
                    clk_cnt   <= '0;
                    done      <= done_flag ? 1'b1 : 1'b0;   
                end

                default: begin
                    spi_fsync <= 1'b1;
                    spi_mosi  <= 1'b0;
                    sclk_int  <= 1'b1;
                    busy      <= 1'b0;
                    done      <= 1'b0;
                    clk_cnt   <= '0;
                    bit_cnt   <= '0;
                end
            endcase
        end
    end

endmodule