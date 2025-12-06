module sram
#(
    parameter DATA_WIDTH = 12, 
    parameter ADDR_WIDTH = 17, 
    parameter RAM_SIZE = 76800,
    parameter FILE = "none.mem"
)
 (
    input wire clk,
    input wire we,
    input wire en,
    input wire [ADDR_WIDTH-1 : 0] addr,
    input wire [DATA_WIDTH-1 : 0] data_i,
    output reg [DATA_WIDTH-1 : 0] data_o
 );

    reg [DATA_WIDTH-1 : 0] RAM [0 : RAM_SIZE - 1];

    initial begin
        if (FILE != "none.mem") begin
            $readmemh(FILE, RAM);
        end
    end

    always @(posedge clk) begin
        if (en) begin
            if (we)
                RAM[addr] <= data_i;
            else
                data_o <= RAM[addr];
        end
    end

endmodule