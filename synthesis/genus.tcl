set_db init_lib_search_path ../lib/
set_db init_hdl_search_path ../rtl/

read_libs sky130_ss_1.62_125_nldm.lib
read_hdl {add_comp_slt.v branch_metric.v control.v extract_bit.v memory.v traceback.v viterbi_decoder.v} 

elaborate viterbi_decoder

read_sdc ../constraints/constraints.sdc

set_db [get_db lib_cells *SDFF*] .dont_use true

set_db syn_generic_effort high
set_db syn_map_effort high
set_db syn_opt_effort high

syn_generic
syn_map
syn_opt

# Report
report_timing > reports/report_timing.rpt
report_area   > reports/report_area.rpt
report_power  > reports/report_power.rpt
report_gates  > reports/report_gates.rpt
report_qor    > reports/report_qor.rpt

# Output
write_hdl > outputs/viterbi_netlist.v
write_sdc > outputs/viterbi_sdc.sdc
