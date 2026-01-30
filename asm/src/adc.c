#include "adc.h"

void adc_process_config(adc_config_t *cfg) {
    
    if (cfg->delay_ns > 0) {
        cfg->delay_ticks = cfg->delay_ns / 10;   //100MHz (10ns/tick)
    }
    if (cfg->sample_ns > 0) {
        cfg->sample_ticks = cfg->sample_ns / 10; //100MHz (10ns/tick)
    }
}