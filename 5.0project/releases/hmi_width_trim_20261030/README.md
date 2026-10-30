# 2026-10-30 HMI formatter width trim

Only HMI formatter counter/length widths change: refresh_count 32 -> 25 at 100MHz, prefix_length 6 -> 5, suffix_length 6 -> 3. Total message length remains 6 bits to represent 32 bytes. All clocks, baud rates and protocol lengths remain unchanged. The rotating-trophy commit fix is retained.

The source file is shared by both projects; both boards were rebuilt with identical current input hashes. A board does not instantiate the modified formatter module.

| Board | LUT previous -> new | Registers previous -> new | RAM9K / RAM32K / DSP | setup / hold ns |
|---|---|---|---|---|
| A | 17253 -> 17253 | 12305 -> 12305 | 62 / 15 / 27 | 0.153 / 0.02 |
| B | 15551 -> 15549 | 10876 -> 10875 | 58 / 16 / 16 | 0.106 / 0.027 |

Checks pass: five-page HMI byte comparison against reference; 100MHz cycle equivalence with 1064 bytes and 40 commands, refresh-count rollover, maximum-length numeric settings, page switches and randomized backpressure. Both routed timing checks pass. Physical hardware validation is pending.

This is a width-only change; it does not improve link speed or shorten packets. Some synthesis width trimming may already occur automatically; resource changes above are measured from routed reports.
