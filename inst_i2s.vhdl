library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity i2s_data_interface is
    Port (
        clk           : in  STD_LOGIC;
        audio_l_in    : in  STD_LOGIC_VECTOR (23 downto 0); -- zamiast resize()!
        audio_r_in    : in  STD_LOGIC_VECTOR (23 downto 0);
        audio_l_out   : out STD_LOGIC_VECTOR (23 downto 0);
        audio_r_out   : out STD_LOGIC_VECTOR (23 downto 0);
        new_sample    : out STD_LOGIC;
        i2s_bclk      : in  STD_LOGIC;
        i2s_d_out     : out STD_LOGIC;
        i2s_d_in      : in  STD_LOGIC;
        i2s_lr        : in  STD_LOGIC
    );
end i2s_data_interface;


architecture Behavioral of i2s_data_interface is
    signal sr_out        : std_logic_vector(47 downto 0) := (others => '0');
    signal sr_in         : std_logic_vector(63 downto 0) := (others => '0');
    signal bit_count     : integer range 0 to 63 := 0;
    signal bclk_last     : std_logic := '0';
    signal i2s_lr_last   : std_logic := '0';
    signal lrclk_edge    : std_logic := '0';
begin

process(clk)
begin
    if rising_edge(clk) then
        new_sample <= '0';
        lrclk_edge <= '0';

        -- detekcja zbocza narastaj?cego i2s_bclk
        if bclk_last = '0' and i2s_bclk = '1' then
            -- odbiór danych z kodeka
            sr_in <= sr_in(62 downto 0) & i2s_d_in;

            -- nadawanie danych do kodeka
            i2s_d_out <= sr_out(47);
            sr_out <= sr_out(46 downto 0) & '0';

            bit_count <= bit_count + 1;

            -- je?li wys?ali?my 48 bitów (2 x 24-bit) - czekamy na now? ramk?
            if bit_count = 47 then
                bit_count <= 0;
            end if;
        end if;

        -- detekcja zbocza LRCLK ? nowa ramka
        if i2s_lr_last = '0' and i2s_lr = '1' then
            lrclk_edge <= '1';

            -- dane wej?ciowe (z kodeka)
            audio_l_out <= sr_in(63 downto 40);
            audio_r_out <= sr_in(31 downto 8);

            -- dane wyj?ciowe (do kodeka)
            sr_out <= audio_l_in & audio_r_in;

            new_sample <= '1';
        end if;

        bclk_last <= i2s_bclk;
        i2s_lr_last <= i2s_lr;
    end if;
end process;

end Behavioral;
