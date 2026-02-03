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

    // Opcodes from adc.h
    localparam [31:16] ADC_OP_BASE = 16'hADCA;
    localparam [15:0]  OP_DELAY    = 16'h0001;
    localparam [15:0]  OP_SAMPLE   = 16'h0002;

    typedef enum logic { IDLE, WAIT_DATA } state_e;
    state_e state;

    logic [1:0] saved_op_type;

    assign if_ready = (state == IDLE) ? exe_ready : 1'b1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            exe_valid     <= 1'b0;
            exe_op_type   <= 2'b00;
            exe_ticks     <= 32'd0;
            saved_op_type <= 2'b00;
        end else begin
        
            if (exe_valid && exe_ready) begin
                exe_valid <= 1'b0;
            end

            case (state)
                IDLE: begin
                    if (if_valid && if_ready) begin
                        if (if_instr[31:16] == ADC_OP_BASE) begin
                            if (if_instr[15:0] == OP_DELAY) begin
                                saved_op_type <= 2'b01;
                                state         <= WAIT_DATA;
                            end else if (if_instr[15:0] == OP_SAMPLE) begin
                                saved_op_type <= 2'b10;
                                state         <= WAIT_DATA;
                            end
                        end
                    end
                end

                WAIT_DATA: begin
                    if (if_valid && if_ready) begin
                        exe_op_type <= saved_op_type;
                        exe_ticks   <= if_instr; 
                        exe_valid   <= 1'b1;
                        state       <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule