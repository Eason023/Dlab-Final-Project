module physic (
    input wire clk,
    input wire rst_n,

    // P1 & P2 動作
    input wire p1_op_move_left, input wire p1_op_move_right, input wire p1_op_jump,
    input wire p2_op_move_left, input wire p2_op_move_right, input wire p2_op_jump,
    
    // 殺球訊號
    input wire p1_is_smash,
    input wire p2_is_smash,

    // 碰撞偵測 (Render 傳入)
    input wire p1_cover, 
    input wire p2_cover, 
    
    // 玩家位置
    input wire [9:0] p1_pos_x_i, p1_pos_y_i,
    input wire [9:0] p2_pos_x_i, p2_pos_y_i,

    output reg [9:0] ball_pos_x, ball_pos_y,
    output reg [3:0] p1_score, p2_score,
    output reg game_over
);
    
    // --- 參數設定 ---
    localparam COORD_W = 10; 
    localparam VEL_W   = 10; 
    localparam FRAC_W  = 6; 
    localparam SCORE_W = 4;  

    localparam BALL_SIZE = 10'd40; 
    localparam BALL_RADIUS = 10'd20;

    // 皮卡丘碰撞箱寬度 (Visual 可能是 64，但 Physics 用 60 比較好算)
    localparam PIKA_W = 10'd60; 
    localparam PIKA_HALF_W = 10'd30;

    // 物理常數
    localparam GRAVITY   = 10'd1; 
    localparam BOUNCE_DAMPING = 10'd55; // 彈性損耗 (~0.85)

    // --- 殺球速度 ---
    localparam P1_SMASH_VX = 10'd320; 
    localparam P1_SMASH_VY = -10'd448; 
    localparam P2_SMASH_VX = -10'd320;
    localparam P2_SMASH_VY = -10'd448;

    // --- 普通擊球參數 ---
    localparam HIT_FACTOR = 10'd5; 
    localparam BASE_UP_FORCE = -10'd256; // -4.0
    localparam MOVE_ADD_VEL = 10'd64;    // 1.0

    // --- 場地參數 ---
    localparam SCREEN_WIDTH  = 10'd320;
    localparam SCREEN_HEIGHT = 10'd240;
    localparam FLOOR_Y_POS   = SCREEN_HEIGHT; 
    
    localparam NET_W       = 10'd6;   
    localparam NET_H       = 10'd90;
    localparam NET_X_POS   = 10'd160; 
    localparam NET_TOP_Y   = FLOOR_Y_POS - NET_H; // 150
    localparam NET_LEFT_X  = NET_X_POS - NET_W;
    localparam NET_RIGHT_X = NET_X_POS + NET_W;

    localparam LEFT_WALL_X  = 10'd0;
    localparam RIGHT_WALL_X = SCREEN_WIDTH; 

    localparam BALL_INIT_X = 10'd260;
    localparam BALL_INIT_Y = 10'd50; 
    
    // --- 變數宣告 ---
    reg signed [VEL_W-1:0] ball_vel_x, ball_vel_y;
    
    wire signed [VEL_W-1:0] ball_vel_y_calc; 
    wire signed [COORD_W-1:0] ball_pos_y_calc;
    wire signed [COORD_W-1:0] ball_pos_x_calc;
    
    wire signed [COORD_W-1:0] ball_bottom;
    wire signed [COORD_W-1:0] ball_right;
    
    // 中心點計算
    wire signed [COORD_W-1:0] ball_center_x;
    wire signed [COORD_W-1:0] p1_center_x;
    wire signed [COORD_W-1:0] p2_center_x;
    
    assign ball_center_x = ball_pos_x + BALL_RADIUS;
    assign p1_center_x   = p1_pos_x_i + PIKA_HALF_W;
    assign p2_center_x   = p2_pos_x_i + PIKA_HALF_W;

    // 1. 物理運算 (預判下一步)
    assign ball_vel_y_calc = ball_vel_y + GRAVITY;
    assign ball_pos_y_calc = ball_pos_y + (ball_vel_y_calc >>> FRAC_W);
    assign ball_pos_x_calc = ball_pos_x + (ball_vel_x >>> FRAC_W);

    // 2. 邊界輔助
    assign ball_bottom = ball_pos_y_calc + BALL_SIZE;
    assign ball_right  = ball_pos_x_calc + BALL_SIZE;

    // 3. 環境碰撞檢測 logic
    wire ball_hit_floor_cond;
    wire ball_hit_net_top_cond;
    wire ball_hit_net_side_cond;
    wire ball_hit_wall_left_cond;
    wire ball_hit_wall_right_cond;

    // 地板：球底 >= 地板
    assign ball_hit_floor_cond = (ball_bottom >= FLOOR_Y_POS);

    // 網子範圍重疊
    wire x_overlap_net = (ball_right > NET_LEFT_X) && (ball_pos_x_calc < NET_RIGHT_X);
    wire y_overlap_net = (ball_bottom > NET_TOP_Y);

    // 網頂判定：必須符合「上一幀」球底在網頂之上 (避免球從側面穿過來誤判)
    assign ball_hit_net_top_cond = x_overlap_net && y_overlap_net && 
                                   ((ball_pos_y + BALL_SIZE) <= NET_TOP_Y); // 關鍵：使用 current pos

    // 網側判定：重疊且不是撞頂
    assign ball_hit_net_side_cond = x_overlap_net && y_overlap_net && !ball_hit_net_top_cond;

    // 牆壁判定
    assign ball_hit_wall_left_cond  = (ball_pos_x_calc <= LEFT_WALL_X);
    assign ball_hit_wall_right_cond = (ball_right >= RIGHT_WALL_X);
    
    // 4. 狀態更新
    reg signed [VEL_W-1:0] final_vel_x, final_vel_y;
    reg signed [COORD_W-1:0] final_pos_x, final_pos_y;
    reg [SCORE_W-1:0] p1_score_next, p2_score_next;
    reg score_happened; 

    // 暫存變數
    reg signed [COORD_W:0] delta_x; 

    always @(*) begin
        // 預設行為：應用物理移動
        final_vel_x = ball_vel_x;
        final_vel_y = ball_vel_y_calc;
        final_pos_x = ball_pos_x_calc;
        final_pos_y = ball_pos_y_calc;
        
        p1_score_next = p1_score;
        p2_score_next = p2_score;
        score_happened = 1'b0; 
        
        delta_x = 0;

        // ==========================================
        // A. 玩家擊球 (最優先)
        // ==========================================
        if (p1_cover || p2_cover) begin
            
            // --- P1 ---
            if (p1_cover) begin
                if (p1_is_smash) begin
                    final_vel_x = P1_SMASH_VX;
                    final_vel_y = P1_SMASH_VY;
                    final_pos_x = p1_pos_x_i + 30; // 固定彈出位置
                    final_pos_y = p1_pos_y_i - 20; // 確保向上彈
                end 
                else begin
                    // 物理碰撞
                    delta_x = ball_center_x - p1_center_x;
                    final_vel_x = delta_x * HIT_FACTOR;

                    if (p1_op_move_right) final_vel_x = final_vel_x + MOVE_ADD_VEL;
                    if (p1_op_move_left)  final_vel_x = final_vel_x - MOVE_ADD_VEL;

                    // 強制向上速度 (如果想讓球不要飛太高，可以減小 BASE_UP_FORCE)
                    // 這裡加個判斷：如果球原本就掉得很快，反彈更用力一點
                    final_vel_y = BASE_UP_FORCE; 

                    // 位置修正 (修正到剛好貼齊邊緣，避免下一幀 p1_cover 還是 true)
                    // P1 右側：PlayerX + PikaW
                    if (delta_x >= 0) 
                        final_pos_x = p1_pos_x_i + PIKA_W - 5; // 稍微重疊一點點 (-5) 比較自然，但要靠速度彈開
                    else 
                        final_pos_x = p1_pos_x_i - BALL_SIZE + 5;
                    
                    final_pos_y = p1_pos_y_i - 20; 
                end
            end
            
            // --- P2 ---
            else if (p2_cover) begin
                if (p2_is_smash) begin
                    final_vel_x = P2_SMASH_VX;
                    final_vel_y = P2_SMASH_VY;
                    final_pos_x = p2_pos_x_i - 30;
                    final_pos_y = p2_pos_y_i - 20;
                end 
                else begin
                    delta_x = ball_center_x - p2_center_x;
                    final_vel_x = delta_x * HIT_FACTOR; 

                    if (p2_op_move_right) final_vel_x = final_vel_x + MOVE_ADD_VEL;
                    if (p2_op_move_left)  final_vel_x = final_vel_x - MOVE_ADD_VEL;

                    final_vel_y = BASE_UP_FORCE; 

                    if (delta_x >= 0) 
                        final_pos_x = p2_pos_x_i + PIKA_W - 5;
                    else 
                        final_pos_x = p2_pos_x_i - BALL_SIZE + 5;

                    final_pos_y = p2_pos_y_i - 20;
                end
            end
        end
        // ==========================================
        // B. 環境碰撞
        // ==========================================
        else begin
            // 1. 地板 (得分)
            if (ball_hit_floor_cond) begin 
                // 只有當速度向下 (正值) 時才反彈，防止黏在地板
                if (final_vel_y > 0) begin
                    final_vel_y = -final_vel_y; 
                    final_vel_y = (final_vel_y * BOUNCE_DAMPING) >>> 6;
                end
                final_pos_y = FLOOR_Y_POS - BALL_SIZE; 

                // 判斷得分
                if (score_happened == 0) begin // 確保單一事件只觸發一次得分
                    if (ball_pos_x_calc < NET_X_POS) begin
                        p2_score_next = p2_score + 1; 
                        score_happened = 1'b1;
                    end else begin
                        p1_score_next = p1_score + 1;
                        score_happened = 1'b1;
                    end
                end
            end 
            
            // 2. 網頂
            else if (ball_hit_net_top_cond) begin
                // 只有向下掉的時候才反彈
                if (final_vel_y > 0) begin
                    final_vel_y = -final_vel_y; 
                    final_vel_y = (final_vel_y * 3) >>> 2; 
                end
                final_pos_y = NET_TOP_Y - BALL_SIZE - 2; 
            end

            // 3. 網側
            else if (ball_hit_net_side_cond) begin
                // 判斷撞哪邊
                if (ball_pos_x_calc + (BALL_SIZE/2) < NET_X_POS) begin
                    // 撞左側：只有往右飛 (vel_x > 0) 才反彈
                    if (final_vel_x > 0) final_vel_x = -final_vel_x;
                    final_pos_x = NET_LEFT_X - BALL_SIZE - 2;
                end
                else begin
                    // 撞右側：只有往左飛 (vel_x < 0) 才反彈
                    if (final_vel_x < 0) final_vel_x = -final_vel_x;
                    final_pos_x = NET_RIGHT_X + 2;
                end
            end

            // 4. 左牆
            else if (ball_hit_wall_left_cond) begin
                // 只有往左飛才反彈
                if (final_vel_x < 0) final_vel_x = -final_vel_x;
                final_pos_x = LEFT_WALL_X + 2;
            end

            // 5. 右牆
            else if (ball_hit_wall_right_cond) begin
                // 只有往右飛才反彈
                if (final_vel_x > 0) final_vel_x = -final_vel_x;
                final_pos_x = RIGHT_WALL_X - BALL_SIZE - 2; 
            end
        end
    end

    // Clock block
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
                // 重置
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