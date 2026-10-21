//
// Core clocks, from the 74.25 MHz APF reference.
//
// clk_sys is 4x the arcade board's 11.289 MHz master crystal. Everything on the
// original board divides down from that crystal, so we run all logic on clk_sys
// and derive the original rates with clock enables:
//   pixel   = clk_sys / 8   (5.6445 MHz)
//   CPU     = clk_sys / 32  (1.411 MHz)
//
// clk_vid / clk_vid_90 are the pixel clock for the APF video scaler. They come
// from the same VCO as clk_sys (exactly clk_sys / 8), so the sys -> vid handoff
// is a related-clock path that timing analysis checks normally.
//
module pll_nibbler (
    input  wire refclk,
    input  wire rst,
    output wire clk_sys,
    output wire clk_vid,
    output wire clk_vid_90,
    output wire locked
);

    altera_pll #(
        .fractional_vco_multiplier("true"),
        .reference_clock_frequency("74.25 MHz"),
        .operation_mode("normal"),
        .number_of_clocks(3),
        .output_clock_frequency0("45.156 MHz"),
        .phase_shift0("0 ps"),
        .duty_cycle0(50),
        .output_clock_frequency1("5.6445 MHz"),
        .phase_shift1("0 ps"),
        .duty_cycle1(50),
        .output_clock_frequency2("5.6445 MHz"),
        .phase_shift2("44291 ps"),          // 90 degrees of 177.165 ns
        .duty_cycle2(50),
        .pll_type("General"),
        .pll_subtype("General")
    ) altera_pll_i (
        .rst      ( rst ),
        .outclk   ( {clk_vid_90, clk_vid, clk_sys} ),
        .locked   ( locked ),
        .fboutclk ( ),
        .fbclk    ( 1'b0 ),
        .refclk   ( refclk )
    );

endmodule
