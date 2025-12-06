module main_player (
    input wire clk,
    input wire rst_n,
    input wire [3:0] usr_btn, // 原始按鍵輸入: [3]L [2]R [1]J [0]S
    
    // 輸出操作指令 (給 physic 模組用)
    output wire op_move_left,
    output wire op_move_right,
    output wire op_jump,
    output wire op_smash
);

    // --- Debounce 參數 ---
    // 假設系統時脈 100MHz，5ms 去彈跳時間 => 500,000 cycles
    localparam DB_THRESHOLD = 20'd500_000; 
    
    reg [3:0] btn_stable;   // 去彈跳後的穩定狀態
    reg [3:0] btn_sync_0;   // 同步暫存器 0
    reg [3:0] btn_sync_1;   // 同步暫存器 1
    reg [19:0] db_cnt [3:0]; // 每個按鍵獨立的計數器
    
    integer i;

    // --- 1. Debounce 邏輯 (負責過濾雜訊) ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_stable <= 4'b0000;
            btn_sync_0 <= 4'b0000;
            btn_sync_1 <= 4'b0000;
            for(i=0; i<4; i=i+1) db_cnt[i] <= 20'd0;
        end else begin
            // 避免亞穩態 (Metastability) 的雙層同步
            btn_sync_0 <= usr_btn;
            btn_sync_1 <= btn_sync_0;

            for(i=0; i<4; i=i+1) begin
                if(btn_sync_1[i] != btn_stable[i]) begin
                    // 如果輸入狀態與目前穩定狀態不同，開始計數
                    if(db_cnt[i] < DB_THRESHOLD) begin
                        db_cnt[i] <= db_cnt[i] + 1;
                    end else begin
                        // 計數達到門檻，確認訊號穩定，更新狀態
                        btn_stable[i] <= btn_sync_1[i];
                        db_cnt[i] <= 0;
                    end
                end else begin
                    // 如果輸入跳回原狀態，重置計數器
                    db_cnt[i] <= 0;
                end
            end
        end
    end

    // --- 2. 輸出映射 (Mapping) ---
    // 將穩定後的 btn_stable 映射到具體的操作訊號
    // 假設 btn 為高電位觸發 (按下去是 1)，如果是低電位觸發請加 ~ 取反
    assign op_move_left  = btn_stable[3];
    assign op_move_right = btn_stable[2];
    assign op_jump       = btn_stable[1];
    assign op_smash      = btn_stable[0];

endmodule
