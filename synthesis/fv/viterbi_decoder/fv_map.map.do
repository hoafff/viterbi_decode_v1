
//input ports
add mapped point clk clk -type PI PI
add mapped point rst_n rst_n -type PI PI
add mapped point en en -type PI PI
add mapped point i_data[15] i_data[15] -type PI PI
add mapped point i_data[14] i_data[14] -type PI PI
add mapped point i_data[13] i_data[13] -type PI PI
add mapped point i_data[12] i_data[12] -type PI PI
add mapped point i_data[11] i_data[11] -type PI PI
add mapped point i_data[10] i_data[10] -type PI PI
add mapped point i_data[9] i_data[9] -type PI PI
add mapped point i_data[8] i_data[8] -type PI PI
add mapped point i_data[7] i_data[7] -type PI PI
add mapped point i_data[6] i_data[6] -type PI PI
add mapped point i_data[5] i_data[5] -type PI PI
add mapped point i_data[4] i_data[4] -type PI PI
add mapped point i_data[3] i_data[3] -type PI PI
add mapped point i_data[2] i_data[2] -type PI PI
add mapped point i_data[1] i_data[1] -type PI PI
add mapped point i_data[0] i_data[0] -type PI PI

//output ports
add mapped point o_data[7] o_data[7] -type PO PO
add mapped point o_data[6] o_data[6] -type PO PO
add mapped point o_data[5] o_data[5] -type PO PO
add mapped point o_data[4] o_data[4] -type PO PO
add mapped point o_data[3] o_data[3] -type PO PO
add mapped point o_data[2] o_data[2] -type PO PO
add mapped point o_data[1] o_data[1] -type PO PO
add mapped point o_data[0] o_data[0] -type PO PO
add mapped point o_done o_done -type PO PO

//inout ports




