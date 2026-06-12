############################################################
# Innovus Physical Design Flow
# Design: viterbi_decoder
############################################################

set DESIGN_NAME viterbi_decoder

# Input files
set MMMC_FILE   viterbi_mmmc.view
set NETLIST     viterbi_netlist.v

set LEF_FILES [list \
    ../lef/sky130_scl_9T.tlef \
    ../lef/sky130_scl_9T.lef \
    ../lef/sky130_scl_9T_phyCells.lef \
]

# Power/Ground nets
set PWR_NET VDD
set GND_NET VSS

# Output folders
file mkdir reports
file mkdir db
file mkdir gds

############################################################
# 1. Init design
############################################################

set_db init_power_nets  $PWR_NET
set_db init_ground_nets $GND_NET

read_mmmc $MMMC_FILE
read_physical -lef $LEF_FILES
read_netlist $NETLIST

init_design

############################################################
# 2. Connect global power/ground nets
############################################################

connect_global_net VDD -type pg_pin -pin_base_name VDD -inst_base_name *
connect_global_net VSS -type pg_pin -pin_base_name VSS -inst_base_name *

############################################################
# 3. Floorplan
# S?a thông s? n?u lab yêu c?u khác
############################################################

# N?u b?n dã có floorplan trong GUI thì có th? comment dòng này.
# D?ng co b?n: floorplan v?i utilization 0.7, margin 10um
create_floorplan \
    -core_margins_by die \
    -site CoreSite \
    -core_density_size 0.70 10 10 10 10

############################################################
# 4. Pin assignment
# B?n có th? s?a l?i chia pin theo Left/Right/Top/Bottom
############################################################

set_db assign_pins_edit_in_batch true

# Control pins bên Left
edit_pin \
    -unit micron \
    -pin_width 0.3 \
    -pin_depth 0.8 \
    -fix_overlap 1 \
    -side Left \
    -layer 3 \
    -spread_type center \
    -spacing 4 \
    -pin {clk rst_n en}

# Input data bên Bottom
edit_pin \
    -unit micron \
    -pin_width 0.3 \
    -pin_depth 0.8 \
    -fix_overlap 1 \
    -side Bottom \
    -layer 2 \
    -spread_type center \
    -spacing 4 \
    -pin {{i_data[0]} {i_data[1]} {i_data[2]} {i_data[3]} {i_data[4]} {i_data[5]} {i_data[6]} {i_data[7]} {i_data[8]} {i_data[9]} {i_data[10]} {i_data[11]} {i_data[12]} {i_data[13]} {i_data[14]} {i_data[15]}}

# Output data bên Right
edit_pin \
    -unit micron \
    -pin_width 0.3 \
    -pin_depth 0.8 \
    -fix_overlap 1 \
    -side Right \
    -layer 3 \
    -spread_type center \
    -spacing 4 \
    -pin {{o_data[0]} {o_data[1]} {o_data[2]} {o_data[3]} {o_data[4]} {o_data[5]} {o_data[6]} {o_data[7]} o_done}

set_db assign_pins_edit_in_batch false

check_pin_assignment > reports/check_pin_assignment.rpt

############################################################
# 5. Power ring and power stripe
# Ch? này có th? c?n ch?nh layer/width/spacing theo lab
############################################################

add_rings \
    -nets "$PWR_NET $GND_NET" \
    -type core_rings \
    -follow core \
    -layer {top met5 bottom met5 left met4 right met4} \
    -width {top 1.0 bottom 1.0 left 1.0 right 1.0} \
    -spacing {top 1.0 bottom 1.0 left 1.0 right 1.0} \
    -offset {top 2.0 bottom 2.0 left 2.0 right 2.0}

add_stripes \
    -nets "$PWR_NET $GND_NET" \
    -layer met4 \
    -direction vertical \
    -width 0.8 \
    -spacing 0.8 \
    -set_to_set_distance 20

############################################################
# 6. Special route: route VDD/VSS follow pins/ring/stripe
############################################################

route_special \
    -connect {core_pin pad_pin block_pin} \
    -nets "$PWR_NET $GND_NET" \
    -core_pin_target first_after_row_end \
    -allow_jogging 1 \
    -crossover_via_layer_range {met1 met5} \
    -target_via_layer_range {met1 met5}

write_db db/floorplanning

############################################################
# 7. Placement optimization
############################################################

place_opt_design

write_db db/placeOpt

############################################################
# 8. CTS setup
############################################################

set_db cts_buffer_cells {CLKBUFX4 CLKBUFX8}
set_db cts_inverter_cells {CLKINVX4 CLKINVX8}

create_clock_tree_spec

############################################################
# 9. Clock optimization / CTS
############################################################

clock_opt_design

write_db db/postCTSOpt

############################################################
# 10. NanoRoute
############################################################

set_db route_design_detail_end_iteration 10
set_db route_design_with_timing_driven true
set_db route_design_with_si_driven true

route_design

############################################################
# 11. Extract RC and timing analysis
############################################################

extract_rc

set_db timing_analysis_type ocv

time_design -post_route       > reports/timing_post_route_setup.rpt
time_design -post_route -hold > reports/timing_post_route_hold.rpt

############################################################
# 12. DRC / Connectivity check before filler
############################################################

check_drc          > reports/check_drc_before_filler.rpt
check_connectivity > reports/check_connectivity_before_filler.rpt

############################################################
# 13. Add filler cells
# N?u báo không tìm th?y cell, g?i mình tên filler trong LEF/lib
############################################################

add_fillers \
    -cells {FILL1 FILL2 FILL4 FILL8} \
    -prefix FILLER

############################################################
# 14. DRC / Connectivity check after filler
############################################################

check_drc          > reports/check_drc_after_filler.rpt
check_connectivity > reports/check_connectivity_after_filler.rpt

############################################################
# 15. Fix DRC if needed
############################################################

set_db route_detail_end_iteration 19
route_design

check_drc          > reports/check_drc_final.rpt
check_connectivity > reports/check_connectivity_final.rpt

############################################################
# 16. Final reports
############################################################

report_power  > reports/report_power.rpt
report_area   > reports/report_area.rpt
report_gates  > reports/report_gates.rpt
report_timing > reports/report_timing.rpt

############################################################
# 17. Save final database
############################################################

write_db db/postRouteOpt

############################################################
# 18. Optional: write GDS
# C?n map file n?u lab có cung c?p streamOut.map / gds.map
############################################################

# N?u lab có map file, dùng dòng du?i và s?a tên map:
# write_stream -format gds -lib_name $DESIGN_NAME -units 1000 -map_file streamOut.map gds/${DESIGN_NAME}.gds

# N?u write_stream không ch?y, xu?t GDS b?ng GUI:
# File -> Save -> GDS/OASIS

############################################################
# Done
############################################################

puts "============================================================"
puts "Innovus flow completed."
puts "Reports are in ./reports"
puts "Final DB is db/postRouteOpt"
puts "============================================================"
