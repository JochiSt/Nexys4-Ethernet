library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity top is
    Port (
        -- main CLOCK
        CLK100MHz   : in    STD_LOGIC;
       
        -- UART RX and TX
        RsRx        : in    STD_LOGIC;
        RsTx        : out   STD_LOGIC;

        -- LEDs and Buttons
        led         : out   STD_LOGIC_VECTOR (15 downto 0);
        btnCpuReset : in    STD_LOGIC;
        
        -- connections to the Ethernet PHY
        PhyMdc      : out   STD_LOGIC;
        PhyMdio     : inout STD_LOGIC;				
        PhyRstn     : out   STD_LOGIC;				
        PhyCrs      : in    STD_LOGIC;						
        PhyRxErr    : in    STD_LOGIC;			
        PhyRxd      : in    STD_LOGIC_VECTOR(1 downto 0);				
        PhyTxEn     : out   STD_LOGIC;					
        PhyTxd      : out   STD_LOGIC_VECTOR(1 downto 0);	
        PhyClk50Mhz : out   STD_LOGIC;		
        PhyIntn     : in    STD_LOGIC			
    );
end top;

architecture Behavioral of top is

begin
    LED(15 downto 1) <= (others => '0') ;
    LED(0) <= btnCpuReset;
end Behavioral;