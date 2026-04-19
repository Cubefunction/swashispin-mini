`timescale 1ns/1ps

module ad4080_model_8bit #(
    parameter int ADDR_W        = 15,
    parameter int DATA_W        = 8,
    parameter int PHASE_W       = 16,
    parameter int PHASE_STEP    = 16'd2048,
    parameter logic [ADDR_W-1:0] SAMPLE_H_ADDR = 15'h0004,
    parameter logic [ADDR_W-1:0] SAMPLE_L_ADDR = 15'h0005
)(
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 sample_trigger,

    input  logic                 spi_cs_n,
    input  logic                 spi_sclk,
    input  logic                 spi_sdi,
    output logic                 spi_sdo
);

    localparam int INST_W = 1 + ADDR_W;

    //==================================================
    // sine LUT
    //==================================================
    logic signed [15:0] sine_lut [0:255];
    logic [PHASE_W-1:0] phase_acc;
    logic signed [15:0] sample_data;
    logic [7:0]         lut_addr;

    integer i;
    real angle, val;

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            angle = 2.0 * 3.14159265358979323846 * i / 256.0;
            val   = $sin(angle) * 32767.0;
            sine_lut[i] = $rtoi(val);
        end
    end

    assign lut_addr = phase_acc[15:8];

    //==================================================
    // sample update
    //==================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_acc   <= '0;
            sample_data <= '0;
        end
        else if (sample_trigger) begin
            phase_acc   <= phase_acc + PHASE_STEP;
            sample_data <= sine_lut[lut_addr];
        end
    end

    //==================================================
    // SPI instruction receive
    //==================================================
    logic [INST_W-1:0] inst_shift;
    logic [INST_W-1:0] inst_word;
    integer            inst_cnt;
    logic              data_phase;
    logic              rw_lat;
    logic [ADDR_W-1:0] addr_lat;

    always_ff @(posedge spi_sclk or negedge rst_n or posedge spi_cs_n) begin
        if (!rst_n) begin
            inst_shift <= '0;
            inst_word  <= '0;
            inst_cnt   <= 0;
            data_phase <= 1'b0;
            rw_lat     <= 1'b0;
            addr_lat   <= '0;
        end
        else if (spi_cs_n) begin
            inst_shift <= '0;
            inst_word  <= '0;
            inst_cnt   <= 0;
            data_phase <= 1'b0;
            rw_lat     <= 1'b0;
            addr_lat   <= '0;
        end
        else if (!data_phase) begin
            inst_word  = {inst_shift[INST_W-2:0], spi_sdi};
            inst_shift <= inst_word;

            if (inst_cnt == INST_W-1) begin
                rw_lat     <= inst_word[INST_W-1];
                addr_lat   <= inst_word[ADDR_W-1:0];
                inst_cnt   <= inst_cnt + 1;
                data_phase <= 1'b1;
            end
            else begin
                inst_cnt <= inst_cnt + 1;
            end
        end
    end

    //==================================================
    // read back one byte
    //==================================================
    logic [7:0] rd_shift;
    logic [7:0] read_byte;
    integer     rd_idx;
    logic       load_done;

    always_comb begin
        case (addr_lat)
            SAMPLE_H_ADDR: read_byte = sample_data[15:8];
            SAMPLE_L_ADDR: read_byte = sample_data[7:0];
            default:       read_byte = 8'h00;
        endcase
    end

    always_ff @(negedge spi_sclk or negedge rst_n or posedge spi_cs_n) begin
        if (!rst_n) begin
            rd_shift  <= 8'h00;
            rd_idx    <= 7;
            spi_sdo   <= 1'b0;
            load_done <= 1'b0;
        end
        else if (spi_cs_n) begin
            rd_shift  <= 8'h00;
            rd_idx    <= 7;
            spi_sdo   <= 1'b0;
            load_done <= 1'b0;
        end
        else if (data_phase && rw_lat) begin
            if (!load_done) begin
                rd_shift  <= read_byte;
                spi_sdo   <= read_byte[7];
                rd_idx    <= 6;
                load_done <= 1'b1;
            end
            else begin
                spi_sdo <= rd_shift[rd_idx];
                if (rd_idx > 0)
                    rd_idx <= rd_idx - 1;
                else
                    rd_idx <= 7;
            end
        end
        else begin
            spi_sdo <= 1'b0;
        end
    end

endmodule