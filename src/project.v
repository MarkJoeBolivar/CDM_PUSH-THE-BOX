/* Port-Hardened, Fully Pipelined 2048 Core & VGA Grid Engine
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
  reg rst_sync_0 = 1'b1;
  reg rst_sync_1 = 1'b1;

  always @(posedge clk) begin
    rst_sync_0 <= ~rst_n;
    rst_sync_1 <= rst_sync_0;
  end
  wire sys_rst = rst_sync_1;

  assign uio_out = 8'b0;
  assign uio_oe  = 8'b0;

  // --------------------------------------------------------------------------
  // DIRECT HARDWARE INPUT DEFINITIONS
  // --------------------------------------------------------------------------
  wire btn_left_in  = ui_in;
  wire btn_right_in = ui_in[1];
  wire btn_up_in    = ui_in[2];
  wire btn_down_in  = ui_in[3];
  wire btn_start_in = ui_in[7];
  wire _unused_ok = &{ena, uio_in};

  // --------------------------------------------------------------------------
  // VGA SYNC GENERATOR
  // --------------------------------------------------------------------------
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
  // HARDENED OUTPUT REGISTERS  (TT VGA pinout)
  // --------------------------------------------------------------------------
  (* keep = "true" *) reg        r_out_hsync, r_out_vsync;
  (* keep = "true" *) reg [1:0]  r_out_R, r_out_G, r_out_B;

  // FIXED: Explicitly mapping bit-slices to prevent array/bus truncation and overwriting
  assign uo_out[7] = r_out_hsync;
  assign uo_out[6] = r_out_B;
  assign uo_out[5] = r_out_G;
  assign uo_out[4] = r_out_R;
  assign uo_out[3] = r_out_vsync;
  assign uo_out[2] = r_out_B[1];
  assign uo_out[1] = r_out_G[1];
  assign uo_out[0] = r_out_R[1];

  // 4-stage sync delay to match the rendering pipeline depth
  reg r_va0, r_va1, r_va2, r_va3;
  reg r_hs0, r_hs1, r_hs2, r_hs3;
  reg r_vs0, r_vs1, r_vs2, r_vs3;

  always @(posedge clk) begin
    r_va0 <= video_active_w;
    r_va1 <= r_va0; r_va2 <= r_va1; r_va3 <= r_va2;
    r_hs0 <= hsync_w;        r_hs1 <= r_hs0; r_hs2 <= r_hs1;
    r_hs3 <= r_hs2;
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
  gamepad_pmod_single driver (
      .rst_n      (~sys_rst),
      .clk        (clk),
      .pmod_data  (r_pmod_data_1),
      .pmod_clk   (ui_in[5]),
      .pmod_latch (ui_in[4]),
      .b          (_unused_buttons),
      .y(), .select(), .start(raw_start),
      .up(raw_up), .down(raw_down), .left(raw_left), .right(raw_right),
      .a(), .x(), .l(), .r()
  );

  // --------------------------------------------------------------------------
  // INPUT SYNCHRONIZERS  (parallel UI pins OR'd with gamepad serializer)
  // --------------------------------------------------------------------------
  reg sync_up_0,    sync_up_1;
  reg sync_down_0,  sync_down_1;
  reg sync_left_0,  sync_left_1;
  reg sync_right_0, sync_right_1;
  reg sync_start_0, sync_start_1;
  always @(posedge clk) begin
    if (sys_rst) begin
      sync_up_0 <= 0;
      sync_up_1 <= 0;
      sync_down_0 <= 0;  sync_down_1 <= 0;
      sync_left_0 <= 0;  sync_left_1 <= 0;
      sync_right_0 <= 0;
      sync_right_1 <= 0;
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
  // VGA COLOR PALETTE  (6-bit: [5:4]=R  [3:2]=G  [1:0]=B)
  // --------------------------------------------------------------------------
  localparam [5:0] BLACK      = 6'b00_00_00;
  localparam [5:0] WHITE      = 6'b11_11_11;
  localparam [5:0] DARK_TEXT  = 6'b01_01_00;
  localparam [5:0] BOARD_BG   = 6'b10_01_00;
  localparam [5:0] GOLD       = 6'b11_10_00;
  localparam [5:0] CREAM      = 6'b11_11_10;
  localparam [5:0] LIGHT_TAN  = 6'b11_10_01;
  localparam [5:0] ORANGE     = 6'b11_01_00;
  localparam [5:0] DEEP_ORA   = 6'b11_00_00;
  localparam [5:0] RED        = 6'b10_00_00;
  localparam [5:0] CYAN       = 6'b00_11_11;
  localparam [5:0] GREEN      = 6'b00_10_00;
  localparam [5:0] PURPLE     = 6'b01_00_10;
  localparam [5:0] DARK_BLUE  = 6'b00_00_10;
  localparam [5:0] MAGENTA    = 6'b11_00_11;
  localparam [5:0] YELLOW     = 6'b11_11_00;

  // --------------------------------------------------------------------------
  // LFSR  (Galois 16-bit, taps 16 13 12 11 ‚Äî maximal length)
  // --------------------------------------------------------------------------
  reg [15:0] lfsr;
  always @(posedge clk) begin
    if (sys_rst) lfsr <= 16'hACE1;
    else         lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
  end

  // --------------------------------------------------------------------------
  // GAME STATE MACHINE
  // --------------------------------------------------------------------------
  localparam STATE_IDLE  = 3'd0;
  localparam STATE_PREP  = 3'd1;
  localparam STATE_CALC  = 3'd2;
  localparam STATE_STORE = 3'd3;
  localparam STATE_CHECK = 3'd4;
  localparam STATE_SPAWN = 3'd5;

  reg [2:0] game_state;
  reg [1:0] current_lane, move_dir;
  reg       any_moved;
  integer reset_idx;
  reg [3:0] board [0:15];

  // --------------------------------------------------------------------------
  // BOARD INDEX FUNCTION
  // dir 0 = Left, 1 = Right, 2 = Up, 3 = Down
  // --------------------------------------------------------------------------
  function [3:0] get_board_idx(
      input [1:0] lane_num,
      input [1:0] cell_pos,
      input [1:0] dir
  );
    begin
      case (dir)
        2'd0: get_board_idx = {lane_num, ~cell_pos};
        2'd1: get_board_idx = {lane_num,  cell_pos};
        2'd2: get_board_idx = { cell_pos, lane_num};
        2'd3: get_board_idx = {~cell_pos, lane_num};
      endcase
    end
  endfunction

  // Spawn walker
  reg [3:0] spawn_base, spawn_offset;
  wire [3:0] current_spawn_check = spawn_base + spawn_offset;

  // FIXED: Extracted ternary expression out of the array context to prevent compiler errors
  wire [3:0] second_spawn_idx = (lfsr[7:4] != lfsr[3:0]) ? lfsr[7:4] : (lfsr[7:4] + 4'd1);

  // Pipeline registers
  reg [3:0] r_idx0, r_idx1, r_idx2, r_idx3;
  reg [3:0] v0, v1, v2, v3;
  reg [3:0] r_f0, r_f1, r_f2, r_f3;

  // --------------------------------------------------------------------------
  // COMBINATIONAL SLIDE + MERGE
  // --------------------------------------------------------------------------
  reg [3:0] s0, s1, s2, s3;
  reg [3:0] c0, c1, c2, c3;
  reg [3:0] combinational_f0, combinational_f1, combinational_f2, combinational_f3;
  always @(*) begin
    // ---- STEP 1: compact ----
    s0 = 4'd0;
    s1 = 4'd0; s2 = 4'd0; s3 = 4'd0;

    if (v3 != 0) begin
      s3 = v3;
      if (v2 != 0) begin
        s2 = v2;
        if (v1 != 0) begin
          s1 = v1;
          if (v0 != 0) s0 = v0;
        end else if (v0 != 0) s1 = v0;
      end else begin
        if (v1 != 0) begin
          s2 = v1;
          if (v0 != 0) s1 = v0;
        end else if (v0 != 0) s2 = v0;
      end
    end else begin
      if (v2 != 0) begin
        s3 = v2;
        if (v1 != 0) begin
          s2 = v1;
          if (v0 != 0) s1 = v0;
        end else if (v0 != 0) s2 = v0;
      end else begin
        if (v1 != 0) begin
          s3 = v1;
          if (v0 != 0) s2 = v0;
        end else if (v0 != 0) s3 = v0;
      end
    end

    // ---- STEP 2: latch compacted values ----
    c0 = s0;
    c1 = s1; c2 = s2; c3 = s3;

    // ---- STEP 3: merge pairs ----
    combinational_f0 = 4'd0;
    combinational_f1 = 4'd0;
    combinational_f2 = 4'd0; combinational_f3 = 4'd0;

    if (c2 != 0 && c2 == c3) begin
      combinational_f3 = c3 + 4'd1;
      if (c0 != 0 && c0 == c1) begin
        combinational_f2 = c1 + 4'd1;
      end else begin
        combinational_f2 = c1;
        combinational_f1 = c0;
      end
    end else begin
      combinational_f3 = c3;
      if (c1 != 0 && c1 == c2) begin
        combinational_f2 = c2 + 4'd1;
        combinational_f1 = c0;
      end else begin
        combinational_f2 = c2;
        if (c0 != 0 && c0 == c1) begin
          combinational_f1 = c1 + 4'd1;
        end else begin
          combinational_f1 = c1;
          combinational_f0 = c0;
        end
      end
    end
  end

  // --------------------------------------------------------------------------
  // MAIN CLOCKED PROCESS
  // --------------------------------------------------------------------------
  always @(posedge clk) begin
    if (sys_rst) begin
      prev_up    <= 1'b0;
      prev_down  <= 1'b0;
      prev_left  <= 1'b0; prev_right <= 1'b0; prev_start <= 1'b0;
      game_state   <= STATE_IDLE;
      current_lane <= 2'd0;
      move_dir     <= 2'd0;
      any_moved    <= 1'b0;
      spawn_base   <= 4'd0;
      spawn_offset <= 4'd0;
      r_f0 <= 4'd0; r_f1 <= 4'd0; r_f2 <= 4'd0; r_f3 <= 4'd0;
      r_idx0 <= 4'd0; r_idx1 <= 4'd0; r_idx2 <= 4'd0; r_idx3 <= 4'd0;
      v0 <= 4'd0; v1 <= 4'd0;
      v2 <= 4'd0; v3 <= 4'd0;

      for (reset_idx = 0; reset_idx < 16; reset_idx = reset_idx + 1)
        board[reset_idx] <= 4'd0;
      board[2]  <= 4'd1; // "2"
      board[10] <= 4'd1;

    end else begin
      prev_up    <= sync_up_1;
      prev_down  <= sync_down_1;
      prev_left  <= sync_left_1;
      prev_right <= sync_right_1;
      prev_start <= sync_start_1;

      case (game_state)
        // ----------------------------------------------------------------
        STATE_IDLE: begin
          current_lane <= 2'd0;
          any_moved    <= 1'b0;

          if (press_start) begin
            for (reset_idx = 0; reset_idx < 16; reset_idx = reset_idx + 1)
              board[reset_idx] <= 4'd0;
            board[lfsr[3:0]] <= 4'd1;
            // FIXED: Using simplified standalone wire here to fix the compilation error
            board[second_spawn_idx] <= 4'd1;
          end else if (press_left) begin
            game_state <= STATE_PREP;
            move_dir   <= 2'd0;                       // Left
            r_idx0 <= get_board_idx(2'd0, 2'd0, 2'd0);
            r_idx1 <= get_board_idx(2'd0, 2'd1, 2'd0);
            r_idx2 <= get_board_idx(2'd0, 2'd2, 2'd0);
            r_idx3 <= get_board_idx(2'd0, 2'd3, 2'd0);
          end else if (press_right) begin
            game_state <= STATE_PREP;
            move_dir   <= 2'd1;                       // Right
            r_idx0 <= get_board_idx(2'd0, 2'd0, 2'd1);
            r_idx1 <= get_board_idx(2'd0, 2'd1, 2'd1);
            r_idx2 <= get_board_idx(2'd0, 2'd2, 2'd1);
            r_idx3 <= get_board_idx(2'd0, 2'd3, 2'd1);
          end else if (press_up) begin
            game_state <= STATE_PREP;
            move_dir   <= 2'd3;                       // Maps to Down index routing
            r_idx0 <= get_board_idx(2'd0, 2'd0, 2'd3);
            r_idx1 <= get_board_idx(2'd0, 2'd1, 2'd3);
            r_idx2 <= get_board_idx(2'd0, 2'd2, 2'd3);
            r_idx3 <= get_board_idx(2'd0, 2'd3, 2'd3);
          end else if (press_down) begin
            game_state <= STATE_PREP;
            move_dir   <= 2'd2;                       // Maps to Up index routing
            r_idx0 <= get_board_idx(2'd0, 2'd0, 2'd2);
            r_idx1 <= get_board_idx(2'd0, 2'd1, 2'd2);
            r_idx2 <= get_board_idx(2'd0, 2'd2, 2'd2);
            r_idx3 <= get_board_idx(2'd0, 2'd3, 2'd2);
          end
        end

        // ----------------------------------------------------------------
        STATE_PREP: begin
          v0 <= board[r_idx0];
          v1 <= board[r_idx1];
          v2 <= board[r_idx2];
          v3 <= board[r_idx3];
          game_state <= STATE_CALC;
        end

        // ----------------------------------------------------------------
        STATE_CALC: begin
          r_f0 <= combinational_f0;
          r_f1 <= combinational_f1;
          r_f2 <= combinational_f2;
          r_f3 <= combinational_f3;
          game_state <= STATE_STORE;
        end

        // ----------------------------------------------------------------
        STATE_STORE: begin
          board[r_idx0] <= r_f0;
          board[r_idx1] <= r_f1;
          board[r_idx2] <= r_f2;
          board[r_idx3] <= r_f3;

          if ((v0 != r_f0) || (v1 != r_f1) || (v2 != r_f2) || (v3 != r_f3))
            any_moved <= 1'b1;
          game_state <= STATE_CHECK;
        end

        // ----------------------------------------------------------------
        STATE_CHECK: begin
          if (current_lane == 2'd3) begin
            if (any_moved) begin
              game_state   <= STATE_SPAWN;
              spawn_base   <= lfsr[3:0];
              spawn_offset <= 4'd0;
            end else begin
              game_state   <= STATE_IDLE;
            end
          end else begin
            current_lane <= current_lane + 2'd1;
            r_idx0 <= get_board_idx(current_lane + 2'd1, 2'd0, move_dir);
            r_idx1 <= get_board_idx(current_lane + 2'd1, 2'd1, move_dir);
            r_idx2 <= get_board_idx(current_lane + 2'd1, 2'd2, move_dir);
            r_idx3 <= get_board_idx(current_lane + 2'd1, 2'd3, move_dir);
            game_state <= STATE_PREP;
          end
        end

        // ----------------------------------------------------------------
        STATE_SPAWN: begin
          if (board[current_spawn_check] == 4'd0) begin
            board[current_spawn_check] <= (lfsr[1:0] == 2'b00) ? 4'd2 : 4'd1;
            game_state <= STATE_IDLE;
          end else begin
            spawn_offset <= spawn_offset + 4'd1;
            if (spawn_offset == 4'd15)
              game_state <= STATE_IDLE;
          end
        end

        default: game_state <= STATE_IDLE;
      endcase
    end
  end

  // --------------------------------------------------------------------------
  // VGA PIPELINE ‚Äî Stage 0: raw pixel ‚Üí grid coordinates
  // --------------------------------------------------------------------------
  reg [9:0] r_grid_x;
  reg [8:0] r_grid_y;
  reg       r_pipe_in_grid;
  reg       r_pipe_border;
  always @(posedge clk) begin
    r_grid_x       <= pix_x - 10'd128;
    r_grid_y       <= pix_y[8:0] - 9'd48;
    r_pipe_in_grid <= (pix_x >= 10'd128 && pix_x < 10'd512) && (pix_y >= 10'd48  && pix_y < 10'd432);
    r_pipe_border  <= ((pix_y == 10'd47  || pix_y == 10'd48 || pix_y == 10'd431 || pix_y == 10'd432) && (pix_x >= 10'd127 && pix_x <= 10'd512)) ||
                      ((pix_x == 10'd127 || pix_x == 10'd128 || pix_x == 10'd511 || pix_x == 10'd512) && (pix_y >= 10'd47  && pix_y <= 10'd432));
  end

  // Tile column and row from grid coordinates
  wire [1:0] tile_col = (r_grid_x < 10'd96)  ? 2'd0 :
                        (r_grid_x < 10'd192) ? 2'd1 :
                        (r_grid_x < 10'd288) ? 2'd2 : 2'd3;
  wire [1:0] tile_row = (r_grid_y < 9'd96)   ? 2'd0 :
                        (r_grid_y < 9'd192)  ? 2'd1 :
                        (r_grid_y < 9'd288)  ? 2'd2 : 2'd3;
  wire [3:0] tile_idx = {tile_row, tile_col};

  wire [8:0] local_x_full = (tile_col == 2'd0) ? r_grid_x[8:0]         :
                             (tile_col == 2'd1) ? r_grid_x[8:0] - 9'd96  :
                             (tile_col == 2'd2) ? r_grid_x[8:0] - 9'd192 :
                                                  r_grid_x[8:0] - 9'd288;
  wire [8:0] local_y_full = (tile_row == 2'd0) ? {1'b0, r_grid_y[7:0]}         :
                             (tile_row == 2'd1) ? {1'b0, r_grid_y[7:0]} - 9'd96  :
                             (tile_row == 2'd2) ? {1'b0, r_grid_y[7:0]} - 9'd192 :
                                                  {1'b0, r_grid_y[7:0]} - 9'd288;
  wire [6:0] local_x = local_x_full[6:0];
  wire [6:0] local_y = local_y_full[6:0];

  // --------------------------------------------------------------------------
  // VGA PIPELINE ‚Äî Stage 1: compute tile value and pixel classification
  // --------------------------------------------------------------------------
  reg [3:0] r_tile_val;
  reg [6:0] r_local_x, r_local_y;
  reg       r_in_grid, r_arena_border;
  always @(posedge clk) begin
    r_local_x      <= local_x;
    r_local_y      <= local_y;
    r_in_grid      <= r_pipe_in_grid;
    r_arena_border <= r_pipe_border;
    r_tile_val     <= r_pipe_in_grid ? board[tile_idx] : 4'd0;
  end

  wire is_gap      = (r_local_x < 7'd4)  || (r_local_y < 7'd4) || (r_local_x >= 7'd92) || (r_local_y >= 7'd92);
  wire is_tile_box = r_in_grid && ~is_gap && (r_tile_val != 4'd0);
  wire is_board_bg = r_in_grid && is_gap;

  // --------------------------------------------------------------------------
  // FONT ENGINE
  // --------------------------------------------------------------------------
  wire [6:0] font_x = r_local_x - 7'd28;
  wire [6:0] font_y = r_local_y - 7'd33;
  wire in_font_bb   = (font_x < 7'd40) && (font_y < 7'd30);
  wire [1:0] char_col = (font_x < 7'd10) ? 2'd0 :
                        (font_x < 7'd20) ? 2'd1 :
                        (font_x < 7'd30) ? 2'd2 : 2'd3;

  wire [3:0] sub_x = (font_x < 7'd10) ? font_x[3:0]          :
                     (font_x < 7'd20) ? font_x[3:0] - 4'd10  :
                     (font_x < 7'd30) ? font_x[3:0] - 4'd20  :
                                         font_x[3:0] - 4'd30;
  wire [1:0] bit_x = (sub_x < 4'd3) ? 2'd0 : (sub_x < 4'd6) ? 2'd1 : 2'd2;
  wire [2:0] bit_y = (font_y < 7'd6)  ? 3'd0 :
                     (font_y < 7'd12) ? 3'd1 :
                     (font_y < 7'd18) ? 3'd2 :
                     (font_y < 7'd24) ? 3'd3 : 3'd4;

  localparam [14:0] G_0 = 15'b111_101_101_101_111;
  localparam [14:0] G_1 = 15'b010_110_010_010_111;
  localparam [14:0] G_2 = 15'b111_001_111_100_111;
  localparam [14:0] G_3 = 15'b111_001_111_001_111;
  localparam [14:0] G_4 = 15'b101_101_111_001_001;
  localparam [14:0] G_5 = 15'b111_100_111_001_111;
  localparam [14:0] G_6 = 15'b111_100_111_101_111;
  localparam [14:0] G_7 = 15'b111_001_001_010_010;
  localparam [14:0] G_8 = 15'b111_101_111_101_111;
  localparam [14:0] G_9 = 15'b111_101_111_001_111;

  reg [14:0] combinational_digit_rom;
  always @(*) begin
    case ({r_tile_val, char_col})
      {4'd1,  2'd0}: combinational_digit_rom = G_2; // "2"
      {4'd2,  2'd0}: combinational_digit_rom = G_4; // "4"
      {4'd3,  2'd0}: combinational_digit_rom = G_8; // "8"
      {4'd4,  2'd0}: combinational_digit_rom = G_1; // "16"
      {4'd4,  2'd1}: combinational_digit_rom = G_6;
      {4'd5,  2'd0}: combinational_digit_rom = G_3; // "32"
      {4'd5,  2'd1}: combinational_digit_rom = G_2;
      {4'd6,  2'd0}: combinational_digit_rom = G_6; // "64"
      {4'd6,  2'd1}: combinational_digit_rom = G_4;
      {4'd7,  2'd0}: combinational_digit_rom = G_1; // "128"
      {4'd7,  2'd1}: combinational_digit_rom = G_2;
      {4'd7,  2'd2}: combinational_digit_rom = G_8;
      {4'd8,  2'd0}: combinational_digit_rom = G_2; // "256"
      {4'd8,  2'd1}: combinational_digit_rom = G_5;
      {4'd8,  2'd2}: combinational_digit_rom = G_6;
      {4'd9,  2'd0}: combinational_digit_rom = G_5; // "512"
      {4'd9,  2'd1}: combinational_digit_rom = G_1;
      {4'd9,  2'd2}: combinational_digit_rom = G_2;
      {4'd10, 2'd0}: combinational_digit_rom = G_1; // "1024"
      {4'd10, 2'd1}: combinational_digit_rom = G_0;
      {4'd10, 2'd2}: combinational_digit_rom = G_2;
      {4'd10, 2'd3}: combinational_digit_rom = G_4;
      {4'd11, 2'd0}: combinational_digit_rom = G_2; // "2048"
      {4'd11, 2'd1}: combinational_digit_rom = G_0;
      {4'd11, 2'd2}: combinational_digit_rom = G_4;
      {4'd11, 2'd3}: combinational_digit_rom = G_8;
      default:       combinational_digit_rom = 15'b0;
    endcase
  end

  // --------------------------------------------------------------------------
  // TILE COLOR + NUMBER TEXT COLOR
  // --------------------------------------------------------------------------
  reg [5:0] combinational_tile_color;
  reg [5:0] combinational_num_color;

  always @(*) begin
    case (r_tile_val)
      4'd1:    begin combinational_tile_color = CREAM;      combinational_num_color = DARK_TEXT; end
      4'd2:    begin combinational_tile_color = LIGHT_TAN;  combinational_num_color = DARK_TEXT; end
      4'd3:    begin combinational_tile_color = ORANGE;     combinational_num_color = WHITE;     end
      4'd4:    begin combinational_tile_color = DEEP_ORA;   combinational_num_color = WHITE;     end
      4'd5:    begin combinational_tile_color = RED;        combinational_num_color = WHITE;     end
      4'd6:    begin combinational_tile_color = CYAN;       combinational_num_color = BLACK;     end
      4'd7:    begin combinational_tile_color = GREEN;      combinational_num_color = WHITE;     end
      4'd8:    begin combinational_tile_color = PURPLE;     combinational_num_color = WHITE;     end
      4'd9:    begin combinational_tile_color = DARK_BLUE;  combinational_num_color = WHITE;     end
      4'd10:   begin combinational_tile_color = MAGENTA;    combinational_num_color = WHITE;     end
      4'd11:   begin combinational_tile_color = YELLOW;     combinational_num_color = BLACK;     end
      default: begin combinational_tile_color = BOARD_BG;   combinational_num_color = WHITE;     end
    endcase
  end

  // --------------------------------------------------------------------------
  // VGA PIPELINE ‚Äî Stage 2: register rendering signals
  // --------------------------------------------------------------------------
  reg [14:0] r_digit_rom;
  reg [1:0]  r_bit_x;
  reg [2:0]  r_bit_y;
  reg        r_sub_x_valid;
  reg        r_is_tile_box, r_is_board_bg, r_border;
  reg [5:0]  r_tile_color, r_num_color;
  always @(posedge clk) begin
    r_digit_rom   <= combinational_digit_rom;
    r_bit_x       <= bit_x;
    r_bit_y       <= bit_y;
    r_sub_x_valid <= (sub_x <= 4'd8) && in_font_bb;
    r_is_tile_box <= is_tile_box;
    r_is_board_bg <= is_board_bg;
    r_border      <= r_arena_border;
    r_tile_color  <= combinational_tile_color;
    r_num_color   <= combinational_num_color;
  end

  wire [3:0] target_bit = ({1'b0, r_bit_y} * 3'd3) + {2'b0, r_bit_x};
  wire active_num_pixel = (r_is_tile_box & r_sub_x_valid) ? r_digit_rom[4'd14 - target_bit] : 1'b0;

  // --------------------------------------------------------------------------
  // VGA PIPELINE ‚Äî Stage 3: final output register
  // --------------------------------------------------------------------------
  reg        r_final_num;
  reg        r_final_tile;
  reg        r_final_bg;
  reg        r_final_border;
  reg [5:0]  r_final_tile_color, r_final_num_color;
  always @(posedge clk) begin
    r_final_num        <= active_num_pixel;
    r_final_tile       <= r_is_tile_box;
    r_final_bg         <= r_is_board_bg;
    r_final_border     <= r_border;
    r_final_tile_color <= r_tile_color;
    r_final_num_color  <= r_num_color;
  end

  // --------------------------------------------------------------------------
  // OUTPUT MUX
  // --------------------------------------------------------------------------
  always @(posedge clk) begin
    if (sys_rst) begin
      r_out_R <= 2'b0;
      r_out_G <= 2'b0; r_out_B <= 2'b0;
      r_out_hsync <= 1'b0; r_out_vsync <= 1'b0;
    end else begin
      r_out_hsync <= r_hs3;
      r_out_vsync <= r_vs3;
      if (r_va3) begin
        if      (r_final_num)    {r_out_R, r_out_G, r_out_B} <= r_final_num_color;
        else if (r_final_tile)   {r_out_R, r_out_G, r_out_B} <= r_final_tile_color;
        else if (r_final_bg)     {r_out_R, r_out_G, r_out_B} <= BOARD_BG;
        else if (r_final_border) {r_out_R, r_out_G, r_out_B} <= GOLD;
        else                     {r_out_R, r_out_G, r_out_B} <= BLACK;
      end else begin
        {r_out_R, r_out_G, r_out_B} <= 6'b0;
      end
    end
  end

endmodule
