module physic (
    input wire clk,
    input wire rst_n,

    // P1 & P2 動作
    input wire p1_op_move_left, input wire p1_op_move_right, input wire p1_op_jump,
    input wire p2_op_move_left, input wire p2_op_move_right, input wire p2_op_jump,
    
    // 殺球訊號
    input wire p1_is_smash,
    input wire p2_is_smash,

    // 碰撞偵測 (Render 傳入，精確碰撞)
    input wire p1_cover, 
    input wire p2_cover, 
    
    // 玩家位置 (Sprite 左上角)
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

    // 半徑平方：20 * 20 = 400
    localparam BALL_RADIUS_SQ = 20'd400;

    localparam PIKA_HALF_W = 10'd32; 

    // 物理常數
    localparam GRAVITY   = 10'd1; 
    localparam BOUNCE_DAMPING = 10'd55; 

    // 速度參數
    localparam P1_SMASH_VX = 10'd320; 
    localparam P1_SMASH_VY = -10'd448; 
    localparam P2_SMASH_VX = -10'd320;
    localparam P2_SMASH_VY = -10'd448;

    localparam HIT_FACTOR = 10'd5; 
    localparam BASE_UP_FORCE = -10'd256; 
    localparam MOVE_ADD_VEL = 10'd64;    

    // --- 網子角落反彈係數 ---
    localparam NET_CORNER_FORCE = 10'd6; 

    // 場地參數
    localparam SCREEN_WIDTH  = 10'd320;
    localparam SCREEN_HEIGHT = 10'd240;
    localparam FLOOR_Y_POS   = SCREEN_HEIGHT; 
    
    localparam NET_W       = 10'd6;   
    localparam NET_H       = 10'd90;
    localparam NET_X_POS   = 10'd160; 
    localparam NET_TOP_Y   = FLOOR_Y_POS - NET_H; 
    localparam NET_LEFT_X  = NET_X_POS - NET_W;
    localparam NET_RIGHT_X = NET_X_POS + NET_W;

    localparam LEFT_WALL_X  = 10'd0;
    localparam RIGHT_WALL_X = SCREEN_WIDTH; 

    localparam BALL_INIT_X = 10'd260;
    localparam BALL_INIT_Y = 10'd50; 

    localparam COOLDOWN_MAX = 4'd12; 
    
    // --- 變數宣告 ---
    reg signed [VEL_W-1:0] ball_vel_x, ball_vel_y;
    
    wire signed [VEL_W-1:0] ball_vel_y_calc; 
    wire signed [COORD_W-1:0] ball_pos_y_calc;
    wire signed [COORD_W-1:0] ball_pos_x_calc;
    
    wire signed [COORD_W-1:0] ball_bottom;
    wire signed [COORD_W-1:0] ball_right;
    
    // 中心點計算
    wire signed [COORD_W-1:0] ball_center_x;
    wire signed [COORD_W-1:0] ball_center_y; 
    wire signed [COORD_W-1:0] p1_center_x;
    wire signed [COORD_W-1:0] p2_center_x;
    
    assign ball_center_x = ball_pos_x + BALL_RADIUS;
    assign ball_center_y = ball_pos_y + BALL_RADIUS; 
    
    assign p1_center_x   = p1_pos_x_i + PIKA_HALF_W;
    assign p2_center_x   = p2_pos_x_i + PIKA_HALF_W;

    // --- 網子角落判定變數 ---
    wire signed [COORD_W:0] diff_net_left_x;
    wire signed [COORD_W:0] diff_net_right_x;
    wire signed [COORD_W:0] diff_net_y; 
    
    assign diff_net_left_x  = ball_center_x - NET_LEFT_X;  
    assign diff_net_right_x = ball_center_x - NET_RIGHT_X; 
    assign diff_net_y       = ball_center_y - NET_TOP_Y;   

    wire signed [20:0] dist_sq_left;
    wire signed [20:0] dist_sq_right;

    assign dist_sq_left  = (diff_net_left_x * diff_net_left_x) + (diff_net_y * diff_net_y);
    assign dist_sq_right = (diff_net_right_x * diff_net_right_x) + (diff_net_y * diff_net_y);

    // 碰撞 Flag
    wire ball_hit_floor_cond;
    wire ball_hit_net_top_cond;
    wire ball_hit_net_side_cond;
    wire ball_hit_wall_left_cond;
    wire ball_hit_wall_right_cond;
    wire ball_hit_corner_left_cond;
    wire ball_hit_corner_right_cond;
    
    reg [3:0] hit_cooldown; 
    reg [3:0] hit_cooldown_next;

    // 1. 物理運算
    assign ball_vel_y_calc = ball_vel_y + GRAVITY;
    assign ball_pos_y_calc = ball_pos_y + (ball_vel_y_calc >>> FRAC_W);
    assign ball_pos_x_calc = ball_pos_x + (ball_vel_x >>> FRAC_W);

    assign ball_bottom = ball_pos_y_calc + BALL_SIZE;
    assign ball_right  = ball_pos_x_calc + BALL_SIZE;

    // 2. 碰撞檢測邏輯
    assign ball_hit_floor_cond = (ball_bottom >= FLOOR_Y_POS);

    // --- 角落碰撞檢測 (圓形判定) ---
    assign ball_hit_corner_left_cond  = (dist_sq_left <= BALL_RADIUS_SQ);
    assign ball_hit_corner_right_cond = (dist_sq_right <= BALL_RADIUS_SQ);

    // --- 平面碰撞檢測 (AABB) ---
    wire x_overlap_net = (ball_right > NET_LEFT_X) && (ball_pos_x_calc < NET_RIGHT_X);
    wire y_overlap_net = (ball_bottom > NET_TOP_Y);
    
    // 互斥邏輯：如果是角落，就不算頂或側
    assign ball_hit_net_top_cond = x_overlap_net && y_overlap_net && 
                                   ((ball_pos_y + BALL_SIZE) <= NET_TOP_Y) &&
                                   !ball_hit_corner_left_cond && !ball_hit_corner_right_cond;

    assign ball_hit_net_side_cond = x_overlap_net && y_overlap_net && 
                                    !ball_hit_net_top_cond &&
                                    !ball_hit_corner_left_cond && !ball_hit_corner_right_cond;
    
    assign ball_hit_wall_left_cond  = (ball_pos_x_calc <= LEFT_WALL_X);
    assign ball_hit_wall_right_cond = (ball_right >= RIGHT_WALL_X);
    
    // 3. 狀態更新
    reg signed [VEL_W-1:0] final_vel_x, final_vel_y;
    reg signed [COORD_W-1:0] final_pos_x, final_pos_y;
    reg [SCORE_W-1:0] p1_score_next, p2_score_next;
    reg score_happened; 

    reg signed [COORD_W:0] delta_x; 

    always @(*) begin
        final_vel_x = ball_vel_x;
        final_vel_y = ball_vel_y_calc;
        final_pos_x = ball_pos_x_calc;
        final_pos_y = ball_pos_y_calc;
        
        p1_score_next = p1_score;
        p2_score_next = p2_score;
        score_happened = 1'b0; 
        
        hit_cooldown_next = (hit_cooldown > 0) ? (hit_cooldown - 1) : 4'd0;
        
        delta_x = 0;

        // A. 玩家擊球
        if ((p1_cover || p2_cover) && (hit_cooldown == 0)) begin
            hit_cooldown_next = COOLDOWN_MAX;

            if (p1_cover) begin
                if (p1_is_smash) begin
                    final_vel_x = P1_SMASH_VX;
                    final_vel_y = P1_SMASH_VY;
                end 
                else begin
                    delta_x = ball_center_x - p1_center_x;
                    final_vel_x = delta_x * HIT_FACTOR;
                    if (p1_op_move_right) final_vel_x = final_vel_x + MOVE_ADD_VEL;
                    if (p1_op_move_left)  final_vel_x = final_vel_x - MOVE_ADD_VEL;
                    final_vel_y = BASE_UP_FORCE; 
                end
            end
            else if (p2_cover) begin
                if (p2_is_smash) begin
                    final_vel_x = P2_SMASH_VX;
                    final_vel_y = P2_SMASH_VY;
                end 
                else begin
                    delta_x = ball_center_x - p2_center_x;
                    final_vel_x = delta_x * HIT_FACTOR; 
                    if (p2_op_move_right) final_vel_x = final_vel_x + MOVE_ADD_VEL;
                    if (p2_op_move_left)  final_vel_x = final_vel_x - MOVE_ADD_VEL;
                    final_vel_y = BASE_UP_FORCE; 
                end
            end
        end
        // B. 環境碰撞
        else begin
            // 1. 左邊角落
            if (ball_hit_corner_left_cond) begin
                final_vel_x = diff_net_left_x * NET_CORNER_FORCE;
                final_vel_y = diff_net_y * NET_CORNER_FORCE;
                if (final_vel_y > -128) final_vel_y = final_vel_y - 64; 
            end
            // 2. 右邊角落
            else if (ball_hit_corner_right_cond) begin
                final_vel_x = diff_net_right_x * NET_CORNER_FORCE;
                final_vel_y = diff_net_y * NET_CORNER_FORCE;
                if (final_vel_y > -128) final_vel_y = final_vel_y - 64;
            end
            // 3. 網頂平面
            else if (ball_hit_net_top_cond) begin
                if (final_vel_y > 0) begin
                    final_vel_y = -final_vel_y; 
                    final_vel_y = (final_vel_y * 3) >>> 2; 
                end
                final_pos_y = NET_TOP_Y - BALL_SIZE - 2; 
            end
            // 4. 網側平面
            else if (ball_hit_net_side_cond) begin
                if (ball_pos_x_calc + (BALL_SIZE/2) < NET_X_POS) begin
                    if (final_vel_x > 0) final_vel_x = -final_vel_x;
                    final_pos_x = NET_LEFT_X - BALL_SIZE - 2;
                end
                else begin
                    if (final_vel_x < 0) final_vel_x = -final_vel_x;
                    final_pos_x = NET_RIGHT_X + 2;
                end
            end
            // 5. 地板
            else if (ball_hit_floor_cond) begin 
                if (final_vel_y > 0) begin
                    final_vel_y = -final_vel_y; 
                    final_vel_y = (final_vel_y * BOUNCE_DAMPING) >>> 6;
                end
                final_pos_y = FLOOR_Y_POS - BALL_SIZE; 

                if (score_happened == 0) begin
                    if (ball_pos_x_calc < NET_X_POS) begin
                        p2_score_next = p2_score + 1; 
                        score_happened = 1'b1;
                    end else begin
                        p1_score_next = p1_score + 1;
                        score_happened = 1'b1;
                    end
                end
            end 
            // 6. 牆壁
            else if (ball_hit_wall_left_cond) begin
                if (final_vel_x < 0) final_vel_x = -final_vel_x;
                final_pos_x = LEFT_WALL_X + 2;
            end
            else if (ball_hit_wall_right_cond) begin
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
            hit_cooldown <= 0; 
        end else begin
            game_over <= score_happened;
            p1_score <= p1_score_next;
            p2_score <= p2_score_next;
            
            hit_cooldown <= hit_cooldown_next;

            if (score_happened) begin
                ball_pos_x <= BALL_INIT_X; 
                ball_pos_y <= BALL_INIT_Y;
                ball_vel_x <= 0;
                ball_vel_y <= 0;
                hit_cooldown <= 0; 
            end else begin
                ball_vel_x <= final_vel_x;
                ball_vel_y <= final_vel_y;
                ball_pos_x <= final_pos_x;
                ball_pos_y <= final_pos_y;
            end
        end
    end
endmodule