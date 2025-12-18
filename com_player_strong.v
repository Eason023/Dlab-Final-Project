module com_player_strong (
    input wire clk,
    input wire rst_n,
    
    // --- 感測器輸入 (Sensor Data) ---
    input wire [9:0] ball_x,
    input wire [9:0] ball_y,
    
    // [新增] 必須知道自己在哪裡，才能決定往哪跑
    // 這個訊號要從 physic 模組拉回來 (Feedback Loop)
    input wire [9:0] my_pos_x, 
    input wire [9:0] my_pos_y,

    // --- 決策輸出 (Control Signals) ---
    output reg op_move_left,
    output reg op_move_right,
    output reg op_jump,
    output reg op_smash
);

    // --- AI 參數設定 ---
    localparam CENTER_X  = 10'd210; // 沒球的時候回到的中心點
    localparam NET_X     = 10'd160; // 網子位置
    localparam TOLERANCE = 10'd5;   // 容許誤差 (避免抖動)

    // AI 思考邏輯 (決策層)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            op_move_left  <= 0;
            op_move_right <= 0;
            op_jump       <= 0;
            op_smash      <= 0;
        end else begin
            // 1. 左右移動決策 (X Axis Logic)
            op_move_left  <= 0;
            op_move_right <= 0;

            if (ball_x > NET_X) begin 
                // A. 球在電腦這一側 (右側)：全力追球
                if (ball_x > my_pos_x + TOLERANCE) 
                    op_move_right <= 1'b1;
                else if (ball_x < my_pos_x - TOLERANCE) 
                    op_move_left  <= 1'b1;
            end else begin 
                // B. 球在玩家那一側 (左側)：回到中心點防守
                if (my_pos_x > CENTER_X + TOLERANCE) 
                    op_move_left  <= 1'b1;
                else if (my_pos_x < CENTER_X - TOLERANCE) 
                    op_move_right <= 1'b1;
            end

            // 2. 跳躍決策 (Jump Logic)
            // 當球在我的 X 範圍內 (+-30) 且高度適合殺球 ( < 200 ) 時起跳
            if (ball_x > NET_X && 
               (ball_x > my_pos_x - 30 && ball_x < my_pos_x + 30) && 
               (ball_y < 10'd200)) begin
                op_jump <= 1'b1;
            end else begin
                op_jump <= 1'b0;
            end

            // 3. 殺球決策 (Smash Logic)
            // 當球跟我的身體非常接近時，按下殺球鍵
            // 這裡的判斷範圍比跳躍更小，模擬抓準時機
            if ((ball_x > my_pos_x - 20 && ball_x < my_pos_x + 20) && 
                (ball_y > my_pos_y - 40 && ball_y < my_pos_y + 40)) begin
                op_smash <= 1'b1;
            end else begin
                op_smash <= 1'b0;
            end
        end
    end

endmodule
