.program dc0
.repeat 10
    swp v1=0.85 v2=0.86 n=100 dt=1us (arm rd dvsr=5)
    lvl v=0.5 t=50ns (v+0.1)
    set cr 0xABCDE
    set dr 0xBEEF
    set scr 0xDEAD
    set clr 0xEFFE
    get scr
    get clr
    nop (rd)
    ful its=10 din=0xABCD cyc=100 (arm rd v+0.8 ldc)

.launch dc0

.adc_config
    .adc_delay 100ns
    .adc_sample 500ns
