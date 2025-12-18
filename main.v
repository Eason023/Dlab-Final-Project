module PikachuVolleyball(
    input  clk,
    input  reset_n,
    input  [3:0] usr_btn,
    input  [3:0] usr_sw,
    output [3:0] usr_led,
    
    // VGA specific I/O ports
    output VGA_HSYNC, 
    output VGA_VSYNC,
    output [3:0] VGA_RED,
    output [3:0] VGA_GREEN,
    output [3:0] VGA_BLUE
    );

reg [1:0] game_state = 2'd0;
localparam INIT = 0, READY = 1, IN_GAME = 2, GAME_OVER = 3;

wire [3:0] db_one_pitch_btn;
genvar k;
generate
  for(k=0; k<4; k=k+1) begin: db
    debounce btn_db0(.clk(clk), .btn_input(usr_btn[k]), .btn_output(db_one_pitch_btn[k]));
  end
endgenerate

reg [3:0] prev_sw;
always @(posedge clk) prev_sw <= usr_sw;

reg p1_op_move_left, p1_op_move_right, p1_op_jump, p1_is_smash;
reg p2_op_move_left, p2_op_move_right, p2_op_jump, p2_is_smash;
wire p1_cover, p2_cover;

wire [9:0] nxt_ball_pos_x, nxt_ball_pos_y, nxt_p1_pos_x, nxt_p1_pos_y, nxt_p2_pos_x, nxt_p2_pos_y;
wire [3:0] p1_score; // Not used directly, using display vars
wire game_over;
wire [1:0] winner;

reg physic_en;
wire is_replay; // [新增] 從 Render 接收

// 物理引擎控制邏輯 [重要]
// 重播時暫停，但若是 Game Over 那瞬間必須跑一幀以 Reset 球的位置
always @(posedge clk) begin
    if(frame_pitch) begin
        // 若正在重播且"不是"剛結束的那一幀(game_over flag還在)，則暫停
        // 注意：game_over 訊號來自 physic，當球落地時為 1，下一幀 physic 執行後會清 0
        if(is_replay && !game_over)
            physic_en <= 1'b0;
        else
            physic_en <= 1'b1;
    end else 
        physic_en <= 1'b0;
end

physic physic_engine(
    .clk(clk), .rst_n(reset_n), .en(physic_en), 
    .p1_move_left(p1_op_move_left), .p1_move_right(p1_op_move_right), .p1_jump(p1_op_jump), .p1_smash(p1_is_smash),
    .p2_move_left(p2_op_move_left), .p2_move_right(p2_op_move_right), .p2_jump(p2_op_jump), .p2_smash(p2_is_smash),
    .p1_cover(p1_cover), .p2_cover(p2_cover), 
    .p1_pos_x(nxt_p1_pos_x), .p1_pos_y(nxt_p1_pos_y),
    .p2_pos_x(nxt_p2_pos_x), .p2_pos_y(nxt_p2_pos_y),
    .ball_pos_x(nxt_ball_pos_x), .ball_pos_y(nxt_ball_pos_y),
    .game_over(game_over), .winner(winner), .valid()
);

wire nxt_p2_op_move_left, nxt_p2_op_move_right, nxt_p2_op_jump, nxt_p2_is_smash;

// COM Player
com_player com_p2 (
    .clk(clk), .rst_n(reset_n),
    .ball_x(display_ball_pos_x), .ball_y(display_ball_pos_y),
    .my_pos_x(display_p2_x), .my_pos_y(display_p2_y),
    .op_move_left(nxt_p2_op_move_left), .op_move_right(nxt_p2_op_move_right),
    .op_jump(nxt_p2_op_jump), .op_smash(nxt_p2_is_smash)
);

reg [1:0] score_mode;
reg [3:0] win_score;
always @(*) begin
  case(score_mode)
    2'd0: win_score = 4'd3;
    2'd1: win_score = 4'd5;
    2'd2: win_score = 4'd7;
    2'd3: win_score = 4'd9;
  endcase
end

