# clock and reset
create_clock -period 10.000 -name sys_clk [get_ports i_clk]
set_property -dict {PACKAGE_PIN N14 IOSTANDARD LVCMOS33} [get_ports i_clk]
set_property -dict {PACKAGE_PIN P6 IOSTANDARD LVCMOS33} [get_ports i_rst_n]

# uart
set_property -dict {PACKAGE_PIN P15 IOSTANDARD LVCMOS33} [get_ports i_rx]
set_property -dict {PACKAGE_PIN P16 IOSTANDARD LVCMOS33} [get_ports o_tx]

# bank A
set_property -dict {PACKAGE_PIN N6 IOSTANDARD LVCMOS33} [get_ports o_a3]
set_property -dict {PACKAGE_PIN M6 IOSTANDARD LVCMOS33} [get_ports o_a5]
set_property -dict {PACKAGE_PIN P9 IOSTANDARD LVCMOS33} [get_ports o_a4]
set_property -dict {PACKAGE_PIN N9 IOSTANDARD LVCMOS33} [get_ports o_a6]

set_property -dict {PACKAGE_PIN J1 IOSTANDARD LVCMOS33} [get_ports o_a9]
set_property -dict {PACKAGE_PIN K1 IOSTANDARD LVCMOS33} [get_ports o_a11]
set_property -dict {PACKAGE_PIN L2 IOSTANDARD LVCMOS33} [get_ports o_a10]
set_property -dict {PACKAGE_PIN L3 IOSTANDARD LVCMOS33} [get_ports o_a12]

set_property -dict {PACKAGE_PIN H1 IOSTANDARD LVCMOS33} [get_ports o_a15]
set_property -dict {PACKAGE_PIN H2 IOSTANDARD LVCMOS33} [get_ports o_a17]
set_property -dict {PACKAGE_PIN K2 IOSTANDARD LVCMOS33} [get_ports o_a16]
set_property -dict {PACKAGE_PIN K3 IOSTANDARD LVCMOS33} [get_ports o_a18]

set_property -dict {PACKAGE_PIN E1 IOSTANDARD LVCMOS33} [get_ports o_a21]
set_property -dict {PACKAGE_PIN F2 IOSTANDARD LVCMOS33} [get_ports o_a23]
set_property -dict {PACKAGE_PIN H3 IOSTANDARD LVCMOS33} [get_ports o_a22]
set_property -dict {PACKAGE_PIN J3 IOSTANDARD LVCMOS33} [get_ports o_a24]

set_property -dict {PACKAGE_PIN G4 IOSTANDARD LVCMOS33} [get_ports o_a27]
set_property -dict {PACKAGE_PIN G5 IOSTANDARD LVCMOS33} [get_ports o_a29]
set_property -dict {PACKAGE_PIN H4 IOSTANDARD LVCMOS33} [get_ports o_a28]
set_property -dict {PACKAGE_PIN H5 IOSTANDARD LVCMOS33} [get_ports o_a30]

set_property -dict {PACKAGE_PIN G1 IOSTANDARD LVCMOS33} [get_ports o_a33]
set_property -dict {PACKAGE_PIN G2 IOSTANDARD LVCMOS33} [get_ports o_a35]
set_property -dict {PACKAGE_PIN J4 IOSTANDARD LVCMOS33} [get_ports o_a34]
set_property -dict {PACKAGE_PIN J5 IOSTANDARD LVCMOS33} [get_ports o_a36]

set_property -dict {PACKAGE_PIN C4 IOSTANDARD LVCMOS33} [get_ports o_a39]
set_property -dict {PACKAGE_PIN D4 IOSTANDARD LVCMOS33} [get_ports o_a41]
set_property -dict {PACKAGE_PIN D3 IOSTANDARD LVCMOS33} [get_ports o_a40]
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports o_a42]

set_property -dict {PACKAGE_PIN E5 IOSTANDARD LVCMOS33} [get_ports o_a45]
set_property -dict {PACKAGE_PIN F5 IOSTANDARD LVCMOS33} [get_ports o_a47]
set_property -dict {PACKAGE_PIN F3 IOSTANDARD LVCMOS33} [get_ports o_a46]
set_property -dict {PACKAGE_PIN F4 IOSTANDARD LVCMOS33} [get_ports o_a48]

