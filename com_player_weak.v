module com_player_smart (
    input wire clk,
    input wire rst_n,
    input wire [9:0] ball_x,
    input wire [9:0] ball_y,
    input wire [9:0] my_pos_x, 
    input wire [9:0] my_pos_y,
    output reg op_move_left,
    output reg op_move_right,
    output reg op_jump,
    output reg op_smash
);

    // 左側玩家參數
    localparam CENTER_X  = 10'd60;   
    localparam NET_X     = 10'd320;  
    localparam TOLERANCE = 10'd5;    

    // 定義地面高度 (參考你的 top module 初始值是 320)
    // 如果 y 小於這個值，代表我在空中
    localparam GROUND_Y  = 10'd315; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            op_move_left <= 0; op_move_right <= 0;
            op_jump <= 0; op_smash <= 0;
        end else begin
            op_move_left <= 0; op_move_right <= 0;
            op_jump <= 0; op_smash <= 0;

            // 1. 移動邏輯 (保持不變)
            if (ball_x < NET_X) begin 
                if (ball_x > my_pos_x + TOLERANCE) 
                    op_move_right <= 1'b1;
                else if (ball_x < my_pos_x - TOLERANCE) 
                    op_move_left  <= 1'b1;
            end else begin 
                if (my_pos_x > CENTER_X + TOLERANCE) 
                    op_move_left  <= 1'b1;
                else if (my_pos_x < CENTER_X - TOLERANCE) 
                    op_move_right <= 1'b1;
            end

            // 2. 跳躍 (放寬條件)
            // 原本是 < 200 才跳，太高了。改成 < 280 (只要球飛起來就準備跳)
            // 且 X 軸範圍從 30 放寬到 40
            if (ball_x < NET_X && 
               (ball_x > my_pos_x - 40 && ball_x < my_pos_x + 40) && 
               (ball_y < 10'd280)) begin
                op_jump <= 1'b1;
            end

            // 3. 殺球 (暴力修正版)
            // 邏輯 A: 只要我在空中 (Y < 地面)，我就死按著殺球鍵不放，等待物理引擎碰撞
            // 邏輯 B: 如果我在地上，但球離我很近 (低空球)，也按殺球
            
            if (my_pos_y < GROUND_Y) begin
                // [空中狀態]：全自動殺球
                op_smash <= 1'b1;
            end 
            else if ((ball_x > my_pos_x - 50 && ball_x < my_pos_x + 50) && 
                     (ball_y > my_pos_y - 80 && ball_y < my_pos_y + 40)) begin
                // [地面狀態]：近身防禦殺球
                op_smash <= 1'b1;
            end else begin
                op_smash <= 1'b0;
            end
        end
    end
endmodule