reg [9:0] display_p1_x, display_p1_y;
reg [9:0] display_p2_x, display_p2_y;
reg [9:0] display_ball_pos_x, display_ball_pos_y;
reg [3:0] display_p1_score, display_p2_score;

localparam [31:0] frame_clk = (100000000/60); 
reg [31:0] frame_time_cnt;
wire frame_pitch = (frame_time_cnt==frame_clk);
always @(posedge clk) frame_time_cnt <= (frame_time_cnt==frame_clk ? 20'd0 : frame_time_cnt + 20'd1);

always @(posedge clk) begin
  if(~reset_n)begin
    game_state <= INIT;
  end else begin
    case(game_state)
      INIT: begin
        score_mode <= 2'd0;
        game_state <= READY;
        display_p1_score <= 4'd0;
        display_p2_score <= 4'd0;
      end
      READY: begin
        display_ball_pos_x <= 10'd280; display_ball_pos_y <= 10'd150;
        display_p1_x <= 10'd60; display_p1_y <= 10'd320;
        display_p2_x <= 10'd452; display_p2_y <= 10'd320;
        
        if(db_one_pitch_btn[1]) score_mode <= (score_mode!=2'd3 ? score_mode+2'd1 : score_mode);
        else if(db_one_pitch_btn[0]) score_mode <= (score_mode!=2'd0 ? score_mode-2'd1 : score_mode);
        
        // Reset Inputs
        p1_is_smash <= 0; p1_op_move_left <= 0; p1_op_jump <= 0; p1_op_move_right <= 0;
        p2_is_smash <= 0; p2_op_move_left <= 0; p2_op_jump <= 0; p2_op_move_right <= 0;
        
        if(usr_sw[2] != prev_sw[2]) begin
          game_state <= IN_GAME;
          display_p1_score <= 4'd0;
          display_p2_score <= 4'd0; 
        end else
          display_p2_score <= win_score;
      end
      IN_GAME: begin
        if(frame_pitch) begin  
          // Input assignments
          p1_is_smash <= usr_btn[3]; p1_op_move_left <= usr_btn[1]; p1_op_jump <= usr_btn[2]; p1_op_move_right <= usr_btn[0];
          p2_op_move_left <= nxt_p2_op_move_left; p2_op_move_right <= nxt_p2_op_move_right;
          p2_op_jump <= nxt_p2_op_jump; p2_is_smash <= nxt_p2_is_smash;
          
          // Display update
          display_p1_x <= nxt_p1_pos_x; display_p1_y <= nxt_p1_pos_y;
          display_p2_x <= nxt_p2_pos_x; display_p2_y  <= nxt_p2_pos_y;
          display_ball_pos_x <= nxt_ball_pos_x; display_ball_pos_y <= nxt_ball_pos_y;
          
          // Score Update (Protected by is_replay to avoid double counting)
          if(!is_replay && game_over && winner==2'd1)
            display_p1_score <= display_p1_score + 4'd1;
          if(!is_replay && game_over && winner==2'd2)
            display_p2_score <= display_p2_score + 4'd1;
            
          if(display_p1_score == win_score || display_p2_score == win_score) begin
            game_state <= GAME_OVER;
          end
        end 
      end
      GAME_OVER: begin
      end
    endcase
  end
end

render scene_display (
    .clk(clk), .reset_n(reset_n),
    
    .game_state(game_state),       // [新增] 傳入 State
    .is_replaying_out(is_replay),  // [新增] 接收 Replay 狀態
    
    .p1_x(display_p1_x), .p1_y(display_p1_y), 
    .p2_x(display_p2_x), .p2_y(display_p2_y), 
    .ball_x(display_ball_pos_x), .ball_y(display_ball_pos_y), 
    
    .p1_score(display_p1_score),
    .p2_score(display_p2_score),
 
    .usr_sw(usr_sw[3]), 
    .player_cover(p1_cover),    
    .COM_cover(p2_cover), 

    .vga_hs(VGA_HSYNC), .vga_vs(VGA_VSYNC),
    .vga_r(VGA_RED), .vga_g(VGA_GREEN), .vga_b(VGA_BLUE)
);   

endmodule