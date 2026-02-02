#include "common.h"
#include "dc.h"
#include "adc.h"
#include "launch.h"
#include "simcli.h"
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <assert.h>
#include <math.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <termios.h>

static int line_empty(char *s) {
    while (isspace((unsigned char)*s))
        s++;
    return *s == '\0' || *s == ';';
}

static int assemble(FILE *fp, 
                    dc_program_t *dc_programs[],
                    launch_t **launch,
                    adc_config_t *adc_cfg) {

    char line[256] = {0};

    typedef enum {
        PROGRAM,
        DC_CTRL,
        DC_REPEAT,
        DC_INSN,
        ADC_CTRL, //adc
        LAUNCH
    } state_t;

    state_t state = PROGRAM;

    char tmp[10];
    char *success = tmp;

    int i;

    while (success != NULL) {

        if (line_empty(line)) {
            success = fgets(line, sizeof(line), fp);
            continue;
        }
        uint32_t channel;
        switch (state) {

            case PROGRAM:{
                if (sscanf(line, ".program dc%u ", &channel)){

                    dc_programs[channel] = (dc_program_t *)calloc(1, sizeof(dc_program_t));
                    dc_programs[channel]->ctrl.dvsr = -1;
                    dc_programs[channel]->ctrl.cs_up_cycles = -1;
                    dc_programs[channel]->ctrl.ldac_cycles = -1;

                    state = DC_CTRL;
                    success = fgets(line, sizeof(line), fp);

                } else if (strncmp(line, ".launch", 7) == 0) {

                    *launch = (launch_t *)calloc(1, sizeof(launch_t));

                    state = LAUNCH;
                } else if (strncmp(line, ".adc_config", 11) == 0) {

                    state = ADC_CTRL;
                    success = fgets(line, sizeof(line), fp);

                } else {
                    return -1;
                }

                break;
            }
            case DC_CTRL:{

                int dc_dvsr;
                int dc_cs_up_cycles;
                int dc_ldac_cycles;

                if (sscanf(line, ".dvsr %d ", &dc_dvsr)) {

                    dc_programs[channel]->ctrl.dvsr = dc_dvsr;
                    assert(dc_dvsr > 0);

                    success = fgets(line, sizeof(line), fp);

                } else if (sscanf(line, ".csup %d ", &dc_cs_up_cycles)) {

                    dc_programs[channel]->ctrl.cs_up_cycles = dc_cs_up_cycles;
                    assert(dc_cs_up_cycles > 0);

                    success = fgets(line, sizeof(line), fp);

                } else if (sscanf(line, ".ldac %d ", &dc_ldac_cycles)) {

                    dc_programs[channel]->ctrl.ldac_cycles = dc_ldac_cycles;
                    assert(dc_ldac_cycles > 0);

                    success = fgets(line, sizeof(line), fp);

                } else {
                    state = DC_REPEAT;
                }

                break;
            }
            case DC_REPEAT:{

                uint32_t dc_repeat;

                if (sscanf(line, ".repeat %u ", &dc_repeat)) {

                    dc_programs[channel]->repeat = dc_repeat;
                    assert(dc_repeat > 0);
                    state = DC_INSN;

                    success = fgets(line, sizeof(line), fp);

                } else {
                    return -1;
                }

                break;
            }
            case DC_INSN:{

                dc_insn_t dc_insn;
                i = 0;

                while (success != NULL) {

                    if (dc_parse_insn(line, &dc_insn) == 0) {

                        if (i >= DC_DEPTH) {
                            printf("Exceeding maximum number of dc instructions:\n");
                            printf("%s\n", line);
                            return -1;
                        } else {
                            dc_programs[channel]->insns[i] = dc_insn;
                            success = fgets(line, sizeof(line), fp);
                            i++;
                        }

                    } else {
                        dc_programs[channel]->len = i;
                        dc_assemble(dc_programs[channel]);
                        i = 0;
                        state = PROGRAM;
                        break;
                    }

                }

                break;
            }
            case ADC_CTRL: {
                char *p = line;
                while (isspace((unsigned char)*p)) p++;

                if (sscanf(p, ".adc_delay %uns", &adc_cfg->delay_ns) == 1) {
                    success = fgets(line, sizeof(line), fp);
                } else if (sscanf(p, ".adc_sample %uns", &adc_cfg->sample_ns) == 1) {
                    success = fgets(line, sizeof(line), fp);
                } else {
                    adc_process_config(adc_cfg);
                    state = PROGRAM;
                }
                break;
            }


            case LAUNCH:

                launch_parse(line, *launch);
                state = PROGRAM;
                success = fgets(line, sizeof(line), fp);
                break;
            
            

        }
    }

    return 0;

}

