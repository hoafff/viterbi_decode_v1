# Clock: Toi thieu 200MHz -> Ck 5ns
# thu voi 4ns
create_clock -name clk -period 5.0 [get_ports clk]


# Clock Uncertainty
set_clock_uncertainty 0.15 [get_clocks clk]


# Input Delay
# delay 20% chu ki
set_input_delay -clock clk 1.0 [all_inputs]


# Output Delay
set_output_delay -clock clk 1.0 [all_outputs]


# Load
set_load 0.1 [all_outputs]

