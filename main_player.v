module main_player (
    input wire clk,
    input wire rst_n,
    input wire [3:0] usr_btn, // [3]L [2]R [1]J [0]S
    input wire move_tick,     // 30Hz 的 Tick

    output reg [9:0] pos_x,   
    output reg [9:0] pos_y,   
    output reg is_smash
);
    // --- 參數設定 ---
    localparam GROUND_Y    = 10'd176; 
    localparam LEFT_BOUND  = 10'd0;
    localparam RIGHT_BOUND = 10'd91;  

    localparam MOVE_SPEED = 10'd3;  
    localparam JUMP_FORCE = 10'd12; 
    localparam GRAVITY    = 10'd1;

    // --- Debounce ---
    localparam DB_THRESHOLD = 20'd500_000; 
    reg [3:0] btn_stable, btn_sync_0, btn_sync_1;
    reg [19:0] db_cnt [3:0];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_stable <= 0; btn_sync_0 <= 0; btn_sync_1 <= 0;
            for(i=0;i<4;i=i+1) db_cnt[i] <= 0;
        end else begin
            btn_sync_0 <= usr_btn;
            btn_sync_1 <= btn_sync_0;
            for(i=0;i<4;i=i+1) begin
                if(btn_sync_1[i] != btn_stable[i]) begin
                    if(db_cnt[i] < DB_THRESHOLD) db_cnt[i] <= db_cnt[i] + 1;
                    else begin btn_stable[i] <= btn_sync_1[i]; db_cnt[i] <= 0; end
                end else db_cnt[i] <= 0;
            end
        end
    end

    wire btn_left = btn_stable[3]; wire btn_right = btn_stable[2];
    wire btn_jump = btn_stable[1]; wire btn_smash = btn_stable[0];

    // --- 物理邏輯 ---
    reg signed [10:0] vel_y; // [修正] 必須是 signed
    reg is_jumping;
    reg gravity_tick; // [修正] 減緩重力用

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pos_x <= 10'd50;
            pos_y <= GROUND_Y;
            vel_y <= 0; is_jumping <= 0; is_smash <= 0;
            gravity_tick <= 0;
        end else if (move_tick) begin
            
            // X 軸移動 (防穿牆)
            if (btn_left) begin
                if (pos_x >= LEFT_BOUND + MOVE_SPEED) pos_x <= pos_x - MOVE_SPEED;
                else pos_x <= LEFT_BOUND;
            end else if (btn_right && pos_x < RIGHT_BOUND) begin
                 pos_x <= pos_x + MOVE_SPEED;
            end

            // Y 軸移動
            if (is_jumping) begin
                pos_y <= pos_y + vel_y; 
                is_smash <= btn_smash;

                // [修正] 重力減速：每兩次 tick 加一次重力
                gravity_tick <= ~gravity_tick;
                if (gravity_tick == 1) begin
                    vel_y <= vel_y + GRAVITY;
                end

                // 落地判定
                if (pos_y >= GROUND_Y && vel_y > 0) begin 
                    pos_y <= GROUND_Y;
                    is_jumping <= 0;
                    vel_y <= 0;
                    is_smash <= 0;
                    gravity_tick <= 0;
                end
            end else begin
                is_smash <= 0;
                if (btn_jump) begin
                    is_jumping <= 1;
                    vel_y <= -JUMP_FORCE;
                    gravity_tick <= 0;
                end
            end
        end
    end
endmodule