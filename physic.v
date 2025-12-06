module physic (
    input wire clk,
    input wire rst_n,
    input wire en, // 60Hz Trigger

    // 輸入
    input wire p1_move_left, p1_move_right, p1_jump, p1_smash,
    input wire p2_move_left, p2_move_right, p2_jump, p2_smash,
    
    // 碰撞範圍輸入
    input wire p1_cover, 
    input wire p2_cover, 

    // 輸出
    output wire [9:0] p1_pos_x, p1_pos_y,
    output wire [9:0] p2_pos_x, p2_pos_y,
    output wire [9:0] ball_pos_x, ball_pos_y,
    
    output reg game_over,
    output reg [1:0] winner,
    output reg valid
);

    // --- 1. 參數設定 (放大 64 倍) ---
    localparam signed [15:0] SCALE = 16'd64; 

    // 物理常數
    localparam signed [15:0] GRAVITY      = 16'd25;   
    localparam signed [15:0] JUMP_FORCE   = 16'd800;  
    localparam signed [15:0] MOVE_SPEED   = 16'd320;  
    
    // --- 殺球參數修改 ---
    // SMASH_X: 殺球水平速度 (要很快，大約 25 px/frame)
    localparam signed [15:0] SMASH_X      = 16'd1600; 
    // SMASH_Y: 殺球垂直速度 (改成正數 = 向下殺球！)
    localparam signed [15:0] SMASH_Y      = 16'd600;  
    
    localparam signed [15:0] BOUNCE_Y     = -16'd700; // 普通反彈
    localparam signed [15:0] HEAD_PUSH_X  = 16'd250;  // 普通頭頂推力

    // 尺寸與邊界
    localparam signed [15:0] FLOOR_Y      = 16'd480 * SCALE;
    localparam signed [15:0] SCREEN_W     = 16'd640 * SCALE;
    localparam signed [15:0] BALL_SIZE    = 16'd80  * SCALE;
    localparam signed [15:0] P_H          = 16'd128 * SCALE;
    localparam signed [15:0] P_W          = 16'd128 * SCALE;
    localparam signed [15:0] NET_H        = 16'd180 * SCALE;
    localparam signed [15:0] NET_X        = 16'd320 * SCALE;

    // --- 初始位置 (置中) ---
    localparam signed [15:0] P1_INIT_X    = 16'd96 * SCALE;
    localparam signed [15:0] P2_INIT_X    = 16'd416 * SCALE; 
    
    // --- 2. 內部變數 ---
    reg signed [19:0] p1_x, p1_y, p1_vy;
    reg signed [19:0] p2_x, p2_y, p2_vy;
    reg signed [19:0] ball_x, ball_y, ball_vx, ball_vy;
    
    reg p1_air, p2_air;
    reg [4:0] cooldown;

    // --- 3. 輸出邏輯 ---
    assign p1_pos_x = p1_x >>> 6;
    assign p1_pos_y = p1_y >>> 6;
    assign p2_pos_x = p2_x >>> 6;
    assign p2_pos_y = p2_y >>> 6;
    assign ball_pos_x = ball_x >>> 6;
    assign ball_pos_y = ball_y >>> 6;

    // --- 4. 碰撞判定輔助變數 ---
    wire p1_hit = (ball_x + BALL_SIZE > p1_x + 20*SCALE) && (ball_x < p1_x + P_W - 20*SCALE) &&
                  (ball_y + BALL_SIZE > p1_y) && (ball_y < p1_y + P_H);
                  
    wire p2_hit = (ball_x + BALL_SIZE > p2_x + 20*SCALE) && (ball_x < p2_x + P_W - 20*SCALE) &&
                  (ball_y + BALL_SIZE > p2_y) && (ball_y < p2_y + P_H);

    // 判斷球在頭的哪一邊
    wire p1_hit_left_side = (ball_x + 40*SCALE) < (p1_x + 64*SCALE);
    wire p2_hit_left_side = (ball_x + 40*SCALE) < (p2_x + 64*SCALE);

    // --- 5. 主邏輯 ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p1_x <= P1_INIT_X; p1_y <= FLOOR_Y - P_H; p1_vy <= 0; p1_air <= 0;
            p2_x <= P2_INIT_X; p2_y <= FLOOR_Y - P_H; p2_vy <= 0; p2_air <= 0;
            
            // 開局球在 P2 頭上
            ball_x <= P2_INIT_X; ball_y <= 50 * SCALE; 
            ball_vx <= 0; ball_vy <= 0;
            
            game_over <= 0; winner <= 0; valid <= 0; cooldown <= 0;
        end 
        else if (en) begin 
            valid <= 1;

            // --- P1 物理 ---
            if (p1_move_left && p1_x > 0) p1_x <= p1_x - MOVE_SPEED;
            if (p1_move_right && p1_x < (NET_X - P_W)) p1_x <= p1_x + MOVE_SPEED;
            
            if (p1_jump && !p1_air) begin p1_vy <= -JUMP_FORCE; p1_air <= 1; end
            
            if (p1_air) begin
                p1_vy <= p1_vy + GRAVITY;
                p1_y <= p1_y + p1_vy;
                if (p1_y >= FLOOR_Y - P_H) begin p1_y <= FLOOR_Y - P_H; p1_vy <= 0; p1_air <= 0; end
            end

            // --- P2 物理 ---
            if (p2_move_left && p2_x > (NET_X)) p2_x <= p2_x - MOVE_SPEED;
            if (p2_move_right && p2_x < (SCREEN_W - P_W)) p2_x <= p2_x + MOVE_SPEED;

            if (p2_jump && !p2_air) begin p2_vy <= -JUMP_FORCE; p2_air <= 1; end
            
            if (p2_air) begin
                p2_vy <= p2_vy + GRAVITY;
                p2_y <= p2_y + p2_vy;
                if (p2_y >= FLOOR_Y - P_H) begin p2_y <= FLOOR_Y - P_H; p2_vy <= 0; p2_air <= 0; end
            end

            // --- 球的物理 ---
            ball_vy <= ball_vy + GRAVITY;
            ball_x <= ball_x + ball_vx;
            ball_y <= ball_y + ball_vy;

            // --- 碰撞處理 (加入殺球邏輯) ---
            if (cooldown > 0) cooldown <= cooldown - 1;
            else if (p1_hit || p2_hit) begin
                cooldown <= 15; 
                
                // === P1 碰到球 ===
                if (p1_hit) begin
                    if (p1_smash) begin 
                        // [殺球邏輯]
                        // X軸：極快往右
                        ball_vx <= SMASH_X; 
                        // Y軸：快速向下 (正值)
                        ball_vy <= SMASH_Y; 
                    end
                    else begin
                        // [普通反彈邏輯]
                        if (p1_hit_left_side) ball_vx <= -HEAD_PUSH_X;
                        else ball_vx <= HEAD_PUSH_X;

                        // 強制向上彈
                        if (ball_vy > -500*SCALE) ball_vy <= BOUNCE_Y; 
                        else ball_vy <= -ball_vy;
                    end
                end 
                
                // === P2 碰到球 ===
                else if (p2_hit) begin
                    if (p2_smash) begin 
                        // [殺球邏輯]
                        // X軸：極快往左 (負值)
                        ball_vx <= -SMASH_X; 
                        // Y軸：快速向下
                        ball_vy <= SMASH_Y; 
                    end
                    else begin
                        // [普通反彈邏輯]
                        if (p2_hit_left_side) ball_vx <= -HEAD_PUSH_X;
                        else ball_vx <= HEAD_PUSH_X;

                        if (ball_vy > -500*SCALE) ball_vy <= BOUNCE_Y; 
                        else ball_vy <= -ball_vy;
                    end
                end
            end

            // --- 邊界與網子 ---
            if (ball_x <= 0) begin ball_x <= 0; ball_vx <= -ball_vx; end
            else if (ball_x >= SCREEN_W - BALL_SIZE) begin ball_x <= SCREEN_W - BALL_SIZE; ball_vx <= -ball_vx; end
            
            if (ball_y >= FLOOR_Y - BALL_SIZE) begin
                game_over <= 1;
                winner <= (ball_x < NET_X) ? 2 : 1;
                ball_y <= FLOOR_Y - BALL_SIZE; ball_vx <= 0; ball_vy <= 0;
            end
            
            if (ball_y + BALL_SIZE > FLOOR_Y - NET_H && 
                ball_x + BALL_SIZE > NET_X - 5*SCALE && ball_x < NET_X + 5*SCALE) begin
                ball_vy <= -ball_vy;
                ball_y <= FLOOR_Y - NET_H - BALL_SIZE;
            end

            if (game_over) begin
                ball_x <= P2_INIT_X; ball_y <= 50 * SCALE; 
                ball_vx <= 0; ball_vy <= 0;
                game_over <= 0;
            end
        end 
        else begin
            valid <= 0;
        end
    end

endmodule
