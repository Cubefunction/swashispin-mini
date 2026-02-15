module adc_core (
    input  logic         clk,
    input  logic         rst_n,

    // UART 
    input  logic [31:0]  uart_wr_data, 
    input  logic [6:0]   uart_addr,    
    input  logic         uart_wr_en,   

    // AD4080 
    output logic         adc_cnv,
    output logic         adc_cs_n,
    output logic         adc_sclk,
    input  logic         adc_sdo,

    //TO UART
    output logic [19:0]  adc_raw_data,
    output logic         adc_data_valid
);

    logic [31:0] fifo_dout;
    logic        fifo_empty;
    logic        fifo_re;

    logic [1:0]  exe_op_type;
    logic [31:0] exe_ticks;
    logic        exe_valid;
    logic        exe_ready;

    logic adc_reg_sel;
    assign adc_reg_sel = (uart_addr == 7'd50) && uart_wr_en;

    //  FIFO
    fifo #(
        .WIDTH(32),
        .DEPTH(16)
    ) u_instr_fifo (
        .i_clk(clk),
        .i_rst(!rst_n),
        .i_data(uart_wr_data),
        .i_enq(adc_reg_sel),   
        .i_deq(fifo_re),
        .o_data(fifo_dout),
        .o_full(),            
        .o_empty(fifo_empty)
    );

    //  decode
    adc_decode u_decode (
        .clk         (clk),
        .rst_n       (rst_n),
        .if_instr    (fifo_dout),
        .if_valid    (!fifo_empty),
        .if_ready    (fifo_re),
        .exe_op_type (exe_op_type),
        .exe_ticks   (exe_ticks),
        .exe_valid   (exe_valid),
        .exe_ready   (exe_ready)
    );

    // EXE
    adc_exe u_exe (
        .clk            (clk),
        .rst_n          (rst_n),
        .exe_op_type    (exe_op_type),
        .exe_ticks      (exe_ticks),
        .exe_valid      (exe_valid),
        .exe_ready      (exe_ready),

        .adc_cnv        (adc_cnv),
        .adc_cs_n       (adc_cs_n),
        .adc_sclk       (adc_sclk),
        .adc_sdo        (adc_sdo),

        .adc_raw_data   (adc_raw_data),
        .adc_data_valid(adc_data_valid)
    );

endmodule