//Sequential Pins
add mapped point u_memory/pm00[0]/q u_memory_pm00_reg[0]/Q -type DFF DFF
add mapped point u_memory/pm10[1]/q u_memory_pm10_reg[1]/Q -type DFF DFF
add mapped point u_memory/pm00[1]/q u_memory_pm00_reg[1]/Q -type DFF DFF
add mapped point u_memory/pm10[0]/q u_memory_pm10_reg[0]/Q -type DFF DFF
add mapped point u_memory/pm11[1]/q u_memory_pm11_reg[1]/Q -type DFF DFF
add mapped point u_memory/pm01[1]/q u_memory_pm01_reg[1]/Q -type DFF DFF
add mapped point u_memory/pm01[0]/q u_memory_pm01_reg[0]/Q -type DFF DFF
add mapped point u_memory/pm11[0]/q u_memory_pm11_reg[0]/Q -type DFF DFF
add mapped point u_memory/dec_s5[0]/q u_memory_dec_s5_reg[0]/Q -type DFF DFF
add mapped point u_memory/dec_s3[0]/q u_memory_dec_s3_reg[0]/Q -type DFF DFF
add mapped point u_memory/dec_s5[2]/q u_memory_dec_s5_reg[2]/Q -type DFF DFF
add mapped point u_memory/dec_s3[2]/q u_memory_dec_s3_reg[2]/Q -type DFF DFF
add mapped point u_memory/dec_s7/q u_memory_dec_s7_reg/Q -type DFF DFF
add mapped point u_memory/dec_s5[1]/q u_memory_dec_s5_reg[1]/Q -type DFF DFF
add mapped point u_memory/dec_s3[1]/q u_memory_dec_s3_reg[1]/Q -type DFF DFF
add mapped point u_memory/dec_s5[3]/q u_memory_dec_s5_reg[3]/Q -type DFF DFF
add mapped point u_memory/dec_s3[3]/q u_memory_dec_s3_reg[3]/Q -type DFF DFF
add mapped point u_memory/dec_s2[0]/q u_memory_dec_s2_reg[0]/Q -type DFF DFF
add mapped point u_memory/dec_s2[2]/q u_memory_dec_s2_reg[2]/Q -type DFF DFF
add mapped point u_memory/dec_s4[2]/q u_memory_dec_s4_reg[2]/Q -type DFF DFF
add mapped point u_memory/dec_s4[0]/q u_memory_dec_s4_reg[0]/Q -type DFF DFF
add mapped point u_memory/dec_s6[0]/q u_memory_dec_s6_reg[0]/Q -type DFF DFF
add mapped point u_memory/dec_s2[1]/q u_memory_dec_s2_reg[1]/Q -type DFF DFF
add mapped point u_memory/dec_s4[1]/q u_memory_dec_s4_reg[1]/Q -type DFF DFF
add mapped point u_memory/dec_s6[1]/q u_memory_dec_s6_reg[1]/Q -type DFF DFF
add mapped point u_memory/dec_s2[3]/q u_memory_dec_s2_reg[3]/Q -type DFF DFF
add mapped point u_memory/dec_s4[3]/q u_memory_dec_s4_reg[3]/Q -type DFF DFF
add mapped point u_memory/o_data[7]/q u_memory_o_data_reg[7]/Q -type DFF DFF
add mapped point u_memory/o_data[6]/q u_memory_o_data_reg[6]/Q -type DFF DFF
add mapped point u_memory/rx_reg[9]/q u_memory_rx_reg_reg[9]/Q -type DFF DFF
add mapped point u_memory/rx_reg[5]/q u_memory_rx_reg_reg[5]/Q -type DFF DFF
add mapped point u_memory/rx_reg[11]/q u_memory_rx_reg_reg[11]/Q -type DFF DFF
add mapped point u_memory/rx_reg[2]/q u_memory_rx_reg_reg[2]/Q -type DFF DFF
add mapped point u_memory/rx_reg[0]/q u_memory_rx_reg_reg[0]/Q -type DFF DFF
add mapped point u_memory/rx_reg[14]/q u_memory_rx_reg_reg[14]/Q -type DFF DFF
add mapped point u_memory/rx_reg[1]/q u_memory_rx_reg_reg[1]/Q -type DFF DFF
add mapped point u_memory/rx_reg[10]/q u_memory_rx_reg_reg[10]/Q -type DFF DFF
add mapped point u_memory/rx_reg[6]/q u_memory_rx_reg_reg[6]/Q -type DFF DFF
add mapped point u_memory/rx_reg[4]/q u_memory_rx_reg_reg[4]/Q -type DFF DFF
add mapped point u_memory/rx_reg[7]/q u_memory_rx_reg_reg[7]/Q -type DFF DFF
add mapped point u_memory/rx_reg[8]/q u_memory_rx_reg_reg[8]/Q -type DFF DFF
add mapped point u_memory/rx_reg[3]/q u_memory_rx_reg_reg[3]/Q -type DFF DFF
add mapped point u_memory/rx_reg[15]/q u_memory_rx_reg_reg[15]/Q -type DFF DFF
add mapped point u_memory/rx_reg[13]/q u_memory_rx_reg_reg[13]/Q -type DFF DFF
add mapped point u_memory/rx_reg[12]/q u_memory_rx_reg_reg[12]/Q -type DFF DFF
add mapped point u_memory/o_data[5]/q u_memory_o_data_reg[5]/Q -type DFF DFF
add mapped point u_memory/o_data[4]/q u_memory_o_data_reg[4]/Q -type DFF DFF
add mapped point u_control/state[0]/q u_control_state_reg[0]/Q -type DFF DFF
add mapped point u_memory/o_data[3]/q u_memory_o_data_reg[3]/Q -type DFF DFF
add mapped point u_control/state[2]/q u_control_state_reg[2]/Q -type DFF DFF
add mapped point u_memory/o_data[2]/q u_memory_o_data_reg[2]/Q -type DFF DFF
add mapped point u_control/state[1]/q u_control_state_reg[1]/Q -type DFF DFF
add mapped point u_memory/o_done/q u_memory_o_done_reg/Q -type DFF DFF



//Black Boxes



//Empty Modules as Blackboxes
