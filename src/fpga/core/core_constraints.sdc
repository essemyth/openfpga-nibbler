#
# user core constraints
#
# put your clock groups in here as well as any net assignments
#

# All pll_nibbler outputs share one VCO and are analyzed together:
# clk_sys -> clk_vid is a real, timed path (see core_top video handoff).
set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group [get_clocks {ic|pll|altera_pll_i|*}]
