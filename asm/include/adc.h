#ifndef ADC_H
#define ADC_H

#include <stdint.h>

#define ADC_OP_BASE        0xADCA0000u

#define ADC_OP_DELAY_NS    (ADC_OP_BASE | 0x0001)
#define ADC_OP_SAMPLE_NS   (ADC_OP_BASE | 0x0002)

typedef struct {
    uint32_t delay_ns;
    uint32_t sample_ns;
    uint32_t delay_ticks;
    uint32_t sample_ticks;
} adc_config_t;

void adc_process_config(adc_config_t *cfg);

#endif