#include "adc.h"

void adc_process_config(adc_config_t *cfg) {
    
    cfg->delay_ticks = cfg->delay_ns / 10;   //100MHz
    cfg->sample_ticks = cfg->sample_ns / 10;
}