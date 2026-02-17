set_property -dict { PACKAGE_PIN R4    IOSTANDARD LVCMOS33 } [get_ports { i_clk }]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports i_clk]

set_property -dict { PACKAGE_PIN AA19  IOSTANDARD LVCMOS33 } [get_ports { o_tx }]
set_property -dict { PACKAGE_PIN V18   IOSTANDARD LVCMOS33 } [get_ports { i_rx }]

set_property -dict { PACKAGE_PIN B22 IOSTANDARD LVCMOS12 } [get_ports { i_btn_c }]

## Pmod header JA
set_property -dict { PACKAGE_PIN AB22  IOSTANDARD LVCMOS33 } [get_ports { o_ja[0] }]; #IO_L10N_T1_D15_14 Sch=ja[1]
set_property -dict { PACKAGE_PIN AB21  IOSTANDARD LVCMOS33 } [get_ports { o_ja[1] }]; #IO_L10P_T1_D14_14 Sch=ja[2]
set_property -dict { PACKAGE_PIN AB20  IOSTANDARD LVCMOS33 } [get_ports { o_ja[2] }]; #IO_L15N_T2_DQS_DOUT_CSO_B_14 Sch=ja[3]
set_property -dict { PACKAGE_PIN AB18  IOSTANDARD LVCMOS33 } [get_ports { o_ja[3] }]; #IO_L17N_T2_A13_D29_14 Sch=ja[4]
set_property -dict { PACKAGE_PIN Y21   IOSTANDARD LVCMOS33 } [get_ports { o_ja[4] }]; #IO_L9P_T1_DQS_14 Sch=ja[7]
set_property -dict { PACKAGE_PIN AA21  IOSTANDARD LVCMOS33 } [get_ports { o_ja[5] }]; #IO_L8N_T1_D12_14 Sch=ja[8]
set_property -dict { PACKAGE_PIN AA20  IOSTANDARD LVCMOS33 } [get_ports { o_ja[6] }]; #IO_L8P_T1_D11_14 Sch=ja[9]
set_property -dict { PACKAGE_PIN AA18  IOSTANDARD LVCMOS33 } [get_ports { o_ja[7] }]; #IO_L17P_T2_A14_D30_14 Sch=ja[10]


## Pmod header JB
set_property -dict { PACKAGE_PIN V9    IOSTANDARD LVCMOS33 } [get_ports { o_jb[0] }]; #IO_L21P_T3_DQS_34 Sch=jb_p[1]
set_property -dict { PACKAGE_PIN V8    IOSTANDARD LVCMOS33 } [get_ports { o_jb[1] }]; #IO_L21N_T3_DQS_34 Sch=jb_n[1]
set_property -dict { PACKAGE_PIN V7    IOSTANDARD LVCMOS33 } [get_ports { o_jb[2] }]; #IO_L19P_T3_34 Sch=jb_p[2]
set_property -dict { PACKAGE_PIN W7    IOSTANDARD LVCMOS33 } [get_ports { o_jb[3] }]; #IO_L19N_T3_VREF_34 Sch=jb_n[2]
set_property -dict { PACKAGE_PIN W9    IOSTANDARD LVCMOS33 } [get_ports { o_jb[4] }]; #IO_L24P_T3_34 Sch=jb_p[3]
set_property -dict { PACKAGE_PIN Y9    IOSTANDARD LVCMOS33 } [get_ports { o_jb[5] }]; #IO_L24N_T3_34 Sch=jb_n[3]
set_property -dict { PACKAGE_PIN Y8    IOSTANDARD LVCMOS33 } [get_ports { o_jb[6] }]; #IO_L23P_T3_34 Sch=jb_p[4]
set_property -dict { PACKAGE_PIN Y7    IOSTANDARD LVCMOS33 } [get_ports { o_jb[7] }]; #IO_L23N_T3_34 Sch=jb_n[4]


## Pmod header JC
set_property -dict { PACKAGE_PIN Y6    IOSTANDARD LVCMOS33 } [get_ports { o_jc[0] }]; #IO_L18P_T2_34 Sch=jc_p[1]
set_property -dict { PACKAGE_PIN AA6   IOSTANDARD LVCMOS33 } [get_ports { o_jc[1] }]; #IO_L18N_T2_34 Sch=jc_n[1]
set_property -dict { PACKAGE_PIN AA8   IOSTANDARD LVCMOS33 } [get_ports { o_jc[2] }]; #IO_L22P_T3_34 Sch=jc_p[2]
set_property -dict { PACKAGE_PIN AB8   IOSTANDARD LVCMOS33 } [get_ports { o_jc[3] }]; #IO_L22N_T3_34 Sch=jc_n[2]
set_property -dict { PACKAGE_PIN R6    IOSTANDARD LVCMOS33 } [get_ports { o_jc[4] }]; #IO_L17P_T2_34 Sch=jc_p[3]
set_property -dict { PACKAGE_PIN T6    IOSTANDARD LVCMOS33 } [get_ports { o_jc[5] }]; #IO_L17N_T2_34 Sch=jc_n[3]
set_property -dict { PACKAGE_PIN AB7   IOSTANDARD LVCMOS33 } [get_ports { o_jc[6] }]; #IO_L20P_T3_34 Sch=jc_p[4]
set_property -dict { PACKAGE_PIN AB6   IOSTANDARD LVCMOS33 } [get_ports { o_jc[7] }]; #IO_L20N_T3_34 Sch=jc_n[4]
