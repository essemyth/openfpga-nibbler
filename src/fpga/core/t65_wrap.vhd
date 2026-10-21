--
-- Plain-port wrapper around T65 so it can be instantiated from Verilog
-- (T65's DEBUG port is a VHDL record type). 6502 mode, BCD enabled.
--
library ieee;
use ieee.std_logic_1164.all;
use work.T65_Pack.all;

entity t65_wrap is
  port(
    clk     : in  std_logic;
    ce      : in  std_logic;
    res_n   : in  std_logic;
    rdy     : in  std_logic;
    irq_n   : in  std_logic;
    nmi_n   : in  std_logic;
    rw_n    : out std_logic;
    sync    : out std_logic;
    vp_n    : out std_logic;
    addr    : out std_logic_vector(15 downto 0);
    din     : in  std_logic_vector(7 downto 0);
    dout    : out std_logic_vector(7 downto 0);
    regs    : out std_logic_vector(63 downto 0)
  );
end t65_wrap;

architecture rtl of t65_wrap is
  signal a24 : std_logic_vector(23 downto 0);
begin
  cpu : entity work.T65
    port map (
      Mode    => "00",
      BCD_en  => '1',
      Res_n   => res_n,
      Enable  => ce,
      Clk     => clk,
      Rdy     => rdy,
      Abort_n => '1',
      IRQ_n   => irq_n,
      NMI_n   => nmi_n,
      SO_n    => '1',
      R_W_n   => rw_n,
      Sync    => sync,
      EF      => open,
      MF      => open,
      XF      => open,
      ML_n    => open,
      VP_n    => vp_n,
      VDA     => open,
      VPA     => open,
      A       => a24,
      DI      => din,
      DO      => dout,
      Regs    => regs,
      DEBUG   => open,
      NMI_ack => open
    );
  addr <= a24(15 downto 0);
end rtl;
