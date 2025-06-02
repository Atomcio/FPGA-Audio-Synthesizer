library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity adsr is
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;
        trigger   : in  std_logic;
        pot_rel   : in  unsigned(11 downto 0);  -- z ADC 12-bit
        amp_out   : out unsigned(15 downto 0)
    );
end entity;

architecture Behavioral of adsr is

    type state_type is (IDLE, ATTACK, DECAY, SUSTAIN, RELEASE);
    signal state    : state_type := IDLE;
    signal amp      : unsigned(15 downto 0) := (others => '0');
    signal counter  : unsigned(25 downto 0) := (others => '0');  -- 26 bitów

    -- sta?e czasu (w cyklach clk, tu 48 MHz)
    constant ATTACK_CYC  : unsigned(25 downto 0) := to_unsigned(1000000, 26);   -- ~20 ms
    constant DECAY_CYC   : unsigned(25 downto 0) := to_unsigned(500000, 26);    -- ~10 ms
    constant MAX_REL_CYC : unsigned(25 downto 0) := to_unsigned(48000000, 26);  -- ~1 s
    constant MAX_AMP     : unsigned(15 downto 0) := to_unsigned(65535, 16);
    constant SUST_LVL    : unsigned(15 downto 0) := to_unsigned(20000, 16);

    -- obliczony z pot_rel: 0…MAX_REL_CYC
    signal rel_time : unsigned(25 downto 0);

begin

    -- skalowanie pot_rel ? rel_time
    rel_time <= resize( (resize(pot_rel,26) * MAX_REL_CYC) / to_unsigned(4095,12), 26 );

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state   <= IDLE;
                amp     <= (others => '0');
                counter <= (others => '0');
            else
                case state is

                    when IDLE =>
                        amp <= (others => '0');
                        if trigger = '1' then
                            state   <= ATTACK;
                            counter <= (others => '0');
                        end if;

                    when ATTACK =>
                        if counter < ATTACK_CYC then
                            counter <= counter + 1;
                            amp <= resize(counter(25 downto 10), 16);
                        else
                            state   <= DECAY;
                            counter <= (others => '0');
                        end if;

                    when DECAY =>
                        if counter < DECAY_CYC then
                            counter <= counter + 1;
                            amp <= MAX_AMP -
                                   resize( ((MAX_AMP - SUST_LVL) * counter) / DECAY_CYC, 16 );
                        else
                            state   <= SUSTAIN;
                        end if;

                    when SUSTAIN =>
                        amp <= SUST_LVL;
                        if trigger = '0' then
                            state   <= RELEASE;
                            counter <= (others => '0');
                        end if;

                    when RELEASE =>
                        if counter < rel_time then
                            counter <= counter + 1;
                            amp <= resize( (SUST_LVL * (rel_time - counter)) / rel_time, 16 );
                        else
                            state <= IDLE;
                        end if;

                end case;
            end if;
        end if;
    end process;

    amp_out <= amp;

end architecture;
