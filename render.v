    `timescale 1ns / 1ps
    
    module render (
        input  wire        clk,
        input  wire        reset_n,
        
        // 物件座標輸入 (0~640)
        input  wire [9:0]  p1_x, p1_y, 
        input  wire [9:0]  p2_x, p2_y, 
        input  wire [9:0]  ball_x, ball_y, 
        
        // 分數輸入
        input  wire [3:0]  p1_score, 
        input  wire [3:0]  p2_score,
    
        input  wire usr_sw, // 控制 SRAM WE
        
        output reg         player_cover, // P1 接觸到球
        output reg         COM_cover,    // P2 (COM) 接觸到球
    
        // VGA 輸出
        output wire        vga_hs, vga_vs,
        output wire [3:0]  vga_r, vga_g, vga_b
    );
    
        // ------------------------------------------------------------------------
        // 1. PARAMETERS
        // ------------------------------------------------------------------------
        localparam VBUF_W = 320; 
        localparam VBUF_H = 240; 
        
        localparam PIKA_W = 64; 
        localparam PIKA_H = 64; 
        localparam BALL_W = 40; 
        localparam BALL_H = 40; 
        
        // 分數顯示設定
        localparam SCORE_W = 20; 
        localparam SCORE_H = 28;
    
        localparam NET_CENTER_X = 160;
        localparam NET_TOP_Y    = 240 - 90; // 150
        localparam NET_LEFT_X   = NET_CENTER_X - 3; // 157
        localparam NET_RIGHT_X  = NET_CENTER_X + 3; // 163
    
        localparam TRANS_COLOR = 12'h0F0; // 綠色透明
        localparam TEXT_COLOR  = 12'hF00; // 文字顏色 (紅)
        localparam NET_COLOR   = 12'hFDD; // 網子顏色 
    
        // ------------------------------------------------------------------------
        // 2. VGA CLOCK & SYNC
        // ------------------------------------------------------------------------
        wire vga_clk;         
        wire video_on;        
        wire pixel_tick;      
        wire [9:0] pixel_x, pixel_y;   
    
        clk_divider#(2) clk_div0 (.clk(clk), .reset(~reset_n), .clk_out(vga_clk));
    
        vga_sync vs0(
          .clk(vga_clk), .reset(~reset_n), 
          .oHS(vga_hs), .oVS(vga_vs),
          .visible(video_on), .p_tick(pixel_tick),
          .pixel_x(pixel_x), .pixel_y(pixel_y)
        );
    
        // ------------------------------------------------------------------------
        // 3. REGION & SRAM Signals
        // ------------------------------------------------------------------------
        wire [9:0] px = pixel_x >> 1;
        wire [9:0] py = pixel_y >> 1;
        wire [9:0] sx_p1 = p1_x >> 1; wire [9:0] sy_p1 = p1_y >> 1;
        wire [9:0] sx_p2 = p2_x >> 1; wire [9:0] sy_p2 = p2_y >> 1;
        wire [9:0] sx_ball = ball_x >> 1; wire [9:0] sy_ball = ball_y >> 1;
    
        wire region_p1, region_p2, region_ball, region_sc1, region_sc2, region_net;
    
        assign region_p1 = (px >= sx_p1 && px < sx_p1 + PIKA_W && py >= sy_p1 && py < sy_p1 + PIKA_H);
        assign region_p2 = (px >= sx_p2 && px < sx_p2 + PIKA_W && py >= sy_p2 && py < sy_p2 + PIKA_H);
        assign region_ball = (px >= sx_ball && px < sx_ball + BALL_W && py >= sy_ball && py < sy_ball + BALL_H);
        
        // 網子區域
        assign region_net = (px >= NET_LEFT_X && px < NET_RIGHT_X && py >= NET_TOP_Y);
    
        // 分數位置
        localparam SC1_X = 20;  localparam SC1_Y = 10;
        localparam SC2_X = 280; localparam SC2_Y = 10;
        
        assign region_sc1 = (px >= SC1_X && px < SC1_X + SCORE_W && py >= SC1_Y && py < SC1_Y + SCORE_H);
        assign region_sc2 = (px >= SC2_X && px < SC2_X + SCORE_W && py >= SC2_Y && py < SC2_Y + SCORE_H);
    
        // SRAM 訊號
        reg [17:0] addr_bg, addr_p1, addr_p2, addr_ball;
        wire [11:0] data_bg, data_p1, data_p2, data_ball;
        wire [11:0] data_zeros = 12'h000;
        wire sram_we = ~usr_sw; 
    
        // ------------------------------------------------------------------------
        // 4. SRAM INSTANCES
        // ------------------------------------------------------------------------
        
        // 背景
        sram #(.DATA_WIDTH(12), .ADDR_WIDTH(17), .RAM_SIZE(VBUF_W*VBUF_H), .FILE("bg.mem"))
          ram_bg_inst (.clk(clk), .we(sram_we), .en(1'b1), .addr(addr_bg[16:0]), .data_i(data_zeros), .data_o(data_bg));
    
        // P1
        sram #(.DATA_WIDTH(12), .ADDR_WIDTH(17), .RAM_SIZE(PIKA_W*PIKA_H), .FILE("pika.mem"))
          ram_p1_inst (.clk(clk), .we(sram_we), .en(1'b1), .addr(addr_p1[16:0]), .data_i(data_zeros), .data_o(data_p1));
    
        // P2
        sram #(.DATA_WIDTH(12), .ADDR_WIDTH(17), .RAM_SIZE(PIKA_W*PIKA_H), .FILE("pika.mem"))
          ram_p2_inst (.clk(clk), .we(sram_we), .en(1'b1), .addr(addr_p2[16:0]), .data_i(data_zeros), .data_o(data_p2));
    
        // 球
        sram #(.DATA_WIDTH(12), .ADDR_WIDTH(17), .RAM_SIZE(BALL_W*BALL_H), .FILE("ball.mem"))
          ram_ball_inst (.clk(clk), .we(sram_we), .en(1'b1), .addr(addr_ball[16:0]), .data_i(data_zeros), .data_o(data_ball));
    
        // ------------------------------------------------------------------------
        // 5. ADDRESS CALCULATION
        // ------------------------------------------------------------------------
        always @(posedge clk) begin
            // 背景
            addr_bg <= py * VBUF_W + px;
    
            // P1
            if (region_p1) 
                addr_p1 <= (py - sy_p1) * PIKA_W + (px - sx_p1);
            else 
                addr_p1 <= 0;
    
            // P2 (鏡像)
            if (region_p2) 
                addr_p2 <= (py - sy_p2) * PIKA_W + ((PIKA_W - 1) - (px - sx_p2));
            else 
                addr_p2 <= 0;
    
            // 球
            if (region_ball)
                addr_ball <= (py - sy_ball) * BALL_W + (px - sx_ball);
            else
                addr_ball <= 0;
        end
    
        // ------------------------------------------------------------------------
        // 6. LOGIC-BASED FONT GENERATOR
        // ------------------------------------------------------------------------
        function pixel_gen_digit;
    input [3:0] digit;
    input [2:0] x; // 0~4
    input [2:0] y; // 0~6
    reg [4:0] row_data;
    begin
        case (digit)
            // Number 0
            4'd0: case (y)
                0: row_data = 5'b01110;
                1: row_data = 5'b10001;
                2: row_data = 5'b10011;
                3: row_data = 5'b10101;
                4: row_data = 5'b11001;
                5: row_data = 5'b10001;
                6: row_data = 5'b01110;
                default: row_data = 0;
            endcase

            // Number 1
            4'd1: case (y)
                0: row_data = 5'b00100;
                1: row_data = 5'b01100;
                2: row_data = 5'b00100;
                3: row_data = 5'b00100;
                4: row_data = 5'b00100;
                5: row_data = 5'b00100;
                6: row_data = 5'b01110;
                default: row_data = 0;
            endcase

            // Number 2
            4'd2: case (y)
                0: row_data = 5'b01110;
                1: row_data = 5'b10001;
                2: row_data = 5'b00001;
                3: row_data = 5'b00010;
                4: row_data = 5'b00100;
                5: row_data = 5'b01000;
                6: row_data = 5'b11111;
                default: row_data = 0;
            endcase

            // Number 3
            4'd3: case (y)
                0: row_data = 5'b11110;
                1: row_data = 5'b00001;
                2: row_data = 5'b00001;
                3: row_data = 5'b01110;
                4: row_data = 5'b00001;
                5: row_data = 5'b00001;
                6: row_data = 5'b11110;
                default: row_data = 0;
            endcase

            // Number 4 (FIXED)
            4'd4: case (y)
                0: row_data = 5'b00010;
                1: row_data = 5'b00110;
                2: row_data = 5'b01010;
                3: row_data = 5'b10010;
                4: row_data = 5'b11111; // <-- middle bar
                5: row_data = 5'b00010;
                6: row_data = 5'b00010;
                default: row_data = 0;
            endcase

            // Number 5
            4'd5: case (y)
                0: row_data = 5'b11111;
                1: row_data = 5'b10000;
                2: row_data = 5'b10000;
                3: row_data = 5'b11110;
                4: row_data = 5'b00001;
                5: row_data = 5'b00001;
                6: row_data = 5'b11110;
                default: row_data = 0;
            endcase

            // Number 6
            4'd6: case (y)
                0: row_data = 5'b01110;
                1: row_data = 5'b10000;
                2: row_data = 5'b10000;
                3: row_data = 5'b11110;
                4: row_data = 5'b10001;
                5: row_data = 5'b10001;
                6: row_data = 5'b01110;
                default: row_data = 0;
            endcase

            // Number 7
            4'd7: case (y)
                0: row_data = 5'b11111;
                1: row_data = 5'b00001;
                2: row_data = 5'b00010;
                3: row_data = 5'b00100;
                4: row_data = 5'b01000;
                5: row_data = 5'b01000;
                6: row_data = 5'b01000;
                default: row_data = 0;
            endcase

            // Number 8
            4'd8: case (y)
                0: row_data = 5'b01110;
                1: row_data = 5'b10001;
                2: row_data = 5'b10001;
                3: row_data = 5'b01110;
                4: row_data = 5'b10001;
                5: row_data = 5'b10001;
                6: row_data = 5'b01110;
                default: row_data = 0;
            endcase

            // Number 9
            4'd9: case (y)
                0: row_data = 5'b01110;
                1: row_data = 5'b10001;
                2: row_data = 5'b10001;
                3: row_data = 5'b01111;
                4: row_data = 5'b00001;
                5: row_data = 5'b00001;
                6: row_data = 5'b01110;
                default: row_data = 0;
            endcase

            default: row_data = 0;
        endcase

        pixel_gen_digit = row_data[4-x];
    end
endfunction

    
        wire is_score1_pixel, is_score2_pixel;
        assign is_score1_pixel = region_sc1 ? pixel_gen_digit(p1_score, (px - SC1_X)>>2, (py - SC1_Y)>>2) : 1'b0;
        assign is_score2_pixel = region_sc2 ? pixel_gen_digit(p2_score, (px - SC2_X)>>2, (py - SC2_Y)>>2) : 1'b0;
    
        // ------------------------------------------------------------------------
        // 7. COLLISION & OVERLAP DETECTION (關鍵更新)
        // ------------------------------------------------------------------------
        
        // 定義當前像素是否為該物件的「實體」(非透明)
        // 注意：data_xx 是從 SRAM 讀出來的，會延遲 1-2 clocks，
        // 但在 25MHz 像素時脈下，這點誤差通常可以忽略，或者視為判定當前顯示像素。
        wire is_ball_pixel = region_ball && (data_ball != TRANS_COLOR);
        wire is_p1_pixel   = region_p1   && (data_p1   != TRANS_COLOR);
        wire is_p2_pixel   = region_p2   && (data_p2   != TRANS_COLOR);
    
        // 每一幀的開始 (VSync) 重置訊號
        // 在掃描過程中，如果發現重疊，就將訊號設為 1 並保持到下一幀
        always @(posedge clk) begin
            if (!reset_n) begin
                player_cover <= 0;
                COM_cover <= 0;
            end else if (pixel_y == 0 && pixel_x == 0) begin
                // 每一幀開始時清除 Flag
                player_cover <= 0;
                COM_cover <= 0;
            end else begin
                // 如果球的實體像素 與 P1 的實體像素 重疊
                if (is_ball_pixel && is_p1_pixel) 
                    player_cover <= 1; // Latch high for the frame
                
                // 如果球的實體像素 與 P2 的實體像素 重疊
                if (is_ball_pixel && is_p2_pixel)
                    COM_cover <= 1;    // Latch high for the frame
            end
        end
    
        // ------------------------------------------------------------------------
        // 8. RGB OUTPUT CONTROL
        // ------------------------------------------------------------------------
        reg [11:0] rgb_reg, rgb_next;
        assign {vga_r, vga_g, vga_b} = rgb_reg;
    
        always @(posedge clk) begin
            if (pixel_tick) rgb_reg <= rgb_next;
        end
    
        always @(*) begin
            if (~video_on)
                rgb_next = 12'h000;
            else begin
                // Layer 0: Scores
                if (is_score1_pixel || is_score2_pixel)         rgb_next = TEXT_COLOR;
                
                // Layer 1: Ball
                else if (is_ball_pixel)                         rgb_next = data_ball;
                
                // Layer 2: Player 1
                else if (is_p1_pixel)                           rgb_next = data_p1;
                
                // Layer 3: Player 2
                else if (is_p2_pixel)                           rgb_next = data_p2;
                
                // Layer 4: Net (更新尺寸)
                else if (region_net)                            rgb_next = NET_COLOR;
                
                // Layer 5: Background
                else                                            rgb_next = data_bg;
            end
        end
    
    endmodule
