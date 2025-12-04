module physic (
    input wire clk,
    input wire rst_n,

    // P1 & P2 動作輸入 (雖然 Player 自己算座標，但保留這些接口以防萬一，外部接 0 即可)
    input wire p1_op_move_left, input wire p1_op_move_right, input wire p1_op_jump,
    input wire p2_op_move_left, input wire p2_op_move_right, input wire p2_op_jump,
    
    // 殺球訊號 (新增，用於實現進階功能)
    input wire p1_is_smash,
    input wire p2_is_smash,

    // 碰撞偵測 (來自 Render)
    input wire p1_cover, // P1 碰到球
    input wire p2_cover, // P2 碰到球
    
    // 玩家位置 (來自 Player 模組)
    input wire [9:0] p1_pos_x_i, p1_pos_y_i,
    input wire [9:0] p2_pos_x_i, p2_pos_y_i,

    output reg [9:0] ball_pos_x, ball_pos_y,
    output reg [3:0] p1_score, p2_score,
    output reg game_over // 1 = 得分/結束
);
    
    // --- 參數設定 ---
    localparam COORD_W = 10; 
    localparam VEL_W   = 10; 
    localparam FRAC_W  = 6;  // 小數點位數 Q4.6
    localparam SCORE_W = 4;  

    // 物理常數 (1.0 = 64)
    localparam FRAC_ONE = 10'd64; 
    localparam GRAVITY  = 10'd1;    
    localparam BOUNCE_DAMPING = 10'd55; // 彈性係數

    // 擊球速度 (一般)
    localparam P1_HIT_VX = 10'd192; // 3.0
    localparam P1_HIT_VY = 10'd320; // 5.0 (向上)
    localparam P2_HIT_VX = -10'd192; 
    localparam P2_HIT_VY = 10'd320; 

    // 擊球速度 (殺球 - Advanced Function)
    localparam P1_SMASH_VX = 10'd320; // 5.0 (更快)
    localparam P1_SMASH_VY = 10'd448; // 7.0 (更高/更平)
    localparam P2_SMASH_VX = -10'd320;
    localparam P2_SMASH_VY = 10'd448;

    // 場地參數 (注意：這裡維持你原始的 Y 軸向上邏輯)
    localparam SCREEN_WIDTH  = 10'd320;
    localparam SCREEN_HEIGHT = 10'd240;

    localparam NET_X_POS   = 10'd160;     
    localparam NET_W       = 10'd6;            
    localparam NET_H       = 10'd90;           
    localparam FLOOR_Y_POS = 10'd30; // 地板在 Y=30 (下方)
    
    localparam NET_TOP_Y = FLOOR_Y_POS + NET_H; // 網頂 Y = 120

    localparam LEFT_WALL_X  = 10'd0;
    localparam RIGHT_WALL_X = SCREEN_WIDTH - 1; 

    localparam BALL_INIT_X = 10'd260;
    localparam BALL_INIT_Y = 10'd150; // 從空中掉下來
    
    // --- 變數宣告 ---
    reg signed [VEL_W-1:0] ball_vel_x, ball_vel_y;
    
    wire signed [VEL_W-1:0] ball_vel_y_calc; 
    wire signed [COORD_W-1:0] ball_pos_y_calc;
    wire signed [COORD_W-1:0] ball_pos_x_calc;
    
    wire ball_hit_floor_p1_side; 
    wire ball_hit_floor_p2_side; 
    
    wire ball_hit_net_top;
    wire ball_hit_net_side_p1;
    wire ball_hit_net_side_p2;
    wire ball_hit_wall_side;      
    
    // 1. 物理運算 (Y 軸向上為正，重力為減)
    assign ball_vel_y_calc = ball_vel_y - GRAVITY; 
    assign ball_pos_y_calc = ball_pos_y + (ball_vel_y_calc >>> FRAC_W);
    assign ball_pos_x_calc = ball_pos_x + (ball_vel_x >>> FRAC_W);
    
    // 2. 碰撞檢測
    // 掉到地板 (Y <= 30)
    assign ball_hit_floor_p1_side = (ball_pos_y_calc <= FLOOR_Y_POS) && (ball_pos_x_calc < NET_X_POS);
    assign ball_hit_floor_p2_side = (ball_pos_y_calc <= FLOOR_Y_POS) && (ball_pos_x_calc >= NET_X_POS);

    // 網子範圍
    wire ball_in_net_x_range = (ball_pos_x < NET_X_POS + NET_W) && (ball_pos_x > NET_X_POS - NET_W);

    // 撞網頂 (從上往下掉到網子上)
    assign ball_hit_net_top = ball_in_net_x_range && 
                              (ball_pos_y > NET_TOP_Y) &&            
                              (ball_pos_y_calc <= NET_TOP_Y);        

    // 撞網側 (低於網頂)
    assign ball_hit_net_side_p1 = ball_in_net_x_range && 
                                  (ball_pos_x_calc < NET_X_POS) && 
                                  (ball_pos_y_calc <= NET_TOP_Y) && 
                                  (ball_pos_y_calc > FLOOR_Y_POS);

    assign ball_hit_net_side_p2 = ball_in_net_x_range && 
                                  (ball_pos_x_calc >= NET_X_POS) && 
                                  (ball_pos_y_calc <= NET_TOP_Y) && 
                                  (ball_pos_y_calc > FLOOR_Y_POS);
                                  
    assign ball_hit_wall_side = (ball_pos_x_calc <= LEFT_WALL_X) || (ball_pos_x_calc >= RIGHT_WALL_X);
    
    // 3. 狀態更新
    reg signed [VEL_W-1:0] final_vel_x, final_vel_y;
    reg signed [COORD_W-1:0] final_pos_x, final_pos_y;
    reg [SCORE_W-1:0] p1_score_next, p2_score_next;
    reg score_happened; 

    always @(*) begin
        // 預設值
        final_vel_x = ball_vel_x;
        final_vel_y = ball_vel_y_calc;
        final_pos_x = ball_pos_x + (ball_vel_x >>> FRAC_W);
        final_pos_y = ball_pos_y_calc;
        
        p1_score_next = p1_score;
        p2_score_next = p2_score;
        score_happened = 1'b0; 

        // A. 玩家擊球 (優先權最高)
        if (p1_cover || p2_cover) begin
            if (p1_cover) begin
                // 判斷是否殺球
                if (p1_is_smash) begin
                    final_vel_x = P1_SMASH_VX;
                    final_vel_y = P1_SMASH_VY;
                end else begin
                    final_vel_x = P1_HIT_VX;
                    final_vel_y = P1_HIT_VY;
                end
                final_pos_x = p1_pos_x_i + 30; // 稍微彈開防止黏住
                // 注意：這裡的 p1_pos_y_i 必須是 Main 模組傳進來的「轉換後(Y向上)」座標
                final_pos_y = p1_pos_y_i + 30; 
            end
            else if (p2_cover) begin
                if (p2_is_smash) begin
                    final_vel_x = P2_SMASH_VX;
                    final_vel_y = P2_SMASH_VY;
                end else begin
                    final_vel_x = P2_HIT_VX;
                    final_vel_y = P2_HIT_VY;
                end
                final_pos_x = p2_pos_x_i - 30;
                final_pos_y = p2_pos_y_i + 30;
            end
        end
        // B. 環境碰撞
        else begin
            // 1. 得分 (掉地板)
            if (ball_hit_floor_p1_side) begin 
                p2_score_next = p2_score + 1;
                score_happened = 1'b1; 
            end 
            else if (ball_hit_floor_p2_side) begin 
                p1_score_next = p1_score + 1;
                score_happened = 1'b1; 
            end
            
            // 2. 撞網頂
            else if (ball_hit_net_top) begin
                final_vel_y = -final_vel_y; // 反彈
                final_vel_y = (final_vel_y * 3) >>> 2; // 能量損耗 (x0.75)
                final_pos_y = NET_TOP_Y + 5; 
            end

            // 3. 撞網側
            else if (ball_hit_net_side_p1 || ball_hit_net_side_p2) begin
                final_vel_x = -final_vel_x; 
                if (ball_pos_x_calc < NET_X_POS) final_pos_x = NET_X_POS - NET_W - 2;
                else final_pos_x = NET_X_POS + NET_W + 2;
            end

            // 4. 地板反彈 (若未結束遊戲)
            else if (ball_pos_y_calc <= FLOOR_Y_POS) begin
                // 如果已經判斷得分，這裡就不重要，但為了物理連續性：
                final_vel_y = -ball_vel_y_calc;
                final_vel_y = (final_vel_y * BOUNCE_DAMPING) >>> 6; // 衰減
                final_pos_y = FLOOR_Y_POS; 
            end

            // 5. 牆壁反彈
            else if (ball_hit_wall_side) begin
                final_vel_x = -final_vel_x; 
                if (ball_pos_x_calc <= LEFT_WALL_X) final_pos_x = LEFT_WALL_X + 2;
                if (ball_pos_x_calc >= RIGHT_WALL_X) final_pos_x = RIGHT_WALL_X - 2;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ball_pos_x <= BALL_INIT_X; 
            ball_pos_y <= BALL_INIT_Y;
            ball_vel_x <= 0; 
            ball_vel_y <= 0;
            p1_score <= 0; 
            p2_score <= 0;
            game_over <= 0;
        end else begin
            game_over <= score_happened;
            
            p1_score <= p1_score_next;
            p2_score <= p2_score_next;

            if (score_happened) begin
                // 得分重置球
                ball_pos_x <= BALL_INIT_X; 
                ball_pos_y <= BALL_INIT_Y;
                ball_vel_x <= 0;
                ball_vel_y <= 0;
            end else begin
                ball_vel_x <= final_vel_x;
                ball_vel_y <= final_vel_y;
                ball_pos_x <= final_pos_x;
                ball_pos_y <= final_pos_y;
            end
        end
    end
endmodule
