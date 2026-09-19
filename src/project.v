/* Port-Hardened Sokoban Core (10 Levels, Fully Verified Geometry)
 * Copyright (c) 2026 AbAdA
 * SPDX-License-Identifier: Apache-2.0
 */
`default_nettype none

module tt_um_AbAdA_2048 (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

  // --------------------------------------------------------------------------
  // RESET SYNCHRONIZER
  // --------------------------------------------------------------------------
  reg rst_sync_0;
  reg rst_sync_1;
  always @(posedge clk) begin
    if (!rst_n) begin
      rst_sync_0 <= 1'b1;
      rst_sync_1 <= 1'b1;
    end else begin
      rst_sync_0 <= 1'b0;
      rst_sync_1 <= rst_sync_0;
    end
  end
  wire sys_rst = rst_sync_1;

  assign uio_out = 8'b0;
  assign uio_oe  = 8'b0;

  // --------------------------------------------------------------------------
  // HARDWARE INPUT DEFINITIONS & SYNC GENERATOR
  // --------------------------------------------------------------------------
  wire btn_left_in  = ui_in[0];
  wire btn_right_in = ui_in[1];
  wire btn_up_in    = ui_in[2];
  wire btn_down_in  = ui_in[3];
  wire btn_start_in = ui_in[7];
  wire _unused_ok = &{ena, uio_in};

  wire        hsync_w, vsync_w, video_active_w;
  wire [9:0]  pix_x, pix_y;

  hvsync_generator vga_sync_gen (
      .clk        (clk),
      .reset      (sys_rst),
      .hsync      (hsync_w),
      .vsync      (vsync_w),
      .display_on (video_active_w),
      .hpos       (pix_x),
      .vpos       (pix_y)
  );

  // --------------------------------------------------------------------------
  // HARDENED OUTPUT REGISTERS
  // --------------------------------------------------------------------------
  (* keep = "true" *) reg        r_out_hsync, r_out_vsync;
  (* keep = "true" *) reg [1:0]  r_out_R, r_out_G, r_out_B;

  assign uo_out[7] = r_out_hsync;
  assign uo_out[6] = r_out_B[0];
  assign uo_out[5] = r_out_G[0];
  assign uo_out[4] = r_out_R[0];
  assign uo_out[3] = r_out_vsync;
  assign uo_out[2] = r_out_B[1];
  assign uo_out[1] = r_out_G[1];
  assign uo_out[0] = r_out_R[1];

  reg r_va0, r_va1, r_va2, r_va3;
  reg r_hs0, r_hs1, r_hs2, r_hs3;
  reg r_vs0, r_vs1, r_vs2, r_vs3;

  always @(posedge clk) begin
    r_va0 <= video_active_w; r_va1 <= r_va0; r_va2 <= r_va1; r_va3 <= r_va2;
    r_hs0 <= hsync_w;        r_hs1 <= r_hs0; r_hs2 <= r_hs1; r_hs3 <= r_hs2;
    r_vs0 <= vsync_w;        r_vs1 <= r_vs0; r_vs2 <= r_vs1; r_vs3 <= r_vs2;
  end

  // --------------------------------------------------------------------------
  // GAMEPAD PMOD INPUT SYNCHRONIZER
  // --------------------------------------------------------------------------
  reg r_pmod_data_0, r_pmod_data_1;
  always @(posedge clk) begin
    if (sys_rst) begin
      r_pmod_data_0 <= 1'b0;
      r_pmod_data_1 <= 1'b0;
    end else begin
      r_pmod_data_0 <= ui_in[6];
      r_pmod_data_1 <= r_pmod_data_0;
    end
  end

  wire raw_up, raw_down, raw_left, raw_right, raw_start;
  wire _unused_buttons;
  wire _unused_y, _unused_select;
  wire _unused_a, _unused_x, _unused_l, _unused_r, _unused_is_present;

  gamepad_pmod_single driver (
      .rst_n      (~sys_rst),
      .clk        (clk),
      .pmod_data  (r_pmod_data_1),
      .pmod_clk   (ui_in[5]),
      .pmod_latch (ui_in[4]),
      .b          (_unused_buttons),
      .y(_unused_y), .select(_unused_select), .start(raw_start),
      .up(raw_up), .down(raw_down), .left(raw_left), .right(raw_right),
      .a(_unused_a), .x(_unused_x), .l(_unused_l), .r(_unused_r),
      .is_present(_unused_is_present)
  );

  // --------------------------------------------------------------------------
  // INPUT SYNCHRONIZERS
  // --------------------------------------------------------------------------
  reg sync_up_0, sync_up_1, sync_down_0, sync_down_1;
  reg sync_left_0, sync_left_1, sync_right_0, sync_right_1, sync_start_0, sync_start_1;

  always @(posedge clk) begin
    if (sys_rst) begin
      sync_up_0 <= 0; sync_up_1 <= 0; sync_down_0 <= 0; sync_down_1 <= 0;
      sync_left_0 <= 0; sync_left_1 <= 0; sync_right_0 <= 0; sync_right_1 <= 0;
      sync_start_0 <= 0; sync_start_1 <= 0;
    end else begin
      sync_up_0    <= raw_up    | btn_up_in;    sync_up_1    <= sync_up_0;
      sync_down_0  <= raw_down  | btn_down_in;  sync_down_1  <= sync_down_0;
      sync_left_0  <= raw_left  | btn_left_in;  sync_left_1  <= sync_left_0;
      sync_right_0 <= raw_right | btn_right_in; sync_right_1 <= sync_right_0;
      sync_start_0 <= raw_start | btn_start_in; sync_start_1 <= sync_start_0;
    end
  end

  reg prev_up, prev_down, prev_left, prev_right, prev_start;
  wire press_up    = sync_up_1    & ~prev_up;
  wire press_down  = sync_down_1  & ~prev_down;
  wire press_left  = sync_left_1  & ~prev_left;
  wire press_right = sync_right_1 & ~prev_right;
  wire press_start = sync_start_1 & ~prev_start;

  // --------------------------------------------------------------------------
  // SOKOBAN DISCRETE STATE (10 Levels)
  // --------------------------------------------------------------------------
  reg [3:0] current_level;
  
  reg [3:0] p_x, p_y;
  reg [3:0] b0_x, b0_y, b1_x, b1_y, b2_x, b2_y;
  reg b0_active, b1_active, b2_active;

  task init_level;
    input [3:0] lvl;
    begin
      case (lvl)
        4'd0: begin 
            p_x <= 6; p_y <= 5;
            b0_x <= 7; b0_y <= 5; b0_active <= 1;
            b1_active <= 0; b2_active <= 0;
        end
        4'd1: begin 
            p_x <= 4; p_y <= 4;
            b0_x <= 5; b0_y <= 5; b0_active <= 1;
            b1_x <= 6; b1_y <= 6; b1_active <= 1;
            b2_active <= 0;
        end
        4'd2: begin 
            p_x <= 3; p_y <= 5;
            b0_x <= 4; b0_y <= 5; b0_active <= 1; 
            b1_x <= 5; b1_y <= 4; b1_active <= 1; 
            b2_x <= 5; b2_y <= 6; b2_active <= 1; 
        end
        4'd3: begin 
            p_x <= 3; p_y <= 5;
            b0_x <= 4; b0_y <= 4; b0_active <= 1;
            b1_x <= 4; b1_y <= 7; b1_active <= 1;
            b2_active <= 0;
        end
        4'd4: begin 
            p_x <= 4; p_y <= 6;
            b0_x <= 5; b0_y <= 6; b0_active <= 1;
            b1_x <= 6; b1_y <= 5; b1_active <= 1;
            b2_x <= 6; b2_y <= 7; b2_active <= 1;
        end
        4'd5: begin 
            p_x <= 3; p_y <= 5;
            b0_x <= 5; b0_y <= 4; b0_active <= 1;
            b1_x <= 5; b1_y <= 5; b1_active <= 1;
            b2_x <= 5; b2_y <= 6; b2_active <= 1;
        end
        4'd6: begin 
            p_x <= 3; p_y <= 5;
            b0_x <= 7; b0_y <= 4; b0_active <= 1;
            b1_x <= 7; b1_y <= 5; b1_active <= 1;
            b2_x <= 7; b2_y <= 6; b2_active <= 1;
        end
        4'd7: begin 
            p_x <= 4; p_y <= 8;
            b0_x <= 6; b0_y <= 6; b0_active <= 1;
            b1_x <= 7; b1_y <= 6; b1_active <= 1;
            b2_x <= 8; b2_y <= 6; b2_active <= 1;
        end
        4'd8: begin // Level 9 (The Core) - REDESIGNED
            p_x <= 3; p_y <= 5;
            b0_x <= 5; b0_y <= 4; b0_active <= 1;
            b1_x <= 5; b1_y <= 5; b1_active <= 1;
            b2_x <= 5; b2_y <= 6; b2_active <= 1;
        end
        4'd9: begin // Level 10 (The Vault) - REDESIGNED
            p_x <= 4; p_y <= 5;
            b0_x <= 5; b0_y <= 4; b0_active <= 1;
            b1_x <= 6; b1_y <= 5; b1_active <= 1;
            b2_x <= 5; b2_y <= 6; b2_active <= 1;
        end
        default: begin
            p_x <= 6; p_y <= 5;
            b0_active <= 0; b1_active <= 0; b2_active <= 0;
        end
      endcase
    end
  endtask

  // --------------------------------------------------------------------------
  // GAME ENGINE COMBINATIONAL QUERIES
  // --------------------------------------------------------------------------
  reg [3:0]  d_x, d_y;
  wire [3:0] t_x = p_x + d_x; // Target X
  wire [3:0] t_y = p_y + d_y; // Target Y
  wire [3:0] b_x = t_x + d_x; // Behind Target X (for pushing)
  wire [3:0] b_y = t_y + d_y; // Behind Target Y

  wire t_is_wall;
  level_map m_t(.level(current_level), .x(t_x), .y(t_y), .is_wall(t_is_wall), .is_goal());

  wire b_is_wall;
  level_map m_b(.level(current_level), .x(b_x), .y(b_y), .is_wall(b_is_wall), .is_goal());

  wire t_has_box0 = b0_active && (t_x == b0_x && t_y == b0_y);
  wire t_has_box1 = b1_active && (t_x == b1_x && t_y == b1_y);
  wire t_has_box2 = b2_active && (t_x == b2_x && t_y == b2_y);
  wire t_has_any_box = t_has_box0 | t_has_box1 | t_has_box2;

  wire b_has_box0 = b0_active && (b_x == b0_x && b_y == b0_y);
  wire b_has_box1 = b1_active && (b_x == b1_x && b_y == b1_y);
  wire b_has_box2 = b2_active && (b_x == b2_x && b_y == b2_y);
  wire b_has_any_box = b_has_box0 | b_has_box1 | b_has_box2;

  wire b0_on_goal, b1_on_goal, b2_on_goal;
  level_map m_b0_check(.level(current_level), .x(b0_x), .y(b0_y), .is_wall(), .is_goal(b0_on_goal));
  level_map m_b1_check(.level(current_level), .x(b1_x), .y(b1_y), .is_wall(), .is_goal(b1_on_goal));
  level_map m_b2_check(.level(current_level), .x(b2_x), .y(b2_y), .is_wall(), .is_goal(b2_on_goal));

  wire win_condition = (!b0_active || b0_on_goal) && 
                       (!b1_active || b1_on_goal) && 
                       (!b2_active || b2_on_goal);

  reg eval_move, check_win_flag;

  always @(posedge clk) begin
    if (sys_rst) begin
      prev_up <= 0; prev_down <= 0; prev_left <= 0; prev_right <= 0; prev_start <= 0;
      eval_move <= 1'b0; check_win_flag <= 1'b0;
      d_x <= 0; d_y <= 0;
      current_level <= 4'd0;
      init_level(4'd0);
    end else begin
      prev_up    <= sync_up_1; prev_down  <= sync_down_1;
      prev_left  <= sync_left_1; prev_right <= sync_right_1;
      prev_start <= sync_start_1;

      if (press_start) begin
          init_level(current_level); // Restart
          eval_move <= 1'b0; check_win_flag <= 1'b0;
      end else if (check_win_flag) begin
          if (win_condition) begin
              current_level <= (current_level == 4'd9) ? 4'd0 : current_level + 4'd1;
              init_level((current_level == 4'd9) ? 4'd0 : current_level + 4'd1);
          end
          check_win_flag <= 1'b0;
      end else if (eval_move) begin
          if (!t_is_wall) begin
              if (t_has_any_box) begin
                  if (!b_is_wall && !b_has_any_box) begin
                      p_x <= t_x; p_y <= t_y;
                      if (t_has_box0) begin b0_x <= b_x; b0_y <= b_y; end
                      if (t_has_box1) begin b1_x <= b_x; b1_y <= b_y; end
                      if (t_has_box2) begin b2_x <= b_x; b2_y <= b_y; end
                      check_win_flag <= 1'b1;
                  end
              end else begin
                  p_x <= t_x; p_y <= t_y;
                  check_win_flag <= 1'b1;
              end
          end
          eval_move <= 1'b0;
      end else begin
          if (press_up) begin
              d_x <= 4'd0; d_y <= 4'b1111; eval_move <= 1'b1;
          end else if (press_down) begin
              d_x <= 4'd0; d_y <= 4'd1;    eval_move <= 1'b1;
          end else if (press_left) begin
              d_x <= 4'b1111; d_y <= 4'd0; eval_move <= 1'b1;
          end else if (press_right) begin
              d_x <= 4'd1; d_y <= 4'd0;    eval_move <= 1'b1;
          end
      end
    end
  end

  // --------------------------------------------------------------------------
  // VGA PIPELINE (16x12 Grid -> 512x384 Pixels centered)
  // --------------------------------------------------------------------------
  reg [8:0] r_grid_x;
  reg [8:0] r_grid_y;
  reg       r_pipe_in_grid;

  always @(posedge clk) begin
    r_grid_x <= pix_x[8:0] - 9'd64;
    r_grid_y       <= pix_y[8:0] - 9'd48;
    r_pipe_in_grid <= (pix_x >= 10'd64 && pix_x < 10'd576) && 
                      (pix_y >= 10'd48 && pix_y < 10'd432);
  end

  wire [3:0] tile_col = r_grid_x[8:5];
  wire [3:0] tile_row = r_grid_y[8:5];
  wire [4:0] local_x  = r_grid_x[4:0];
  wire [4:0] local_y  = r_grid_y[4:0];

  wire render_is_wall, render_is_goal;
  level_map render_map (
      .level(current_level), .x(tile_col), .y(tile_row),
      .is_wall(render_is_wall), .is_goal(render_is_goal)
  );
  
  wire render_is_player = (tile_col == p_x && tile_row == p_y);
  wire render_is_box0   = b0_active && (tile_col == b0_x && tile_row == b0_y);
  wire render_is_box1   = b1_active && (tile_col == b1_x && tile_row == b1_y);
  wire render_is_box2   = b2_active && (tile_col == b2_x && tile_row == b2_y);

  reg [4:0] r_local_x, r_local_y;
  reg r_in_grid, r_wall, r_goal, r_player, r_box0, r_box1, r_box2;
  always @(posedge clk) begin
      r_local_x <= local_x; r_local_y <= local_y;
      r_in_grid <= r_pipe_in_grid;
      r_wall    <= render_is_wall;
      r_goal    <= render_is_goal;
      r_player  <= render_is_player;
      r_box0    <= render_is_box0;
      r_box1    <= render_is_box1;
      r_box2    <= render_is_box2;
  end

  wire signed [5:0] dx = {1'b0, r_local_x} - 6'd15;
  wire signed [5:0] dy = {1'b0, r_local_y} - 6'd15;
  wire [9:0] dist_sq = dx*dx + dy*dy;
  wire is_circle = (dist_sq < 10'd120);

  wire [4:0] abs_dx = (r_local_x > 15) ? (r_local_x - 15) : (15 - r_local_x);
  wire [4:0] abs_dy = (r_local_y > 15) ? (r_local_y - 15) : (15 - r_local_y);
  wire is_star = (abs_dx + abs_dy < 12) || (abs_dx < 2 && abs_dy < 14) || (abs_dy < 2 && abs_dx < 14);

  wire is_box_shape = (r_local_x > 2 && r_local_x < 29 && r_local_y > 2 && r_local_y < 29);
  wire is_border = (r_local_x == 5'd0 || r_local_y == 5'd0 || r_local_x == 5'd31 || r_local_y == 5'd31);
  wire r_any_box = r_box0 | r_box1 | r_box2;

  localparam [5:0] C_BLACK      = 6'b00_00_00;
  localparam [5:0] C_GRAY       = 6'b01_01_01; 
  localparam [5:0] C_GREEN      = 6'b00_11_00; 
  localparam [5:0] C_BROWN      = 6'b10_01_00; 
  localparam [5:0] C_GOLD       = 6'b11_11_00; 
  localparam [5:0] C_BLUE       = 6'b00_01_11; 
  localparam [5:0] C_GRID_LINE  = 6'b00_00_01; 

  reg [5:0] r_final_color;
  always @(posedge clk) begin
      if (r_in_grid) begin
           if (is_border) r_final_color <= C_GRID_LINE;
           else if (r_player && is_circle) r_final_color <= C_BLUE;
           else if (r_any_box && is_box_shape) r_final_color <= r_goal ? C_GOLD : C_BROWN;
           else if (r_wall) r_final_color <= C_GRAY;
           else if (r_goal && is_star) r_final_color <= C_GREEN;
           else r_final_color <= C_BLACK;
      end else begin
          r_final_color <= C_BLACK;
      end
  end

  always @(posedge clk) begin
    if (sys_rst) begin
      r_out_R <= 2'b0; r_out_G <= 2'b0; r_out_B <= 2'b0;
      r_out_hsync <= 1'b0; r_out_vsync <= 1'b0;
    end else begin
      r_out_hsync <= r_hs3;
      r_out_vsync <= r_vs3;
      if (r_va3) begin
        {r_out_R, r_out_G, r_out_B} <= r_final_color;
      end else begin
        {r_out_R, r_out_G, r_out_B} <= 6'b0;
      end
    end
  end
endmodule

// --------------------------------------------------------------------------
// STATIC MAP LOOKUP MODULE (10 Levels)
// --------------------------------------------------------------------------
module level_map (
    input  wire [3:0] level,
    input  wire [3:0] x,
    input  wire [3:0] y,
    output reg  is_wall,
    output reg  is_goal
);
  always @(*) begin
      is_wall = (x == 0 || x == 15 || y == 0 || y == 11);
      is_goal = 0;
      case (level)
          4'd0: begin 
              if (x >= 4 && x <= 11 && (y == 3 || y == 8)) is_wall = 1;
              if (y >= 4 && y <= 8  && (x == 4 || x == 11)) is_wall = 1;
              if (x == 9 && y == 6) is_goal = 1;
          end
          4'd1: begin 
              if (x >= 2 && x <= 13 && (y == 2 || y == 9)) is_wall = 1;
              if (y >= 2 && y <= 9  && (x == 2 || x == 13)) is_wall = 1;
              if (x == 10 && y == 5) is_goal = 1;
              if (x == 11 && y == 6) is_goal = 1;
          end
          4'd2: begin 
              if (x >= 1 && x <= 14 && (y == 1 || y == 10)) is_wall = 1;
              if (y >= 1 && y <= 10 && (x == 1 || x == 14)) is_wall = 1;
              if (x == 7 && (y >= 2 && y <= 4)) is_wall = 1;
              if (x == 7 && (y >= 6 && y <= 9)) is_wall = 1;
              if (x == 10 && (y >= 4 && y <= 6)) is_goal = 1;
          end
          4'd3: begin 
              if (x >= 2 && x <= 11 && (y == 2 || y == 9)) is_wall = 1;
              if (y >= 2 && y <= 9 && (x == 2 || x == 11)) is_wall = 1;
              if (x == 6 && (y == 3 || y == 4 || y == 7 || y == 8)) is_wall = 1; 
              if (x == 9 && y == 4) is_goal = 1;
              if (x == 9 && y == 5) is_goal = 1;
          end
          4'd4: begin 
              if (x >= 3 && x <= 12 && (y == 3 || y == 9)) is_wall = 1;
              if (y >= 3 && y <= 9 && (x == 3 || x == 12)) is_wall = 1;
              if (x == 7 && y == 6) is_wall = 1; 
              if (x == 10 && y >= 5 && y <= 7) is_goal = 1;
          end
          4'd5: begin  
              if (x >= 2 && x <= 12 && (y == 2 || y == 9)) is_wall = 1;
              if (y >= 2 && y <= 9 && (x == 2 || x == 12)) is_wall = 1;
              if (x == 7 && (y == 3 || y == 5 || y == 7)) is_wall = 1; 
              if (x == 10 && y >= 4 && y <= 6) is_goal = 1;
          end
          4'd6: begin 
              if (x >= 2 && x <= 13 && (y == 2 || y == 9)) is_wall = 1;
              if (y >= 2 && y <= 9 && (x == 2 || x == 13)) is_wall = 1;
              if (x == 5 && (y == 3 || y == 4 || y == 7 || y == 8)) is_wall = 1;
              if (x == 9 && (y == 3 || y == 4 || y == 7 || y == 8)) is_wall = 1;
              if (x == 11 && (y == 4 || y == 5 || y == 6)) is_goal = 1;
          end
          4'd7: begin 
              if (x >= 3 && x <= 12 && (y == 2 || y == 9)) is_wall = 1;
              if (y >= 2 && y <= 9 && (x == 3 || x == 12)) is_wall = 1;
              if (x >= 3 && x <= 5 && y >= 2 && y <= 4) is_wall = 1; 
              if (x >= 10 && x <= 12 && y >= 7 && y <= 9) is_wall = 1; 
              if (x == 11 && y >= 3 && y <= 5) is_goal = 1;
          end
          4'd8: begin // Level 9 (The Core) - REDESIGNED
              if (x >= 2 && x <= 13 && (y == 2 || y == 9)) is_wall = 1;
              if (y >= 2 && y <= 9 && (x == 2 || x == 13)) is_wall = 1;
              if (x >= 7 && x <= 8 && y >= 5 && y <= 6) is_wall = 1;
              if (x == 11 && y >= 4 && y <= 6) is_goal = 1;
          end
          4'd9: begin // Level 10 (The Vault) - REDESIGNED
              if (x >= 2 && x <= 13 && (y == 2 || y == 9)) is_wall = 1;
              if (y >= 2 && y <= 9 && (x == 2 || x == 13)) is_wall = 1;
              if (x == 8 && (y == 3 || y == 5 || y == 6 || y == 8)) is_wall = 1;
              if (x == 11 && y >= 4 && y <= 6) is_goal = 1;
          end
         default: begin
    // Base border remains active; no interior walls or goals.
end
endcase
end
endmodule
