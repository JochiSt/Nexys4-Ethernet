----------------------------------------------------------------------------------
-- Company: The Hong Kong Polytechnic University
-- Engineer: Alexandr Melnikov
-- 
-- Create Date:    14:56:38 02/16/2017 
-- Design Name: 
-- Module Name:    clock_mod - Behavioral 
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
-- This module generates 2.5mhz clocks for the SMI interface.
-- 2.5mhz clock is the MDC clock and 2.5mhz_shift clock is used for read/write
-- MDIO operations and it's shifted by -pi/2 with respect to 2.5mhz clock
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity clock_mod2 is
    Generic ( M_clk1 : integer;
				  M_clk2 : integer);
	 Port ( clk100mhz : in  STD_LOGIC;
           clk_out1 : out  STD_LOGIC;
			  clk_out2 : out STD_LOGIC);
end clock_mod2;

architecture Behavioral of clock_mod2 is

signal temp_clk1 : std_logic := '0';
signal temp_clk2 : std_logic := '0';
signal count1 : integer range 0 to M_clk1-1 :=0;
signal count2 : integer range 0 to M_clk1+M_clk1-1 :=0;

begin
	
	clock1: process (clk100mhz)
	begin
		if (rising_edge(clk100mhz)) then
			if (count1 < M_clk1-1) then
				count1 <= count1+1;
			elsif (count1 = M_clk1-1) then
				count1 <= 0;
				temp_clk1 <= not (temp_clk1);
			end if;
		end if;
	end process clock1;
	
	clock2: process (clk100mhz)
	begin
		if (rising_edge(clk100mhz)) then
			if (count2 < M_clk1-1 and count2 <= M_clk2-1) then
				count2 <= count2+1;
			elsif (count2 < M_clk1-1 and count2 = M_clk2) then
				count2 <= count2+1;
				temp_clk2 <= not (temp_clk2);
			elsif (count2 <= (M_clk1+M_clk2-1)) then
				count2 <= count2+1;
			elsif (count2 = (M_clk1+M_clk2)) then
				count2 <= count2+1;
				temp_clk2 <= not (temp_clk2);
			elsif (count2 < (M_clk1+M_clk1-1)) then
				count2 <= count2+1;
			elsif (count2 = (M_clk1+M_clk1-1))then
				count2 <= 0;
			end if;
		end if;
	end process clock2;
	
	clk_out1 <= temp_clk1;
	clk_out2 <= temp_clk2;

end Behavioral;

