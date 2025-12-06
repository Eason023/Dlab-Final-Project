module physic (
    input wire clk,
    input wire rst_n,
    input wire en, // 60Hz Trigger

    // 輸入
    input wire p1_move_left, p1_move_right, p1_jump, p1_smash,
    input wire p2_move_left, p2_move_right, p2_jump, p2_smash,
    
    // 碰撞範圍輸入 (這裡直接當作矩形判定)
    input wire p1_cover, 
    input wire p2_cover, 

    // 輸出 (除以 64 後的真實座標)
    output wire [9:0] p1_pos_x, p1_pos_y,
    output wire [9:0] p2_pos_x, p2_pos_y,
    output wire [9:0] ball_pos_x, ball_pos_y,
    
    output reg game_over,
    output reg [1:0] winner,
    output reg valid
);

    // --- 1. 參數設定 (所有數值都放大 64 倍) ---
    // 為什麼要放大？因為整數運算沒有小數點。
    // 放大 64 倍後，數值 1 代表 1/64 pixel，這樣重力才算得準。

    localparam signed [15:0] SCALE = 16'd64; 

    // 速度與重力
    localparam signed [15:0] GRAVITY      = 16'd25;   // 重力 (約 0.4 px)
    localparam signed [15:0] JUMP_FORCE   = 16'd800;  // 跳躍力 (12.5 px)
    localparam signed [15:0] MOVE_SPEED   = 16'd320;  // 玩家移動速度 (5 px)
    localparam signed [15:0] SMASH_X      = 16'd600;  // 殺球 X 速度
    localparam signed [15:0] SMASH_Y      = -16'd900; // 殺球 Y 速度 (向上)
    localparam signed [15:0] BOUNCE_Y     = -16'd700; // 普通頂球高度

    // 尺寸與邊界 (真實像素 * 64)
    localparam signed [15:0] FLOOR_Y      = 16'd480 * SCALE;
    localparam signed [15:0] SCREEN_W     = 16'd640 * SCALE;
    localparam signed [15:0] BALL_SIZE    = 16'd80  * SCALE;
    localparam signed [15:0] P_H          = 16'd128 * SCALE;
    localparam signed [15:0] P_W          = 16'd128 * SCALE;
    localparam signed [15:0] NET_H        = 16'd180 * SCALE;
    localparam signed [15:0] NET_X        = 16'd320 * SCALE;

    // --- 2. 內部變數 (全部 Signed，且包含放大倍率) ---
    reg signed [19:0] p1_x, p1_y, p1_vy;
    reg signed [19:0] p2_x, p2_y, p2_vy;
    reg signed [19:0] ball_x, ball_y, ball_vx, ball_vy;
    
    reg p1_air, p2_air;
    reg [4:0] cooldown; // 碰撞冷卻時間

    // --- 3. 輸出邏輯 (把數值除以 64 變回正常像素) ---
    // >>> 6 等同於 除以 64
    assign p1_pos_x = p1_x >>> 6;
    assign p1_pos_y = p1_y >>> 6;
    assign p2_pos_x = p2_x >>> 6;
    assign p2_pos_y = p2_y >>> 6;
    assign ball_pos_x = ball_x >>> 6;
    assign ball_pos_y = ball_y >>> 6;

    // --- 4. 碰撞判定輔助變數 ---
    // 判斷 P1 是否碰到球 (簡單矩形重疊判定)
    wire p1_hit = (ball_x + BALL_SIZE > p1_x + 20*SCALE) && (ball_x < p1_x + P_W - 20*SCALE) &&
                  (ball_y + BALL_SIZE > p1_y) && (ball_y < p1_y + P_H);
                  
    wire p2_hit = (ball_x + BALL_SIZE > p2_x + 20*SCALE) && (ball_x < p2_x + P_W - 20*SCALE) &&
                  (ball_y + BALL_SIZE > p2_y) && (ball_y < p2_y + P_H);

    // --- 5. 主邏輯 ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 初始位置 (設定在高空，避免開局卡住)
            p1_x <= 100 * SCALE; p1_y <= (480 - 128) * SCALE; p1_vy <= 0; p1_air <= 0;
            p2_x <= 520 * SCALE; p2_y <= (480 - 128) * SCALE; p2_vy <= 0; p2_air <= 0;
            
            ball_x <= 520 * SCALE; 
            ball_y <= 50  * SCALE; // <--- 改這裡！從 50px 高度落下
            ball_vx <= 0; ball_vy <= 0;
            
            game_over <= 0; winner <= 0; valid <= 0; cooldown <= 0;
        end 
        else if (en) begin // 每幀觸發一次 (60Hz)
            valid <= 1;

            // --- P1 移動與跳躍 ---
            if (p1_move_left && p1_x > 0) p1_x <= p1_x - MOVE_SPEED;
            if (p1_move_right && p1_x < (NET_X - P_W)) p1_x <= p1_x + MOVE_SPEED;
            
            if (p1_jump && !p1_air) begin p1_vy <= -JUMP_FORCE; p1_air <= 1; end
            else if (p1_air) begin
                p1_vy <= p1_vy + GRAVITY; // 重力
                p1_y <= p1_y + p1_vy;
                if (p1_y >= FLOOR_Y - P_H) begin // 落地
                    p1_y <= FLOOR_Y - P_H; p1_vy <= 0; p1_air <= 0;
                end
            end

            // --- P2 移動與跳躍 ---
            if (p2_move_left && p2_x > (NET_X)) p2_x <= p2_x - MOVE_SPEED;
            if (p2_move_right && p2_x < (SCREEN_W - P_W)) p2_x <= p2_x + MOVE_SPEED;

            if (p2_jump && !p2_air) begin p2_vy <= -JUMP_FORCE; p2_air <= 1; end
            else if (p2_air) begin
                p2_vy <= p2_vy + GRAVITY;
                p2_y <= p2_y + p2_vy;
                if (p2_y >= FLOOR_Y - P_H) begin
                    p2_y <= FLOOR_Y - P_H; p2_vy <= 0; p2_air <= 0;
                end
            end

            // --- 球的移動 (先加重力) ---
            ball_vy <= ball_vy + GRAVITY;
            ball_x <= ball_x + ball_vx;
            ball_y <= ball_y + ball_vy;

            // --- 球與玩家碰撞 (Hitbox) ---
            if (cooldown > 0) cooldown <= cooldown - 1;
            else if (p1_hit || p2_hit) begin
                cooldown <= 15; // 冷卻，避免連點
                if (p1_hit) begin
                    if (p1_smash) begin ball_vx <= SMASH_X; ball_vy <= SMASH_Y; end
                    else begin
                        // 普通碰撞：依據是否移動給推力
                        ball_vx <= (p1_move_right) ? 200*SCALE : (p1_move_left) ? -200*SCALE : ball_vx; 
                        // 強制彈起
                        if (ball_vy > -500*SCALE) ball_vy <= BOUNCE_Y; else ball_vy <= -ball_vy;
                    end
                end 
                else if (p2_hit) begin
                    if (p2_smash) begin ball_vx <= -SMASH_X; ball_vy <= SMASH_Y; end
                    else begin
                        ball_vx <= (p2_move_right) ? 200*SCALE : (p2_move_left) ? -200*SCALE : ball_vx;
                        if (ball_vy > -500*SCALE) ball_vy <= BOUNCE_Y; else ball_vy <= -ball_vy;
                    end
                end
            end

            // --- 球的邊界反彈 ---
            
            // 左牆
            if (ball_x <= 0) begin ball_x <= 0; ball_vx <= -ball_vx; end
            // 右牆 (640 - 80)
            else if (ball_x >= SCREEN_W - BALL_SIZE) begin ball_x <= SCREEN_W - BALL_SIZE; ball_vx <= -ball_vx; end
            
            // 地板 (重置遊戲)
            if (ball_y >= FLOOR_Y - BALL_SIZE) begin
                game_over <= 1;
                winner <= (ball_x < NET_X) ? 2 : 1;
                // 碰到地就停住，避免無限運算
                ball_y <= FLOOR_Y - BALL_SIZE; ball_vx <= 0; ball_vy <= 0;
            end
            
            // 網子 (簡單版：只判定高度)
            // 如果球在網子中間且高度低於網子，反彈 Y
            if (ball_y + BALL_SIZE > FLOOR_Y - NET_H && 
                ball_x + BALL_SIZE > NET_X - 5*SCALE && ball_x < NET_X + 5*SCALE) begin
                
                // 簡單處理：彈回上面
                ball_vy <= -ball_vy;
                ball_y <= FLOOR_Y - NET_H - BALL_SIZE;
            end

            // 遊戲結束重置位置
            if (game_over) begin
                ball_x <= 520 * SCALE; ball_y <= 50 * SCALE; // 重置到高空
                game_over <= 0;
            end
        end 
        else begin
            valid <= 0;
        end
    end

endmodule
