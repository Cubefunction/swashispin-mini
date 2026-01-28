module adc_decode (
    input  logic        clk,
    input  logic        rst_n,

    // Fetch 
    input  logic [31:0] if_instr,
    input  logic        if_valid,
    output logic        if_ready,

    // Execute
    output logic [1:0]  exe_op_type, // 1: Delay, 2: Sample
    output logic [31:0] exe_ticks,
    output logic        exe_valid,
    input  logic        exe_ready
);

    // adc.h design
    localparam [31:16] ADC_OP_BASE = 16'hADCA;
    localparam [15:0]  OP_DELAY    = 16'h0001;
    localparam [15:0]  OP_SAMPLE   = 16'h0002;

    typedef enum logic { IDLE, WAIT_DATA } state_e;
    state_e state;

    logic [1:0] saved_op_type;

    // after IDLE  Fetch next
    assign if_ready = (state == IDLE && exe_ready) || (state == WAIT_DATA);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            exe_valid    <= 1'b0;
            exe_op_type  <= 2'b00;
            exe_ticks    <= 32'd0;
            saved_op_type <= 2'b00;
        end else begin
            case (state)
                IDLE: begin
                    exe_valid <= 1'b0;
                    // Identify: Opcode base address
                    if (if_valid && if_ready && (if_instr[31:16] == ADC_OP_BASE)) begin
                        saved_op_type <= (if_instr[15:0] == OP_DELAY) ? 2'b01 : 2'b10;
                        state         <= WAIT_DATA;
                    end
                end

                WAIT_DATA: begin
                    // Identify：Ticks 
                    if (if_valid && if_ready) begin
                        exe_op_type <= saved_op_type;
                        exe_ticks   <= if_instr; 
                        exe_valid   <= 1'b1;
                        state       <= IDLE;
                    end
                end
            endcase

            // valid
            if (exe_valid && exe_ready) begin
                exe_valid <= 1'b0;
            end
        end
    end

endmodule