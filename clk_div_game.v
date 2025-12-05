module clk_div_game (
    input wire clk,       // System Clock (100MHz)
    input wire rst_n,
    output reg game_tick  // Slow Tick (30Hz pulse)
);
    // [修正] 設定為板子的 100MHz
    parameter CLK_FREQ = 32'd100_000_000; 
    // [修正] 降到 30 FPS，讓遊戲節奏變慢、重力變輕
    parameter TARGET_FPS = 32'd30; 
    
    localparam THRESHOLD = CLK_FREQ / TARGET_FPS;
    reg [31:0] count; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 0;
            game_tick <= 0;
        end else begin
            if (count >= THRESHOLD) begin
                count <= 0;
                game_tick <= 1; 
            end else begin
                count <= count + 1;
                game_tick <= 0;
            end
        end
    end
endmodule