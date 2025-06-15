library work;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.sine_lut_pkg.all;

entity top_module is
  port(
    --Clock
    clk_100     : in  std_logic;
    --Audio codec
    AC_SCK      : out std_logic;
    AC_SDA      : inout std_logic;
    AC_ADR0     : out std_logic;
    AC_ADR1     : out std_logic;
    AC_GPIO0    : out std_logic;
    AC_GPIO1    : in  std_logic;
    AC_GPIO2    : in  std_logic;
    AC_GPIO3    : in  std_logic;
    AC_MCLK     : out std_logic;
    
    ---nterface
    btn_up      : in  std_logic;
    btn_down    : in  std_logic;
    btn_left    : in  std_logic;
    btn_right   : in  std_logic;
    btn_center  : in  std_logic;
    btn_c       : in  std_logic;
    
    --SW&led
    SW          : in  std_logic_vector(6 downto 0);
    LD          : out std_logic_vector(7 downto 0);
    
   --XADC
    vauxp8      : in  std_logic;
    vauxn8      : in  std_logic;
    vauxp0      : in  std_logic;
    vauxn0      : in  std_logic
  );
end entity top_module;

architecture Behavioral of top_module is
--clk
  signal clk_48         : std_logic;
  signal reset          : std_logic := '0';
  signal sample_tick_48k : std_logic;
  --audio
  signal phase_inc      : unsigned(31 downto 0) := (others => '0');
  signal dds_out        : signed(15 downto 0);
  signal dds_valid      : std_logic;
  signal dds_square_out : signed(15 downto 0);
  signal dds_square_valid : std_logic;
  
--audio_processing
  signal selected_sample  : signed(15 downto 0) := (others => '0');
  signal filtered_sample  : signed(15 downto 0) := (others => '0');
  signal hp_l             : std_logic_vector(23 downto 0) := (others => '0');
  signal hp_r             : std_logic_vector(23 downto 0) := (others => '0');
  
  signal dc_accumulator : signed(31 downto 0) := (others => '0');
  signal dc_offset      : signed(15 downto 0) := (others => '0');
  signal filter_stage1  : signed(63 downto 0) := (others => '0');
  signal filter_stage2  : signed(63 downto 0) := (others => '0');
  signal noise_counter  : unsigned(15 downto 0) := (others => '0');
  signal dither        : signed(15 downto 0) := (others => '0');
  
 --XADC
  signal channel_out    : std_logic_vector(4 downto 0);
  signal do_data        : std_logic_vector(15 downto 0);
  signal drdy           : std_logic;
  signal pot_value      : unsigned(11 downto 0) := (others => '0');
  
 --SW
  signal sw_debounced     : std_logic_vector(1 downto 0) := "00";
  signal debounce_counter : integer range 0 to 480000 := 0;
  signal audio_enabled    : std_logic := '1';
  
--freq modulation 
  constant CLK_FREQ     : integer := 48_000_000;
  constant MAX_FREQ     : integer := 10_000;
  constant MIN_FREQ     : integer := 100;
  constant PHASE_SCALE  : unsigned(31 downto 0) := to_unsigned(89478, 32); -- 2^32/48000

  component clocking
    port(
      CLK_100 : in  std_logic;
      CLK_48  : out std_logic;
      RESET   : in  std_logic;
      LOCKED  : out std_logic
    );
  end component;

  component xadc_wiz_0
    port(
      daddr_in    : in  std_logic_vector(6 downto 0);
      dclk_in     : in  std_logic;
      den_in      : in  std_logic;
      di_in       : in  std_logic_vector(15 downto 0);
      dwe_in      : in  std_logic;
      vauxp8      : in  std_logic;
      vauxn8      : in  std_logic;
      busy_out    : out std_logic;
      channel_out : out std_logic_vector(4 downto 0);
      do_out      : out std_logic_vector(15 downto 0);
      drdy_out    : out std_logic;
      eoc_out     : out std_logic;
      eos_out     : out std_logic;
      alarm_out   : out std_logic
    );
  end component;

  component adau1761_izedboard
    port(
      clk_48     : in  std_logic;
      AC_GPIO1   : in  std_logic;
      AC_GPIO2   : in  std_logic;
      AC_GPIO3   : in  std_logic;
      hphone_l   : in  std_logic_vector(23 downto 0);
      hphone_r   : in  std_logic_vector(23 downto 0);
      AC_SDA     : inout std_logic;
      AC_ADR0    : out std_logic;
      AC_ADR1    : out std_logic;
      AC_GPIO0   : out std_logic;
      AC_MCLK    : out std_logic;
      AC_SCK     : out std_logic;
      line_in_l  : out std_logic_vector(23 downto 0);
      line_in_r  : out std_logic_vector(23 downto 0);
      new_sample : out std_logic;
      sw         : in  std_logic_vector(1 downto 0);
      active     : out std_logic_vector(1 downto 0)
    );
  end component;

  component dds_square
    generic(
      ADDR_WIDTH : positive := 12;
      DATA_WIDTH : positive := 16;
      FRAC_BITS  : positive := 4
    );
    port(
      clk       : in  std_logic;
      rst       : in  std_logic;
      en        : in  std_logic;
      PHASE_INC : in  unsigned(19 downto 0);
      square_o  : out signed(15 downto 0);
      valid     : out std_logic
    );
  end component;

