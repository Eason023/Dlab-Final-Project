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
    
    output wire p1_is_smash,  // P1 正在按殺球
    output wire p2_is_smash,  // P2 正在按殺球
    output wire ball_is_smash,   // 球目前處於「被殺球」的高速狀態
    
    output reg game_over,
    output reg [1:0] winner,
    output reg valid
);

    // --- 1. 參數設定 (所有數值都放大 64 倍) ---
    localparam signed [15:0] SCALE = 16'd64; 

    // 速度與重力
    localparam signed [15:0] GRAVITY      = 16'd25;   // 重力
    localparam signed [15:0] JUMP_FORCE   = 16'd650;  // 跳躍力
    localparam signed [15:0] MOVE_SPEED   = 16'd200;  // 玩家移動速度
    localparam signed [15:0] SMASH_X      = 16'd1500;  // 殺球 X 速度
    localparam signed [15:0] SMASH_Y      = 16'd100; // 殺球 Y 速度
    localparam signed [15:0] BOUNCE_Y     = -16'd750; // 普通頂球高度
    localparam signed [15:0] FRICTION = 16'd3;
    localparam signed [19:0] FRICTION_SPEED = 20'd400;
    localparam signed [15:0] SPEED_THRESHOLD = 16'd600;//多少以上算是殺球

    // 尺寸與邊界 (真實像素 * 64)
    localparam signed [19:0] FLOOR_Y      = 20'd480 * SCALE;
    localparam signed [19:0] SCREEN_W     = 20'd640 * SCALE;
    localparam signed [19:0] BALL_SIZE    = 20'd80  * SCALE;
    
    localparam signed [19:0] P_H          = 20'd128 * SCALE;
    localparam signed [19:0] P_W          = 20'd128 * SCALE;
    localparam signed [19:0] P1_HIT_START = 20'd64  * SCALE;//[64 124]
    localparam signed [19:0] P1_HIT_END   = 20'd124 * SCALE;
    localparam signed [19:0] P2_HIT_START = 20'd4   * SCALE;//[4 64]
    localparam signed [19:0] P2_HIT_END   = 20'd64  * SCALE;
    
    localparam signed [19:0] NET_H        = 20'd180 * SCALE;
    localparam signed [19:0] NET_X        = 20'd320 * SCALE;
    localparam signed [19:0] BALL_START_L = 20'd120 * SCALE;
    localparam signed [19:0] BALL_START_R = 20'd440 * SCALE;
    // --- 2. 內部變數 (全部 Signed，且包含放大倍率) ---
    reg signed [19:0] p1_x, p1_y, p1_vy;
    reg signed [19:0] p2_x, p2_y, p2_vy;
    reg signed [19:0] ball_x, ball_y, ball_vx, ball_vy;
    
    reg p1_air, p2_air;
    reg [9:0] cooldown; // 碰撞冷卻時間
    reg [9:0] net_cooldown;  // [新增] 網子碰撞冷卻

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
    wire p1_hit = (ball_x + BALL_SIZE > p1_x + P1_HIT_START) && (ball_x < p1_x + P1_HIT_END) &&
                  (ball_y + BALL_SIZE > p1_y) && (ball_y < p1_y + P_H);
                  
    wire p2_hit = (ball_x + BALL_SIZE > p2_x + P2_HIT_START) && (ball_x < p2_x + P2_HIT_END) &&
                  (ball_y + BALL_SIZE > p2_y) && (ball_y < p2_y + P_H);

    wire signed [15:0] abs_ball_vx = (ball_vx < 0) ? -ball_vx : ball_vx;
    wire signed [15:0] abs_ball_vy = (ball_vy < 0) ? -ball_vy : ball_vy;
    assign ball_is_smash = (abs_ball_vx > SPEED_THRESHOLD) || (abs_ball_vy > SPEED_THRESHOLD);
    assign p1_is_smash = p1_hit && p1_smash;
    assign p2_is_smash = p2_hit && p2_smash;
    
    // --- 5. 主邏輯 ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 初始位置 (設定在高空，避免開局卡住)
            p1_x <= 100 * SCALE; p1_y <= (480 - 128) * SCALE; p1_vy <= 0; p1_air <= 0;
            p2_x <= 520 * SCALE; p2_y <= (480 - 128) * SCALE; p2_vy <= 0; p2_air <= 0;
            
            ball_x <= BALL_START_L; 
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
                if (p1_y >= FLOOR_Y - P_H && p1_vy > 0) begin // 落地
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
                if (p2_y >= FLOOR_Y - P_H && p2_vy > 0) begin
                    p2_y <= FLOOR_Y - P_H; p2_vy <= 0; p2_air <= 0;
                end
            end


            if (ball_vx > FRICTION_SPEED) begin
                // 只有往右飛太快時，才減速
                ball_vx <= ball_vx - FRICTION; 
            end
            else if (ball_vx < -FRICTION_SPEED) begin
                // 只有往左飛太快時，才減速 (加回 0)
                ball_vx <= ball_vx + FRICTION;
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
                    if (p1_smash) begin
                        ball_vx <= SMASH_X;
                        ball_vy <= SMASH_Y;
                    end
                    else begin
                        if ((ball_x + (BALL_SIZE >>> 1)) > (p1_x + (P_W >>> 1))) begin
                            // 球在 P1 右側 -> 往右彈 (正速度)
                            ball_vx <= ball_vx + 5 * SCALE; 
                        end
                        else begin
                            // 球在 P1 左側 -> 往左彈 (負速度)
                            ball_vx <= ball_vx - 5 * SCALE;
                        end
                        // 強制彈起
                        if (ball_vy > -8*SCALE) ball_vy <= BOUNCE_Y;
                        else ball_vy <= -ball_vy;
                    end
                end 
                else if (p2_hit) begin
                    if (p2_smash) begin
                        ball_vx <= -SMASH_X;
                        ball_vy <= SMASH_Y;
                    end
                    else begin
                        if ((ball_x + (BALL_SIZE >>> 1)) > (p2_x + (P_W >>> 1))) begin
                            // 球在 P2 右側 -> 往右彈
                            ball_vx <= ball_vx + 5 * SCALE;
                        end
                        else begin
                            // 球在 P2 左側 -> 往左彈
                            ball_vx <= ball_vx - 5 * SCALE;
                        end
                        if (ball_vy > -8*SCALE) ball_vy <= BOUNCE_Y;
                        else ball_vy <= -ball_vy;
                    end
                end
            end

            // --- 球的邊界反彈 ---
            
            // 左牆
            if (ball_x <= 1) begin 
                ball_x <= 2; 
                ball_vx <= -ball_vx; 
            end
            // 右牆 (640 - 80)
            else if (ball_x >= SCREEN_W - BALL_SIZE - 1) begin
                ball_x <= SCREEN_W - BALL_SIZE - 2;
                ball_vx <= -ball_vx;
            end
            
            // 地板 (重置遊戲)
            if (ball_y >= FLOOR_Y - BALL_SIZE) begin
                game_over <= 1;
                winner <= (ball_x < NET_X) ? 2 : 1;
                // 碰到地就停住，避免無限運算
                ball_y <= FLOOR_Y - BALL_SIZE; ball_vx <= 0; ball_vy <= 0;
            end

            //天花板
            if(ball_y <= 0) begin
                ball_y <= 1;
                ball_vy <= - ball_vy;
            end
            
            // --- 網子碰撞判定 ---
            if (net_cooldown > 0) net_cooldown <= net_cooldown - 1;
            if (ball_y + BALL_SIZE > FLOOR_Y - NET_H && ball_x + BALL_SIZE > NET_X - 3*SCALE && ball_x < NET_X + 3*SCALE && net_cooldown == 0) begin
                net_cooldown <= 20;
                // 如果球比較高，就算撞到上面
                if ((ball_y + (BALL_SIZE >>> 1) + ((BALL_SIZE >>> 2))) < (FLOOR_Y - NET_H)) begin// [撞到頂部]
                    // 只有當球是「往下掉」的時候，才讓它彈起來
                    if (ball_vy > 0) begin
                        ball_vy <= -ball_vy; 
                    end
                end
                else begin // [撞到側面]
                    // 判斷是撞到左邊還是右邊
                    if ((ball_x + (BALL_SIZE >>> 1)) < NET_X) begin// 球在網子左邊 -> 它是往右飛撞過來的
                        // 所以只有當 vx > 0 (向右) 時才反彈
                        if (ball_vx > 0) begin
                            ball_vx <= -ball_vx;
                        end
                    end
                    else begin// 球在網子右邊 -> 它是往左飛撞過來的
                        // 所以只有當 vx < 0 (向左) 時才反彈
                        if (ball_vx < 0) begin
                            ball_vx <= -ball_vx;
                        end
                    end
                end
            end

            // 遊戲結束重置位置
            if (game_over) begin
                ball_y <= 50 * SCALE; 
                ball_vx <= 0; 
                ball_vy <= 0;
                if (winner == 1) ball_x <= BALL_START_R;
                else ball_x <= BALL_START_L;
                game_over <= 0;
                net_cooldown <= 0;
            end
        end 
        else begin
            valid <= 0;
        end
    end

endmodule
