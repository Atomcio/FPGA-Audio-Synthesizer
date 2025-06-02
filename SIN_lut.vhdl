library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

entity dds_sin_lut is
  generic (
    ADDR_WIDTH : positive := 12;
    DATA_WIDTH : positive := 16;
    FRAC_BITS  : positive := 4
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    en        : in  std_logic := '1';  -- pod??czone do new_sample
    PHASE_INC : in  unsigned(ADDR_WIDTH+FRAC_BITS-1 downto 0);
    sin_o     : out signed(DATA_WIDTH-1 downto 0);
    valid     : out std_logic
  );
end entity;

architecture rtl of dds_sin_lut is

  subtype rom_addr is integer range 0 to 2**ADDR_WIDTH-1;
  type rom_t is array(rom_addr) of signed(DATA_WIDTH-1 downto 0);
  constant SCALE : real := 2.0**(DATA_WIDTH-1) - 1.0;

  function build_sin return rom_t is
    variable tmp : rom_t;
  begin
    for i in tmp'range loop
      tmp(i) := to_signed(integer(round(SCALE * sin(2.0*math_pi*real(i)/real(2**ADDR_WIDTH)))), DATA_WIDTH);
    end loop;
    return tmp;
  end function;

  constant SIN_ROM : rom_t := build_sin;
  attribute ram_style : string;
  attribute ram_style of SIN_ROM : constant is "block";

  signal phase_acc : unsigned(ADDR_WIDTH+FRAC_BITS-1 downto 0) := (others=>'0');
  signal valid_reg : std_logic := '0';

begin

  process(clk)
    variable index : integer;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        phase_acc <= (others=>'0');
        sin_o     <= (others=>'0');
        valid_reg <= '0';
      else
        valid_reg <= en;
        if en = '1' then
          phase_acc <= phase_acc + PHASE_INC;
          index := to_integer(phase_acc(ADDR_WIDTH+FRAC_BITS-1 downto FRAC_BITS));
          sin_o <= SIN_ROM(index);
        end if;
      end if;
    end if;
  end process;

  valid <= valid_reg;

end architecture;