set_property -dict {PACKAGE_PIN A3 IOSTANDARD LVCMOS33} [get_ports o_a51]
set_property -dict {PACKAGE_PIN B4 IOSTANDARD LVCMOS33} [get_ports o_a53]
set_property -dict {PACKAGE_PIN D5 IOSTANDARD LVCMOS33} [get_ports o_a52]
set_property -dict {PACKAGE_PIN D6 IOSTANDARD LVCMOS33} [get_ports o_a54]

set_property -dict {PACKAGE_PIN A4 IOSTANDARD LVCMOS33} [get_ports o_a57]
set_property -dict {PACKAGE_PIN A5 IOSTANDARD LVCMOS33} [get_ports o_a59]
set_property -dict {PACKAGE_PIN B1 IOSTANDARD LVCMOS33} [get_ports o_a58]
set_property -dict {PACKAGE_PIN C1 IOSTANDARD LVCMOS33} [get_ports o_a60]

set_property -dict {PACKAGE_PIN D1 IOSTANDARD LVCMOS33} [get_ports o_a63]
set_property -dict {PACKAGE_PIN E2 IOSTANDARD LVCMOS33} [get_ports o_a65]
set_property -dict {PACKAGE_PIN A2 IOSTANDARD LVCMOS33} [get_ports o_a64]
set_property -dict {PACKAGE_PIN B2 IOSTANDARD LVCMOS33} [get_ports o_a66]

set_property -dict {PACKAGE_PIN C2 IOSTANDARD LVCMOS33} [get_ports o_a69]
set_property -dict {PACKAGE_PIN C3 IOSTANDARD LVCMOS33} [get_ports o_a71]
set_property -dict {PACKAGE_PIN C6 IOSTANDARD LVCMOS33} [get_ports o_a70]
set_property -dict {PACKAGE_PIN C7 IOSTANDARD LVCMOS33} [get_ports o_a72]

set_property -dict {PACKAGE_PIN B5 IOSTANDARD LVCMOS33} [get_ports o_a75]
set_property -dict {PACKAGE_PIN B6 IOSTANDARD LVCMOS33} [get_ports o_a77]
set_property -dict {PACKAGE_PIN A7 IOSTANDARD LVCMOS33} [get_ports o_a76]
set_property -dict {PACKAGE_PIN B7 IOSTANDARD LVCMOS33} [get_ports o_a78]

# bank B
set_property -dict {PACKAGE_PIN T8 IOSTANDARD LVCMOS33} [get_ports o_b3]
set_property -dict {PACKAGE_PIN T7 IOSTANDARD LVCMOS33} [get_ports o_b5]
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports o_b4]
set_property -dict {PACKAGE_PIN T9 IOSTANDARD LVCMOS33} [get_ports o_b6]

set_property -dict {PACKAGE_PIN T5 IOSTANDARD LVCMOS33} [get_ports o_b9]
set_property -dict {PACKAGE_PIN R5 IOSTANDARD LVCMOS33} [get_ports o_b11]
set_property -dict {PACKAGE_PIN T12 IOSTANDARD LVCMOS33} [get_ports o_b10]
set_property -dict {PACKAGE_PIN R12 IOSTANDARD LVCMOS33} [get_ports o_b12]

set_property -dict {PACKAGE_PIN R7 IOSTANDARD LVCMOS33} [get_ports o_b15]
set_property -dict {PACKAGE_PIN R6 IOSTANDARD LVCMOS33} [get_ports o_b17]
set_property -dict {PACKAGE_PIN T13 IOSTANDARD LVCMOS33} [get_ports o_b16]
set_property -dict {PACKAGE_PIN R13 IOSTANDARD LVCMOS33} [get_ports o_b18]

set_property -dict {PACKAGE_PIN R8 IOSTANDARD LVCMOS33} [get_ports o_b21]
set_property -dict {PACKAGE_PIN P8 IOSTANDARD LVCMOS33} [get_ports o_b23]
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33} [get_ports o_b22]
set_property -dict {PACKAGE_PIN T14 IOSTANDARD LVCMOS33} [get_ports o_b24]

