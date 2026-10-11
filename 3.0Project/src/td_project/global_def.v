


`define   DATA_WIDTH                        32
`define   ADDR_WIDTH                        21
`define   DM_WIDTH                          4

`define   ROW_WIDTH                        11
`define   BA_WIDTH                        2

`define	  SDR_CLK_PERIOD				(1000000000 / 50000000)
// EM638325 requires 4096 AUTO REFRESH operations per 64 ms even though
// each bank has only 2048 addressable rows. ROW_WIDTH is NOT the refresh
// counter width. Also parenthesize SDR_CLK_PERIOD: without parentheses,
// 64000000/SDR_CLK_PERIOD expands to 64000000/1000000000/50000000 = 0,
// disabling the refresh timer rather than producing a period in clocks.
// Counter includes zero: subtract one, plus 16 clocks of scheduling margin.
`define   SDR_REFRESH_CYCLES                 4096
`define   SELF_REFRESH_INTERVAL             ((64000000 / `SDR_CLK_PERIOD / `SDR_REFRESH_CYCLES) - 1 - 16)