begin
  --Clock buffer & PLL
  pll: clocking port map(
    CLK_100 => clk_100,
    CLK_48 => clk_48,
    RESET => reset,
    LOCKED => open
  );

  --Switch debouncing (10ms @ 48MHz)
  process(clk_48)
  begin
    if rising_edge(clk_48) then
      if debounce_counter < 480000 then
        debounce_counter <= debounce_counter + 1;
      else
        debounce_counter <= 0;
        sw_debounced <= SW(1 downto 0);
      end if;
    end if;
  end process;

  --XADC for potentiometer reading
  xadc_inst: xadc_wiz_0
    port map(
      daddr_in => "0011000",
      dclk_in => clk_48,
      den_in => '1',
      di_in => (others=>'0'),
      dwe_in => '0',
      vauxp8 => vauxp8,
      vauxn8 => vauxn8,
      busy_out => open,
      channel_out => channel_out,
      do_out => do_data,
      drdy_out => drdy,
      eoc_out => open,
      eos_out => open,
      alarm_out => open
    );

  --Read XADC values
  process(clk_48) 
  begin
    if rising_edge(clk_48) then
      if drdy = '1' and channel_out = "01000" then
        pot_value <= unsigned(do_data(15 downto 4));
      end if;
    end if;
  end process;

  --Fixed-point frequency calculation
  process(clk_48)
    variable freq_scaled : unsigned(31 downto 0);
  begin
    if rising_edge(clk_48) then
      freq_scaled := resize((pot_value * to_unsigned(MAX_FREQ - MIN_FREQ, 12)) / 4095, 32) + MIN_FREQ;
      phase_inc <= resize((freq_scaled * PHASE_SCALE), 32);
    end if;
  end process;

  --DDS Generator with 32-git phase accumulator
  process(clk_48)
    variable phase_acc : unsigned(31 downto 0) := (others => '0');
    variable lut_addr : integer range 0 to LUT_SIZE-1;
  begin
    if rising_edge(clk_48) then
      if sample_tick_48k = '1' then
        phase_acc := phase_acc + phase_inc;
        lut_addr := to_integer(phase_acc(31 downto 20));
        dds_out <= sine_lut(lut_addr);
        dds_valid <= '1';
      else
        dds_valid <= '0';
      end if;
    end if;
  end process;

  --Square wave generator
  dds_square_inst: dds_square
    generic map(
      ADDR_WIDTH => 12,
      DATA_WIDTH => 16,
      FRAC_BITS => 8
    )
    port map(
      clk => clk_48,
      rst => reset,
      en => sample_tick_48k,
      PHASE_INC => phase_inc(19 downto 0),
      square_o => dds_square_out,
      valid => dds_square_valid
    );

  -- Waveform selection
  process(clk_48)
  begin
    if rising_edge(clk_48) then
      if (dds_valid = '1' or dds_square_valid = '1') and audio_enabled = '1' then
        if sw_debounced(0) = '0' then
          selected_sample <= dds_out;
          LD(7) <= '0';
        else
          selected_sample <= dds_square_out;
          LD(7) <= '1';
        end if;
      elsif audio_enabled = '0' then
        selected_sample <= (others => '0');
      end if;
    end if;
  end process;

  --DC filter
  process(clk_48)
    constant alpha : signed(15 downto 0) := to_signed(3276, 16);
    variable temp : signed(31 downto 0);
  begin
    if rising_edge(clk_48) then
      if sample_tick_48k = '1' then
        temp := resize(selected_sample, 32) - resize(dc_offset, 32);
        dc_accumulator <= dc_accumulator + temp;
        dc_offset <= resize(dc_accumulator(31 downto 16), 16) + 
                    resize(alpha * dc_accumulator(15 downto 0), 16);
        filtered_sample <= selected_sample - dc_offset;
      end if;
    end if;
  end process;

  -- Low-pass filter
  process(clk_48)
    variable diff1 : signed(63 downto 0);
    variable diff2 : signed(63 downto 0);
    variable temp_in : signed(31 downto 0);
    variable temp_stage1 : signed(31 downto 0);
  begin
    if rising_edge(clk_48) then
      if sample_tick_48k = '1' then
        temp_in := resize(filtered_sample, 32);
        temp_stage1 := resize(filter_stage1(63 downto 32), 32);
        diff1 := resize(temp_in, 64) - resize(temp_stage1, 64);
        filter_stage1 <= filter_stage1 + diff1;
        
        temp_stage1 := resize(filter_stage1(63 downto 32), 32);
        diff2 := resize(temp_stage1, 64) - resize(signed(filter_stage2(63 downto 32)), 64);
        filter_stage2 <= filter_stage2 + diff2;
      end if;
    end if;
  end process;

  --Dithering
  process(clk_48)
    variable temp : signed(15 downto 0);
  begin
    if rising_edge(clk_48) then
      noise_counter <= noise_counter + 1;
      temp := resize(signed('0' & noise_counter(7 downto 0)), 16) - to_signed(128, 16);
      dither <= temp;
    end if;
  end process;

  -- Main output with volume control
  process(clk_48)
    variable final_sample : signed(63 downto 0);
    variable volume_gain : signed(15 downto 0);
    variable temp_sample : signed(31 downto 0);
    variable multiplied : signed(47 downto 0);
  begin
    if rising_edge(clk_48) then
      if sample_tick_48k = '1' then
        volume_gain := to_signed(256 + to_integer(unsigned(SW(3 downto 0))) * 16, 16);
        temp_sample := signed(filter_stage2(63 downto 32));
        multiplied := temp_sample * volume_gain;
        final_sample := resize(multiplied(47 downto 16), 64) + resize(dither, 64);
        
        if final_sample > to_signed(16777215, 64) then
          hp_l <= X"7FFFFF";
          hp_r <= X"7FFFFF";
        elsif final_sample < to_signed(-16777216, 64) then
          hp_l <= X"800000";
          hp_r <= X"800000";
        else
          hp_l <= std_logic_vector(resize(final_sample, 24));
          hp_r <= std_logic_vector(resize(final_sample, 24));
        end if;
      end if;
    end if;
  end process;

  --Audio enable control
  audio_enabled <= not sw_debounced(1);

  --LED indicators
  LD(6 downto 0) <= std_logic_vector(pot_value(11 downto 5));

  --Audio codec interface
  codec: adau1761_izedboard
    port map(
      clk_48 => clk_48,
      AC_GPIO1 => AC_GPIO1,
      AC_GPIO2 => AC_GPIO2,
      AC_GPIO3 => AC_GPIO3,
      hphone_l => hp_l,
      hphone_r => hp_r,
      AC_SDA => AC_SDA,
      AC_ADR0 => AC_ADR0,
      AC_ADR1 => AC_ADR1,
      AC_GPIO0 => AC_GPIO0,
      AC_MCLK => AC_MCLK,
      AC_SCK => AC_SCK,
      line_in_l => open,
      line_in_r => open,
      new_sample => sample_tick_48k,
      sw => "11",
      active => open
    );

end architecture Behavioral;