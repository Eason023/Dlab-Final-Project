module com_player (
    input wire clk, // 接到 game_clk (30Hz)
    input wire rst_n,
    input wire [9:0] ball_x,
    input wire [9:0] ball_y,
    output reg [9:0] pos_x,
    output reg [9:0] pos_y,
    output reg is_smash
);
    localparam GROUND_Y    = 10'd176; 
    localparam LEFT_BOUND  = 10'd165;
    localparam RIGHT_BOUND = 10'd256;
    localparam CENTER_X    = 10'd210;
    
    localparam MOVE_SPEED = 10'd3;
    localparam JUMP_FORCE = 10'd14;
    localparam GRAVITY    = 10'd1;
    localparam TOLERANCE  = 10'd5;

    reg signed [10:0] vel_y;
    reg is_jumping;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pos_x <= CENTER_X; pos_y <= GROUND_Y;
            vel_y <= 0; is_jumping <= 0; is_smash <= 0;
        end else begin
            // X AI
            if (ball_x > 10'd160) begin
                if (ball_x > pos_x + TOLERANCE && pos_x < RIGHT_BOUND) pos_x <= pos_x + MOVE_SPEED;
                else if (ball_x < pos_x - TOLERANCE && pos_x > LEFT_BOUND) pos_x <= pos_x - MOVE_SPEED;
            end else begin
                if (pos_x > CENTER_X + TOLERANCE) pos_x <= pos_x - MOVE_SPEED;
                else if (pos_x < CENTER_X - TOLERANCE) pos_x <= pos_x - MOVE_SPEED;
            end

            // Y AI
            if (is_jumping) begin
                pos_y <= pos_y + vel_y;
                vel_y <= vel_y + GRAVITY;

                if ((ball_x > pos_x - 20 && ball_x < pos_x + 20) && (ball_y > pos_y - 40 && ball_y < pos_y + 40))
                    is_smash <= 1'b1;
                else is_smash <= 1'b0;

                if (pos_y >= GROUND_Y && vel_y > 0) begin
                    pos_y <= GROUND_Y; is_jumping <= 0; vel_y <= 0; is_smash <= 0;
                end
            end else begin
                is_smash <= 0;
                if (ball_x > 10'd160 && (ball_x > pos_x - 30 && ball_x < pos_x + 30) && (ball_y < 10'd200)) begin
                    is_jumping <= 1;
                    vel_y <= -JUMP_FORCE;
                end
            end
        end
    end
endmodule