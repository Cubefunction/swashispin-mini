#ifndef ADC_H
#define ADC_H

#include <stdint.h>

typedef struct {
    uint32_t delay_ns;
    uint32_t sample_ns;
    uint32_t delay_ticks;
    uint32_t sample_ticks;
} adc_config_t;

void adc_process_config(adc_config_t *cfg);

#endif