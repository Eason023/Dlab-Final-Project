`timescale 1ns / 1ps

module render (
    input  wire        clk,
    input  wire        reset_n,
    
    // 物件座標輸入
    input  wire [9:0]  p1_x, p1_y, 
    input  wire [9:0]  p2_x, p2_y, 
    input  wire [9:0]  ball_x, ball_y, 
    
    // 分數輸入
    input  wire [3:0]  p1_score, 
    input  wire [3:0]  p2_score,

    // 遊戲狀態輸入
    input  wire [1:0]  game_state,

    input  wire usr_sw, 
    
    // 輸出重播狀態
    output wire        is_replaying_out,

    output reg         player_cover, 
    output reg         COM_cover,    

    output wire        vga_hs, vga_vs,
    output wire [3:0]  vga_r, vga_g, vga_b
);

    // ------------------------------------------------------------------------
    // 1. PARAMETERS
    // ------------------------------------------------------------------------
    localparam VBUF_W = 320; 
    localparam VBUF_H = 240; 
    localparam SCREEN_CX = 160;
    localparam SCREEN_CY = 120;
    
    localparam PIKA_W = 64; 
    localparam PIKA_H = 64; 
    localparam BALL_W = 40; 
    localparam BALL_H = 40; 
    
    localparam SCORE_W = 20; 
    localparam SCORE_H = 28;
    localparam SC1_X = 20;  localparam SC1_Y = 10;
    localparam SC2_X = 280; localparam SC2_Y = 10;

    localparam NET_CENTER_X = 160;
    localparam NET_TOP_Y    = 150; 
    localparam NET_LEFT_X   = NET_CENTER_X - 3;
    localparam NET_RIGHT_X  = NET_CENTER_X + 3;

    localparam TRANS_COLOR = 12'h0F0;
    localparam TEXT_COLOR  = 12'hF00;
    localparam NET_COLOR   = 12'hFDD;
    localparam BORDER_COLOR = 12'hF00;

    // ------------------------------------------------------------------------
    // 2. VGA CLOCK & SYNC & DELAY PIPELINE
    // ------------------------------------------------------------------------
    wire vga_clk;         
    wire video_on;        
    wire pixel_tick;      
    wire [9:0] pixel_x, pixel_y;   

    clk_divider#(2) clk_div0 (.clk(clk), .reset(~reset_n), .clk_out(vga_clk));

    wire raw_hs, raw_vs, raw_video_on;
    
    vga_sync vs0(
      .clk(vga_clk), .reset(~reset_n), 
      .oHS(raw_hs), .oVS(raw_vs),
      .visible(raw_video_on), .p_tick(pixel_tick),
      .pixel_x(pixel_x), .pixel_y(pixel_y)
    );

    reg [2:0] hs_d, vs_d, de_d; 
    
    always @(posedge clk) begin
        if (pixel_tick) begin
            hs_d <= {hs_d[1:0], raw_hs};
            vs_d <= {vs_d[1:0], raw_vs};
            de_d <= {de_d[1:0], raw_video_on};
        end
    end
    
    assign vga_hs = hs_d[2];
    assign vga_vs = vs_d[2];
    wire video_on_delayed = de_d[2];

    // ------------------------------------------------------------------------
    // 3. REPLAY SYSTEM (Ring Buffer)
    // ------------------------------------------------------------------------
    localparam RECORD_FRAMES = 60; 
    (* ram_style = "block" *) reg [59:0] replay_mem [0:511]; 
    
    reg [8:0] wr_ptr;
    reg [8:0] rd_ptr;
    
    reg prev_vs;
    wire vs_tick = (raw_vs && !prev_vs); 
    always @(posedge clk) if(reset_n) prev_vs <= raw_vs; else prev_vs <= 0;

    reg [3:0] p1_score_prev, p2_score_prev;
    reg is_replaying;      
    reg [8:0] replay_timer; 
    reg [1:0] slow_mo_cnt;

    assign is_replaying_out = is_replaying;

    wire state_allow_replay = game_state[1]; // 2(IN_GAME) or 3(GAME_OVER)
    wire score_trigger = state_allow_replay && 
                         ((p1_score > p1_score_prev) || (p2_score > p2_score_prev));

    always @(posedge clk) begin
        if (!reset_n) begin
            wr_ptr <= 0; rd_ptr <= 0;
            p1_score_prev <= 0; p2_score_prev <= 0;
            is_replaying <= 0; replay_timer <= 0; slow_mo_cnt <= 0;
        end else if (vs_tick) begin
            p1_score_prev <= p1_score;
            p2_score_prev <= p2_score;

            if (is_replaying) begin
                slow_mo_cnt <= slow_mo_cnt + 1;
                if (slow_mo_cnt == 2'b11) begin
                    rd_ptr <= rd_ptr + 1;
                    if (replay_timer == 0) begin
                        is_replaying <= 0; 
                        rd_ptr <= wr_ptr; 
                    end else begin
                        replay_timer <= replay_timer - 1;
                    end
                end
            end else begin
                slow_mo_cnt <= 0;
                replay_mem[wr_ptr] <= {p1_x, p1_y, p2_x, p2_y, ball_x, ball_y};
                wr_ptr <= wr_ptr + 1;
                
                if (score_trigger) begin
                    is_replaying <= 1;
                    replay_timer <= RECORD_FRAMES; 
                    rd_ptr <= wr_ptr - RECORD_FRAMES; 
                end
            end
        end
    end

    wire [59:0] replay_data_out = replay_mem[rd_ptr];

    wire [9:0] raw_p1_x, raw_p1_y;
    wire [9:0] raw_p2_x, raw_p2_y;
    wire [9:0] raw_ball_x, raw_ball_y;

    assign {raw_p1_x, raw_p1_y, raw_p2_x, raw_p2_y, raw_ball_x, raw_ball_y} = 
           (is_replaying) ? replay_data_out : {p1_x, p1_y, p2_x, p2_y, ball_x, ball_y};
    
    // ------------------------------------------------------------------------
    // 4. CAMERA & ZOOM LOGIC (Registered)
    // ------------------------------------------------------------------------
    wire signed [9:0] ball_cx = (raw_ball_x >> 1) + (BALL_W / 2); 
    wire signed [9:0] ball_cy = (raw_ball_y >> 1) + (BALL_H / 2); 
    reg signed [9:0] cam_x, cam_y;
    
    always @(posedge clk) begin
        if (!reset_n) begin
            cam_x <= 160; cam_y <= 120;
        end else if (vs_tick) begin
            if (ball_cx < 80)       cam_x <= 80;
            else if (ball_cx > 240) cam_x <= 240;
            else                    cam_x <= ball_cx;
            
            if (ball_cy < 60)       cam_y <= 60;
            else if (ball_cy > 180) cam_y <= 180;
            else                    cam_y <= ball_cy;
        end
    end

    wire signed [9:0] px = pixel_x >> 1;
    wire signed [9:0] py = pixel_y >> 1;
    
    // [修改] 使用 signed [11:0] 來避免負數座標 Wrap Around 問題
    reg signed [11:0] eff_px, eff_py; 

    always @(*) begin
        if (is_replaying) begin
            // 這裡加上 $signed 確保運算以有號數進行
            if (px >= SCREEN_CX) 
                eff_px = $signed({1'b0, cam_x}) + $signed({1'b0, (px - SCREEN_CX) >> 1});
            else 
                eff_px = $signed({1'b0, cam_x}) - $signed({1'b0, (SCREEN_CX - px) >> 1});
            
            if (py >= SCREEN_CY) 
                eff_py = $signed({1'b0, cam_y}) + $signed({1'b0, (py - SCREEN_CY) >> 1});
            else 
                eff_py = $signed({1'b0, cam_y}) - $signed({1'b0, (SCREEN_CY - py) >> 1});
        end else begin
            eff_px = $signed({2'b0, px});
            eff_py = $signed({2'b0, py});
        end
    end

    // ------------------------------------------------------------------------
    // 5. REGION DETECTION (Optimized with Signed Arithmetic)
    // ------------------------------------------------------------------------
    reg region_p1, region_p2, region_ball, region_net;
    reg region_sc1, region_sc2, region_border;

    // [修改] 物件座標轉為 signed [11:0]，方便與 eff_px 進行比較
    wire signed [11:0] sx_p1 = $signed({2'b0, raw_p1_x >> 1}); 
    wire signed [11:0] sy_p1 = $signed({2'b0, raw_p1_y >> 1});
    
    wire signed [11:0] sx_p2 = $signed({2'b0, raw_p2_x >> 1}); 
    wire signed [11:0] sy_p2 = $signed({2'b0, raw_p2_y >> 1});
    
    wire signed [11:0] sx_ball = $signed({2'b0, raw_ball_x >> 1}); 
    wire signed [11:0] sy_ball = $signed({2'b0, raw_ball_y >> 1});

    // 區域判定 (因為都是 signed，所以如果 eff_px 為負數，這裡會正確判定為 False 而不是很大的正數)
    wire r_p1 = (eff_px >= sx_p1 && eff_px < sx_p1 + PIKA_W && eff_py >= sy_p1 && eff_py < sy_p1 + PIKA_H);
    wire r_p2 = (eff_px >= sx_p2 && eff_px < sx_p2 + PIKA_W && eff_py >= sy_p2 && eff_py < sy_p2 + PIKA_H);
    wire r_ball = (eff_px >= sx_ball && eff_px < sx_ball + BALL_W && eff_py >= sy_ball && eff_py < sy_ball + BALL_H);
    
    // 網子判定也用 signed
    wire signed [11:0] s_net_lx = NET_LEFT_X;
    wire signed [11:0] s_net_rx = NET_RIGHT_X;
    wire signed [11:0] s_net_ty = NET_TOP_Y;
    wire r_net = (eff_px >= s_net_lx && eff_px < s_net_rx && eff_py >= s_net_ty);

    // UI 保持原樣 (因為 px, py 本來就是正的)
    wire r_sc1 = (px >= SC1_X && px < SC1_X + SCORE_W && py >= SC1_Y && py < SC1_Y + SCORE_H);
    wire r_sc2 = (px >= SC2_X && px < SC2_X + SCORE_W && py >= SC2_Y && py < SC2_Y + SCORE_H);
    wire r_border = is_replaying && (px < 4 || px > 316 || py < 4 || py > 236);

    // ------------------------------------------------------------------------
    // 6. ADDRESS CALCULATION & REGISTERING
    // ------------------------------------------------------------------------
    reg [17:0] addr_bg, addr_p1, addr_p2, addr_ball;
    
    always @(posedge clk) begin
        // Pipeline Stage 1: Register Region Flags
        region_p1 <= r_p1;
        region_p2 <= r_p2;
        region_ball <= r_ball;
        region_net <= r_net;
        region_sc1 <= r_sc1;
        region_sc2 <= r_sc2;
        region_border <= r_border;

        // Pipeline Stage 1: Address Calculation
        // 背景如果變成負的，地址可能會錯亂，但通常背景是靜態平鋪
        // 我們直接將 eff_px 轉回 unsigned 18位元計算即可，溢位部分反正也不會被顯示 (因為在螢幕外)
        addr_bg <= (eff_py << 8) + (eff_py << 6) + eff_px; 

        if (r_p1) 
            addr_p1 <= ((eff_py - sy_p1) << 6) + (eff_px - sx_p1);
        else 
            addr_p1 <= 0;

        if (r_p2) 
            addr_p2 <= ((eff_py - sy_p2) << 6) + ((PIKA_W - 1) - (eff_px - sx_p2));
        else 
            addr_p2 <= 0;

        if (r_ball) 
            addr_ball <= ((eff_py - sy_ball) << 5) + ((eff_py - sy_ball) << 3) + (eff_px - sx_ball);
        else 
            addr_ball <= 0;
    end

    // ------------------------------------------------------------------------
    // 7. SRAM INSTANCES
    // ------------------------------------------------------------------------
    wire [11:0] data_bg, data_p1, data_p2, data_ball;
    wire [11:0] data_zeros = 12'h000;
    wire sram_we = ~usr_sw; 

    sram #(.DATA_WIDTH(12), .ADDR_WIDTH(17), .RAM_SIZE(VBUF_W*VBUF_H), .FILE("bg.mem"))
      ram_bg_inst (.clk(clk), .we(sram_we), .en(1'b1), .addr(addr_bg[16:0]), .data_i(data_zeros), .data_o(data_bg));
    sram #(.DATA_WIDTH(12), .ADDR_WIDTH(17), .RAM_SIZE(PIKA_W*PIKA_H), .FILE("pika.mem"))
      ram_p1_inst (.clk(clk), .we(sram_we), .en(1'b1), .addr(addr_p1[16:0]), .data_i(data_zeros), .data_o(data_p1));
    sram #(.DATA_WIDTH(12), .ADDR_WIDTH(17), .RAM_SIZE(PIKA_W*PIKA_H), .FILE("pika.mem"))
      ram_p2_inst (.clk(clk), .we(sram_we), .en(1'b1), .addr(addr_p2[16:0]), .data_i(data_zeros), .data_o(data_p2));
    sram #(.DATA_WIDTH(12), .ADDR_WIDTH(17), .RAM_SIZE(BALL_W*BALL_H), .FILE("ball.mem"))
      ram_ball_inst (.clk(clk), .we(sram_we), .en(1'b1), .addr(addr_ball[16:0]), .data_i(data_zeros), .data_o(data_ball));

    // ------------------------------------------------------------------------
    // 8. FONT GENERATOR
    // ------------------------------------------------------------------------
    function pixel_gen_digit;
        input [3:0] digit;
        input [2:0] x; input [2:0] y;
        reg [4:0] row_data;
        begin
            case (digit)
                4'd0: case (y) 0:row_data=5'b01110; 1:row_data=5'b10001; 2:row_data=5'b10011; 3:row_data=5'b10101; 4:row_data=5'b11001; 5:row_data=5'b10001; 6:row_data=5'b01110; default:row_data=0; endcase
                4'd1: case (y) 0:row_data=5'b00100; 1:row_data=5'b01100; 2:row_data=5'b00100; 3:row_data=5'b00100; 4:row_data=5'b00100; 5:row_data=5'b00100; 6:row_data=5'b01110; default:row_data=0; endcase
                4'd2: case (y) 0:row_data=5'b01110; 1:row_data=5'b10001; 2:row_data=5'b00001; 3:row_data=5'b00010; 4:row_data=5'b00100; 5:row_data=5'b01000; 6:row_data=5'b11111; default:row_data=0; endcase
                4'd3: case (y) 0:row_data=5'b11110; 1:row_data=5'b00001; 2:row_data=5'b00001; 3:row_data=5'b01110; 4:row_data=5'b00001; 5:row_data=5'b00001; 6:row_data=5'b11110; default:row_data=0; endcase
                4'd4: case (y) 0:row_data=5'b00010; 1:row_data=5'b00110; 2:row_data=5'b01010; 3:row_data=5'b10010; 4:row_data=5'b11111; 5:row_data=5'b00010; 6:row_data=5'b00010; default:row_data=0; endcase
                4'd5: case (y) 0:row_data=5'b11111; 1:row_data=5'b10000; 2:row_data=5'b10000; 3:row_data=5'b11110; 4:row_data=5'b00001; 5:row_data=5'b00001; 6:row_data=5'b11110; default:row_data=0; endcase
                4'd6: case (y) 0:row_data=5'b01110; 1:row_data=5'b10000; 2:row_data=5'b10000; 3:row_data=5'b11110; 4:row_data=5'b10001; 5:row_data=5'b10001; 6:row_data=5'b01110; default:row_data=0; endcase
                4'd7: case (y) 0:row_data=5'b11111; 1:row_data=5'b00001; 2:row_data=5'b00010; 3:row_data=5'b00100; 4:row_data=5'b01000; 5:row_data=5'b01000; 6:row_data=5'b01000; default:row_data=0; endcase
                4'd8: case (y) 0:row_data=5'b01110; 1:row_data=5'b10001; 2:row_data=5'b10001; 3:row_data=5'b01110; 4:row_data=5'b10001; 5:row_data=5'b10001; 6:row_data=5'b01110; default:row_data=0; endcase
                4'd9: case (y) 0:row_data=5'b01110; 1:row_data=5'b10001; 2:row_data=5'b10001; 3:row_data=5'b01111; 4:row_data=5'b00001; 5:row_data=5'b00001; 6:row_data=5'b01110; default:row_data=0; endcase
                default: row_data = 0;
            endcase
            pixel_gen_digit = row_data[4-x];
        end
    endfunction
    
    wire is_score1_pixel = region_sc1 ? pixel_gen_digit(p1_score, (px - SC1_X)>>2, (py - SC1_Y)>>2) : 1'b0;
    wire is_score2_pixel = region_sc2 ? pixel_gen_digit(p2_score, (px - SC2_X)>>2, (py - SC2_Y)>>2) : 1'b0;

    // ------------------------------------------------------------------------
    // 9. COLLISION OUTPUT (To Game Logic)
    // ------------------------------------------------------------------------
    wire is_ball_pixel = region_ball && (data_ball != TRANS_COLOR);
    wire is_p1_pixel   = region_p1   && (data_p1   != TRANS_COLOR);
    wire is_p2_pixel   = region_p2   && (data_p2   != TRANS_COLOR);

    always @(posedge clk) begin
        if (!reset_n) begin
            player_cover <= 0;
            COM_cover <= 0;
        end else if (pixel_y == 0 && pixel_x == 0) begin
            player_cover <= 0;
            COM_cover <= 0;
        end else if (!is_replaying) begin 
            if (is_ball_pixel && is_p1_pixel) player_cover <= 1; 
            if (is_ball_pixel && is_p2_pixel) COM_cover <= 1;    
        end
    end

    // ------------------------------------------------------------------------
    // 10. OUTPUT MIXER
    // ------------------------------------------------------------------------
    reg [11:0] rgb_reg, rgb_next;
    assign {vga_r, vga_g, vga_b} = rgb_reg;

    always @(posedge clk) if (pixel_tick) rgb_reg <= rgb_next;

    always @(*) begin
        if (~video_on_delayed) 
            rgb_next = 12'h000;
        else begin
            if (is_score1_pixel || is_score2_pixel)         rgb_next = TEXT_COLOR;
            else if (region_border)                         rgb_next = BORDER_COLOR;
            
            else if (is_ball_pixel)                         rgb_next = data_ball;
            else if (is_p1_pixel)                           rgb_next = data_p1;
            else if (is_p2_pixel)                           rgb_next = data_p2;
            else if (region_net)                            rgb_next = NET_COLOR;
            else                                            rgb_next = data_bg;
        end
    end

endmodule