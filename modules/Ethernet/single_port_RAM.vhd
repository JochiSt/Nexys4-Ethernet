----------------------------------------------------------------------------------
-- Company: The Hong Kong Polytechnic University
-- Engineer: Alexandr Melnikov 
-- 
-- Create Date:    17:24:25 02/19/2017 
-- Design Name: 
-- Module Name:    single_port_RAM - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
-- RAM module stores the data received with incoming packets and supplies it back to 
-- Transmitter module for outgoing packets
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity single_port_RAM is
	 Generic ( ADDR_WIDTH : integer;
				  DATA_WIDTH : integer);
    Port ( clk50mhz : in  STD_LOGIC; -- reference clock
           we : in  STD_LOGIC;       -- write enable
			  re : in STD_LOGIC;        -- read enable
           addr_r : in  STD_LOGIC_VECTOR (ADDR_WIDTH-1 downto 0); -- address to write
			  addr_w : in  STD_LOGIC_VECTOR (ADDR_WIDTH-1 downto 0); -- address to read
           din : in  STD_LOGIC_VECTOR (DATA_WIDTH-1 downto 0);    -- data-in bus
           dout : out  STD_LOGIC_VECTOR (DATA_WIDTH-1 downto 0)); -- data-out bus
end single_port_RAM;

architecture Behavioral of single_port_RAM is

type ram_type is array (2**ADDR_WIDTH-1 downto 0) of 
	std_logic_vector (DATA_WIDTH-1 downto 0);
signal ram: ram_type := (others =>(others => '0'));

begin
	
	memory: process (clk50mhz)
	begin
		if (rising_edge(clk50mhz)) then
			if (we = '1') then -- when write is enabled
				ram(to_integer(unsigned(addr_w))) <= din; -- write data on data-in bus into specified in addr_w register
			end if;
			if (re = '1') then -- when read is enabled
				dout <= ram(to_integer(unsigned(addr_r)));-- read data from specified in addr_r register and place it on data-out bus
			end if;
		end if;
	end process memory;

end Behavioral;

