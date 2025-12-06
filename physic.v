module physic (
    input wire clk,
    input wire rst_n,
    input wire en, // 物理更新使能 (Enable)

    // --- 操作輸入 ---
    input wire p1_op_move_left, p1_op_move_right, p1_op_jump, p1_is_smash,
    input wire p2_op_move_left, p2_op_move_right, p2_op_jump, p2_is_smash,

    // --- 碰撞偵測 (Render 傳入) ---
    input wire p1_cover, 
    input wire p2_cover, 
    
    // --- 位置輸出 (傳給 Render) ---
    output reg [9:0] p1_pos_x, p1_pos_y,
    output reg [9:0] p2_pos_x, p2_pos_y,
    output reg [9:0] ball_pos_x, ball_pos_y,
    
    // --- 遊戲狀態輸出 ---
    output reg game_over,      // 1 = 球落地 (回合結束)
    output reg [1:0] winner,   // 0=無, 1=P1贏, 2=P2贏
    output reg valid           // 1 = 資料更新完畢
);
    
    
    //  參數設定 (Parameters)
    
    localparam COORD_W = 10; 
    localparam VEL_W   = 10; 
    localparam FRAC_W  = 6; 

    // 尺寸
    localparam BALL_SIZE = 10'd40; 
    localparam BALL_RADIUS = 10'd20;
    localparam BALL_RADIUS_SQ = 20'd400;
    localparam PLAYER_W = 10'd64; 
    localparam PLAYER_H = 10'd64; 
    localparam PIKA_HALF_W = 10'd32; 
    localparam PIKA_HALF_H = 10'd32;

    // 物理常數
    localparam GRAVITY   = 10'd1; 
    localparam BOUNCE_DAMPING = 10'd55; 
    localparam PLAYER_SPEED = 10'd6;   
    localparam JUMP_FORCE   = 10'd16;  

    // 擊球與推力
    localparam P1_SMASH_VX = 10'd320; localparam P1_SMASH_VY = -10'd448; 
    localparam P2_SMASH_VX = -10'd320; localparam P2_SMASH_VY = -10'd448;
    localparam PLAYER_PUSH_VEL = 10'd96; 
    localparam NET_CORNER_PUSH = 10'd4; 

    // 場地邊界
    localparam SCREEN_WIDTH  = 10'd320; localparam SCREEN_HEIGHT = 10'd240;
    localparam FLOOR_Y_POS   = SCREEN_HEIGHT; 
    localparam NET_W = 10'd6; localparam NET_H = 10'd90; localparam NET_X_POS = 10'd160; 
    localparam NET_TOP_Y = FLOOR_Y_POS - NET_H; 
    localparam NET_LEFT_X = NET_X_POS - NET_W; localparam NET_RIGHT_X = NET_X_POS + NET_W;
    localparam LEFT_WALL_X = 10'd0; localparam RIGHT_WALL_X = SCREEN_WIDTH; 

    // 初始值
    localparam BALL_INIT_X = 10'd260;
    localparam BALL_INIT_Y = 10'd200;
    localparam P1_INIT_X   = 10'd50;  localparam P1_INIT_Y   = FLOOR_Y_POS - PLAYER_H;
    localparam P2_INIT_X   = 10'd260; localparam P2_INIT_Y   = FLOOR_Y_POS - PLAYER_H; 
    localparam COOLDOWN_MAX = 4'd12; 

    
    //  內部變數與 Wire
    
    reg signed [VEL_W-1:0] ball_vel_x, ball_vel_y;
    reg [3:0] hit_cooldown;
    reg signed [10:0] p1_vel_y, p2_vel_y;
    reg p1_in_air, p2_in_air;

    // --- 中心點計算 ---
    wire signed [COORD_W-1:0] ball_center_x = ball_pos_x + BALL_RADIUS;
    wire signed [COORD_W-1:0] ball_center_y = ball_pos_y + BALL_RADIUS;
    wire signed [COORD_W-1:0] p1_center_x = p1_pos_x + PIKA_HALF_W;
    wire signed [COORD_W-1:0] p1_center_y = p1_pos_y + PIKA_HALF_H;
    wire signed [COORD_W-1:0] p2_center_x = p2_pos_x + PIKA_HALF_W;
    wire signed [COORD_W-1:0] p2_center_y = p2_pos_y + PIKA_HALF_H;

    // --- 網子距離計算 (補上這裡) ---
    wire signed [COORD_W:0] diff_net_left_x = ball_center_x - NET_LEFT_X;
    wire signed [COORD_W:0] diff_net_right_x = ball_center_x - NET_RIGHT_X;
    wire signed [COORD_W:0] diff_net_y  = ball_center_y - NET_TOP_Y;
    
    wire signed [20:0] dist_sq_L = (diff_net_left_x * diff_net_left_x) + (diff_net_y * diff_net_y);
    wire signed [20:0] dist_sq_R = (diff_net_right_x * diff_net_right_x) + (diff_net_y * diff_net_y);

    // --- 玩家距離計算 (補上這裡) ---
    wire signed [COORD_W:0] diff_p1_x = ball_center_x - p1_center_x;
    wire signed [COORD_W:0] diff_p1_y = ball_center_y - p1_center_y;
    wire signed [COORD_W:0] diff_p2_x = ball_center_x - p2_center_x;
    wire signed [COORD_W:0] diff_p2_y = ball_center_y - p2_center_y;

    // --- 絕對值計算 ---
    wire [COORD_W:0] abs_diff_p1_x = (diff_p1_x < 0) ? -diff_p1_x : diff_p1_x;
    wire [COORD_W:0] abs_diff_p1_y = (diff_p1_y < 0) ? -diff_p1_y : diff_p1_y;
    wire [COORD_W:0] abs_diff_p2_x = (diff_p2_x < 0) ? -diff_p2_x : diff_p2_x;
    wire [COORD_W:0] abs_diff_p2_y = (diff_p2_y < 0) ? -diff_p2_y : diff_p2_y;
    wire [COORD_W:0] abs_diff_net_Lx = (diff_net_left_x < 0) ? -diff_net_left_x : diff_net_left_x;
    wire [COORD_W:0] abs_diff_net_Rx = (diff_net_right_x < 0) ? -diff_net_right_x : diff_net_right_x;
    wire [COORD_W:0] abs_diff_net_y  = (diff_net_y < 0) ? -diff_net_y : diff_net_y;

    // --- 球體預判 ---
    wire signed [9:0] ball_vel_y_predict = ball_vel_y + GRAVITY;
    wire signed [9:0] ball_pos_y_predict = ball_pos_y + (ball_vel_y_predict >>> FRAC_W);
    wire signed [9:0] ball_pos_x_predict = ball_pos_x + (ball_vel_x >>> FRAC_W);
    wire signed [9:0] ball_bottom_predict = ball_pos_y_predict + BALL_SIZE;
    wire signed [9:0] ball_right_predict  = ball_pos_x_predict + BALL_SIZE;

    // --- 碰撞 Flags ---
    wire hit_floor = (ball_bottom_predict >= FLOOR_Y_POS);
    wire hit_corner_L = (dist_sq_L <= BALL_RADIUS_SQ);
    wire hit_corner_R = (dist_sq_R <= BALL_RADIUS_SQ);
    wire x_over_net = (ball_right_predict > NET_LEFT_X) && (ball_pos_x_predict < NET_RIGHT_X);
    wire y_over_net = (ball_bottom_predict > NET_TOP_Y);
    wire hit_net_top  = x_over_net && y_over_net && ((ball_pos_y + BALL_SIZE) <= NET_TOP_Y) && !hit_corner_L && !hit_corner_R;
    wire hit_net_side = x_over_net && y_over_net && !hit_net_top && !hit_corner_L && !hit_corner_R;
    wire hit_wall_L = (ball_pos_x_predict <= LEFT_WALL_X);
    wire hit_wall_R = (ball_right_predict >= RIGHT_WALL_X);

    // --- 暫存 Next State 變數 ---
    reg signed [VEL_W-1:0] next_ball_vx, next_ball_vy;
    reg signed [COORD_W-1:0] next_ball_px, next_ball_py;
    reg next_game_over;
    reg [1:0] next_winner;
    reg [3:0] hit_cooldown_next;
    reg signed [11:0] temp_p1_x, temp_p1_y;
    reg signed [11:0] temp_p2_x, temp_p2_y;

    
    //  State Update Logic
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset
            p1_pos_x <= P1_INIT_X; p1_pos_y <= P1_INIT_Y; p1_vel_y <= 0; p1_in_air <= 0;
            p2_pos_x <= P2_INIT_X; p2_pos_y <= P2_INIT_Y; p2_vel_y <= 0; p2_in_air <= 0;
            ball_pos_x <= BALL_INIT_X; ball_pos_y <= BALL_INIT_Y;
            ball_vel_x <= 0; ball_vel_y <= 0;
            game_over <= 0;
            winner <= 0;
            hit_cooldown <= 0;
            valid <= 0;
        end 
        else if (en) begin
            valid <= 1;

            // --- 1. P1 角色移動 ---
            if (p1_op_move_left)  temp_p1_x = p1_pos_x - PLAYER_SPEED;
            else if (p1_op_move_right) temp_p1_x = p1_pos_x + PLAYER_SPEED;
            else temp_p1_x = p1_pos_x;
            
            if (temp_p1_x < LEFT_WALL_X) temp_p1_x = LEFT_WALL_X;
            else if (temp_p1_x + PLAYER_W > NET_LEFT_X) temp_p1_x = NET_LEFT_X - PLAYER_W;
            p1_pos_x <= temp_p1_x;

            if (p1_op_jump && !p1_in_air) begin p1_vel_y <= -JUMP_FORCE; p1_in_air <= 1; end 
            else if (p1_in_air && p1_vel_y < 15) p1_vel_y <= p1_vel_y + GRAVITY;
            
            temp_p1_y = p1_pos_y + p1_vel_y;
            if (temp_p1_y + PLAYER_H >= FLOOR_Y_POS) begin p1_pos_y <= FLOOR_Y_POS - PLAYER_H; p1_vel_y <= 0; p1_in_air <= 0; end 
            else begin p1_pos_y <= temp_p1_y; if (p1_pos_y + PLAYER_H < FLOOR_Y_POS - 2) p1_in_air <= 1; end

            // --- 2. P2 角色移動 ---
            if (p2_op_move_left)  temp_p2_x = p2_pos_x - PLAYER_SPEED;
            else if (p2_op_move_right) temp_p2_x = p2_pos_x + PLAYER_SPEED;
            else temp_p2_x = p2_pos_x;
            
            if (temp_p2_x < NET_RIGHT_X) temp_p2_x = NET_RIGHT_X;
            else if (temp_p2_x + PLAYER_W > RIGHT_WALL_X) temp_p2_x = RIGHT_WALL_X - PLAYER_W;
            p2_pos_x <= temp_p2_x;

            if (p2_op_jump && !p2_in_air) begin p2_vel_y <= -JUMP_FORCE; p2_in_air <= 1; end 
            else if (p2_in_air && p2_vel_y < 15) p2_vel_y <= p2_vel_y + GRAVITY;
            
            temp_p2_y = p2_pos_y + p2_vel_y;
            if (temp_p2_y + PLAYER_H >= FLOOR_Y_POS) begin p2_pos_y <= FLOOR_Y_POS - PLAYER_H; p2_vel_y <= 0; p2_in_air <= 0; end 
            else begin p2_pos_y <= temp_p2_y; if (p2_pos_y + PLAYER_H < FLOOR_Y_POS - 2) p2_in_air <= 1; end

            // --- 3. 球體物理 ---
            next_ball_vx = ball_vel_x; next_ball_vy = ball_vel_y_predict;
            next_ball_px = ball_pos_x_predict; next_ball_py = ball_pos_y_predict;
            next_game_over = 0; next_winner = 0;
            hit_cooldown_next = (hit_cooldown > 0) ? (hit_cooldown - 1) : 4'd0;

            if ((p1_cover || p2_cover) && (hit_cooldown == 0)) begin
                hit_cooldown_next = COOLDOWN_MAX;
                if (p1_cover) begin
                    if (p1_is_smash) begin next_ball_vx = P1_SMASH_VX; next_ball_vy = P1_SMASH_VY; end 
                    else begin
                        if (abs_diff_p1_x > abs_diff_p1_y) begin if (diff_p1_x > 0) begin if (ball_vel_x < 0) next_ball_vx = -ball_vel_x; end else begin if (ball_vel_x > 0) next_ball_vx = -ball_vel_x; end end 
                        else begin if (ball_vel_y_predict > -128) next_ball_vy = -192; else next_ball_vy = -ball_vel_y_predict; end
                        if (p1_op_move_right) next_ball_vx = next_ball_vx + PLAYER_PUSH_VEL; if (p1_op_move_left) next_ball_vx = next_ball_vx - PLAYER_PUSH_VEL;
                        next_ball_vx = next_ball_vx + (diff_p1_x >>> 1);
                    end
                end else if (p2_cover) begin
                    if (p2_is_smash) begin next_ball_vx = P2_SMASH_VX; next_ball_vy = P2_SMASH_VY; end 
                    else begin
                        if (abs_diff_p2_x > abs_diff_p2_y) begin if (diff_p2_x > 0) begin if (ball_vel_x < 0) next_ball_vx = -ball_vel_x; end else begin if (ball_vel_x > 0) next_ball_vx = -ball_vel_x; end end 
                        else begin if (ball_vel_y_predict > -128) next_ball_vy = -192; else next_ball_vy = -ball_vel_y_predict; end
                        if (p2_op_move_right) next_ball_vx = next_ball_vx + PLAYER_PUSH_VEL; if (p2_op_move_left) next_ball_vx = next_ball_vx - PLAYER_PUSH_VEL;
                        next_ball_vx = next_ball_vx + (diff_p2_x >>> 1);
                    end
                end
            end else begin
                if (hit_corner_L) begin
                    if (abs_diff_net_Lx > abs_diff_net_y) begin if (ball_vel_x > 0) next_ball_vx = -ball_vel_x; end else begin if (ball_vel_y_predict > 0) next_ball_vy = -ball_vel_y_predict; end
                    next_ball_vx = next_ball_vx + (diff_net_left_x * NET_CORNER_PUSH); next_ball_vy = next_ball_vy + (diff_net_y * NET_CORNER_PUSH);
                end else if (hit_corner_R) begin
                    if (abs_diff_net_Rx > abs_diff_net_y) begin if (ball_vel_x < 0) next_ball_vx = -ball_vel_x; end else begin if (ball_vel_y_predict > 0) next_ball_vy = -ball_vel_y_predict; end
                    next_ball_vx = next_ball_vx + (diff_net_right_x * NET_CORNER_PUSH); next_ball_vy = next_ball_vy + (diff_net_y * NET_CORNER_PUSH);
                end else if (hit_net_top) begin
                    if (ball_vel_y_predict > 0) begin next_ball_vy = -ball_vel_y_predict; next_ball_vy = (next_ball_vy * 3) >>> 2; end
                    next_ball_py = NET_TOP_Y - BALL_SIZE - 2;
                end else if (hit_net_side) begin
                    if (ball_pos_x_predict + (BALL_SIZE/2) < NET_X_POS) begin if (ball_vel_x > 0) next_ball_vx = -ball_vel_x; next_ball_px = NET_LEFT_X - BALL_SIZE - 2; end
                    else begin if (ball_vel_x < 0) next_ball_vx = -ball_vel_x; next_ball_px = NET_RIGHT_X + 2; end
                end else if (hit_floor) begin
                    if (ball_vel_y_predict > 0) begin next_ball_vy = -ball_vel_y_predict; next_ball_vy = (next_ball_vy * BOUNCE_DAMPING) >>> 6; end
                    next_ball_py = FLOOR_Y_POS - BALL_SIZE;
                    next_game_over = 1'b1;
                    if (ball_pos_x_predict < NET_X_POS) next_winner = 2; else next_winner = 1;
                end else if (hit_wall_L) begin
                    if (ball_vel_x < 0) next_ball_vx = -ball_vel_x; next_ball_px = LEFT_WALL_X + 2;
                end else if (hit_wall_R) begin
                    if (ball_vel_x > 0) next_ball_vx = -ball_vel_x; next_ball_px = RIGHT_WALL_X - BALL_SIZE - 2;
                end
            end

            game_over <= next_game_over;
            winner    <= next_winner;
            hit_cooldown <= hit_cooldown_next;

            if (next_game_over) begin
                ball_pos_x <= BALL_INIT_X; ball_pos_y <= BALL_INIT_Y;
                ball_vel_x <= 0; ball_vel_y <= 0;
                hit_cooldown <= 0;
            end else begin
                ball_vel_x <= next_ball_vx; ball_vel_y <= next_ball_vy;
                ball_pos_x <= next_ball_px; ball_pos_y <= next_ball_py;
            end

        end else begin
            valid <= 0;
        end
    end

endmodule
