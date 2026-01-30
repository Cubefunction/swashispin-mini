module adc_core (
    input  logic        clk,
    input  logic        rst_n,

    // uart_regs 
    input  logic [31:0] uart_wr_data, 
    input  logic [6:0]  uart_addr,    
    input  logic        uart_wr_en,   

    // Execute SPI
    output logic [1:0]  exe_op_type,
    output logic [31:0] exe_ticks,
    output logic        exe_valid,
    input  logic        exe_ready
);

    //   FIFO 
    logic [31:0] fifo_dout;
    logic        fifo_empty;
    logic        fifo_re;
    
    //  ADC addr 50
    logic        adc_reg_sel;
    assign adc_reg_sel = (uart_addr == 7'd50) && uart_wr_en;

    fifo #(
        .WIDTH(32),
        .DEPTH(16)
    ) u_instr_fifo (
        .i_clk(clk),
        .i_rst(!rst_n),
        .i_data(uart_wr_data),
        .i_enq(adc_reg_sel),   //  50 
        .i_deq(fifo_re),
        .o_data(fifo_dout),
        .o_full(),
        .o_empty(fifo_empty)
    );

    adc_decode u_decode (
        .clk       (clk),
        .rst_n     (rst_n),
        
        // Fetch 
        .if_instr  (fifo_dout),
        .if_valid  (!fifo_empty),
        .if_ready  (fifo_re),

        // Execute  
        .exe_op_type(exe_op_type),
        .exe_ticks  (exe_ticks),
        .exe_valid  (exe_valid),
        .exe_ready  (exe_ready)
    );

endmodule