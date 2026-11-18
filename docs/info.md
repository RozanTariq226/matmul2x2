## How it works

Computes **C = A x B** for 2x2 matrices of signed 8-bit integers.
One 8x8 signed multiplier is shared: an FSM runs 8 cycles
(4 result elements x 2 products), adding the two products of each element.
Each result is exact and needs **17 bits** (worst case (-128)x(-128)x2 = 32768).

Block diagram:

    ui_in --> [load regs A(4B), B(4B)] --> [mux] --> [8x8 signed MUL] --> [+] --> C regs (4 x 17b)
                      ^                       ^                    ^acc            |
                    WR edge                 FSM step counter                     SEL/HI mux --> uo_out, uio[7]

## How to test

1. Reset (rst_n low for a few clocks, then high).
2. Put a byte on `ui_in` and give `uio[0]` (WR) a rising edge. Do this 8 times, in this order
   (row-major, two's complement): A00 A01 A10 A11 B00 B01 B10 B11.
3. Give `uio[1]` (START) a rising edge. `uio[6]` BUSY is high for 8 clocks, then `uio[5]` DONE goes high.
4. Select a result with `uio[3:2]` (0=C00, 1=C01, 2=C10, 3=C11).
   `uio[4]`=0 -> `uo_out` = bits [7:0]; `uio[4]`=1 -> bits [15:8]; `uio[7]` = bit 16 (sign).
   Result = 17-bit two's complement {uio[7], hi, lo}.

Example: A = [1 2; 3 4], B = [5 6; 7 8] -> C = [19 22; 43 50].
Writes while BUSY are ignored. WR and START are edge-triggered, so holding them high is safe.

## External hardware

None. The RP2350 on the Tiny Tapeout demo board drives the pins.
