library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity xadc_to_led is
    port (
        clk         : in  std_logic;
        xadc_data   : in  std_logic_vector(15 downto 0);
        drdy        : in  std_logic;
        led         : out std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of xadc_to_led is
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if drdy = '1' then
                led <= xadc_data(15 downto 8); -- pokazuje napi?cie jako "bar"
            end if;
        end if;
    end process;
end rtl;
