module physic (
    input wire clk,
    input wire rst_n,
    input wire en, // 啟動訊號 (Pulse)

    // --- 操作輸入 ---
    input wire p1_op_move_left, p1_op_move_right, p1_op_jump, p1_is_smash,
    input wire p2_op_move_left, p2_op_move_right, p2_op_jump, p2_is_smash,

    // --- 碰撞偵測 ---
    input wire p1_cover, 
    input wire p2_cover, 
    
    // --- 輸出 ---
    output reg [9:0] p1_pos_x, p1_pos_y,
    output reg [9:0] p2_pos_x, p2_pos_y,
    output reg [9:0] ball_pos_x, ball_pos_y,
    
    output reg game_over,
    output reg [1:0] winner,
    output reg valid // 計算完成訊號
);
    
    
    //  參數設定
    
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
    localparam PLAYER_SPEED = 10'd1;
    localparam JUMP_FORCE   = 10'd2;  

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

    // 初始位置
    localparam BALL_INIT_X = 10'd260; localparam BALL_INIT_Y = 10'd120; 
    localparam P1_INIT_X   = 10'd50;  localparam P1_INIT_Y   = FLOOR_Y_POS - PLAYER_H;
    localparam P2_INIT_X   = 10'd260; localparam P2_INIT_Y   = FLOOR_Y_POS - PLAYER_H; 
    localparam COOLDOWN_MAX = 4'd12; 

    
    //  狀態機定義
    
    localparam S_IDLE          = 3'd0;
    localparam S_PLAYER        = 3'd1; // 算角色移動 & 球的預測位置
    localparam S_CALC_MATH     = 3'd2; // 算碰撞距離平方 (耗時運算)
    localparam S_BALL_RESOLVE  = 3'd3; // 根據結果更新球的速度與位置
    localparam S_DONE          = 3'd4; // 輸出 Valid

    reg [2:0] state, next_state;

    
    //  內部暫存器 (Registers)
    
    reg signed [VEL_W-1:0] ball_vel_x, ball_vel_y;
    reg [3:0] hit_cooldown;
    reg signed [10:0] p1_vel_y, p2_vel_y;
    reg p1_in_air, p2_in_air;

    // --- 中間運算暫存器 (Pipeline Registers) ---
    // 這些是用來存 S_CALC_MATH 算出來的結果，給 S_BALL_RESOLVE 用
    reg signed [COORD_W-1:0] ball_cx, ball_cy;
    reg signed [COORD_W-1:0] p1_cx, p1_cy, p2_cx, p2_cy;
    
    reg signed [COORD_W:0] diff_p1_x, diff_p1_y, diff_p2_x, diff_p2_y;
    reg signed [COORD_W:0] diff_net_Lx, diff_net_Rx, diff_net_y;
    reg signed [20:0] dist_sq_L, dist_sq_R; // 平方結果存這裡

    // 球的預測位置暫存
    reg signed [9:0] ball_vx_pred, ball_vy_pred;
    reg signed [9:0] ball_px_pred, ball_py_pred;
    reg signed [9:0] ball_bottom_pred, ball_right_pred;

    
    //  FSM 狀態轉移
    
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

    //  邏輯運算 (分階段執行)    
    // 輔助變數
    reg signed [11:0] temp_tx, temp_ty;
    
    // 用於 RESOLVE 階段的絕對值計算 (Combinational)
    wire [COORD_W:0] abs_p1_x = (diff_p1_x < 0) ? -diff_p1_x : diff_p1_x;
    wire [COORD_W:0] abs_p1_y = (diff_p1_y < 0) ? -diff_p1_y : diff_p1_y;
    wire [COORD_W:0] abs_p2_x = (diff_p2_x < 0) ? -diff_p2_x : diff_p2_x;
    wire [COORD_W:0] abs_p2_y = (diff_p2_y < 0) ? -diff_p2_y : diff_p2_y;
    wire [COORD_W:0] abs_net_Lx = (diff_net_Lx < 0) ? -diff_net_Lx : diff_net_Lx;
    wire [COORD_W:0] abs_net_Rx = (diff_net_Rx < 0) ? -diff_net_Rx : diff_net_Rx;
    wire [COORD_W:0] abs_net_y  = (diff_net_y < 0) ? -diff_net_y : diff_net_y;

    // 碰撞 Flags (基於暫存器計算)
    wire hit_cnr_L = (dist_sq_L <= BALL_RADIUS_SQ);
    wire hit_cnr_R = (dist_sq_R <= BALL_RADIUS_SQ);
    wire x_ov_net  = (ball_right_pred > NET_LEFT_X) && (ball_px_pred < NET_RIGHT_X);
    wire y_ov_net  = (ball_bottom_pred > NET_TOP_Y);
    wire hit_top   = x_ov_net && y_ov_net && ((ball_pos_y + BALL_SIZE) <= NET_TOP_Y) && !hit_cnr_L && !hit_cnr_R;
    wire hit_side  = x_ov_net && y_ov_net && !hit_top && !hit_cnr_L && !hit_cnr_R;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset logic
            p1_pos_x <= P1_INIT_X; p1_pos_y <= P1_INIT_Y; p1_vel_y <= 0; p1_in_air <= 0;
            p2_pos_x <= P2_INIT_X; p2_pos_y <= P2_INIT_Y; p2_vel_y <= 0; p2_in_air <= 0;
            ball_pos_x <= BALL_INIT_X; ball_pos_y <= BALL_INIT_Y;
            ball_vel_x <= 0; ball_vel_y <= 0;
            game_over <= 0; winner <= 0; valid <= 0; hit_cooldown <= 0;
        end 
        else begin
            valid <= 0; // Default low

            case (state)
                
                // Stage 1: 更新玩家位置 & 準備球的預測
                
                S_PLAYER: begin
                    // P1 Update
                    if (p1_op_move_left)  temp_tx = p1_pos_x - PLAYER_SPEED;
                    else if (p1_op_move_right) temp_tx = p1_pos_x + PLAYER_SPEED;
                    else temp_tx = p1_pos_x;
                    if (temp_tx < LEFT_WALL_X) temp_tx = LEFT_WALL_X;
                    else if (temp_tx + PLAYER_W > NET_LEFT_X) temp_tx = NET_LEFT_X - PLAYER_W;
                    p1_pos_x <= temp_tx;

                    if (p1_op_jump && !p1_in_air) begin p1_vel_y <= -JUMP_FORCE; p1_in_air <= 1; end
                    else if (p1_in_air && p1_vel_y < 15) p1_vel_y <= p1_vel_y + GRAVITY;
                    temp_ty = p1_pos_y + p1_vel_y;
                    if (temp_ty + PLAYER_H >= FLOOR_Y_POS) begin p1_pos_y <= FLOOR_Y_POS - PLAYER_H; p1_vel_y <= 0; p1_in_air <= 0; end
                    else begin p1_pos_y <= temp_ty; if (p1_pos_y + PLAYER_H < FLOOR_Y_POS - 2) p1_in_air <= 1; end

                    // P2 Update
                    if (p2_op_move_left)  temp_tx = p2_pos_x - PLAYER_SPEED;
                    else if (p2_op_move_right) temp_tx = p2_pos_x + PLAYER_SPEED;
                    else temp_tx = p2_pos_x;
                    if (temp_tx < NET_RIGHT_X) temp_tx = NET_RIGHT_X;
                    else if (temp_tx + PLAYER_W > RIGHT_WALL_X) temp_tx = RIGHT_WALL_X - PLAYER_W;
                    p2_pos_x <= temp_tx;

                    if (p2_op_jump && !p2_in_air) begin p2_vel_y <= -JUMP_FORCE; p2_in_air <= 1; end
                    else if (p2_in_air && p2_vel_y < 15) p2_vel_y <= p2_vel_y + GRAVITY;
                    temp_ty = p2_pos_y + p2_vel_y;
                    if (temp_ty + PLAYER_H >= FLOOR_Y_POS) begin p2_pos_y <= FLOOR_Y_POS - PLAYER_H; p2_vel_y <= 0; p2_in_air <= 0; end
                    else begin p2_pos_y <= temp_ty; if (p2_pos_y + PLAYER_H < FLOOR_Y_POS - 2) p2_in_air <= 1; end

                    // Ball Prediction (Calculate gravity effect here)
                    ball_vx_pred <= ball_vel_x;
                    ball_vy_pred <= ball_vel_y + GRAVITY;
                    ball_px_pred <= ball_pos_x + (ball_vel_x >>> FRAC_W);
                    ball_py_pred <= ball_pos_y + ((ball_vel_y + GRAVITY) >>> FRAC_W);
                    
                    // Update Cooldown
                    if (hit_cooldown > 0) hit_cooldown <= hit_cooldown - 1;
                end

                
                // Stage 2: 繁重的數學運算 (距離、平方)
                
                S_CALC_MATH: begin
                    // 準備下一步碰撞判定需要的數值
                    ball_bottom_pred <= ball_py_pred + BALL_SIZE;
                    ball_right_pred  <= ball_px_pred + BALL_SIZE;

                    // 計算中心點 (注意：用的是當前位置，不是預測位置，避免穿模判定問題)
                    // 或者可以用預測位置來算碰撞，這裡沿用之前的邏輯，使用 pos_curr 算 corner distance
                    ball_cx <= ball_pos_x + BALL_RADIUS;
                    ball_cy <= ball_pos_y + BALL_RADIUS;
                    p1_cx   <= p1_pos_x + PIKA_HALF_W; // 注意：這裡已經是 Stage 1 更新後的 p1_pos_x
                    p1_cy   <= p1_pos_y + PIKA_HALF_H;
                    p2_cx   <= p2_pos_x + PIKA_HALF_W;
                    p2_cy   <= p2_pos_y + PIKA_HALF_H;

                    // 計算向量差
                    diff_net_Lx <= (ball_pos_x + BALL_RADIUS) - NET_LEFT_X;
                    diff_net_Rx <= (ball_pos_x + BALL_RADIUS) - NET_RIGHT_X;
                    diff_net_y  <= (ball_pos_y + BALL_RADIUS) - NET_TOP_Y;
                    
                    diff_p1_x <= (ball_pos_x + BALL_RADIUS) - (p1_pos_x + PIKA_HALF_W);
                    diff_p1_y <= (ball_pos_y + BALL_RADIUS) - (p1_pos_y + PIKA_HALF_H);
                    diff_p2_x <= (ball_pos_x + BALL_RADIUS) - (p2_pos_x + PIKA_HALF_W);
                    diff_p2_y <= (ball_pos_y + BALL_RADIUS) - (p2_pos_y + PIKA_HALF_H);

                    // 計算平方 (Critical Path Breaker)
                    // 在這裡計算，下一個 Cycle 就可以直接比較大小
                    dist_sq_L <= ((ball_pos_x + BALL_RADIUS) - NET_LEFT_X) * ((ball_pos_x + BALL_RADIUS) - NET_LEFT_X) + 
                                 ((ball_pos_y + BALL_RADIUS) - NET_TOP_Y)  * ((ball_pos_y + BALL_RADIUS) - NET_TOP_Y);
                    
                    dist_sq_R <= ((ball_pos_x + BALL_RADIUS) - NET_RIGHT_X) * ((ball_pos_x + BALL_RADIUS) - NET_RIGHT_X) + 
                                 ((ball_pos_y + BALL_RADIUS) - NET_TOP_Y)   * ((ball_pos_y + BALL_RADIUS) - NET_TOP_Y);
                end

                
                // Stage 3: 解決球的物理碰撞 (Resolution)
                
                S_BALL_RESOLVE: begin
                    // 如果這回合結束了，重置
                    if (game_over) begin
                        ball_pos_x <= BALL_INIT_X; ball_pos_y <= BALL_INIT_Y;
                        ball_vel_x <= 0; ball_vel_y <= 0;
                        hit_cooldown <= 0;
                        game_over <= 0; // Clear flag
                    end
                    // 玩家擊球
                    else if ((p1_cover || p2_cover) && (hit_cooldown == 0)) begin
                        hit_cooldown <= COOLDOWN_MAX;
                        if (p1_cover) begin
                            if (p1_is_smash) begin ball_vel_x <= P1_SMASH_VX; ball_vel_y <= P1_SMASH_VY; end 
                            else begin
                                if (abs_p1_x > abs_p1_y) begin if (diff_p1_x > 0) begin if (ball_vx_pred < 0) ball_vel_x <= -ball_vx_pred; end else begin if (ball_vx_pred > 0) ball_vel_x <= -ball_vx_pred; end ball_vel_y <= ball_vy_pred; end 
                                else begin if (ball_vy_pred > -128) ball_vel_y <= -192; else ball_vel_y <= -ball_vy_pred; ball_vel_x <= ball_vx_pred; end
                                if (p1_op_move_right) ball_vel_x <= ball_vel_x + PLAYER_PUSH_VEL; if (p1_op_move_left) ball_vel_x <= ball_vel_x - PLAYER_PUSH_VEL;
                                ball_vel_x <= ball_vel_x + (diff_p1_x >>> 1);
                            end
                        end else begin
                            if (p2_is_smash) begin ball_vel_x <= P2_SMASH_VX; ball_vel_y <= P2_SMASH_VY; end 
                            else begin
                                if (abs_p2_x > abs_p2_y) begin if (diff_p2_x > 0) begin if (ball_vx_pred < 0) ball_vel_x <= -ball_vx_pred; end else begin if (ball_vx_pred > 0) ball_vel_x <= -ball_vx_pred; end ball_vel_y <= ball_vy_pred; end 
                                else begin if (ball_vy_pred > -128) ball_vel_y <= -192; else ball_vel_y <= -ball_vy_pred; ball_vel_x <= ball_vx_pred; end
                                if (p2_op_move_right) ball_vel_x <= ball_vel_x + PLAYER_PUSH_VEL; if (p2_op_move_left) ball_vel_x <= ball_vel_x - PLAYER_PUSH_VEL;
                                ball_vel_x <= ball_vel_x + (diff_p2_x >>> 1);
                            end
                        end
                    end 
                    // 環境碰撞
                    else begin
                        if (hit_cnr_L) begin
                            if (abs_net_Lx > abs_net_y) begin if (ball_vx_pred > 0) ball_vel_x <= -ball_vx_pred; end else begin if (ball_vy_pred > 0) ball_vel_y <= -ball_vy_pred; end
                            ball_vel_x <= ball_vel_x + (diff_net_Lx <<< 2); ball_vel_y <= ball_vel_y + (diff_net_y <<< 2);
                        end 
                        else if (hit_cnr_R) begin
                            if (abs_net_Rx > abs_net_y) begin if (ball_vx_pred < 0) ball_vel_x <= -ball_vx_pred; end else begin if (ball_vy_pred > 0) ball_vel_y <= -ball_vy_pred; end
                            ball_vel_x <= ball_vel_x + (diff_net_Rx <<< 2); ball_vel_y <= ball_vel_y + (diff_net_y <<< 2);
                        end
                        else if (hit_top) begin
                            if (ball_vy_pred > 0) begin ball_vel_y <= -ball_vy_pred - (ball_vy_pred >>> 2); end
                            ball_pos_y <= NET_TOP_Y - BALL_SIZE - 2; ball_pos_x <= ball_px_pred; ball_vel_x <= ball_vx_pred;
                        end
                        else if (hit_side) begin
                            if (ball_px_pred + (BALL_SIZE/2) < NET_X_POS) begin if (ball_vx_pred > 0) ball_vel_x <= -ball_vx_pred; ball_pos_x <= NET_LEFT_X - BALL_SIZE - 2; end
                            else begin if (ball_vx_pred < 0) ball_vel_x <= -ball_vx_pred; ball_pos_x <= NET_RIGHT_X + 2; end
                            ball_pos_y <= ball_py_pred; ball_vel_y <= ball_vy_pred;
                        end
                        else if (ball_bottom_pred >= FLOOR_Y_POS) begin // Hit Floor
                            if (ball_vy_pred > 0) begin ball_vel_y <= -ball_vy_pred - (ball_vy_pred >>> 3); end
                            ball_pos_y <= FLOOR_Y_POS - BALL_SIZE; ball_pos_x <= ball_px_pred; ball_vel_x <= ball_vx_pred;
                            game_over <= 1; // 觸發得分
                            if (ball_px_pred < NET_X_POS) winner <= 2; else winner <= 1;
                        end
                        else if (ball_px_pred <= LEFT_WALL_X) begin
                            if (ball_vx_pred < 0) ball_vel_x <= -ball_vx_pred; ball_pos_x <= LEFT_WALL_X + 2; ball_pos_y <= ball_py_pred; ball_vel_y <= ball_vy_pred;
                        end
                        else if (ball_right_pred >= RIGHT_WALL_X) begin
                            if (ball_vx_pred > 0) ball_vel_x <= -ball_vx_pred; ball_pos_x <= RIGHT_WALL_X - BALL_SIZE - 2; ball_pos_y <= ball_py_pred; ball_vel_y <= ball_vy_pred;
                        end
                        else begin
                            // No collision, just update
                            ball_pos_x <= ball_px_pred;
                            ball_pos_y <= ball_py_pred;
                            ball_vel_x <= ball_vx_pred;
                            ball_vel_y <= ball_vy_pred;
                        end
                    end
                end
                // Stage 4: 完成
                
                S_DONE: begin
                    valid <= 1;
                end
            endcase
        end
    end

endmodule