static uint64_t program_t(dc_program_t *dc_programs[]) {

    uint64_t max_ns = 0;
    uint64_t cycle_ns = NS_PER_CYCLE;

    for (int i = 0; i < DC_CHANNELS; i++) {

        if (dc_programs[i] != NULL) {

            uint64_t t_ns = 0;

            for (unsigned int j = 0; j < dc_programs[i]->len; j++) {

                dc_insn_t *insn = &(dc_programs[i]->insns[j]);
                uint64_t iters = (uint64_t)insn->iters;
                uint64_t hold_cycles = (uint64_t)insn->hold_cycles;

                t_ns += iters * hold_cycles * cycle_ns;

            }

            uint64_t repeat = dc_programs[i]->repeat;
            t_ns *= repeat;

            if (t_ns > max_ns)
                max_ns = t_ns;

        }

    }

    return max_ns;

}

static void write_reg_sim(uint8_t idx, uint32_t data) {
    sim_sendf("0x%02X\n", (uint8_t)(idx & 0x7f));
    sim_sendf("0x%02X\n", (uint8_t)(data >> 24));
    sim_sendf("0x%02X\n", (uint8_t)(data >> 16));
    sim_sendf("0x%02X\n", (uint8_t)(data >> 8));
    sim_sendf("0x%02X\n", (uint8_t)(data));
}

static int write_sim(dc_program_t *dc_programs[], 
                     launch_t *launch) {

    if (sim_connect(SOCKET) != 0) {
        printf("Connection unseccessful\n");
        return -1;
    }

    for (int i = 0; i < DC_CHANNELS; i++) {

        if (dc_programs[i] != NULL) {

            write_reg_sim(DC_SEQ_REGS - 1, 0);
            
            for (unsigned int j = 0; j < DC_SEQ_REGS - 1; j++) {
                write_reg_sim(j, dc_programs[i]->seq_regs[j]);
            }

            write_reg_sim(DC_SEQ_REGS - 1, (1U << i));

            write_reg_sim(DC_SEQ_REGS + DC_CTRL_REGS - 1, 0);
            
            for (unsigned int j = 0; j < DC_CTRL_REGS - 1; j++) {
                if (dc_programs[i]->ctrl_regs[j] != -1)
                    write_reg_sim(DC_SEQ_REGS + j, dc_programs[i]->ctrl_regs[j]);
            }

            write_reg_sim(DC_SEQ_REGS + DC_CTRL_REGS - 1, (1U << i));

        }

    }

    if (launch != NULL) {

        uint32_t base = DC_SEQ_REGS + DC_CTRL_REGS + 15;

        write_reg_sim(base + LAUNCH_TOTAL_REGS - 1, 0);
        
        write_reg_sim(base, launch->dc_chmask);
        write_reg_sim(base + 1, launch->rf_chmask);
        write_reg_sim(base + 2, launch->li_chmask);
        write_reg_sim(base + LAUNCH_TOTAL_REGS - 1, 1);

    }

    sim_sendf("run %lu\n", program_t(dc_programs) + 1000);

    return 0;
}

static void write_bin(dc_program_t *dc_programs[], 
                      launch_t *launch,  adc_config_t *adc_cfg,
                      FILE *op) {

    for (int i = 0; i < DC_CHANNELS; i++) {

        if (dc_programs[i] != NULL) {

            fprintf(op, "dc%d\n", i);

            for (int j = 0; j < DC_SEQ_REGS; j++) {
                fprintf(op, "0x%08X\n", (dc_programs[i]->seq_regs)[j]);
            }

            for (int j = 0; j < DC_CTRL_REGS; j++) {
                fprintf(op, "0x%08X\n", (dc_programs[i]->ctrl_regs)[j]);
            }

            fprintf(op, "\n");

        }
    }

    if (launch != NULL) {

        fprintf(op, "launch\n");

        fprintf(op, "0x%08X\n", launch->dc_chmask);
        fprintf(op, "0x%08X\n", launch->rf_chmask);
        fprintf(op, "0x%08X\n", launch->li_chmask);
        fprintf(op, "0x%08X\n", 1);

        fprintf(op, "\n");

    }

        // ---- ADC config ----
    if (adc_cfg != NULL) {
        fprintf(op, "adc\n");

        fprintf(op, "0x%08X\n", ADC_OP_DELAY_NS);
        fprintf(op, "0x%08X\n", adc_cfg->delay_ns);

        fprintf(op, "0x%08X\n", ADC_OP_SAMPLE_NS);
        fprintf(op, "0x%08X\n", adc_cfg->sample_ns);

        fprintf(op, "\n");

    }

}

