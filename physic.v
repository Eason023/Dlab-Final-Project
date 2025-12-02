// physic.v
//-----------------------------------------------------------------------------
// 模組功能：專注於皮卡丘打排球遊戲中的【球體物理運動】和【得分判定】。
// 處理球的位置、速度、重力、環境碰撞和角色碰撞後的反彈計算。
// 解析度目標：320 x 240
//-----------------------------------------------------------------------------

module physic (
    input wire clk,
    input wire rst_n,

    // P1 & P2 動作輸入 (僅接收操作，用於擊球判斷)
    input wire p1_op_move_left, input wire p1_op_move_right, input wire p1_op_jump,
    input wire p2_op_move_left, input wire p2_op_move_right, input wire p2_op_jump,

    // 碰撞偵測結果輸入 (來自 render/bounding detect 模組)
    input wire p1_cover, // P1 玩家與球是否發生碰撞
    input wire p2_cover, // P2 玩家與球是否發生碰撞
    
    // 玩家的當前位置 (僅用於計算擊球後的球體起始位置)
    // 保持 [9:0] 位寬，但值會限制在 0-320/240 範圍
    input wire [9:0] p1_pos_x_i, p1_pos_y_i,
    input wire [9:0] p2_pos_x_i, p2_pos_y_i,

    output reg [9:0] ball_pos_x, ball_pos_y,
    
    output reg [3:0] p1_score, p2_score,
    output reg game_over // 遊戲是否結束 (有得分/球落地)
);
    
    //位寬定義
    localparam COORD_W = 10; // 座標位寬 (0-1023), 實際使用 0-320/240
    localparam VEL_W   = 10; // 速度位寬 (定點數 Q4.6)
    localparam FRAC_W  = 6;  // 定點數的小數部分位寬
    localparam SCORE_W = 4;  // 分數位寬 (0-15)

    //物理常數 (定點數 Q4.6: 1.0 = 10'd64)
    localparam FRAC_ONE = 10'd64; 
    localparam GRAVITY = 10'd2;   
    localparam BOUNCE_DAMPING = 10'd55; 

    //擊球反彈速度
    localparam P1_HIT_VX = 10'd192; 
    localparam P1_HIT_VY = 10'd320; 
    localparam P2_HIT_VX = -10'd192; 
    localparam P2_HIT_VY = 10'd320; 

    localparam SCREEN_WIDTH = 10'd320;
    localparam SCREEN_HEIGHT = 10'd240;

    localparam NET_X_POS = 10'd160;     // 球網 X 座標 (中線 320/2)
    localparam NET_W = 10'd6;           // 球網半寬 (您要求的參數)
    localparam NET_H = 10'd90;          // 球網高度 (您要求的參數)
    localparam FLOOR_Y_POS = 10'd30;    // 地面 Y 座標 (相對較低)
    
    localparam NET_TOP_Y = FLOOR_Y_POS + NET_H; // 球網頂部 Y 座標

    localparam LEFT_WALL_X = 10'd0;
    localparam RIGHT_WALL_X = SCREEN_WIDTH - 1; // 319

    localparam BALL_INIT_X = NET_X_POS;
    localparam BALL_INIT_Y = 10'd150; // 畫面中線偏上
    
    reg [VEL_W-1:0] ball_vel_x, ball_vel_y;
    
    wire [VEL_W-1:0] ball_vel_y_calc; 
    wire [COORD_W-1:0] ball_pos_y_calc;
    
    wire ball_hit_floor_p1_side; 
    wire ball_hit_floor_p2_side; 
    
    // 新增網子頂部碰撞
    wire ball_hit_net_top;
    // 修改網子側面碰撞
    wire ball_hit_net_side_p1;
    wire ball_hit_net_side_p2;

    wire ball_hit_wall_side;     
    
    //1. 物理運動學計算 (下一週期預計狀態)

    assign ball_vel_y_calc = ball_vel_y - GRAVITY; 
    assign ball_pos_y_calc = ball_pos_y + (ball_vel_y_calc >>> FRAC_W);
    
    //2. 環境碰撞與得分偵測

    // 球落地/得分偵測 (球的 Y 座標小於等於地面 Y 座標)
    assign ball_hit_floor_p1_side = (ball_pos_y_calc <= FLOOR_Y_POS) && (ball_pos_x_calc < NET_X_POS);
    assign ball_hit_floor_p2_side = (ball_pos_y_calc <= FLOOR_Y_POS) && (ball_pos_x_calc >= NET_X_POS);

    // 網子X軸範圍判斷
    wire ball_in_net_x_range = (ball_pos_x < NET_X_POS + NET_W) && (ball_pos_x > NET_X_POS - NET_W);

    // 網子頂部碰撞 (從上方砸到網頂)
    assign ball_hit_net_top = ball_in_net_x_range && 
                              (ball_pos_y > NET_TOP_Y) &&           // 當前在網頂上方
                              (ball_pos_y_calc <= NET_TOP_Y);       // 下一週期撞到網頂

    // 網子側面碰撞 (撞到網子主體，排除網頂)
    assign ball_hit_net_side_p1 = ball_in_net_x_range && 
                                  (ball_pos_x_calc < NET_X_POS) &&  // 球心在 P1 側
                                  (ball_pos_y_calc <= NET_TOP_Y) && // 且高度在網子主體內
                                  (ball_pos_y_calc > FLOOR_Y_POS);

    assign ball_hit_net_side_p2 = ball_in_net_x_range && 
                                  (ball_pos_x_calc >= NET_X_POS) && // 球心在 P2 側
                                  (ball_pos_y_calc <= NET_TOP_Y) && // 且高度在網子主體內
                                  (ball_pos_y_calc > FLOOR_Y_POS);
                                  
    // 牆壁碰撞
    assign ball_hit_wall_side = (ball_pos_x_calc <= LEFT_WALL_X) || (ball_pos_x_calc >= RIGHT_WALL_X);
    
    //3. 碰撞反應與狀態更新 (核心組合邏輯)
    
    reg [VEL_W-1:0] final_vel_x, final_vel_y;
    reg [COORD_W-1:0] final_pos_x, final_pos_y;
    reg [SCORE_W-1:0] p1_score_next, p2_score_next;
    
    reg score_happened; 
    
    assign game_over = score_happened; 

    always @(*) begin
        // 預設下一狀態
        final_vel_x = ball_vel_x;
        final_vel_y = ball_vel_y_calc;
        final_pos_x = ball_pos_x + (ball_vel_x >>> FRAC_W);
        final_pos_y = ball_pos_y_calc;
        
        p1_score_next = p1_score;
        p2_score_next = p2_score;
        score_happened = 1'b0; 

        // A. 優先級最高的碰撞：角色擊球 (外部輸入 p1_cover/p2_cover)
        if (p1_cover || p2_cover) begin
            if (p1_cover) begin
                final_vel_x = P1_HIT_VX;
                final_vel_y = P1_HIT_VY;
                final_pos_x = p1_pos_x_i + 30; // 確保不卡點
                final_pos_y = p1_pos_y_i + 30;
            end
            else if (p2_cover) begin
                final_vel_x = P2_HIT_VX;
                final_vel_y = P2_HIT_VY;
                final_pos_x = p2_pos_x_i - 30; // 確保不卡點
                final_pos_y = p2_pos_y_i + 30;
            end
        end
        // B. 環境與得分碰撞 (內部處理)
        else begin
            // 1. 得分落地 (最高優先級的環境碰撞)
            if (ball_hit_floor_p1_side) begin // 球落在 P1 區，P2 得分
                p2_score_next = p2_score + 1;
                score_happened = 1'b1; 
            end 
            else if (ball_hit_floor_p2_side) begin // 球落在 P2 區，P1 得分
                p1_score_next = p1_score + 1;
                score_happened = 1'b1; 
            end
            
            // 2. 網子頂部碰撞 (從上方落到網子上)
            else if (ball_hit_net_top) begin
                final_vel_y = (~final_vel_y + 1); // 垂直速度反向
                final_pos_y = NET_TOP_Y;         // 鎖定在網頂
            end

            // 3. 網子側面碰撞
            else if (ball_hit_net_side_p1 || ball_hit_net_side_p2) begin
                final_vel_x = (~final_vel_x + 1); // 水平速度反向
                // 鎖定位置以防止穿透
                if (ball_pos_x_calc < NET_X_POS) final_pos_x = NET_X_POS - NET_W; // P1 側反彈
                else final_pos_x = NET_X_POS + NET_W;                           // P2 側反彈
            end

            // 4. 地面碰撞 (非得分區，即排球網下)
            else if (ball_pos_y_calc <= FLOOR_Y_POS) begin
                // 速度反向 * 衰減
                final_vel_y = (FRAC_ONE - ball_vel_y_calc) * BOUNCE_DAMPING / FRAC_ONE;
                final_pos_y = FLOOR_Y_POS; 
            end

            // 5. 牆壁碰撞
            else if (ball_hit_wall_side) begin
                final_vel_x = (~final_vel_x + 1); 
                if (ball_pos_x_calc <= LEFT_WALL_X) final_pos_x = LEFT_WALL_X;
                if (ball_pos_x_calc >= RIGHT_WALL_X) final_pos_x = RIGHT_WALL_X;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 系統重置 (硬體重置/遊戲重開)
            ball_pos_x <= BALL_INIT_X; ball_pos_y <= BALL_INIT_Y;
            ball_vel_x <= 0; ball_vel_y <= 0;
            p1_score <= 0; p2_score <= 0;
        end else begin
            
            // 分數更新
            p1_score <= p1_score_next;
            p2_score <= p2_score_next;

            //球的位置和速度更新 (如果得分，則重置球)
            if (score_happened) begin
                // 球得分/發球重置時的位置/速度
                ball_pos_x <= BALL_INIT_X; 
                ball_pos_y <= BALL_INIT_Y;
                ball_vel_x <= 0;
                ball_vel_y <= 0;
            end else begin
                // 正常物理運動
                ball_vel_x <= final_vel_x;
                ball_vel_y <= final_vel_y;
                ball_pos_x <= final_pos_x;
                ball_pos_y <= final_pos_y;
            end
        end
    end
endmodule