#######################################################
#                                                     
#  Innovus Command Logging File                     
#  Created on Sun May 17 16:52:18 2026                
#                                                     
#######################################################

#@(#)CDS: Innovus v23.37-s090_1 (64bit) 02/09/2026 16:09 (Linux 3.10.0-693.el7.x86_64)
#@(#)CDS: NanoRoute 23.37-s090_1 NR260126-2134/23_17-UB (database version 18.20.682_1) {superthreading v2.20}
#@(#)CDS: AAE 23.17-s025 (64bit) 02/09/2026 (Linux 3.10.0-693.el7.x86_64)
#@(#)CDS: CTE 23.17-s038_1 () Feb  4 2026 22:23:13 ( )
#@(#)CDS: SYNTECH 23.17-s006_1 () Jan 20 2026 01:15:57 ( )
#@(#)CDS: CPE v23.17-s060
#@(#)CDS: IQuantus/TQuantus 23.1.1-s583 (64bit) Mon Nov 24 21:09:39 PST 2025 (Linux 3.10.0-693.el7.x86_64)

set_db init_power_nets VDD
set_db init_ground_nets VSS
read_mmmc viterbi_mmmc.view
#@ Begin verbose source viterbi_mmmc.view (pre)
create_library_set -name max_timing \
    -timing ../lib/sky130_ss_1.62_125_nldm.lib
create_library_set -name min_timing \
    -timing ../lib/sky130_ff_1.98_0_nldm.lib
create_timing_condition -name default_mapping_tc_1 \
    -library_sets max_timing
create_timing_condition -name default_mapping_tc_2 \
    -library_sets min_timing
create_rc_corner -name rccorners\
    -pre_route_res 1\
    -pre_route_cap 1\
    -post_route_res 1\
    -post_route_cap 1\
    -post_route_cross_cap 1\
    -pre_route_clock_res 0\
    -pre_route_clock_cap 0\
    -qrc_tech ../qrc/qrcTechFile_RCgen
create_delay_corner -name max_delay\
    -timing_condition default_mapping_tc_1\
    -rc_corner rccorners
create_delay_corner -name min_delay\
    -timing_condition default_mapping_tc_2\
    -rc_corner rccorners
create_constraint_mode -name sdc_cons\
    -sdc_files viterbi_sdc.sdc
create_analysis_view -name wc -constraint_mode sdc_cons -delay_corner max_delay
create_analysis_view -name bc -constraint_mode sdc_cons -delay_corner min_delay
set_analysis_view -setup wc -hold bc
#@ End verbose source viterbi_mmmc.view
exit