static int setup_uart(int fd, spped_t speed) {

    struct termios tty;

    if (tcgetattr(fd, &tty) != 0) {
        perror("tcgetattr");
        return -1;
    }

    // Set baud rate
    cfsetispeed(&tty, speed);
    cfsetospeed(&tty, speed);

    // 8N1, no flow control
    tty.c_cflag = (tty.c_cflag & ~CSIZE) | CS8; // 8-bit chars
    tty.c_iflag &= ~(IGNBRK | BRKINT | PARMRK | ISTRIP
                   | INLCR | IGNCR | ICRNL | IXON | IXOFF | IXANY);
    tty.c_lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
    tty.c_oflag &= ~OPOST;

    tty.c_cflag |= (CLOCAL | CREAD);            // ignore modem controls, enable reading
    tty.c_cflag &= ~(PARENB | PARODD);          // no parity
    tty.c_cflag &= ~CSTOPB;                     // 1 stop bit
    tty.c_cflag &= ~CRTSCTS;                    // no HW flow control

    // Read timeout behavior:
    // VMIN=0, VTIME=10 => read returns immediately with what’s available,
    // or waits up to 1.0s (10 deciseconds) for at least 1 byte.
    tty.c_cc[VMIN]  = 0;
    tty.c_cc[VTIME] = 10;

    if (tcsetattr(fd, TCSANOW, &tty) != 0) {
        perror("tcsetattr");
        return -1;
    }

    // Flush any pending data
    tcflush(fd, TCIOFLUSH);
    return 0;

}

int main(int argc, char *argv[]) {

    int opt;
    char *file = NULL;
    char *out = NULL;
    int sim = 0;
    int exe = 0;
    int uart = 0;
    char *ttyf = NULL;

    while ((opt = getopt(argc, argv, "f:o:sx")) != -1) {
        switch (opt) {
            case 'f':
                file = optarg;
                break;
            case 'o':
                out = optarg;
                break;
            case 's':
                sim = 1;
                break;
            case 'x':
                exe = 1;
                break;
            case 'u':
                uart = 1;
                ttyf = optarg;
            default:
                fprintf(stderr, "Usage: %s [-f file] [-o out] [-s] [-x]\n", argv[0]);
                return 1;
        }
    }

    if (file == NULL) {
        fprintf(stderr, "Usage: %s [-f file] [-o out] [-s] [-x] [-u]\n", argv[0]);
        return 1;
    }

    if (out == NULL) {
        out = "out";
    }

    FILE *fp = fopen(file, "r");
    dc_program_t *dc_programs[DC_CHANNELS] = {NULL};
    adc_config_t adc_cfg = {0};
    launch_t *launch = NULL;
    assemble(fp, dc_programs, &launch, &adc_cfg);

    FILE *op = fopen(out, "w");
    write_bin(dc_programs, launch, &adc_cfg, op);
    printf("program t: %ld ns\n", program_t(dc_programs));

    if (sim) {
        printf("simulate\n");
        write_sim(dc_programs, launch);
    }

    if (exe) {
        for (int ch = 0; ch < DC_CHANNELS; ch++) {
            if (dc_programs[ch] != NULL)
                dc_load_insns(ch, dc_programs[ch]);
        }
        if (launch != NULL)
            launch_load(launch);
    }

    if (uart) {

        int uartfd = open(ttyf, O_RDWR | O_NOCTTY | O_SYNC);

        if (fd < 0) {
            fprintf(stderr, "open(%s) failed: %s\n", ttyf, strerror(errno));
            return 1;
        }

        if (setup_uart(fd, B921600) != 0) {
            close(uartfd);
            return 1;
        }

        for (int ch = 0; ch < DC_CHANNELS; ch++) {
            if (dc_programs[ch] != NULL)
                dc_uart_insns(ch, dc_programs[ch]);
        }
        if (launch != NULL)
            launch_load(launch);
    }

    for (int i = 0; i < DC_CHANNELS; i++) {
        if (dc_programs[i] != NULL)
            free(dc_programs[i]);
    }
    if (launch != NULL)
        free(launch);

    return 0;

}

