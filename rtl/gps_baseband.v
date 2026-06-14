//                              -*- Mode: Verilog -*-
// Filename        : gps_baseband.v
// Description     : top level, includes address decoder and X tracking channels
// Author          : Peter Mumford UNSW 2005
// Modified by     : Takji Ebinuma, 2026

/* This module connects to the Avalon bus

 address map
 block       address offset
 -------------------------
 chan 0        00-0F
 chan 1        10-1F
 chan 2        20-2F
 chan 3        30-3F
 chan 4        40-4F
 chan 5        50-5F
 chan 6        60-6F
 chan 7        70-7F
 chan 8        80-8F
 chan 9        90-9F
 chan 10       A0-AF
 chan 11       B0-BF
 spare         C0-CF
 spare         D0-DF
 status        E0-EF
 control       F0-FF
 
 channel     address offset
 -------------------------
 prn_key      0    write
 carrier_nco  1    write
 code_nco     2    write
 code_slew    3    write
 I_early      4    read
 Q_early      5    read
 I_prompt     6    read
 Q_prompt     7    read
 I_late       8    read
 Q_late       9    read
 carrier_val  A    read
 code_val     B    read
 epoch        C    read
 epoch_check  D    read
 spare       E-F
 
 status     address offset
 -------------------------
 status       0    read
 new_data     1    read
 tic_count    2    read
 accum_count  3    read
 spare       4-F
 
 control    address offset
 -------------------------
 reset           0
 prog_tic        1   write
 prog_accum_int  2   write
 spare          3-F
 
*/

