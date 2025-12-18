`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Dept. of Computer Science, National Chiao Tung University
// Engineer: Chun-Jen Tsai
// 
// Create Date:    09:43:16 10/20/2015 
// Design Name: 
// Module Name:    debounce
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module debounce(input clk, input btn_input, output btn_output);

parameter DEBOUNCE_PERIOD = 2_000_000; /* 20 msec = (100,000,000*0.2) ticks @100MHz */

reg [31:0] counter;
reg pre_btn;

assign btn_output = (pre_btn == 0)&&(counter == DEBOUNCE_PERIOD);

always@(posedge clk) begin
  pre_btn <= (counter == DEBOUNCE_PERIOD);
  if (btn_input == 0)
    counter <= 0;
  else
    counter <= counter + (counter != DEBOUNCE_PERIOD);
end

endmodule
