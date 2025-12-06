module physic (
    input wire clk,
    input wire rst_n,

    // --- 操作輸入 (由 Keypad/Keyboard 模組傳入) ---
    // P1
    input wire p1_op_move_left, 
    input wire p1_op_move_right, 
    input wire p1_op_jump,
    input wire p1_is_smash,
    // P2
    input wire p2_op_move_left, 
    input wire p2_op_move_right, 
    input wire p2_op_jump,
    input wire p2_is_smash,

    // --- 碰撞偵測 (Render 傳入，用於精確判定球是否碰到皮卡丘像素) ---
    input wire p1_cover, 
    input wire p2_cover, 
    
    // --- 輸出 (傳給 Render 畫圖用) ---
    output reg [9:0] p1_pos_x, p1_pos_y, // P1 位置 (新)
    output reg [9:0] p2_pos_x, p2_pos_y, // P2 位置 (新)
    output reg [9:0] ball_pos_x, ball_pos_y,
    
    // --- 遊戲狀態輸出 ---
    output reg [3:0] p1_score, p2_score,
    output reg game_over
);
    
    localparam COORD_W = 10; 
    localparam VEL_W   = 10; 
    localparam FRAC_W  = 6; 

    // --- 尺寸設定 ---
    localparam BALL_SIZE = 10'd40; 
    localparam BALL_RADIUS = 10'd20;
    localparam BALL_RADIUS_SQ = 20'd400;

    localparam PLAYER_W = 10'd64; // 角色寬
    localparam PLAYER_H = 10'd64; // 角色高
    localparam PIKA_HALF_W = 10'd32; 
    localparam PIKA_HALF_H = 10'd32;

    // --- 物理常數 ---
    localparam GRAVITY   = 10'd1; 
    localparam BOUNCE_DAMPING = 10'd55; 

    // --- 角色移動參數 ---
    localparam PLAYER_SPEED = 10'd6;   // 角色跑步速度
    localparam JUMP_FORCE   = 10'd16;  // 跳躍初速度 (負值)

    // --- 球速與力道 ---
    localparam P1_SMASH_VX = 10'd320; 
    localparam P1_SMASH_VY = -10'd448; 
    localparam P2_SMASH_VX = -10'd320;
    localparam P2_SMASH_VY = -10'd448;
    localparam PLAYER_PUSH_VEL = 10'd96; 
    localparam NET_CORNER_PUSH = 10'd4; 

    // --- 場地邊界 ---
    localparam SCREEN_WIDTH  = 10'd320;
    localparam SCREEN_HEIGHT = 10'd240;
    localparam FLOOR_Y_POS   = SCREEN_HEIGHT; // 地板 Y 座標
    
    localparam NET_W       = 10'd6;   
    localparam NET_H       = 10'd90;
    localparam NET_X_POS   = 10'd160; 
    localparam NET_TOP_Y   = FLOOR_Y_POS - NET_H; 
    localparam NET_LEFT_X  = NET_X_POS - NET_W;
    localparam NET_RIGHT_X = NET_X_POS + NET_W;

    localparam LEFT_WALL_X  = 10'd0;
    localparam RIGHT_WALL_X = SCREEN_WIDTH; 

    // --- 初始位置 ---
    localparam BALL_INIT_X = 10'd260;
    localparam BALL_INIT_Y = 10'd50; 
    localparam P1_INIT_X   = 10'd50;
    localparam P1_INIT_Y   = FLOOR_Y_POS - PLAYER_H; // 貼地
    localparam P2_INIT_X   = 10'd260;
    localparam P2_INIT_Y   = FLOOR_Y_POS - PLAYER_H; // 貼地

    localparam COOLDOWN_MAX = 4'd12; 
    
    // --- 球的變數 ---
    reg signed [VEL_W-1:0] ball_vel_x, ball_vel_y;
    wire signed [VEL_W-1:0] ball_vel_y_calc; 
    wire signed [COORD_W-1:0] ball_pos_y_calc;
    wire signed [COORD_W-1:0] ball_pos_x_calc;
    wire signed [COORD_W-1:0] ball_bottom, ball_right;
    wire signed [COORD_W-1:0] ball_center_x, ball_center_y;

    // --- 角色變數 ---
    reg signed [10:0] p1_vel_y, p2_vel_y; // 角色垂直速度 (處理跳躍)
    reg p1_in_air, p2_in_air;             // 是否在空中

    // --- 中心點與距離向量 (用於碰撞) ---
    wire signed [COORD_W-1:0] p1_center_x, p1_center_y;
    wire signed [COORD_W-1:0] p2_center_x, p2_center_y;

    assign p1_center_x = p1_pos_x + PIKA_HALF_W;
    assign p1_center_y = p1_pos_y + PIKA_HALF_H;
    assign p2_center_x = p2_pos_x + PIKA_HALF_W;
    assign p2_center_y = p2_pos_y + PIKA_HALF_H;
    
    assign ball_center_x = ball_pos_x + BALL_RADIUS;
    assign ball_center_y = ball_pos_y + BALL_RADIUS;

    // --- 網子角落距離計算 ---
    wire signed [COORD_W:0] diff_net_left_x  = ball_center_x - NET_LEFT_X;
    wire signed [COORD_W:0] diff_net_right_x = ball_center_x - NET_RIGHT_X;
    wire signed [COORD_W:0] diff_net_y       = ball_center_y - NET_TOP_Y;

    wire signed [20:0] dist_sq_left  = (diff_net_left_x * diff_net_left_x) + (diff_net_y * diff_net_y);
    wire signed [20:0] dist_sq_right = (diff_net_right_x * diff_net_right_x) + (diff_net_y * diff_net_y);

    // --- 玩家碰撞距離計算 ---
    wire signed [COORD_W:0] diff_p1_x = ball_center_x - p1_center_x;
    wire signed [COORD_W:0] diff_p1_y = ball_center_y - p1_center_y;
    wire signed [COORD_W:0] diff_p2_x = ball_center_x - p2_center_x;
    wire signed [COORD_W:0] diff_p2_y = ball_center_y - p2_center_y;

    // 絕對值
    wire [COORD_W:0] abs_diff_p1_x = (diff_p1_x < 0) ? -diff_p1_x : diff_p1_x;
    wire [COORD_W:0] abs_diff_p1_y = (diff_p1_y < 0) ? -diff_p1_y : diff_p1_y;
    wire [COORD_W:0] abs_diff_p2_x = (diff_p2_x < 0) ? -diff_p2_x : diff_p2_x;
    wire [COORD_W:0] abs_diff_p2_y = (diff_p2_y < 0) ? -diff_p2_y : diff_p2_y;
    
    wire [COORD_W:0] abs_diff_net_Lx = (diff_net_left_x < 0) ? -diff_net_left_x : diff_net_left_x;
    wire [COORD_W:0] abs_diff_net_Rx = (diff_net_right_x < 0) ? -diff_net_right_x : diff_net_right_x;
    wire [COORD_W:0] abs_diff_net_y  = (diff_net_y < 0) ? -diff_net_y : diff_net_y;

    // --- 碰撞 Flag ---
    reg [3:0] hit_cooldown, hit_cooldown_next;
    wire ball_hit_floor_cond = (ball_bottom >= FLOOR_Y_POS);
    wire ball_hit_corner_left_cond  = (dist_sq_left <= BALL_RADIUS_SQ);
    wire ball_hit_corner_right_cond = (dist_sq_right <= BALL_RADIUS_SQ);

    // 球體預判
    assign ball_vel_y_calc = ball_vel_y + GRAVITY;
    assign ball_pos_y_calc = ball_pos_y + (ball_vel_y_calc >>> FRAC_W);
    assign ball_pos_x_calc = ball_pos_x + (ball_vel_x >>> FRAC_W);
    assign ball_bottom = ball_pos_y_calc + BALL_SIZE;
    assign ball_right  = ball_pos_x_calc + BALL_SIZE;

    // 網子平面判定
    wire x_overlap_net = (ball_right > NET_LEFT_X) && (ball_pos_x_calc < NET_RIGHT_X);
    wire y_overlap_net = (ball_bottom > NET_TOP_Y);
    wire ball_hit_net_top_cond  = x_overlap_net && y_overlap_net && ((ball_pos_y + BALL_SIZE) <= NET_TOP_Y) && !ball_hit_corner_left_cond && !ball_hit_corner_right_cond;
    wire ball_hit_net_side_cond = x_overlap_net && y_overlap_net && !ball_hit_net_top_cond && !ball_hit_corner_left_cond && !ball_hit_corner_right_cond;
    
    wire ball_hit_wall_left_cond  = (ball_pos_x_calc <= LEFT_WALL_X);
    wire ball_hit_wall_right_cond = (ball_right >= RIGHT_WALL_X);

    // --- 暫存變數 ---
    reg signed [VEL_W-1:0] final_vel_x, final_vel_y;
    reg signed [COORD_W-1:0] final_pos_x, final_pos_y;
    reg [SCORE_W-1:0] p1_score_next, p2_score_next;
    reg score_happened; 
    
    reg signed [11:0] p1_next_x, p1_next_y;
    reg signed [11:0] p2_next_x, p2_next_y;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // --- Reset ---
            p1_pos_x <= P1_INIT_X; p1_pos_y <= P1_INIT_Y; p1_vel_y <= 0; p1_in_air <= 0;
            p2_pos_x <= P2_INIT_X; p2_pos_y <= P2_INIT_Y; p2_vel_y <= 0; p2_in_air <= 0;
            
            ball_pos_x <= BALL_INIT_X; ball_pos_y <= BALL_INIT_Y;
            ball_vel_x <= 0; ball_vel_y <= 0;
            
            p1_score <= 0; p2_score <= 0;
            game_over <= 0;
            hit_cooldown <= 0;
        end else begin
            // 1. P1 角色移動物理
            // A. X 軸移動
            if (p1_op_move_left)  p1_next_x = p1_pos_x - PLAYER_SPEED;
            else if (p1_op_move_right) p1_next_x = p1_pos_x + PLAYER_SPEED;
            else p1_next_x = p1_pos_x;

            // B. X 軸邊界限制 (左牆 ~ 網子左側)
            if (p1_next_x < LEFT_WALL_X) p1_next_x = LEFT_WALL_X;
            else if (p1_next_x + PLAYER_W > NET_LEFT_X) p1_next_x = NET_LEFT_X - PLAYER_W;
            p1_pos_x <= p1_next_x;

            // C. Y 軸跳躍與重力
            if (p1_op_jump && !p1_in_air) begin
                p1_vel_y <= -JUMP_FORCE;
                p1_in_air <= 1;
            end else if (p1_in_air) begin
                if (p1_vel_y < 15) p1_vel_y <= p1_vel_y + GRAVITY; // 終端速度
            end
            p1_next_y = p1_pos_y + p1_vel_y;

            // D. Y 軸地板碰撞
            if (p1_next_y + PLAYER_H >= FLOOR_Y_POS) begin
                p1_pos_y <= FLOOR_Y_POS - PLAYER_H;
                p1_vel_y <= 0;
                p1_in_air <= 0;
            end else begin
                p1_pos_y <= p1_next_y;
                if (p1_pos_y + PLAYER_H < FLOOR_Y_POS - 2) p1_in_air <= 1; // 離地偵測
            end

            // 2. P2 角色移動物理
            // A. X 軸移動
            if (p2_op_move_left)  p2_next_x = p2_pos_x - PLAYER_SPEED;
            else if (p2_op_move_right) p2_next_x = p2_pos_x + PLAYER_SPEED;
            else p2_next_x = p2_pos_x;

            // B. X 軸邊界限制 (網子右側 ~ 右牆)
            if (p2_next_x < NET_RIGHT_X) p2_next_x = NET_RIGHT_X;
            else if (p2_next_x + PLAYER_W > RIGHT_WALL_X) p2_next_x = RIGHT_WALL_X - PLAYER_W;
            p2_pos_x <= p2_next_x;

            // C. Y 軸跳躍與重力
            if (p2_op_jump && !p2_in_air) begin
                p2_vel_y <= -JUMP_FORCE;
                p2_in_air <= 1;
            end else if (p2_in_air) begin
                if (p2_vel_y < 15) p2_vel_y <= p2_vel_y + GRAVITY;
            end
            p2_next_y = p2_pos_y + p2_vel_y;

            // D. Y 軸地板碰撞
            if (p2_next_y + PLAYER_H >= FLOOR_Y_POS) begin
                p2_pos_y <= FLOOR_Y_POS - PLAYER_H;
                p2_vel_y <= 0;
                p2_in_air <= 0;
            end else begin
                p2_pos_y <= p2_next_y;
                if (p2_pos_y + PLAYER_H < FLOOR_Y_POS - 2) p2_in_air <= 1;
            end

            // 3. 球體物理 (Ball Physics)
            // 狀態準備
            final_vel_x = ball_vel_x;
            final_vel_y = ball_vel_y_calc;
            final_pos_x = ball_pos_x_calc;
            final_pos_y = ball_pos_y_calc;
            p1_score_next = p1_score;
            p2_score_next = p2_score;
            score_happened = 1'b0;
            hit_cooldown_next = (hit_cooldown > 0) ? (hit_cooldown - 1) : 4'd0;

            // --- A. 玩家擊球 ---
            if ((p1_cover || p2_cover) && (hit_cooldown == 0)) begin
                hit_cooldown_next = COOLDOWN_MAX;

                if (p1_cover) begin
                    if (p1_is_smash) begin
                        final_vel_x = P1_SMASH_VX; final_vel_y = P1_SMASH_VY;
                    end else begin
                        // 物理反射
                        if (abs_diff_p1_x > abs_diff_p1_y) begin // 撞側
                            if (diff_p1_x > 0) begin if (final_vel_x < 0) final_vel_x = -final_vel_x; end
                            else begin if (final_vel_x > 0) final_vel_x = -final_vel_x; end
                        end else begin // 撞頭
                            if (final_vel_y > -128) final_vel_y = -192; else final_vel_y = -final_vel_y;
                        end
                        // 推力摩擦
                        if (p1_op_move_right) final_vel_x = final_vel_x + PLAYER_PUSH_VEL;
                        if (p1_op_move_left)  final_vel_x = final_vel_x - PLAYER_PUSH_VEL;
                        final_vel_x = final_vel_x + (diff_p1_x >>> 1);
                    end
                end
                else if (p2_cover) begin
                    if (p2_is_smash) begin
                        final_vel_x = P2_SMASH_VX; final_vel_y = P2_SMASH_VY;
                    end else begin
                        if (abs_diff_p2_x > abs_diff_p2_y) begin
                            if (diff_p2_x > 0) begin if (final_vel_x < 0) final_vel_x = -final_vel_x; end
                            else begin if (final_vel_x > 0) final_vel_x = -final_vel_x; end
                        end else begin
                            if (final_vel_y > -128) final_vel_y = -192; else final_vel_y = -final_vel_y;
                        end
                        if (p2_op_move_right) final_vel_x = final_vel_x + PLAYER_PUSH_VEL;
                        if (p2_op_move_left)  final_vel_x = final_vel_x - PLAYER_PUSH_VEL;
                        final_vel_x = final_vel_x + (diff_p2_x >>> 1);
                    end
                end
            end
            // --- B. 環境碰撞 ---
            else begin
                if (ball_hit_corner_left_cond) begin
                    if (abs_diff_net_Lx > abs_diff_net_y) begin if (final_vel_x > 0) final_vel_x = -final_vel_x; end
                    else begin if (final_vel_y > 0) final_vel_y = -final_vel_y; end
                    final_vel_x = final_vel_x + (diff_net_left_x * NET_CORNER_PUSH);
                    final_vel_y = final_vel_y + (diff_net_y * NET_CORNER_PUSH);
                end
                else if (ball_hit_corner_right_cond) begin
                    if (abs_diff_net_Rx > abs_diff_net_y) begin if (final_vel_x < 0) final_vel_x = -final_vel_x; end
                    else begin if (final_vel_y > 0) final_vel_y = -final_vel_y; end
                    final_vel_x = final_vel_x + (diff_net_right_x * NET_CORNER_PUSH);
                    final_vel_y = final_vel_y + (diff_net_y * NET_CORNER_PUSH);
                end
                else if (ball_hit_net_top_cond) begin
                    if (final_vel_y > 0) begin final_vel_y = -final_vel_y; final_vel_y = (final_vel_y * 3) >>> 2; end
                    final_pos_y = NET_TOP_Y - BALL_SIZE - 2;
                end
                else if (ball_hit_net_side_cond) begin
                    if (ball_pos_x_calc + (BALL_SIZE/2) < NET_X_POS) begin if (final_vel_x > 0) final_vel_x = -final_vel_x; final_pos_x = NET_LEFT_X - BALL_SIZE - 2; end
                    else begin if (final_vel_x < 0) final_vel_x = -final_vel_x; final_pos_x = NET_RIGHT_X + 2; end
                end
                else if (ball_hit_floor_cond) begin
                    if (final_vel_y > 0) begin final_vel_y = -final_vel_y; final_vel_y = (final_vel_y * BOUNCE_DAMPING) >>> 6; end
                    final_pos_y = FLOOR_Y_POS - BALL_SIZE;
                    if (!score_happened) begin
                        if (ball_pos_x_calc < NET_X_POS) begin p2_score_next = p2_score + 1; score_happened = 1'b1; end
                        else begin p1_score_next = p1_score + 1; score_happened = 1'b1; end
                    end
                end
                else if (ball_hit_wall_left_cond) begin
                    if (final_vel_x < 0) final_vel_x = -final_vel_x; final_pos_x = LEFT_WALL_X + 2;
                end
                else if (ball_hit_wall_right_cond) begin
                    if (final_vel_x > 0) final_vel_x = -final_vel_x; final_pos_x = RIGHT_WALL_X - BALL_SIZE - 2;
                end
            end

            // --- C. 更新球的變數 ---
            game_over <= score_happened;
            p1_score <= p1_score_next;
            p2_score <= p2_score_next;
            hit_cooldown <= hit_cooldown_next;

            if (score_happened) begin
                ball_pos_x <= BALL_INIT_X; ball_pos_y <= BALL_INIT_Y;
                ball_vel_x <= 0; ball_vel_y <= 0;
                hit_cooldown <= 0;
            end else begin
                ball_vel_x <= final_vel_x; ball_vel_y <= final_vel_y;
                ball_pos_x <= final_pos_x; ball_pos_y <= final_pos_y;
            end
        end
    end

endmodule
