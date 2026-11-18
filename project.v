/*
 * 2x2 signed 8-bit matrix multiplier  (C = A x B)
 * Tiny Tapeout IHP template compatible.
 *
 * One shared 8x8 signed multiplier is reused for 8 cycles
 * (4 result elements x 2 products each).
 *
 * Host protocol (all pins synchronous to clk):
 *   1. Load 8 bytes on ui_in, one rising edge of uio[0] (WR) per byte:
 *        A00, A01, A10, A11, B00, B01, B10, B11   (row-major, signed int8)
 *   2. Rising edge on uio[1] (START).  uio[6] BUSY=1 for 8 cycles, then
 *      uio[5] DONE=1 (stays 1 until the next START).
 *   3. Read results: choose element with uio[3:2] (SEL) and byte with
 *      uio[4] (HI).  uo_out = byte, uio[7] = bit 16 (17-bit signed result).
 *        SEL: 0=C00 1=C01 2=C10 3=C11     HI: 0=bits[7:0] 1=bits[15:8]
 */
`default_nettype none

module tt_um_matmul2x2_int8 (
    input  wire [7:0] ui_in,    // data in
    output wire [7:0] uo_out,   // result byte
    input  wire [7:0] uio_in,   // control in
    output wire [7:0] uio_out,  // status out
    output wire [7:0] uio_oe,   // 1 = output
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

  // ---------------- pin decode ----------------
  wire       wr_in    = uio_in[0];
  wire       start_in = uio_in[1];
  wire [1:0] sel      = uio_in[3:2];
  wire       hi_sel   = uio_in[4];

  // ---------------- state ----------------
  reg [31:0] a_flat;            // A00,A01,A10,A11  (8 bits each)
  reg [31:0] b_flat;            // B00,B01,B10,B11
  reg [67:0] c_flat;            // 4 x 17-bit results
  reg [15:0] acc;               // first product of each element
  reg  [2:0] step;              // 0..7 while busy
  reg  [2:0] wr_ptr;            // 0..7 load pointer
  reg        busy, done;
  reg        wr_q, start_q;     // edge detectors

  wire wr_pulse    = wr_in    & ~wr_q;
  wire start_pulse = start_in & ~start_q;

  // ---------------- datapath ----------------
  wire [1:0] e = step[2:1];     // which C element: {row i, col j}
  wire       t = step[0];       // which of the 2 products
  wire [1:0] a_idx = {e[1], t}; // A[i][t]
  wire [1:0] b_idx = {t, e[0]}; // B[t][j]

  wire signed [7:0]  a_sel = a_flat[8*a_idx +: 8];
  wire signed [7:0]  b_sel = b_flat[8*b_idx +: 8];
  wire signed [15:0] prod  = a_sel * b_sel;
  wire signed [16:0] sum   = $signed(acc) + prod;   // 17-bit, no overflow

  always @(posedge clk) begin
    if (!rst_n) begin
      a_flat  <= 32'd0;
      b_flat  <= 32'd0;
      c_flat  <= 68'd0;
      acc     <= 16'd0;
      step    <= 3'd0;
      wr_ptr  <= 3'd0;
      busy    <= 1'b0;
      done    <= 1'b0;
      wr_q    <= 1'b0;
      start_q <= 1'b0;
    end else begin
      wr_q    <= wr_in;
      start_q <= start_in;

      if (busy) begin
        if (!t) acc <= prod;
        else    c_flat[17*e +: 17] <= sum;
        step <= step + 3'd1;
        if (step == 3'd7) begin
          busy <= 1'b0;
          done <= 1'b1;
        end
      end else begin
        if (start_pulse) begin
          busy   <= 1'b1;
          done   <= 1'b0;
          step   <= 3'd0;
          wr_ptr <= 3'd0;
        end else if (wr_pulse) begin
          if (!wr_ptr[2]) a_flat[8*wr_ptr[1:0] +: 8] <= ui_in;
          else            b_flat[8*wr_ptr[1:0] +: 8] <= ui_in;
          wr_ptr <= wr_ptr + 3'd1;
        end
      end
    end
  end

  // ---------------- read-out (pure mux, no state) ----------------
  wire [16:0] c_sel = c_flat[17*sel +: 17];

  assign uo_out  = hi_sel ? c_sel[15:8] : c_sel[7:0];
  assign uio_out = {c_sel[16], busy, done, 5'b00000};
  assign uio_oe  = 8'b1110_0000;

  wire _unused = &{ena, uio_in[7:5], 1'b0};

endmodule
