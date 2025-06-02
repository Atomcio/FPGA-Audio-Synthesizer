library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity i2c is
    port (
        clk        : in  std_logic;                    -- 48?MHz (clk_48)

        -- I²C magistrala
        i2c_sda_i  : in  std_logic;                    -- SDA z kodeka
        i2c_sda_o  : out std_logic;                    -- SDA wyj?cie FPGA
        i2c_sda_t  : out std_logic;                    -- ster. tri-state
        i2c_scl    : out std_logic;                    -- SCL


        sw     : in  std_logic_vector(1 downto 0);
        active : out std_logic_vector(1 downto 0)
    );
end entity;

architecture Behavioral of i2c is
    ----------------------------------------------------------------------------
    --  ATTRIBUTES DEBUG  ------------------------------------------------------
    ----------------------------------------------------------------------------
    attribute MARK_DEBUG : string;
    attribute MARK_DEBUG of i2c_scl   : signal is "true";
    attribute MARK_DEBUG of i2c_sda_i : signal is "true";
    attribute MARK_DEBUG of i2c_sda_o : signal is "true";
    attribute MARK_DEBUG of i2c_sda_t : signal is "true";
    ----------------------------------------------------------------------------

    component i3c2
        generic (
            clk_divide : std_logic_vector(7 downto 0)
        );
        port (
            clk          : in  std_logic;
            -- I²C linie
            i2c_sda_i    : in  std_logic;
            i2c_sda_o    : out std_logic;
            i2c_sda_t    : out std_logic;
            i2c_scl      : out std_logic;

            -- mikrokontroler instrukcji
            inst_data    : in  std_logic_vector(8 downto 0);
            inputs       : in  std_logic_vector(15 downto 0);
            inst_address : out std_logic_vector(9 downto 0);

            -- debug (nieu?ywane)
            debug_sda    : out std_logic;
            debug_scl    : out std_logic;

            outputs      : out std_logic_vector(15 downto 0);
            reg_addr     : out std_logic_vector(4 downto 0);
            reg_data     : out std_logic_vector(7 downto 0);
            reg_write    : out std_logic;
            error        : out std_logic
        );
    end component;

    component adau1761_configuraiton_data
        port (
            clk     : in  std_logic;
            address : in  std_logic_vector(9 downto 0);
            data    : out std_logic_vector(8 downto 0)
        );
    end component;

    -- wewn?trzne sygna?y steruj?ce sekwencj?
    signal inst_address  : std_logic_vector(9 downto 0);
    signal inst_data     : std_logic_vector(8 downto 0);
    signal sw_full       : std_logic_vector(15 downto 0) := (others => '0');
    signal active_full   : std_logic_vector(15 downto 0) := (others => '0');

    -- dodatkowe debug (ilo?? bitów, busy) - je?li chcesz je podgl?da?,
    -- wystarczy odkomentowa? MARK_DEBUG
    -- attribute MARK_DEBUG of inst_address : signal is "true";
    -- attribute MARK_DEBUG of inst_data    : signal is "true";

begin
    ---------------------------------------------------------------------------
    -- mapowanie prze??czników / aktywno?ci na 16-bitowe wektory (oryginalny kod)
    sw_full(1 downto 0)  <= sw;
    active               <= active_full(1 downto 0);

    ---------------------------------------------------------------------------
    -- ROM z sekwencj? konfiguracji
    Inst_adau1761_configuraiton_data : adau1761_configuraiton_data
        port map (
            clk     => clk,
            address => inst_address,
            data    => inst_data
        );

    ---------------------------------------------------------------------------
    -- w?a?ciwy kontroler I²C
    Inst_i3c2 : i3c2
        generic map (
            -- 48?MHz / 120 = 400?kHz SCL  (dzia?a tak?e z 200 kHz)
            clk_divide => "01111000"
        )
        port map (
            clk          => clk,

            -- I²C linie
            i2c_scl      => i2c_scl,
            i2c_sda_i    => i2c_sda_i,
            i2c_sda_o    => i2c_sda_o,
            i2c_sda_t    => i2c_sda_t,

            -- sterowanie mikro-ROMem
            inst_address => inst_address,
            inst_data    => inst_data,

            -- dodatkowe porty (nieu?ywane w tym projekcie)
            inputs       => sw_full,
            outputs      => active_full,
            reg_addr     => open,
            reg_data     => open,
            reg_write    => open,
            debug_scl    => open,
            debug_sda    => open,
            error        => open
        );

end architecture;
