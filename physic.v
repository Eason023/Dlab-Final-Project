module physic (
    input wire clk,
    input wire rst_n,
    input wire en, // 啟動訊號 (Pulse, 建議 60Hz)

    // --- 操作輸入 ---
    input wire p1_op_move_left, p1_op_move_right, p1_op_jump, p1_is_smash,
    input wire p2_op_move_left, p2_op_move_right, p2_op_jump, p2_is_smash,

    // --- 碰撞偵測 ---
    input wire p1_cover, 
    input wire p2_cover, 
    
    // --- 輸出 (保持 [9:0] 足夠容納 640) ---
    output reg [9:0] p1_pos_x, p1_pos_y,
    output reg [9:0] p2_pos_x, p2_pos_y,
    output reg [9:0] ball_pos_x, ball_pos_y,
    
    output reg game_over,
    output reg [1:0] winner,
    output reg valid // 計算完成訊號
);
    
    // --- 參數設定 (已擴充位元寬以防溢位) ---
    
    localparam COORD_W = 11; // 加大到 11 bits (最大 2047)
    localparam VEL_W   = 12; // 加大到 12 bits (支援速度 > 512)
    localparam FRAC_W  = 6; 

    // --- 尺寸 (全部 * 2) ---
    localparam BALL_SIZE = 10'd80;         // 40 * 2
    localparam BALL_RADIUS = 10'd40;       // 20 * 2
    localparam BALL_RADIUS_SQ = 20'd1600;  // 40^2
    localparam PLAYER_W = 10'd128;         // 64 * 2
    localparam PLAYER_H = 10'd128;         // 64 * 2
    localparam PIKA_HALF_W = 10'd64;       // 32 * 2
    localparam PIKA_HALF_H = 10'd64;       // 32 * 2

    // --- 物理常數 (全部 * 2 以維持手感) ---
    localparam GRAVITY   = 10'd2;      // 1 * 2
    localparam BOUNCE_DAMPING = 10'd110; // 55 * 2
    
    // 移動速度：原本 2 (慢速)，現在改為 4 (在 640 解析度下等同原本的慢速)
    localparam PLAYER_SPEED = 10'd4;   
    localparam JUMP_FORCE   = 10'd24;  // 12 * 2

    // --- 擊球與推力 (* 2) ---
    localparam P1_SMASH_VX = 10'd320; localparam P1_SMASH_VY = -10'd512; 
    localparam P2_SMASH_VX = -10'd320; localparam P2_SMASH_VY = -10'd512;
    localparam PLAYER_PUSH_VEL = 10'd96; 
    localparam NET_CORNER_PUSH = 10'd8; 

    // --- 場地邊界 (640 x 480) ---
    localparam SCREEN_WIDTH  = 10'd640; localparam SCREEN_HEIGHT = 10'd480;
    localparam FLOOR_Y_POS   = SCREEN_HEIGHT; 
    
    // 網子尺寸與位置 (* 2)
    localparam NET_W = 10'd12; localparam NET_H = 10'd180; localparam NET_X_POS = 10'd320; 
    localparam NET_TOP_Y = FLOOR_Y_POS - NET_H; 
    localparam NET_LEFT_X = NET_X_POS - NET_W; localparam NET_RIGHT_X = NET_X_POS + NET_W;
    localparam LEFT_WALL_X = 10'd0; localparam RIGHT_WALL_X = SCREEN_WIDTH; 

    // 初始位置 (* 2)
    localparam BALL_INIT_X = 10'd520; localparam BALL_INIT_Y = 10'd240; 
    localparam P1_INIT_X   = 10'd100;  localparam P1_INIT_Y   = FLOOR_Y_POS - PLAYER_H;
    localparam P2_INIT_X   = 10'd520;  localparam P2_INIT_Y   = FLOOR_Y_POS - PLAYER_H; 
    localparam COOLDOWN_MAX = 4'd12; 

    
    //  狀態機定義
    
    localparam S_IDLE          = 3'd0;
    localparam S_PLAYER        = 3'd1; 
    localparam S_CALC_MATH     = 3'd2; 
    localparam S_BALL_RESOLVE  = 3'd3; 
    localparam S_DONE          = 3'd4; 

    reg [2:0] state, next_state;

    
    //  內部暫存器 (Registers)
    //  注意：這裡改用 VEL_W (12 bits) 防止溢位
    reg signed [VEL_W-1:0] ball_vel_x, ball_vel_y;
    reg [3:0] hit_cooldown;
    reg signed [10:0] p1_vel_y, p2_vel_y;
    reg p1_in_air, p2_in_air;

    // --- 中間運算暫存器 (Pipeline Registers) ---
    //  注意：這裡改用 COORD_W (11 bits) 防止運算溢位
    reg signed [COORD_W-1:0] ball_cx, ball_cy;
    reg signed [COORD_W-1:0] p1_cx, p1_cy, p2_cx, p2_cy;
    
    reg signed [COORD_W:0] diff_p1_x, diff_p1_y, diff_p2_x, diff_p2_y;
    reg signed [COORD_W:0] diff_net_Lx, diff_net_Rx, diff_net_y;
    reg signed [24:0] dist_sq_L, dist_sq_R; // 平方結果位元數加大

    // 球的預測位置暫存
    reg signed [10:0] ball_vx_pred, ball_vy_pred; // 加大
    reg signed [10:0] ball_px_pred, ball_py_pred; // 加大
    reg signed [10:0] ball_bottom_pred, ball_right_pred;

    
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

    //  邏輯運算   
    reg signed [12:0] temp_tx, temp_ty; // 加大暫存變數
    
    // 輔助變數 (Combinational)
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
                
                // Stage 1: 更新玩家位置 & 準備球的預測
                
                S_PLAYER: begin
                    // --- P1 Update (左側) ---
                    if (p1_op_move_left)  temp_tx = p1_pos_x - PLAYER_SPEED;
                    else if (p1_op_move_right) temp_tx = p1_pos_x + PLAYER_SPEED;
                    else temp_tx = p1_pos_x;
                    
                    if (temp_tx < LEFT_WALL_X) temp_tx = LEFT_WALL_X;
                    else if (temp_tx + PLAYER_W > NET_LEFT_X) temp_tx = NET_LEFT_X - PLAYER_W;
                    p1_pos_x <= temp_tx;

                    if (p1_op_jump && !p1_in_air) begin p1_vel_y <= -JUMP_FORCE; p1_in_air <= 1; end
                    else if (p1_in_air && p1_vel_y < 30) p1_vel_y <= p1_vel_y + GRAVITY; // 終端速度也稍微放大
                    temp_ty = p1_pos_y + p1_vel_y;
                    if (temp_ty + PLAYER_H >= FLOOR_Y_POS) begin p1_pos_y <= FLOOR_Y_POS - PLAYER_H; p1_vel_y <= 0; p1_in_air <= 0; end
                    else begin p1_pos_y <= temp_ty; if (p1_pos_y + PLAYER_H < FLOOR_Y_POS - 4) p1_in_air <= 1; end

                    // --- P2 Update (右側 - 含防卡死) ---
                    if (p2_op_move_left)  temp_tx = p2_pos_x - PLAYER_SPEED;
                    else if (p2_op_move_right) temp_tx = p2_pos_x + PLAYER_SPEED;
                    else temp_tx = p2_pos_x;
                    
                    // 右側玩家的網子邊界檢查
                    if (temp_tx < NET_RIGHT_X) temp_tx = NET_RIGHT_X; 
                    else if (temp_tx + PLAYER_W > RIGHT_WALL_X) temp_tx = RIGHT_WALL_X - PLAYER_W;
                    p2_pos_x <= temp_tx;

                    if (p2_op_jump && !p2_in_air) begin p2_vel_y <= -JUMP_FORCE; p2_in_air <= 1; end
                    else if (p2_in_air && p2_vel_y < 30) p2_vel_y <= p2_vel_y + GRAVITY;
                    
                    temp_ty = p2_pos_y + p2_vel_y;
                    if (temp_ty + PLAYER_H >= FLOOR_Y_POS) begin 
                        p2_pos_y <= FLOOR_Y_POS - PLAYER_H; 
                        p2_vel_y <= 0; 
                        p2_in_air <= 0; 
                    end
                    else begin 
                        p2_pos_y <= temp_ty; 
                        if (p2_pos_y + PLAYER_H < FLOOR_Y_POS - 4) p2_in_air <= 1; 
                    end
                    
                    // 保險：強制推回右邊
                    if (temp_tx < NET_RIGHT_X) p2_pos_x <= NET_RIGHT_X;

                    // --- Ball Prediction ---
                    ball_vx_pred <= ball_vel_x;
                    ball_vy_pred <= ball_vel_y + GRAVITY;
                    ball_px_pred <= ball_pos_x + (ball_vel_x >>> FRAC_W);
                    ball_py_pred <= ball_pos_y + ((ball_vel_y + GRAVITY) >>> FRAC_W);
                    
                    if (hit_cooldown > 0) hit_cooldown <= hit_cooldown - 1;
                end

                
                // Stage 2: 運算 (距離判定)
                
                S_CALC_MATH: begin
                    ball_bottom_pred <= ball_py_pred + BALL_SIZE;
                    ball_right_pred  <= ball_px_pred + BALL_SIZE;
                    ball_cx <= ball_pos_x + BALL_RADIUS;
                    ball_cy <= ball_pos_y + BALL_RADIUS;
                    p1_cx   <= p1_pos_x + PIKA_HALF_W;
                    p1_cy   <= p1_pos_y + PIKA_HALF_H;
                    p2_cx   <= p2_pos_x + PIKA_HALF_W;
                    p2_cy   <= p2_pos_y + PIKA_HALF_H;

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
                                 ((ball_pos_y + BALL_RADIUS) - NET_TOP_Y)   * ((ball_pos_y + BALL_RADIUS) - NET_TOP_Y);
                end

                
                // Stage 3: Resolve (碰撞反應)
                
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
                                if (abs_p1_x > abs_p1_y) begin if (diff_p1_x > 0) begin if (ball_vx_pred < 0) ball_vel_x <= -ball_vx_pred; end else begin if (ball_vx_pred > 0) ball_vel_x <= -ball_vx_pred; end ball_vel_y <= ball_vy_pred; end 
                                else begin if (ball_vy_pred > -256) ball_vel_y <= -384; else ball_vel_y <= -ball_vy_pred; ball_vel_x <= ball_vx_pred; end // 閾值也 *2
                                if (p1_op_move_right) ball_vel_x <= ball_vel_x + PLAYER_PUSH_VEL; if (p1_op_move_left) ball_vel_x <= ball_vel_x - PLAYER_PUSH_VEL;
                                ball_vel_x <= ball_vel_x + (diff_p1_x >>> 1);
                            end
                        end else begin
                            if (p2_is_smash) begin ball_vel_x <= P2_SMASH_VX; ball_vel_y <= P2_SMASH_VY; end 
                            else begin
                                if (abs_p2_x > abs_p2_y) begin if (diff_p2_x > 0) begin if (ball_vx_pred < 0) ball_vel_x <= -ball_vx_pred; end else begin if (ball_vx_pred > 0) ball_vel_x <= -ball_vx_pred; end ball_vel_y <= ball_vy_pred; end 
                                else begin if (ball_vy_pred > -256) ball_vel_y <= -384; else ball_vel_y <= -ball_vy_pred; ball_vel_x <= ball_vx_pred; end
                                if (p2_op_move_right) ball_vel_x <= ball_vel_x + PLAYER_PUSH_VEL; if (p2_op_move_left) ball_vel_x <= ball_vel_x - PLAYER_PUSH_VEL;
                                ball_vel_x <= ball_vel_x + (diff_p2_x >>> 1);
                            end
                        end
                    end 
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
                        else if (ball_bottom_pred >= FLOOR_Y_POS) begin 
                            if (ball_vy_pred > 0) begin ball_vel_y <= -ball_vy_pred - (ball_vy_pred >>> 3); end
                            ball_pos_y <= FLOOR_Y_POS - BALL_SIZE; ball_pos_x <= ball_px_pred; ball_vel_x <= ball_vx_pred;
                            game_over <= 1; 
                            if (ball_px_pred < NET_X_POS) winner <= 2; else winner <= 1;
                        end
                        else if (ball_px_pred <= LEFT_WALL_X) begin
                            if (ball_vx_pred < 0) ball_vel_x <= -ball_vx_pred; ball_pos_x <= LEFT_WALL_X + 2; ball_pos_y <= ball_py_pred; ball_vel_y <= ball_vy_pred;
                        end
                        else if (ball_right_pred >= RIGHT_WALL_X) begin
                            if (ball_vx_pred > 0) ball_vel_x <= -ball_vx_pred; ball_pos_x <= RIGHT_WALL_X - BALL_SIZE - 2; ball_pos_y <= ball_py_pred; ball_vel_y <= ball_vy_pred;
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
