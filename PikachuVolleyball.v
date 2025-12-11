`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/05 15:17:37
// Design Name: 
// Module Name: PikachuVolleyball
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


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
  for(k=0; k<4; k=k+1)
  begin: db
    debounce btn_db0(
      .clk(clk),
      .btn_input(usr_btn[k]),
      .btn_output(db_one_pitch_btn[k])
    );
  end
endgenerate

reg [3:0] prev_sw;
always @(posedge clk) begin
  prev_sw <= usr_sw;
end

reg p1_op_move_left, p1_op_move_right, p1_op_jump, p1_is_smash;
reg p2_op_move_left, p2_op_move_right, p2_op_jump, p2_is_smash;
wire p1_cover;
wire p2_cover;

wire [9:0] nxt_ball_pos_x, nxt_ball_pos_y,
           nxt_p1_pos_x, nxt_p1_pos_y,
           nxt_p2_pos_x, nxt_p2_pos_y;
wire [3:0] p1_score, p2_score;
wire game_over;
wire [1:0] winner;

reg physic_en;

physic physic_engine(
    .clk(clk),
    .rst_n(reset_n),
    .en(physic_en),

    // P1 & P2 動作
    .p1_move_left(p1_op_move_left), .p1_move_right(p1_op_move_right), .p1_jump(p1_op_jump), .p1_smash(p1_is_smash),
    .p2_move_left(p2_op_move_left), .p2_move_right(p2_op_move_right), .p2_jump(p2_op_jump), .p2_smash(p2_is_smash),
    
    // 碰撞偵測 (Render 傳入，精確碰撞)
    .p1_cover(p1_cover), 
    .p2_cover(p2_cover), 

    // next xy
    .p1_pos_x(nxt_p1_pos_x), .p1_pos_y(nxt_p1_pos_y),
    .p2_pos_x(nxt_p2_pos_x), .p2_pos_y(nxt_p2_pos_y),
    .ball_pos_x(nxt_ball_pos_x), .ball_pos_y(nxt_ball_pos_y),
    
    .game_over(game_over),
    .winner(winner),
    .valid()
);

wire nxt_p2_op_move_left, nxt_p2_op_move_right, nxt_p2_op_jump, nxt_p2_is_smash;

com_player com_p2 (
    .clk(clk),
    .rst_n(reset_n),
    // xy input
    .ball_x(display_ball_pos_x),
    .ball_y(display_ball_pos_y),
    .my_pos_x(display_p2_x), 
    .my_pos_y(display_p2_y),
    // op output
    .op_move_left(nxt_p2_op_move_left),
    .op_move_right(nxt_p2_op_move_right),
    .op_jump(nxt_p2_op_jump),
    .op_smash(nxt_p2_is_smash)
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

localparam [31:0] frame_clk = (100000000/60); // 60hz
reg [31:0] frame_time_cnt;
wire frame_pitch = (frame_time_cnt==frame_clk);
always @(posedge clk) begin
    frame_time_cnt <= (frame_time_cnt==frame_clk ? 20'd0 : frame_time_cnt + 20'd1);
end

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
        display_ball_pos_x <= 10'd280;
        display_ball_pos_y <= 10'd150;
        display_p1_x <= 10'd60;
        display_p1_y <= 10'd320;
        display_p2_x <= 10'd452;
        display_p2_y <= 10'd320;
        if(db_one_pitch_btn[1])
          score_mode <= (score_mode!=2'd3 ? score_mode+2'd1 : score_mode);
        else if(db_one_pitch_btn[0])
          score_mode <= (score_mode!=2'd0 ? score_mode-2'd1 : score_mode);
        // p1
        p1_is_smash <= 1'b0;
        p1_op_move_left <= 1'b0;
        p1_op_jump <= 1'b0;
        p1_op_move_right <= 1'b0;
        // p2
        p2_is_smash <= 1'b0;
        p2_op_move_left <= 1'b0;
        p2_op_jump <= 1'b0;
        p2_op_move_right <= 1'b0;
        if(usr_sw[2] != prev_sw[2]) begin
          game_state <= IN_GAME;
          display_p1_score <= 4'd0;
          display_p2_score <= 4'd0;
        end else
          display_p2_score <= win_score;
      end
      IN_GAME: begin
        if(frame_pitch) begin
          physic_en <= 1'b1;
          p1_is_smash <= usr_btn[3];
          p1_op_move_left <= usr_btn[2];
          p1_op_jump <= usr_btn[1];
          p1_op_move_right <= usr_btn[0];
          p2_op_move_left <= nxt_p2_op_move_left;
          p2_op_move_right <= nxt_p2_op_move_right;
          p2_op_jump <= nxt_p2_op_jump;
          p2_is_smash <= nxt_p2_is_smash;
          //display
          display_p1_x <= nxt_p1_pos_x; display_p1_y <= nxt_p1_pos_y;
          display_p2_x <= nxt_p2_pos_x; display_p2_y  <= nxt_p2_pos_y;
          display_ball_pos_x <= nxt_ball_pos_x; display_ball_pos_y <= nxt_ball_pos_y;
          if(game_over && winner==2'd1)
            display_p1_score <= display_p1_score + 4'd1;
          if(game_over && winner==2'd2)
            display_p2_score <= display_p2_score + 4'd1;
          if(display_p1_score == win_score || display_p2_score == win_score) begin
            game_state <= GAME_OVER;
          end
        end else 
          physic_en <= 1'b0;
      end
      GAME_OVER: begin
      end
    endcase
  end
end

render scene_display (
    .clk(clk),
    .reset_n(reset_n),
    
    // 物件座標輸入 (0~640)
    .p1_x(display_p1_x), .p1_y(display_p1_y), 
    .p2_x(display_p2_x), .p2_y(display_p2_y), 
    .ball_x(display_ball_pos_x), .ball_y(display_ball_pos_y), 
    
    // 分數輸入
    .p1_score(display_p1_score),
    .p2_score(display_p2_score),

    .usr_sw(usr_sw[3]), // 控制 SRAM WE
    
    .player_cover(p1_cover), // P1 接觸到球
    .COM_cover(p2_cover),    // P2 (COM) 接觸到球

    // VGA 輸出
    .vga_hs(VGA_HSYNC), .vga_vs(VGA_VSYNC),
    .vga_r(VGA_RED), .vga_g(VGA_GREEN), .vga_b(VGA_BLUE)
);

endmodule