set_property -dict {PACKAGE_PIN R11 IOSTANDARD LVCMOS33} [get_ports o_b27]
set_property -dict {PACKAGE_PIN R10 IOSTANDARD LVCMOS33} [get_ports o_b29]
set_property -dict {PACKAGE_PIN R16 IOSTANDARD LVCMOS33} [get_ports o_b28]
set_property -dict {PACKAGE_PIN R15 IOSTANDARD LVCMOS33} [get_ports o_b30]

set_property -dict {PACKAGE_PIN K5 IOSTANDARD LVCMOS33} [get_ports o_b33]
set_property -dict {PACKAGE_PIN E6 IOSTANDARD LVCMOS33} [get_ports o_b35]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports o_b34]
set_property -dict {PACKAGE_PIN M16 IOSTANDARD LVCMOS33} [get_ports o_b36]

set_property -dict {PACKAGE_PIN P11 IOSTANDARD LVCMOS33} [get_ports o_b39]
set_property -dict {PACKAGE_PIN P10 IOSTANDARD LVCMOS33} [get_ports o_b41]
set_property -dict {PACKAGE_PIN P13 IOSTANDARD LVCMOS33} [get_ports o_b40]
set_property -dict {PACKAGE_PIN N13 IOSTANDARD LVCMOS33} [get_ports o_b42]

set_property -dict {PACKAGE_PIN N12 IOSTANDARD LVCMOS33} [get_ports o_b45]
set_property -dict {PACKAGE_PIN N11 IOSTANDARD LVCMOS33} [get_ports o_b47]
set_property -dict {PACKAGE_PIN D9 IOSTANDARD LVCMOS33} [get_ports o_b46]
set_property -dict {PACKAGE_PIN D10 IOSTANDARD LVCMOS33} [get_ports o_b48]

set_property -dict {PACKAGE_PIN M1 IOSTANDARD LVCMOS33} [get_ports o_b51]
set_property -dict {PACKAGE_PIN M2 IOSTANDARD LVCMOS33} [get_ports o_b53]
set_property -dict {PACKAGE_PIN P1 IOSTANDARD LVCMOS33} [get_ports o_b52]
set_property -dict {PACKAGE_PIN N1 IOSTANDARD LVCMOS33} [get_ports o_b54]

set_property -dict {PACKAGE_PIN N2 IOSTANDARD LVCMOS33} [get_ports o_b57]
set_property -dict {PACKAGE_PIN N3 IOSTANDARD LVCMOS33} [get_ports o_b59]
set_property -dict {PACKAGE_PIN R1 IOSTANDARD LVCMOS33} [get_ports o_b58]
set_property -dict {PACKAGE_PIN R2 IOSTANDARD LVCMOS33} [get_ports o_b60]

set_property -dict {PACKAGE_PIN P3 IOSTANDARD LVCMOS33} [get_ports o_b63]
set_property -dict {PACKAGE_PIN P4 IOSTANDARD LVCMOS33} [get_ports o_b65]
set_property -dict {PACKAGE_PIN T2 IOSTANDARD LVCMOS33} [get_ports o_b64]
set_property -dict {PACKAGE_PIN R3 IOSTANDARD LVCMOS33} [get_ports o_b66]

set_property -dict {PACKAGE_PIN M4 IOSTANDARD LVCMOS33} [get_ports o_b69]
set_property -dict {PACKAGE_PIN L4 IOSTANDARD LVCMOS33} [get_ports o_b71]
set_property -dict {PACKAGE_PIN T3 IOSTANDARD LVCMOS33} [get_ports o_b70]
set_property -dict {PACKAGE_PIN T4 IOSTANDARD LVCMOS33} [get_ports o_b72]

set_property -dict {PACKAGE_PIN L5 IOSTANDARD LVCMOS33} [get_ports o_b75]
set_property -dict {PACKAGE_PIN P5 IOSTANDARD LVCMOS33} [get_ports o_b77]
set_property -dict {PACKAGE_PIN N4 IOSTANDARD LVCMOS33} [get_ports o_b76]
set_property -dict {PACKAGE_PIN M5 IOSTANDARD LVCMOS33} [get_ports o_b78]