`timescale 1ns/1ps

module gps_baseband (clk, hw_rstn,
		     sign_in, mag_in,
		     chip_select, write, read, 
           address, write_data, read_data,
           accum_int
		     );

   input clk, hw_rstn, chip_select, write, read;
   input sign_in, mag_in; // raw data in from RF front end
   input [7:0] address;
   input [31:0] write_data;
	output reg [31:0] read_data;
   output reg accum_int; // interrupt pulse to tell FW to collect accumulation data, cleared on STATUS read

   wire accum_enable_s;
   wire pre_tic_enable, tic_enable;

   wire [23:0] tic_count;
   wire [23:0] accum_count;

   reg sw_rst; // reset to tracking module
   wire rstn; // software generated reset  

   reg [11:0] ch_active;  // 1 = channel is active (PRN key has been programmed at least once)

   // channel 0 registers
   reg [9:0] ch0_prn_key;
   reg [27:0] ch0_carr_nco;
   reg [26:0] ch0_code_nco;
   reg [10:0] ch0_code_slew;
   reg [10:0] ch0_epoch_load;
   reg ch0_prn_key_enable, ch0_slew_enable, ch0_epoch_enable;
   wire ch0_dump;
   //wire [31:0] ch0_i_early, ch0_q_early, ch0_i_prompt, ch0_q_prompt, ch0_i_late, ch0_q_late;
   wire [15:0] ch0_i_early, ch0_q_early, ch0_i_prompt, ch0_q_prompt, ch0_i_late, ch0_q_late;
   wire [31:0] ch0_carrier_val;
   wire [20:0] ch0_code_val;
   wire [10:0] ch0_epoch, ch0_epoch_check;
      
   // channel 1 registers
   reg [9:0] ch1_prn_key;
   reg [27:0] ch1_carr_nco;
   reg [26:0] ch1_code_nco;
   reg [10:0] ch1_code_slew;
   reg [10:0] ch1_epoch_load;
   reg ch1_prn_key_enable, ch1_slew_enable, ch1_epoch_enable;
   wire ch1_dump;
   //wire [31:0] ch1_i_early, ch1_q_early, ch1_i_prompt, ch1_q_prompt, ch1_i_late, ch1_q_late;
   wire [15:0] ch1_i_early, ch1_q_early, ch1_i_prompt, ch1_q_prompt, ch1_i_late, ch1_q_late;
   wire [31:0] ch1_carrier_val;
   wire [20:0] ch1_code_val;
   wire [10:0] ch1_epoch, ch1_epoch_check;

   // channel 2 registers
   reg [9:0] ch2_prn_key;
   reg [27:0] ch2_carr_nco;
   reg [26:0] ch2_code_nco;
   reg [10:0] ch2_code_slew;
   reg [10:0] ch2_epoch_load;
   reg ch2_prn_key_enable, ch2_slew_enable, ch2_epoch_enable;
   wire ch2_dump;
   //wire [31:0] ch2_i_early, ch2_q_early, ch2_i_prompt, ch2_q_prompt, ch2_i_late, ch2_q_late;
   wire [15:0] ch2_i_early, ch2_q_early, ch2_i_prompt, ch2_q_prompt, ch2_i_late, ch2_q_late;
   wire [31:0] ch2_carrier_val;
   wire [20:0] ch2_code_val;
   wire [10:0] ch2_epoch, ch2_epoch_check;

   // channel 3 registers
   reg [9:0] ch3_prn_key;
   reg [27:0] ch3_carr_nco;
   reg [26:0] ch3_code_nco;
   reg [10:0] ch3_code_slew;
   reg [10:0] ch3_epoch_load;
   reg ch3_prn_key_enable, ch3_slew_enable, ch3_epoch_enable;
   wire ch3_dump;
   //wire [31:0] ch3_i_early, ch3_q_early, ch3_i_prompt, ch3_q_prompt, ch3_i_late, ch3_q_late;
   wire [15:0] ch3_i_early, ch3_q_early, ch3_i_prompt, ch3_q_prompt, ch3_i_late, ch3_q_late;
   wire [31:0] ch3_carrier_val;
   wire [20:0] ch3_code_val;
   wire [10:0] ch3_epoch, ch3_epoch_check;

   // channel 4 registers
   reg [9:0] ch4_prn_key;
   reg [27:0] ch4_carr_nco;
   reg [26:0] ch4_code_nco;
   reg [10:0] ch4_code_slew;
   reg [10:0] ch4_epoch_load;
   reg ch4_prn_key_enable, ch4_slew_enable, ch4_epoch_enable;
   wire ch4_dump;
   //wire [31:0] ch4_i_early, ch4_q_early, ch4_i_prompt, ch4_q_prompt, ch4_i_late, ch4_q_late;
   wire [15:0] ch4_i_early, ch4_q_early, ch4_i_prompt, ch4_q_prompt, ch4_i_late, ch4_q_late;
   wire [31:0] ch4_carrier_val;
   wire [20:0] ch4_code_val;
   wire [10:0] ch4_epoch, ch4_epoch_check;

   // channel 5 registers
   reg [9:0] ch5_prn_key;
   reg [27:0] ch5_carr_nco;
   reg [26:0] ch5_code_nco;
   reg [10:0] ch5_code_slew;
   reg [10:0] ch5_epoch_load;
   reg ch5_prn_key_enable, ch5_slew_enable, ch5_epoch_enable;
   wire ch5_dump;
   //wire [31:0] ch5_i_early, ch5_q_early, ch5_i_prompt, ch5_q_prompt, ch5_i_late, ch5_q_late;
   wire [15:0] ch5_i_early, ch5_q_early, ch5_i_prompt, ch5_q_prompt, ch5_i_late, ch5_q_late;
   wire [31:0] ch5_carrier_val;
   wire [20:0] ch5_code_val;
   wire [10:0] ch5_epoch, ch5_epoch_check;

   // channel 6 registers
   reg [9:0] ch6_prn_key;
   reg [27:0] ch6_carr_nco;
   reg [26:0] ch6_code_nco;
   reg [10:0] ch6_code_slew;
   reg [10:0] ch6_epoch_load;
   reg ch6_prn_key_enable, ch6_slew_enable, ch6_epoch_enable;
   wire ch6_dump;
   //wire [31:0] ch6_i_early, ch6_q_early, ch6_i_prompt, ch6_q_prompt, ch6_i_late, ch6_q_late;
   wire [15:0] ch6_i_early, ch6_q_early, ch6_i_prompt, ch6_q_prompt, ch6_i_late, ch6_q_late;
   wire [31:0] ch6_carrier_val;
   wire [20:0] ch6_code_val;
   wire [10:0] ch6_epoch, ch6_epoch_check;

   // channel 7 registers
   reg [9:0] ch7_prn_key;
   reg [27:0] ch7_carr_nco;
   reg [26:0] ch7_code_nco;
   reg [10:0] ch7_code_slew;
   reg [10:0] ch7_epoch_load;
   reg ch7_prn_key_enable, ch7_slew_enable, ch7_epoch_enable;
   wire ch7_dump;
   //wire [31:0] ch7_i_early, ch7_q_early, ch7_i_prompt, ch7_q_prompt, ch7_i_late, ch7_q_late;
   wire [15:0] ch7_i_early, ch7_q_early, ch7_i_prompt, ch7_q_prompt, ch7_i_late, ch7_q_late;
   wire [31:0] ch7_carrier_val;
   wire [20:0] ch7_code_val;
   wire [10:0] ch7_epoch, ch7_epoch_check;

   // channel 8 registers
   reg [9:0] ch8_prn_key;
   reg [27:0] ch8_carr_nco;
   reg [26:0] ch8_code_nco;
   reg [10:0] ch8_code_slew;
   reg [10:0] ch8_epoch_load;
   reg ch8_prn_key_enable, ch8_slew_enable, ch8_epoch_enable;
   wire ch8_dump;
   //wire [31:0] ch8_i_early, ch8_q_early, ch8_i_prompt, ch8_q_prompt, ch8_i_late, ch8_q_late;
   wire [15:0] ch8_i_early, ch8_q_early, ch8_i_prompt, ch8_q_prompt, ch8_i_late, ch8_q_late;
   wire [31:0] ch8_carrier_val;
   wire [20:0] ch8_code_val;
   wire [10:0] ch8_epoch, ch8_epoch_check;

   // channel 9 registers
   reg [9:0] ch9_prn_key;
   reg [27:0] ch9_carr_nco;
   reg [26:0] ch9_code_nco;
   reg [10:0] ch9_code_slew;
   reg [10:0] ch9_epoch_load;
   reg ch9_prn_key_enable, ch9_slew_enable, ch9_epoch_enable;
   wire ch9_dump;
   //wire [31:0] ch9_i_early, ch9_q_early, ch9_i_prompt, ch9_q_prompt, ch9_i_late, ch9_q_late;
   wire [15:0] ch9_i_early, ch9_q_early, ch9_i_prompt, ch9_q_prompt, ch9_i_late, ch9_q_late;
   wire [31:0] ch9_carrier_val;
   wire [20:0] ch9_code_val;
   wire [10:0] ch9_epoch, ch9_epoch_check;

   // channel 10 registers
   reg [9:0] ch10_prn_key;
   reg [27:0] ch10_carr_nco;
   reg [26:0] ch10_code_nco;
   reg [10:0] ch10_code_slew;
   reg [10:0] ch10_epoch_load;
   reg ch10_prn_key_enable, ch10_slew_enable, ch10_epoch_enable;
   wire ch10_dump;
   //wire [31:0] ch10_i_early, ch10_q_early, ch10_i_prompt, ch10_q_prompt, ch10_i_late, ch10_q_late;
   wire [15:0] ch10_i_early, ch10_q_early, ch10_i_prompt, ch10_q_prompt, ch10_i_late, ch10_q_late;
   wire [31:0] ch10_carrier_val;
   wire [20:0] ch10_code_val;
   wire [10:0] ch10_epoch, ch10_epoch_check;

   // channel 11 registers
   reg [9:0] ch11_prn_key;
   reg [27:0] ch11_carr_nco;
   reg [26:0] ch11_code_nco;
   reg [10:0] ch11_code_slew;
   reg [10:0] ch11_epoch_load;
   reg ch11_prn_key_enable, ch11_slew_enable, ch11_epoch_enable;
   wire ch11_dump;
   //wire [31:0] ch11_i_early, ch11_q_early, ch11_i_prompt, ch11_q_prompt, ch11_i_late, ch11_q_late;
   wire [15:0] ch11_i_early, ch11_q_early, ch11_i_prompt, ch11_q_prompt, ch11_i_late, ch11_q_late;
   wire [31:0] ch11_carrier_val;
   wire [20:0] ch11_code_val;
   wire [10:0] ch11_epoch, ch11_epoch_check;
  
   // status registers
   reg [1:0] status; // TIC = bit 0, ACCUM_INT = bit 1, cleared on read
	reg [1:0] status_mask;
	reg [1:0] status_mask2;
   reg status_read; // pulse when status register is read
   reg [11:0] new_data; // chan0 = bit 0, chan1 = bit 1 etc, cleared on read
   reg new_data_read; // pules when new_data register is read

   // control registers
   reg [23:0] prog_tic;
   reg [23:0] prog_accum_int;

	// sign and mag samples - 2-FF synchronizer for async PMOD inputs.
	// ASYNC_REG on both stages keeps the FF pair adjacent for best MTBF.
	(* ASYNC_REG = "TRUE" *) reg sign_tmp, mag_tmp;
	(* ASYNC_REG = "TRUE" *) reg sign, mag;

	always @ (posedge clk) begin
		if (!hw_rstn) begin
			sign_tmp <= 0;
			sign     <= 0;
			mag_tmp  <= 0;
			mag      <= 0;
		end
		else begin
			sign_tmp <= sign_in;
			sign     <= sign_tmp;
			mag_tmp  <= mag_in;
			mag      <= mag_tmp;
		end
	end
	
   // connect up time base
   time_base tb (.clk(clk), .rstn(rstn),
		 .tic_divide(prog_tic),
		 .accum_divide(prog_accum_int),
		 .pre_tic_enable(pre_tic_enable),
		 .tic_enable(tic_enable),
		 .accum_enable(accum_enable_s),
		 .tic_count(tic_count),
		 .accum_count(accum_count)
		 );
	
   assign rstn = hw_rstn & ~sw_rst;
   
   // connect up tracking channels
   tracking_channel tc0 (.clk(clk), .rstn(rstn),
                         .if_sign(sign), .if_mag(mag),
                         .pre_tic_enable(pre_tic_enable),
                         .tic_enable(tic_enable),
                         .carr_nco_fc(ch0_carr_nco),
                         .code_nco_fc(ch0_code_nco),
                         .prn_key(ch0_prn_key),
                         .prn_key_enable(ch0_prn_key_enable),
                         .code_slew(ch0_code_slew),
                         .slew_enable(ch0_slew_enable),
                         .epoch_enable(ch0_epoch_enable),
	                      .dump(ch0_dump),
	                      .i_early(ch0_i_early),
	                      .q_early(ch0_q_early),
	                      .i_prompt(ch0_i_prompt),
	                      .q_prompt(ch0_q_prompt),
	                      .i_late(ch0_i_late),
	                      .q_late(ch0_q_late),
	                      .carrier_val(ch0_carrier_val),
		                   .code_val(ch0_code_val),
                         .epoch_load(ch0_epoch_load),
	                      .epoch(ch0_epoch),
                         .epoch_check(ch0_epoch_check));

   tracking_channel tc1 (.clk(clk), .rstn(rstn),
                         .if_sign(sign), .if_mag(mag),
                         .pre_tic_enable(pre_tic_enable),
                         .tic_enable(tic_enable),
                         .carr_nco_fc(ch1_carr_nco),
                         .code_nco_fc(ch1_code_nco),
                         .prn_key(ch1_prn_key),
                         .prn_key_enable(ch1_prn_key_enable),
                         .code_slew(ch1_code_slew),
                         .slew_enable(ch1_slew_enable),
                         .epoch_enable(ch1_epoch_enable),
	                      .dump(ch1_dump),
	                      .i_early(ch1_i_early),
	                      .q_early(ch1_q_early),
	                      .i_prompt(ch1_i_prompt),
	                      .q_prompt(ch1_q_prompt),
	                      .i_late(ch1_i_late),
	                      .q_late(ch1_q_late),
	                      .carrier_val(ch1_carrier_val),
	                      .code_val(ch1_code_val),
	                      .epoch_load(ch1_epoch_load),
	                      .epoch(ch1_epoch),
                         .epoch_check(ch1_epoch_check));      
  
   tracking_channel tc2 (.clk(clk), .rstn(rstn),
                         .if_sign(sign), .if_mag(mag),
                         .pre_tic_enable(pre_tic_enable),
                         .tic_enable(tic_enable),
                         .carr_nco_fc(ch2_carr_nco),
                         .code_nco_fc(ch2_code_nco),
                         .prn_key(ch2_prn_key),
                         .prn_key_enable(ch2_prn_key_enable),
                         .code_slew(ch2_code_slew),
                         .slew_enable(ch2_slew_enable),
                         .epoch_enable(ch2_epoch_enable),
	                      .dump(ch2_dump),
	                      .i_early(ch2_i_early),
	                      .q_early(ch2_q_early),
	                      .i_prompt(ch2_i_prompt),
	                      .q_prompt(ch2_q_prompt),
	                      .i_late(ch2_i_late),
	                      .q_late(ch2_q_late),
	                      .carrier_val(ch2_carrier_val),
		                   .code_val(ch2_code_val),
		                   .epoch_load(ch2_epoch_load),
	                      .epoch(ch2_epoch),
                         .epoch_check(ch2_epoch_check));

   tracking_channel tc3 (.clk(clk), .rstn(rstn),
                         .if_sign(sign), .if_mag(mag),
                         .pre_tic_enable(pre_tic_enable),
                         .tic_enable(tic_enable),
                         .carr_nco_fc(ch3_carr_nco),
                         .code_nco_fc(ch3_code_nco),
                         .prn_key(ch3_prn_key),
                         .prn_key_enable(ch3_prn_key_enable),
                         .code_slew(ch3_code_slew),
                         .slew_enable(ch3_slew_enable),
                         .epoch_enable(ch3_epoch_enable),
	                      .dump(ch3_dump),
	                      .i_early(ch3_i_early),
	                      .q_early(ch3_q_early),
	                      .i_prompt(ch3_i_prompt),
	                      .q_prompt(ch3_q_prompt),
	                      .i_late(ch3_i_late),
	                      .q_late(ch3_q_late),
	                      .carrier_val(ch3_carrier_val),
		                  .code_val(ch3_code_val),
		                  .epoch_load(ch3_epoch_load),
	                      .epoch(ch3_epoch),
                         .epoch_check(ch3_epoch_check));

   tracking_channel tc4 (.clk(clk), .rstn(rstn),
                         .if_sign(sign), .if_mag(mag),
                         .pre_tic_enable(pre_tic_enable),
                         .tic_enable(tic_enable),
                         .carr_nco_fc(ch4_carr_nco),
                         .code_nco_fc(ch4_code_nco),
                         .prn_key(ch4_prn_key),
                         .prn_key_enable(ch4_prn_key_enable),
                         .code_slew(ch4_code_slew),
                         .slew_enable(ch4_slew_enable),
                         .epoch_enable(ch4_epoch_enable),
	                      .dump(ch4_dump),
	                      .i_early(ch4_i_early),
	                      .q_early(ch4_q_early),
	                      .i_prompt(ch4_i_prompt),
	                      .q_prompt(ch4_q_prompt),
	                      .i_late(ch4_i_late),
	                      .q_late(ch4_q_late),
	                      .carrier_val(ch4_carrier_val),
		                   .code_val(ch4_code_val),
		                  .epoch_load(ch4_epoch_load),
	                      .epoch(ch4_epoch),
                         .epoch_check(ch4_epoch_check));

   tracking_channel tc5 (.clk(clk), .rstn(rstn),
                         .if_sign(sign), .if_mag(mag),
                         .pre_tic_enable(pre_tic_enable),
                         .tic_enable(tic_enable),
                         .carr_nco_fc(ch5_carr_nco),
                         .code_nco_fc(ch5_code_nco),
                         .prn_key(ch5_prn_key),
                         .prn_key_enable(ch5_prn_key_enable),
                         .code_slew(ch5_code_slew),
                         .slew_enable(ch5_slew_enable),
                         .epoch_enable(ch5_epoch_enable),
	                      .dump(ch5_dump),
	                      .i_early(ch5_i_early),
	                      .q_early(ch5_q_early),
	                      .i_prompt(ch5_i_prompt),
	                      .q_prompt(ch5_q_prompt),
	                      .i_late(ch5_i_late),
	                      .q_late(ch5_q_late),
	                      .carrier_val(ch5_carrier_val),
		                   .code_val(ch5_code_val),
		                  .epoch_load(ch5_epoch_load),
	                      .epoch(ch5_epoch),
                         .epoch_check(ch5_epoch_check));

   tracking_channel tc6 (.clk(clk), .rstn(rstn),
                         .if_sign(sign), .if_mag(mag),
                         .pre_tic_enable(pre_tic_enable),
                         .tic_enable(tic_enable),
                         .carr_nco_fc(ch6_carr_nco),
                         .code_nco_fc(ch6_code_nco),
                         .prn_key(ch6_prn_key),
                         .prn_key_enable(ch6_prn_key_enable),
                         .code_slew(ch6_code_slew),
                         .slew_enable(ch6_slew_enable),
                         .epoch_enable(ch6_epoch_enable),
	                      .dump(ch6_dump),
	                      .i_early(ch6_i_early),
	                      .q_early(ch6_q_early),
	                      .i_prompt(ch6_i_prompt),
	                      .q_prompt(ch6_q_prompt),
	                      .i_late(ch6_i_late),
	                      .q_late(ch6_q_late),
	                      .carrier_val(ch6_carrier_val),
		                   .code_val(ch6_code_val),
		                  .epoch_load(ch6_epoch_load),
	                      .epoch(ch6_epoch),
                         .epoch_check(ch6_epoch_check));

   tracking_channel tc7 (.clk(clk), .rstn(rstn),
                         .if_sign(sign), .if_mag(mag),
                         .pre_tic_enable(pre_tic_enable),
                         .tic_enable(tic_enable),
                         .carr_nco_fc(ch7_carr_nco),
                         .code_nco_fc(ch7_code_nco),
                         .prn_key(ch7_prn_key),
                         .prn_key_enable(ch7_prn_key_enable),
                         .code_slew(ch7_code_slew),
                         .slew_enable(ch7_slew_enable),
                         .epoch_enable(ch7_epoch_enable),
	                      .dump(ch7_dump),
	                      .i_early(ch7_i_early),
	                      .q_early(ch7_q_early),
	                      .i_prompt(ch7_i_prompt),
	                      .q_prompt(ch7_q_prompt),
	                      .i_late(ch7_i_late),
	                      .q_late(ch7_q_late),
	                      .carrier_val(ch7_carrier_val),
		                   .code_val(ch7_code_val),
		                  .epoch_load(ch7_epoch_load),
	                      .epoch(ch7_epoch),
                         .epoch_check(ch7_epoch_check));

   tracking_channel tc8 (.clk(clk), .rstn(rstn),
                         .if_sign(sign), .if_mag(mag),
                         .pre_tic_enable(pre_tic_enable),
                         .tic_enable(tic_enable),
                         .carr_nco_fc(ch8_carr_nco),
                         .code_nco_fc(ch8_code_nco),
                         .prn_key(ch8_prn_key),
                         .prn_key_enable(ch8_prn_key_enable),
                         .code_slew(ch8_code_slew),
                         .slew_enable(ch8_slew_enable),
                         .epoch_enable(ch8_epoch_enable),
	                      .dump(ch8_dump),
	                      .i_early(ch8_i_early),
	                      .q_early(ch8_q_early),
	                      .i_prompt(ch8_i_prompt),
	                      .q_prompt(ch8_q_prompt),
	                      .i_late(ch8_i_late),
	                      .q_late(ch8_q_late),
	                      .carrier_val(ch8_carrier_val),
		                   .code_val(ch8_code_val),
		                  .epoch_load(ch8_epoch_load),
	                      .epoch(ch8_epoch),
                         .epoch_check(ch8_epoch_check));

   tracking_channel tc9 (.clk(clk), .rstn(rstn),
                         .if_sign(sign), .if_mag(mag),
                         .pre_tic_enable(pre_tic_enable),
                         .tic_enable(tic_enable),
                         .carr_nco_fc(ch9_carr_nco),
                         .code_nco_fc(ch9_code_nco),
                         .prn_key(ch9_prn_key),
                         .prn_key_enable(ch9_prn_key_enable),
                         .code_slew(ch9_code_slew),
                         .slew_enable(ch9_slew_enable),
                         .epoch_enable(ch9_epoch_enable),
	                      .dump(ch9_dump),
	                      .i_early(ch9_i_early),
	                      .q_early(ch9_q_early),
	                      .i_prompt(ch9_i_prompt),
	                      .q_prompt(ch9_q_prompt),
	                      .i_late(ch9_i_late),
	                      .q_late(ch9_q_late),
	                      .carrier_val(ch9_carrier_val),
		                   .code_val(ch9_code_val),
		                  .epoch_load(ch9_epoch_load),
	                      .epoch(ch9_epoch),
                         .epoch_check(ch9_epoch_check));

   tracking_channel tc10 (.clk(clk), .rstn(rstn),
                         .if_sign(sign), .if_mag(mag),
                         .pre_tic_enable(pre_tic_enable),
                         .tic_enable(tic_enable),
                         .carr_nco_fc(ch10_carr_nco),
                         .code_nco_fc(ch10_code_nco),
                         .prn_key(ch10_prn_key),
                         .prn_key_enable(ch10_prn_key_enable),
                         .code_slew(ch10_code_slew),
                         .slew_enable(ch10_slew_enable),
                         .epoch_enable(ch10_epoch_enable),
	                      .dump(ch10_dump),
	                      .i_early(ch10_i_early),
	                      .q_early(ch10_q_early),
	                      .i_prompt(ch10_i_prompt),
	                      .q_prompt(ch10_q_prompt),
	                      .i_late(ch10_i_late),
	                      .q_late(ch10_q_late),
	                      .carrier_val(ch10_carrier_val),
		                   .code_val(ch10_code_val),
		                  .epoch_load(ch10_epoch_load),
	                      .epoch(ch10_epoch),
                         .epoch_check(ch10_epoch_check));

   tracking_channel tc11 (.clk(clk), .rstn(rstn),
                         .if_sign(sign), .if_mag(mag),
                         .pre_tic_enable(pre_tic_enable),
                         .tic_enable(tic_enable),
                         .carr_nco_fc(ch11_carr_nco),
                         .code_nco_fc(ch11_code_nco),
                         .prn_key(ch11_prn_key),
                         .prn_key_enable(ch11_prn_key_enable),
                         .code_slew(ch11_code_slew),
                         .slew_enable(ch11_slew_enable),
                         .epoch_enable(ch11_epoch_enable),
	                      .dump(ch11_dump),
	                      .i_early(ch11_i_early),
	                      .q_early(ch11_q_early),
	                      .i_prompt(ch11_i_prompt),
	                      .q_prompt(ch11_q_prompt),
	                      .i_late(ch11_i_late),
	                      .q_late(ch11_q_late),
	                      .carrier_val(ch11_carrier_val),
		                   .code_val(ch11_code_val),
		                  .epoch_load(ch11_epoch_load),
	                      .epoch(ch11_epoch),
                         .epoch_check(ch11_epoch_check));
                       	     
   // address decoder ----------------------------------

   always @ (posedge clk)
   begin
   if (!hw_rstn)
      begin
	    // Need to initialize nco's (at least for simulation) or they don't run.
	    ch0_carr_nco <= 0;
	    ch0_code_nco <= 0;
	    ch1_carr_nco <= 0;
	    ch1_code_nco <= 0;
	    ch2_carr_nco <= 0;
	    ch2_code_nco <= 0;
	    ch3_carr_nco <= 0;
	    ch3_code_nco <= 0;
	    ch4_carr_nco <= 0;
	    ch4_code_nco <= 0;
	    ch5_carr_nco <= 0;
	    ch5_code_nco <= 0;
	    ch6_carr_nco <= 0;
	    ch6_code_nco <= 0;
	    ch7_carr_nco <= 0;
	    ch7_code_nco <= 0;
	    ch8_carr_nco <= 0;
	    ch8_code_nco <= 0;
	    ch9_carr_nco <= 0;
	    ch9_code_nco <= 0;
	    ch10_carr_nco <= 0;
	    ch10_code_nco <= 0;
	    ch11_carr_nco <= 0;
	    ch11_code_nco <= 0;
	
	    // Anything else need initializing here?
       ch_active <= 12'h000;

      end
   else if(chip_select)

      case (address)
      // channel 0
         8'h00 : begin
	         if (write) begin
	            ch0_prn_key <= write_data[9:0];
				   ch0_prn_key_enable <= 1;
               ch_active[0] <= 1'b1;  // Mark channel 0 active
				end
	      end
         8'h01 : if (write) ch0_carr_nco <= write_data[28:0];
         8'h02 : if (write) ch0_code_nco <= write_data[27:0];
         8'h03 : begin
	         //ch0_slew_enable <= write;// & chip_select;
	         if (write) begin
	            ch0_code_slew <= write_data[10:0];
				   ch0_slew_enable <= 1;
				end
	      end
         8'h04 : read_data <= {16'h0, ch0_i_early};
         8'h05 : read_data <= {16'h0, ch0_q_early};			 
         8'h06 : read_data <= {16'h0, ch0_i_prompt};			 
         8'h07 : read_data <= {16'h0, ch0_q_prompt};   	      		 
         8'h08 : read_data <= {16'h0, ch0_i_late};			 
         8'h09 : read_data <= {16'h0, ch0_q_late};   
         8'h0A : read_data <= ch0_carrier_val; // 32 bits
         8'h0B : read_data <= {11'h0, ch0_code_val}; // 21 bits
         8'h0C : read_data <= {21'h0, ch0_epoch}; // 11 bits
         8'h0D : read_data <= {21'h0, ch0_epoch_check}; // 11 bits
         8'h0E : begin
            if (write) begin
               ch0_epoch_load <= write_data[10:0];
               ch0_epoch_enable <= 1;
            end
			end

     // channel 1
         8'h10 : begin
	          if (write) begin
				ch1_prn_key <= write_data[9:0];
				ch1_prn_key_enable <= 1;
            ch_active[1] <= 1'b1;  // Mark channel 1 active
				end
	          end
         8'h11 : if (write) ch1_carr_nco <= write_data[28:0];
         8'h12 : if (write) ch1_code_nco <= write_data[27:0];
         8'h13 : begin
	          if (write) begin
				ch1_code_slew <= write_data[10:0];
				ch1_slew_enable <= 1;
				end
	          end
         8'h14 : read_data <= {16'h0, ch1_i_early};
         8'h15 : read_data <= {16'h0, ch1_q_early};			 
         8'h16 : read_data <= {16'h0, ch1_i_prompt};			 
         8'h17 : read_data <= {16'h0, ch1_q_prompt};   	      		 
         8'h18 : read_data <= {16'h0, ch1_i_late};			 
         8'h19 : read_data <= {16'h0, ch1_q_late};   
         8'h1A : read_data <= ch1_carrier_val; // 32 bits
         8'h1B : read_data <= {11'h0, ch1_code_val}; // 21 bits
         8'h1C : read_data <= {21'h0, ch1_epoch}; // 11 bits
         8'h1D : read_data <= {21'h0, ch1_epoch_check};
         8'h1E : begin
              if (write) begin
				ch1_epoch_load <= write_data[10:0];
				ch1_epoch_enable <= 1;
				end
              end

     // channel 2
         8'h20 : begin
	          if (write) begin
				ch2_prn_key <= write_data[9:0];
				ch2_prn_key_enable <= 1;
            ch_active[2] <= 1'b1;  // Mark channel 2 active
				end
	          end
         8'h21 : if (write) ch2_carr_nco <= write_data[28:0];
         8'h22 : if (write) ch2_code_nco <= write_data[27:0];
         8'h23 : begin
	          if (write) begin
				ch2_code_slew <= write_data[10:0];
				ch2_slew_enable <= 1;
				end
	          end
         8'h24 : read_data <= {16'h0, ch2_i_early};
         8'h25 : read_data <= {16'h0, ch2_q_early};			 
         8'h26 : read_data <= {16'h0, ch2_i_prompt};			 
         8'h27 : read_data <= {16'h0, ch2_q_prompt};   	      		 
         8'h28 : read_data <= {16'h0, ch2_i_late};			 
         8'h29 : read_data <= {16'h0, ch2_q_late};   
         8'h2A : read_data <= ch2_carrier_val; // 32 bits
         8'h2B : read_data <= {11'h0, ch2_code_val}; // 21 bits
         8'h2C : read_data <= {21'h0, ch2_epoch}; // 11 bits
         8'h2D : read_data <= {21'h0, ch2_epoch_check};
         8'h2E : begin
              if (write) begin
				ch2_epoch_load <= write_data[10:0];
				ch2_epoch_enable <= 1;
				end
              end

     // channel 3
         8'h30 : begin
	          if (write) begin
				ch3_prn_key <= write_data[9:0];
				ch3_prn_key_enable <= 1;
            ch_active[3] <= 1'b1;  // Mark channel 3 active
				end
	          end
         8'h31 : if (write) ch3_carr_nco <= write_data[28:0];
         8'h32 : if (write) ch3_code_nco <= write_data[27:0];
         8'h33 : begin
	          if (write) begin
				ch3_code_slew <= write_data[10:0];
				ch3_slew_enable <= 1;
				end
	          end
         8'h34 : read_data <= {16'h0, ch3_i_early};
         8'h35 : read_data <= {16'h0, ch3_q_early};			 
         8'h36 : read_data <= {16'h0, ch3_i_prompt};			 
         8'h37 : read_data <= {16'h0, ch3_q_prompt};   	      		 
         8'h38 : read_data <= {16'h0, ch3_i_late};			 
         8'h39 : read_data <= {16'h0, ch3_q_late};   
         8'h3A : read_data <= ch3_carrier_val; // 32 bits
         8'h3B : read_data <= {11'h0, ch3_code_val}; // 21 bits
         8'h3C : read_data <= {21'h0, ch3_epoch}; // 11 bits
         8'h3D : read_data <= {21'h0, ch3_epoch_check};
         8'h3E : begin
              if (write) begin
				ch3_epoch_load <= write_data[10:0];
				ch3_epoch_enable <= 1;
				end
              end

     // channel 4
         8'h40 : begin
	          if (write) begin
				ch4_prn_key <= write_data[9:0];
				ch4_prn_key_enable <= 1;
            ch_active[4] <= 1'b1;  // Mark channel 4 active
				end
	          end
         8'h41 : if (write) ch4_carr_nco <= write_data[28:0];
         8'h42 : if (write) ch4_code_nco <= write_data[27:0];
         8'h43 : begin
	          if (write) begin
				ch4_code_slew <= write_data[10:0];
				ch4_slew_enable <= 1;
				end
	          end
         8'h44 : read_data <= {16'h0, ch4_i_early};
         8'h45 : read_data <= {16'h0, ch4_q_early};			 
         8'h46 : read_data <= {16'h0, ch4_i_prompt};			 
         8'h47 : read_data <= {16'h0, ch4_q_prompt};   	      		 
         8'h48 : read_data <= {16'h0, ch4_i_late};			 
         8'h49 : read_data <= {16'h0, ch4_q_late};   
         8'h4A : read_data <= ch4_carrier_val; // 32 bits
         8'h4B : read_data <= {11'h0, ch4_code_val}; // 21 bits
         8'h4C : read_data <= {21'h0, ch4_epoch}; // 11 bits
         8'h4D : read_data <= {21'h0, ch4_epoch_check};
         8'h4E : begin
              if (write) begin
				ch4_epoch_load <= write_data[10:0];
				ch4_epoch_enable <= 1;
				end
              end

     // channel 5
         8'h50 : begin
	          if (write) begin
				ch5_prn_key <= write_data[9:0];
				ch5_prn_key_enable <= 1;
            ch_active[5] <= 1'b1;  // Mark channel 5 active
				end
	          end
         8'h51 : if (write) ch5_carr_nco <= write_data[28:0];
         8'h52 : if (write) ch5_code_nco <= write_data[27:0];
         8'h53 : begin
	          if (write) begin
				ch5_code_slew <= write_data[10:0];
				ch5_slew_enable <= 1;
				end
	          end
         8'h54 : read_data <= {16'h0, ch5_i_early};
         8'h55 : read_data <= {16'h0, ch5_q_early};			 
         8'h56 : read_data <= {16'h0, ch5_i_prompt};			 
         8'h57 : read_data <= {16'h0, ch5_q_prompt};   	      		 
         8'h58 : read_data <= {16'h0, ch5_i_late};			 
         8'h59 : read_data <= {16'h0, ch5_q_late};   
         8'h5A : read_data <= ch5_carrier_val; // 32 bits
         8'h5B : read_data <= {11'h0, ch5_code_val}; // 21 bits
         8'h5C : read_data <= {21'h0, ch5_epoch}; // 11 bits
         8'h5D : read_data <= {21'h0, ch5_epoch_check};
         8'h5E : begin
              if (write) begin
				ch5_epoch_load <= write_data[10:0];
				ch5_epoch_enable <= 1;
				end
              end

     // channel 6
         8'h60 : begin
	          if (write) begin
				ch6_prn_key <= write_data[9:0];
				ch6_prn_key_enable <= 1;
            ch_active[6] <= 1'b1;  // Mark channel 6 active
				end
	          end
         8'h61 : if (write) ch6_carr_nco <= write_data[28:0];
         8'h62 : if (write) ch6_code_nco <= write_data[27:0];
         8'h63 : begin
	          if (write) begin
				ch6_code_slew <= write_data[10:0];
				ch6_slew_enable <= 1;
				end
	          end
         8'h64 : read_data <= {16'h0, ch6_i_early};
         8'h65 : read_data <= {16'h0, ch6_q_early};			 
         8'h66 : read_data <= {16'h0, ch6_i_prompt};			 
         8'h67 : read_data <= {16'h0, ch6_q_prompt};   	      		 
         8'h68 : read_data <= {16'h0, ch6_i_late};			 
         8'h69 : read_data <= {16'h0, ch6_q_late};   
         8'h6A : read_data <= ch6_carrier_val; // 32 bits
         8'h6B : read_data <= {11'h0, ch6_code_val}; // 21 bits
         8'h6C : read_data <= {21'h0, ch6_epoch}; // 11 bits
         8'h6D : read_data <= {21'h0, ch6_epoch_check};
         8'h6E : begin
              if (write) begin
				ch6_epoch_load <= write_data[10:0];
				ch6_epoch_enable <= 1;
				end
              end

     // channel 7
         8'h70 : begin
	          if (write) begin
				ch7_prn_key <= write_data[9:0];
				ch7_prn_key_enable <= 1;
            ch_active[7] <= 1'b1;  // Mark channel 7 active
				end
	          end
         8'h71 : if (write) ch7_carr_nco <= write_data[28:0];
         8'h72 : if (write) ch7_code_nco <= write_data[27:0];
         8'h73 : begin
	          if (write) begin
				ch7_code_slew <= write_data[10:0];
				ch7_slew_enable <= 1;
				end
	          end
         8'h74 : read_data <= {16'h0, ch7_i_early};
         8'h75 : read_data <= {16'h0, ch7_q_early};			 
         8'h76 : read_data <= {16'h0, ch7_i_prompt};			 
         8'h77 : read_data <= {16'h0, ch7_q_prompt};   	      		 
         8'h78 : read_data <= {16'h0, ch7_i_late};			 
         8'h79 : read_data <= {16'h0, ch7_q_late};   
         8'h7A : read_data <= ch7_carrier_val; // 32 bits
         8'h7B : read_data <= {11'h0, ch7_code_val}; // 21 bits
         8'h7C : read_data <= {21'h0, ch7_epoch}; // 11 bits
         8'h7D : read_data <= {21'h0, ch7_epoch_check};
         8'h7E : begin
              if (write) begin
				ch7_epoch_load <= write_data[10:0];
				ch7_epoch_enable <= 1;
				end
              end

     // channel 8
         8'h80 : begin
	          if (write) begin
				ch8_prn_key <= write_data[9:0];
				ch8_prn_key_enable <= 1;
            ch_active[8] <= 1'b1;  // Mark channel 8 active
				end
	          end
         8'h81 : if (write) ch8_carr_nco <= write_data[28:0];
         8'h82 : if (write) ch8_code_nco <= write_data[27:0];
         8'h83 : begin
	          if (write) begin
				ch8_code_slew <= write_data[10:0];
				ch8_slew_enable <= 1;
				end
	          end
         8'h84 : read_data <= {16'h0, ch8_i_early};
         8'h85 : read_data <= {16'h0, ch8_q_early};			 
         8'h86 : read_data <= {16'h0, ch8_i_prompt};			 
         8'h87 : read_data <= {16'h0, ch8_q_prompt};   	      		 
         8'h88 : read_data <= {16'h0, ch8_i_late};			 
         8'h89 : read_data <= {16'h0, ch8_q_late};   
         8'h8A : read_data <= ch8_carrier_val; // 32 bits
         8'h8B : read_data <= {11'h0, ch8_code_val}; // 21 bits
         8'h8C : read_data <= {21'h0, ch8_epoch}; // 11 bits
         8'h8D : read_data <= {21'h0, ch8_epoch_check};
         8'h8E : begin
              if (write) begin
				ch8_epoch_load <= write_data[10:0];
				ch8_epoch_enable <= 1;
				end
              end

     // channel 9
         8'h90 : begin
	          if (write) begin
				ch9_prn_key <= write_data[9:0];
				ch9_prn_key_enable <= 1;
            ch_active[9] <= 1'b1;  // Mark channel 9 active
				end
	          end
         8'h91 : if (write) ch9_carr_nco <= write_data[28:0];
         8'h92 : if (write) ch9_code_nco <= write_data[27:0];
         8'h93 : begin
	          if (write) begin
				ch9_code_slew <= write_data[10:0];
				ch9_slew_enable <= 1;
				end
	          end
         8'h94 : read_data <= {16'h0, ch9_i_early};
         8'h95 : read_data <= {16'h0, ch9_q_early};			 
         8'h96 : read_data <= {16'h0, ch9_i_prompt};			 
         8'h97 : read_data <= {16'h0, ch9_q_prompt};   	      		 
         8'h98 : read_data <= {16'h0, ch9_i_late};			 
         8'h99 : read_data <= {16'h0, ch9_q_late};   
         8'h9A : read_data <= ch9_carrier_val; // 32 bits
         8'h9B : read_data <= {11'h0, ch9_code_val}; // 21 bits
         8'h9C : read_data <= {21'h0, ch9_epoch}; // 11 bits
         8'h9D : read_data <= {21'h0, ch9_epoch_check};
         8'h9E : begin
              if (write) begin
				ch9_epoch_load <= write_data[10:0];
				ch9_epoch_enable <= 1;
				end
              end

     // channel 10
         8'hA0 : begin
	          if (write) begin
				ch10_prn_key <= write_data[9:0];
				ch10_prn_key_enable <= 1;
            ch_active[10] <= 1'b1;  // Mark channel 10 active
				end
	          end
         8'hA1 : if (write) ch10_carr_nco <= write_data[28:0];
         8'hA2 : if (write) ch10_code_nco <= write_data[27:0];
         8'hA3 : begin
	          if (write) begin
				ch10_code_slew <= write_data[10:0];
				ch10_slew_enable <= 1;
				end
	          end
         8'hA4 : read_data <= {16'h0, ch10_i_early};
         8'hA5 : read_data <= {16'h0, ch10_q_early};			 
         8'hA6 : read_data <= {16'h0, ch10_i_prompt};			 
         8'hA7 : read_data <= {16'h0, ch10_q_prompt};   	      		 
         8'hA8 : read_data <= {16'h0, ch10_i_late};			 
         8'hA9 : read_data <= {16'h0, ch10_q_late};   
         8'hAA : read_data <= ch10_carrier_val; // 32 bits
         8'hAB : read_data <= {11'h0, ch10_code_val}; // 21 bits
         8'hAC : read_data <= {21'h0, ch10_epoch}; // 11 bits
         8'hAD : read_data <= {21'h0, ch10_epoch_check};
         8'hAE : begin
              if (write) begin
				ch10_epoch_load <= write_data[10:0];
				ch10_epoch_enable <= 1;
				end
              end

     // channel 11
         8'hB0 : begin
	          if (write) begin
				ch11_prn_key <= write_data[9:0];
				ch11_prn_key_enable <= 1;
            ch_active[11] <= 1'b1;  // Mark channel 11 active
				end
	          end
         8'hB1 : if (write) ch11_carr_nco <= write_data[28:0];
         8'hB2 : if (write) ch11_code_nco <= write_data[27:0];
         8'hB3 : begin
	          if (write) begin
				ch11_code_slew <= write_data[10:0];
				ch11_slew_enable <= 1;
				end
	          end
         8'hB4 : read_data <= {16'h0, ch11_i_early};
         8'hB5 : read_data <= {16'h0, ch11_q_early};			 
         8'hB6 : read_data <= {16'h0, ch11_i_prompt};			 
         8'hB7 : read_data <= {16'h0, ch11_q_prompt};   	      		 
         8'hB8 : read_data <= {16'h0, ch11_i_late};			 
         8'hB9 : read_data <= {16'h0, ch11_q_late};   
         8'hBA : read_data <= ch11_carrier_val; // 32 bits
         8'hBB : read_data <= {11'h0, ch11_code_val}; // 21 bits
         8'hBC : read_data <= {21'h0, ch11_epoch}; // 11 bits
         8'hBD : read_data <= {21'h0, ch11_epoch_check};       
         8'hBE : begin
              if (write) begin
				ch11_epoch_load <= write_data[10:0];
				ch11_epoch_enable <= 1;
				end
              end

      // status
         8'hE0 : begin // get status and pulse status_flag to clear status
            read_data <= {30'h0, status}; // only 2 status bits, therefore need to pad 30ms bits
	         //status_read <= read; // pulse status flag to clear status register
	        if(read) status_read <= 1;
			   // make sure the flag is not cleared if a tic_enable is aligned to status_read
				if (tic_enable)
					status_mask <= 2'b01;
				else
					status_mask <= 2'b00;
			  end
         8'hE1 : begin // get new_data
            read_data <= {20'h0,new_data}; // one new_data bit per channel, need to pad other bits
            if(read) new_data_read <= 1; // pulse to clear new_data
            end
         8'hE2 : begin // tic count read
            read_data <= {8'h0,tic_count}; // 24 bits of TIC count
            end
         8'hE3 : begin // accum count read
            read_data <= {8'h0,accum_count}; // 24 bits of accum count
            end
		 8'hEF : begin
		    read_data <= 32'h64; // hardware version control = 1.00 = 100 = 0x64 (15/5/2007)
		    end // HWID used to align hardware and software builds. 

      // control
         8'hF0 : if (write) sw_rst <= 1; // software reset
         8'hF1 : if (write) prog_tic <= write_data[23:0]; // program TIC
         8'hF2 : if (write) prog_accum_int <= write_data[23:0]; // program ACCUM_INT
       
         default : read_data <= 0;

    endcase // case(address)
   else begin
	ch0_prn_key_enable <= 0;
	ch0_slew_enable <= 0;
	ch0_epoch_enable <= 0;

	ch1_prn_key_enable <= 0;
	ch1_slew_enable <= 0;
	ch1_epoch_enable <= 0;

	ch2_prn_key_enable <= 0;
	ch2_slew_enable <= 0;
	ch2_epoch_enable <= 0;

	ch3_prn_key_enable <= 0;
	ch3_slew_enable <= 0;
	ch3_epoch_enable <= 0;

	ch4_prn_key_enable <= 0;
	ch4_slew_enable <= 0;
	ch4_epoch_enable <= 0;

	ch5_prn_key_enable <= 0;
	ch5_slew_enable <= 0;
	ch5_epoch_enable <= 0;

	ch6_prn_key_enable <= 0;
	ch6_slew_enable <= 0;
	ch6_epoch_enable <= 0;

	ch7_prn_key_enable <= 0;
	ch7_slew_enable <= 0;
	ch7_epoch_enable <= 0;

	ch8_prn_key_enable <= 0;
	ch8_slew_enable <= 0;
	ch8_epoch_enable <= 0;

	ch9_prn_key_enable <= 0;
	ch9_slew_enable <= 0;
	ch9_epoch_enable <= 0;

	ch10_prn_key_enable <= 0;
	ch10_slew_enable <= 0;
	ch10_epoch_enable <= 0;
	
	ch11_prn_key_enable <= 0;
	ch11_slew_enable <= 0;
	ch11_epoch_enable <= 0;
	
    status_read <= 0;
	new_data_read <= 0;
	sw_rst <= 0;
	end
   end // if chip_select

   // process to reset the status register after a read
   // also create accum_int signal that is cleared after status read
   
   always @ (posedge clk)
   begin
	 if (!rstn || status_read)
	    begin
	    //status <= 0;
		 status <= status_mask;
       accum_int <= 0;
	    end
	 else
      begin
	    if (tic_enable)
	       status[0] <= 1;
	    if (accum_enable_s)
          begin
	      status[1] <= 1;
          accum_int <= 1;
          end
	    end
   end

   // Sticky new_data flags: set on dump, cleared on read
   wire [11:0] dumps_now;
   assign dumps_now[0]  = ch0_dump;
   assign dumps_now[1]  = ch1_dump;
   assign dumps_now[2]  = ch2_dump;
   assign dumps_now[3]  = ch3_dump;
   assign dumps_now[4]  = ch4_dump;
   assign dumps_now[5]  = ch5_dump;
   assign dumps_now[6]  = ch6_dump;
   assign dumps_now[7]  = ch7_dump;
   assign dumps_now[8]  = ch8_dump;
   assign dumps_now[9]  = ch9_dump;
   assign dumps_now[10] = ch10_dump;
   assign dumps_now[11] = ch11_dump;

   always @(posedge clk) begin
   if (!rstn) begin
      new_data <= 12'h000;
   end else begin
      // Always accumulate dump events
      new_data <= new_data | (dumps_now & ch_active);
      // Clear bits that were acknowledged by reading Q_LATE.
      // If a dump arrives in the same cycle, the bit remains set due to the OR above.
      if (nd_clear_pulse != 12'h000) begin
         //new_data <= (new_data | (dumps_now & ch_active)) & ~nd_clear_pulse;
         new_data <= ((new_data & ~nd_clear_pulse) | (dumps_now & ch_active));
      end
      /*
      // Clear flags after software reads new_data
      if (new_data_read) begin
         // Clear after presenting; next dumps will be re-latched
         new_data <= 12'h000 | dumps_now;
      end
      */
   end
   end

   // One-cycle pulse indicating that software acknowledged channel data by reading Q_LATE.
   reg [11:0] nd_clear_pulse;

   always @(posedge clk) begin
   if (!hw_rstn) begin
      nd_clear_pulse <= 12'h000;
   end else begin
      nd_clear_pulse <= 12'h000; // default: no clear
      if (chip_select && read) begin
         case (address)
         8'h09: nd_clear_pulse[0] <= 1'b1; // ch0 Q_LATE read -> clear ch0 new_data
         8'h19: nd_clear_pulse[1] <= 1'b1; // ch1 Q_LATE read -> clear ch1 new_data
         8'h29: nd_clear_pulse[2] <= 1'b1; // ...
         8'h39: nd_clear_pulse[3] <= 1'b1;
         8'h49: nd_clear_pulse[4] <= 1'b1;
         8'h59: nd_clear_pulse[5] <= 1'b1;
         8'h69: nd_clear_pulse[6] <= 1'b1;
         8'h79: nd_clear_pulse[7] <= 1'b1;
         8'h89: nd_clear_pulse[8] <= 1'b1;
         8'h99: nd_clear_pulse[9] <= 1'b1;
         8'hA9: nd_clear_pulse[10] <= 1'b1;
         8'hB9: nd_clear_pulse[11] <= 1'b1;
         default: ;
         endcase
      end
   end
   end

endmodule // gps_baseband
			 
			 
			 