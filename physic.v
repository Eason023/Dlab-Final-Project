// physic.v
// --------------------------------------------------------------------------------
// 模組功能：專注於皮卡丘打排球遊戲中的【球體物理運動】和【得分判定】。
// 處理球的位置、速度、重力、環境碰撞和角色碰撞後的反彈計算。
// --------------------------------------------------------------------------------

module physic (
    input wire clk,
    input wire rst_n,

    // P1 & P2 動作輸入 (僅接收操作，用於擊球判斷)
    input wire p1_op_move_left, p1_op_move_right, p1_op_jump, // P1 (人類)
    input wire p2_op_move_left, p2_op_move_right, p2_op_jump, // P2 (COM)

    // 碰撞偵測結果輸入 (來自 render/bounding detect 模組)
    input wire p1_cover, // P1 玩家與球是否發生碰撞
    input wire p2_cover, // P2 玩家與球是否發生碰撞
    
    // 玩家的當前位置 (僅用於計算擊球後的球體起始位置)
    input wire [9:0] p1_pos_x_i, p1_pos_y_i,
    input wire [9:0] p2_pos_x_i, p2_pos_y_i,

    // --------------------------------------------------------
    // Output: 輸出球的當前位置和遊戲狀態
    // --------------------------------------------------------
    output reg [9:0] ball_pos_x, ball_pos_y,
    
    output reg [3:0] p1_score, p2_score,
    output reg game_over // 遊戲是否結束 (有得分/球落地)
);

    // =======================================================
    // --- 內部常數與參數定義 ---
    // =======================================================
    
    // --- 位寬定義 ---
    localparam COORD_W = 10; // 座標位寬 (0-1023)
    localparam VEL_W   = 10; // 速度位寬 (定點數 Q4.6)
    localparam FRAC_W  = 6;  // 定點數的小數部分位寬
    localparam SCORE_W = 4;  // 分數位寬 (0-15)

    // --- 物理常數 (定點數 Q4.6: 1.0 = 10'd64) ---
    localparam FRAC_ONE = 10'd64; 
    localparam GRAVITY = 10'd2;   
    localparam BOUNCE_DAMPING = 10'd55; 

    // --- 擊球反彈速度 ---
    localparam P1_HIT_VX = 10'd192; // P1 擊球後的 X 速度 (約 3.0)
    localparam P1_HIT_VY = 10'd320; // P1 擊球後的 Y 速度 (約 5.0)
    localparam P2_HIT_VX = -10'd192; // P2 擊球後的 X 速度
    localparam P2_HIT_VY = 10'd320; 

    // --- 座標邊界與初始位置 ---
    localparam NET_X_POS = 10'd512;  // 球網 X 座標
    localparam NET_WIDTH = 10'd5;    // 球網半徑
    localparam FLOOR_Y_POS = 10'd100; // 地面 Y 座標
    localparam LEFT_WALL_X = 10'd10;
    localparam RIGHT_WALL_X = 10'd1014;

    localparam BALL_INIT_X = 10'd512;
    localparam BALL_INIT_Y = 10'd300;
    
    // 球的速度
    reg [VEL_W-1:0] ball_vel_x, ball_vel_y;
    
    // 預計的下一速度/位置(未經碰撞修正)
    wire [VEL_W-1:0] ball_vel_y_calc; 
    wire [COORD_W-1:0] ball_pos_y_calc;

    // 碰撞/得分偵測旗標 (Combinational)
    wire ball_hit_floor_p1_side; 
    wire ball_hit_floor_p2_side; 
    wire ball_hit_net_side;      
    wire ball_hit_wall_side;     
    
    // --- 1. 物理運動學計算 (下一週期預計狀態) ---

    // Y 軸運動：受重力影響
    assign ball_vel_y_calc = ball_vel_y - GRAVITY; 
    assign ball_pos_y_calc = ball_pos_y + (ball_vel_y_calc >>> FRAC_W);
    
    // --- 2. 環境碰撞與得分偵測 ---

    // 球落地/得分偵測 (球的 Y 座標小於等於地面 Y 座標)
    assign ball_hit_floor_p1_side = (ball_pos_y_calc <= FLOOR_Y_POS) && (ball_pos_x_calc < NET_X_POS);
    assign ball_hit_floor_p2_side = (ball_pos_y_calc <= FLOOR_Y_POS) && (ball_pos_x_calc >= NET_X_POS);

    // 網子碰撞
    assign ball_hit_net_side = (ball_pos_x < NET_X_POS + NET_WIDTH) && (ball_pos_x > NET_X_POS - NET_WIDTH) && (ball_pos_y > FLOOR_Y_POS);

    // 牆壁碰撞
    assign ball_hit_wall_side = (ball_pos_x_calc <= LEFT_WALL_X) || (ball_pos_x_calc >= RIGHT_WALL_X);
    
    // --- 3. 碰撞反應與狀態更新 (核心組合邏輯) ---
    
    // 最終的位置和速度 (用於下一週期寫入寄存器)
    reg [VEL_W-1:0] final_vel_x, final_vel_y;
    reg [COORD_W-1:0] final_pos_x, final_pos_y;
    reg [SCORE_W-1:0] p1_score_next, p2_score_next;
    
    reg score_happened; // 得分旗標 (用於觸發 game_over 和重置)
    
    // 遊戲結束判定：只要任何一邊得分，game_over 就會被拉高
    assign game_over = score_happened; 

    always @(*) begin
        // 預設下一狀態
        final_vel_x = ball_vel_x;
        final_vel_y = ball_vel_y_calc;
        final_pos_x = ball_pos_x + (ball_vel_x >>> FRAC_W);
        final_pos_y = ball_pos_y_calc;
        
        p1_score_next = p1_score;
        p2_score_next = p2_score;
        score_happened = 1'b0; // 預設沒有得分

        // A. 優先級最高的碰撞：角色擊球 (外部輸入 p1_cover/p2_cover)
        if (p1_cover || p2_cover) begin
            if (p1_cover) begin
                final_vel_x = P1_HIT_VX;
                final_vel_y = P1_HIT_VY;
                // 使用傳入的玩家位置作為球的新起點，避免卡點
                final_pos_x = p1_pos_x_i + 30;
                final_pos_y = p1_pos_y_i + 30;
            end
            else if (p2_cover) begin
                final_vel_x = P2_HIT_VX;
                final_vel_y = P2_HIT_VY;
                final_pos_x = p2_pos_x_i - 30;
                final_pos_y = p2_pos_y_i + 30;
            end
        end
        // B. 環境與得分碰撞 (內部處理)
        else begin
            // 1. 地面碰撞 (非得分區)
            if (ball_pos_y_calc <= FLOOR_Y_POS) begin
                if (~ball_hit_floor_p1_side && ~ball_hit_floor_p2_side) begin
                    // 速度反向 * 衰減
                    final_vel_y = (FRAC_ONE - ball_vel_y_calc) * BOUNCE_DAMPING / FRAC_ONE;
                    final_pos_y = FLOOR_Y_POS; 
                end
            end

            // 2. 得分落地 (觸發 game_over)
            if (ball_hit_floor_p1_side) begin // 球落在 P1 區，P2 得分
                p2_score_next = p2_score + 1;
                score_happened = 1'b1; 
            end 
            else if (ball_hit_floor_p2_side) begin // 球落在 P2 區，P1 得分
                p1_score_next = p1_score + 1;
                score_happened = 1'b1; 
            end

            // 3. 牆壁碰撞
            if (ball_hit_wall_side) begin
                final_vel_x = (~final_vel_x + 1); 
                if (ball_pos_x_calc <= LEFT_WALL_X) final_pos_x = LEFT_WALL_X;
                if (ball_pos_x_calc >= RIGHT_WALL_X) final_pos_x = RIGHT_WALL_X;
            end

            // 4. 網子側面碰撞
            if (ball_hit_net_side) begin
                final_vel_x = (~final_vel_x + 1); 
            end
        end
    end


    // =======================================================
    // --- 4. 時序邏輯 (狀態更新) ---
    // =======================================================
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

            // --- 球的位置和速度更新 (如果得分，則重置球) ---
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