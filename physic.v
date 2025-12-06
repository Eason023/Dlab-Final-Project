module physic (
    input wire clk,
    input wire rst_n,
    input wire en, // 60Hz Pulse

    // --- 操作輸入 ---
    input wire p1_op_move_left, p1_op_move_right, p1_op_jump, p1_is_smash,
    input wire p2_op_move_left, p2_op_move_right, p2_op_jump, p2_is_smash,

    // --- 碰撞偵測 (Hitbox) ---
    input wire p1_cover, 
    input wire p2_cover, 
    
    // --- 輸出 ---
    output reg [9:0] p1_pos_x, p1_pos_y,
    output reg [9:0] p2_pos_x, p2_pos_y,
    output reg [9:0] ball_pos_x, ball_pos_y,
    
    output reg game_over,
    output reg [1:0] winner,
    output reg valid
);
    
    // --- 1. 參數設定：保持高精度與 Signed 計算 ---
    
    localparam FRAC_W  = 8;  // 速度精度 8 bits (x256)
    localparam COORD_W = 12; // 座標位元寬
    localparam VEL_W   = 14; // 速度位元寬

    // --- 尺寸 (全部 * 2) ---
    localparam signed [COORD_W-1:0] BALL_SIZE      = 12'd80;
    localparam signed [COORD_W-1:0] BALL_RADIUS    = 12'd40;
    localparam signed [24:0]        BALL_RADIUS_SQ = 25'd1600;
    localparam signed [COORD_W-1:0] PLAYER_W       = 12'd128;
    localparam signed [COORD_W-1:0] PLAYER_H       = 12'd128;
    localparam signed [COORD_W-1:0] PIKA_HALF_W    = 12'd64;
    localparam signed [COORD_W-1:0] PIKA_HALF_H    = 12'd64;

    // --- 物理常數 ---
    localparam signed [VEL_W-1:0] GRAVITY      = 14'd8;   
    localparam signed [VEL_W-1:0] JUMP_FORCE   = 14'd110; 
    localparam signed [VEL_W-1:0] PLAYER_SPEED = 14'd16;  

    // --- 擊球力道 ---
    localparam signed [VEL_W-1:0] P1_SMASH_VX =  14'd1024; 
    localparam signed [VEL_W-1:0] P1_SMASH_VY = -14'd1536; 
    localparam signed [VEL_W-1:0] P2_SMASH_VX = -14'd1024; 
    localparam signed [VEL_W-1:0] P2_SMASH_VY = -14'd1536;
    localparam signed [VEL_W-1:0] PLAYER_PUSH_VEL = 14'd256; 

    // --- 場地邊界 ---
    localparam signed [COORD_W-1:0] SCREEN_WIDTH  = 12'd640; 
    localparam signed [COORD_W-1:0] SCREEN_HEIGHT = 12'd480;
    localparam signed [COORD_W-1:0] FLOOR_Y_POS   = SCREEN_HEIGHT; 
    
    localparam signed [COORD_W-1:0] LEFT_WALL_X   = 12'sd0;        
    localparam signed [COORD_W-1:0] RIGHT_WALL_X  = SCREEN_WIDTH;

    // 網子
    localparam signed [COORD_W-1:0] NET_W = 12'd12; 
    localparam signed [COORD_W-1:0] NET_H = 12'd180; 
    localparam signed [COORD_W-1:0] NET_X_POS = 12'd320; 
    localparam signed [COORD_W-1:0] NET_TOP_Y = FLOOR_Y_POS - NET_H; 
    localparam signed [COORD_W-1:0] NET_LEFT_X = NET_X_POS - NET_W; 
    localparam signed [COORD_W-1:0] NET_RIGHT_X = NET_X_POS + NET_W;

    // --- 2. 初始位置修正：設定得非常高 ---
    localparam signed [COORD_W-1:0] BALL_INIT_X = 12'd520; 
    // 修改這裡：從 240 改成 60，避免開局碰到玩家頭頂
    localparam signed [COORD_W-1:0] BALL_INIT_Y = 12'd60; 
    
    localparam signed [COORD_W-1:0] P1_INIT_X   = 12'd100; 
    localparam signed [COORD_W-1:0] P1_INIT_Y   = FLOOR_Y_POS - PLAYER_H;
    localparam signed [COORD_W-1:0] P2_INIT_X   = 12'd520;
    localparam signed [COORD_W-1:0] P2_INIT_Y   = FLOOR_Y_POS - PLAYER_H;
    
    localparam COOLDOWN_MAX = 4'd12; 

    // 狀態機
    localparam S_IDLE        = 3'd0;
    localparam S_PLAYER      = 3'd1; 
    localparam S_CALC_MATH   = 3'd2; 
    localparam S_BALL_RESOLVE= 3'd3; 
    localparam S_DONE        = 3'd4; 

    reg [2:0] state, next_state;

    // 內部暫存器
    reg signed [VEL_W-1:0] ball_vel_x, ball_vel_y;
    reg [3:0] hit_cooldown;
    
    reg signed [VEL_W-1:0] p1_vel_y, p2_vel_y;
    reg p1_in_air, p2_in_air;

    // 運算暫存
    reg signed [COORD_W-1:0] ball_cx, ball_cy;
    reg signed [COORD_W-1:0] p1_cx, p1_cy, p2_cx, p2_cy;
    
    reg signed [COORD_W:0] diff_p1_x, diff_p1_y, diff_p2_x, diff_p2_y;
    reg signed [COORD_W:0] diff_net_Lx, diff_net_Rx, diff_net_y;
    reg signed [24:0] dist_sq_L, dist_sq_R; 

    // 球的預測位置
    reg signed [VEL_W-1:0] ball_vx_pred, ball_vy_pred; 
    reg signed [COORD_W-1:0] ball_px_pred, ball_py_pred; 
    reg signed [COORD_W-1:0] ball_bottom_pred, ball_right_pred;

    // FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else state <= next_state;
    end

    always @(*) begin
        case (state)
            S_IDLE:         next_state = (en) ? S_PLAYER : S_IDLE;
            S_PLAYER:       next_state = S_CALC_MATH;
            S_CALC_MATH:    next_state = S_BALL_RESOLVE;
            S_BALL_RESOLVE: next_state = S_DONE;
            S_DONE:         next_state = S_IDLE;
            default:        next_state = S_IDLE;
        endcase
    end

    // 邏輯運算
    reg signed [COORD_W:0] temp_tx, temp_ty;
    
    // 輔助變數
    wire [COORD_W:0] abs_p1_x = (diff_p1_x < 0) ? -diff_p1_x : diff_p1_x;
    wire [COORD_W:0] abs_p1_y = (diff_p1_y < 0) ? -diff_p1_y : diff_p1_y;
    wire [COORD_W:0] abs_p2_x = (diff_p2_x < 0) ? -diff_p2_x : diff_p2_x;
    wire [COORD_W:0] abs_p2_y = (diff_p2_y < 0) ? -diff_p2_y : diff_p2_y;
    wire [COORD_W:0] abs_net_Lx = (diff_net_Lx < 0) ? -diff_net_Lx : diff_net_Lx;
    wire [COORD_W:0] abs_net_Rx = (diff_net_Rx < 0) ? -diff_net_Rx : diff_net_Rx;
    wire [COORD_W:0] abs_net_y  = (diff_net_y < 0) ? -diff_net_y : diff_net_y;

    wire hit_cnr_L = (dist_sq_L <= BALL_RADIUS_SQ);
    wire hit_cnr_R = (dist_sq_R <= BALL_RADIUS_SQ);
    wire x_ov_net  = (ball_right_pred > NET_LEFT_X) && (ball_px_pred < NET_RIGHT_X);
    wire y_ov_net  = (ball_bottom_pred > NET_TOP_Y);
    
    wire hit_top   = x_ov_net && y_ov_net && ((ball_pos_y + BALL_SIZE) <= NET_TOP_Y) && !hit_cnr_L && !hit_cnr_R;
    wire hit_side  = x_ov_net && y_ov_net && !hit_top && !hit_cnr_L && !hit_cnr_R;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p1_pos_x <= P1_INIT_X; p1_pos_y <= P1_INIT_Y; p1_vel_y <= 0; p1_in_air <= 0;
            p2_pos_x <= P2_INIT_X; p2_pos_y <= P2_INIT_Y; p2_vel_y <= 0; p2_in_air <= 0;
            ball_pos_x <= BALL_INIT_X; ball_pos_y <= BALL_INIT_Y;
            ball_vel_x <= 0; ball_vel_y <= 0;
            game_over <= 0; winner <= 0; valid <= 0; hit_cooldown <= 0;
        end 
        else begin
            valid <= 0; 

            case (state)
                S_PLAYER: begin
                    // --- P1 Logic ---
                    if (p1_op_move_left)  temp_tx = p1_pos_x - PLAYER_SPEED;
                    else if (p1_op_move_right) temp_tx = p1_pos_x + PLAYER_SPEED;
                    else temp_tx = p1_pos_x;
                    
                    if (temp_tx < LEFT_WALL_X) temp_tx = LEFT_WALL_X;
                    else if (temp_tx + PLAYER_W > NET_LEFT_X) temp_tx = NET_LEFT_X - PLAYER_W;
                    p1_pos_x <= temp_tx;

                    if (p1_op_jump && !p1_in_air) begin p1_vel_y <= -JUMP_FORCE; p1_in_air <= 1; end
                    else if (p1_in_air && p1_vel_y < 14'd256) p1_vel_y <= p1_vel_y + GRAVITY; 
                    temp_ty = p1_pos_y + (p1_vel_y >>> 2);
                    if (temp_ty + PLAYER_H >= FLOOR_Y_POS) begin p1_pos_y <= FLOOR_Y_POS - PLAYER_H; p1_vel_y <= 0; p1_in_air <= 0; end
                    else begin p1_pos_y <= temp_ty; if (p1_pos_y + PLAYER_H < FLOOR_Y_POS - 4) p1_in_air <= 1; end

                    // --- P2 Logic ---
                    if (p2_op_move_left)  temp_tx = p2_pos_x - PLAYER_SPEED;
                    else if (p2_op_move_right) temp_tx = p2_pos_x + PLAYER_SPEED;
                    else temp_tx = p2_pos_x;
                    
                    if (temp_tx < NET_RIGHT_X) temp_tx = NET_RIGHT_X; 
                    else if (temp_tx + PLAYER_W > RIGHT_WALL_X) temp_tx = RIGHT_WALL_X - PLAYER_W;
                    p2_pos_x <= temp_tx;

                    if (p2_op_jump && !p2_in_air) begin p2_vel_y <= -JUMP_FORCE; p2_in_air <= 1; end
                    else if (p2_in_air && p2_vel_y < 14'd256) p2_vel_y <= p2_vel_y + GRAVITY;
                    temp_ty = p2_pos_y + (p2_vel_y >>> 2);
                    if (temp_ty + PLAYER_H >= FLOOR_Y_POS) begin p2_pos_y <= FLOOR_Y_POS - PLAYER_H; p2_vel_y <= 0; p2_in_air <= 0; end
                    else begin p2_pos_y <= temp_ty; if (p2_pos_y + PLAYER_H < FLOOR_Y_POS - 4) p2_in_air <= 1; end
                    
                    if (temp_tx < NET_RIGHT_X) p2_pos_x <= NET_RIGHT_X;

                    // --- Ball Prediction ---
                    ball_vx_pred <= ball_vel_x;
                    ball_vy_pred <= ball_vel_y + GRAVITY;
                    
                    ball_px_pred <= ball_pos_x + (ball_vel_x >>> FRAC_W);
                    ball_py_pred <= ball_pos_y + ((ball_vel_y + GRAVITY) >>> FRAC_W);
                    
                    if (hit_cooldown > 0) hit_cooldown <= hit_cooldown - 1;
                end

                S_CALC_MATH: begin
                    ball_bottom_pred <= ball_py_pred + BALL_SIZE;
                    ball_right_pred  <= ball_px_pred + BALL_SIZE;
                    
                    ball_cx <= ball_pos_x + BALL_RADIUS;
                    ball_cy <= ball_pos_y + BALL_RADIUS;
                    
                    p1_cx <= p1_pos_x + PIKA_HALF_W; p1_cy <= p1_pos_y + PIKA_HALF_H;
                    p2_cx <= p2_pos_x + PIKA_HALF_W; p2_cy <= p2_pos_y + PIKA_HALF_H;

                    diff_net_Lx <= (ball_pos_x + BALL_RADIUS) - NET_LEFT_X;
                    diff_net_Rx <= (ball_pos_x + BALL_RADIUS) - NET_RIGHT_X;
                    diff_net_y  <= (ball_pos_y + BALL_RADIUS) - NET_TOP_Y;
                    
                    diff_p1_x <= (ball_pos_x + BALL_RADIUS) - (p1_pos_x + PIKA_HALF_W);
                    diff_p1_y <= (ball_pos_y + BALL_RADIUS) - (p1_pos_y + PIKA_HALF_H);
                    diff_p2_x <= (ball_pos_x + BALL_RADIUS) - (p2_pos_x + PIKA_HALF_W);
                    diff_p2_y <= (ball_pos_y + BALL_RADIUS) - (p2_pos_y + PIKA_HALF_H);

                    dist_sq_L <= ((ball_pos_x + BALL_RADIUS) - NET_LEFT_X) * ((ball_pos_x + BALL_RADIUS) - NET_LEFT_X) + 
                                 ((ball_pos_y + BALL_RADIUS) - NET_TOP_Y)  * ((ball_pos_y + BALL_RADIUS) - NET_TOP_Y);
                    dist_sq_R <= ((ball_pos_x + BALL_RADIUS) - NET_RIGHT_X) * ((ball_pos_x + BALL_RADIUS) - NET_RIGHT_X) + 
                                 ((ball_pos_y + BALL_RADIUS) - NET_TOP_Y)  * ((ball_pos_y + BALL_RADIUS) - NET_TOP_Y);
                end

                S_BALL_RESOLVE: begin
                    if (game_over) begin
                        ball_pos_x <= BALL_INIT_X; ball_pos_y <= BALL_INIT_Y;
                        ball_vel_x <= 0; ball_vel_y <= 0;
                        hit_cooldown <= 0;
                        game_over <= 0; 
                    end
                    else if ((p1_cover || p2_cover) && (hit_cooldown == 0)) begin
                        hit_cooldown <= COOLDOWN_MAX;
                        if (p1_cover) begin
                            if (p1_is_smash) begin ball_vel_x <= P1_SMASH_VX; ball_vel_y <= P1_SMASH_VY; end 
                            else begin
                                if (abs_p1_x > abs_p1_y) begin 
                                    if (diff_p1_x > 0) begin if (ball_vx_pred < 0) ball_vel_x <= -ball_vx_pred; end 
                                    else begin if (ball_vx_pred > 0) ball_vel_x <= -ball_vx_pred; end 
                                    ball_vel_y <= ball_vy_pred; 
                                end 
                                else begin 
                                    if (ball_vy_pred > -14'd1024) ball_vel_y <= -14'd1536; 
                                    else ball_vel_y <= -ball_vy_pred; 
                                    ball_vel_x <= ball_vx_pred; 
                                end 
                                if (p1_op_move_right) ball_vel_x <= ball_vel_x + PLAYER_PUSH_VEL; 
                                if (p1_op_move_left) ball_vel_x <= ball_vel_x - PLAYER_PUSH_VEL;
                                ball_vel_x <= ball_vel_x + (diff_p1_x >>> 1);
                            end
                        end else begin
                             if (p2_is_smash) begin ball_vel_x <= P2_SMASH_VX; ball_vel_y <= P2_SMASH_VY; end 
                            else begin
                                if (abs_p2_x > abs_p2_y) begin 
                                    if (diff_p2_x > 0) begin if (ball_vx_pred < 0) ball_vel_x <= -ball_vx_pred; end 
                                    else begin if (ball_vx_pred > 0) ball_vel_x <= -ball_vx_pred; end 
                                    ball_vel_y <= ball_vy_pred; 
                                end 
                                else begin 
                                    if (ball_vy_pred > -14'd1024) ball_vel_y <= -14'd1536; 
                                    else ball_vel_y <= -ball_vy_pred; 
                                    ball_vel_x <= ball_vx_pred; 
                                end
                                if (p2_op_move_right) ball_vel_x <= ball_vel_x + PLAYER_PUSH_VEL; 
                                if (p2_op_move_left) ball_vel_x <= ball_vel_x - PLAYER_PUSH_VEL;
                                ball_vel_x <= ball_vel_x + (diff_p2_x >>> 1);
                            end
                        end
                    end 
                    else begin
                        if (hit_cnr_L) begin
                             ball_vel_x <= ball_vel_x + (diff_net_Lx <<< 2); ball_vel_y <= ball_vel_y + (diff_net_y <<< 2);
                        end 
                        else if (hit_cnr_R) begin
                             ball_vel_x <= ball_vel_x + (diff_net_Rx <<< 2); ball_vel_y <= ball_vel_y + (diff_net_y <<< 2);
                        end
                        else if (hit_top) begin
                            if (ball_vy_pred > 0) ball_vel_y <= -ball_vy_pred + (ball_vy_pred >>> 2);
                            ball_pos_y <= NET_TOP_Y - BALL_SIZE - 2; ball_pos_x <= ball_px_pred; ball_vel_x <= ball_vx_pred;
                        end
                        else if (hit_side) begin
                            if (ball_px_pred + BALL_RADIUS < NET_X_POS) begin 
                                ball_vel_x <= -((ball_vx_pred > 0) ? ball_vx_pred : -ball_vx_pred); 
                                ball_pos_x <= NET_LEFT_X - BALL_SIZE - 2; 
                            end
                            else begin 
                                ball_vel_x <= ((ball_vx_pred < 0) ? -ball_vx_pred : ball_vx_pred);
                                ball_pos_x <= NET_RIGHT_X + 2; 
                            end
                            ball_pos_y <= ball_py_pred; ball_vel_y <= ball_vy_pred;
                        end
                        else if (ball_bottom_pred >= FLOOR_Y_POS) begin 
                            ball_pos_y <= FLOOR_Y_POS - BALL_SIZE; ball_pos_x <= ball_px_pred; 
                            game_over <= 1; 
                            if (ball_px_pred < NET_X_POS) winner <= 2; else winner <= 1;
                        end
                        // 修正後的牆壁判定 (使用 signed)
                        else if ($signed(ball_px_pred) <= $signed(LEFT_WALL_X)) begin
                            ball_vel_x <= -ball_vx_pred + (ball_vx_pred >>> 3); 
                            ball_pos_x <= LEFT_WALL_X; 
                            ball_pos_y <= ball_py_pred; ball_vel_y <= ball_vy_pred;
                        end
                        else if ($signed(ball_right_pred) >= $signed(RIGHT_WALL_X)) begin
                            ball_vel_x <= -ball_vx_pred + (ball_vx_pred >>> 3);
                            ball_pos_x <= RIGHT_WALL_X - BALL_SIZE; 
                            ball_pos_y <= ball_py_pred; ball_vel_y <= ball_vy_pred;
                        end
                        else begin
                            ball_pos_x <= ball_px_pred; ball_pos_y <= ball_py_pred;
                            ball_vel_x <= ball_vx_pred; ball_vel_y <= ball_vy_pred;
                        end
                    end
                end
                
                S_DONE: begin
                    valid <= 1;
                end
            endcase
        end
    end

endmodule
