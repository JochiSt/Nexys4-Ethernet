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
-- This module provides Transceiver design with 2 clocks:
-- - 50mhz clock, which is reference clock for the ethernet chip and
-- - 50mhz_shifted clock, which is used for write Tx operations.
-- 50mhz_shift clock is shifted by -pi/2 with respect to 50mhz clock
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

entity clock_mod is
--    Generic ( M_clk : integer);
	 Port ( clk100mhz : in  STD_LOGIC;
           clk_out : out  STD_LOGIC;
			  clk_out_shift: out STD_LOGIC);
end clock_mod;

architecture Behavioral of clock_mod is

signal temp_clk : std_logic := '0';
signal temp_clk_shift : std_logic := '1';
--signal count : integer range 0 to M_clk-1 :=0;

begin
	
	clock: process (clk100mhz)
	begin
		if (rising_edge(clk100mhz)) then
		temp_clk <= not(temp_clk);
		end if;
	end process clock;
	
	shift_clock: process (clk100mhz)
	begin
		if (falling_edge(clk100mhz)) then
			temp_clk_shift <= not(temp_clk_shift);
		end if;
	end process shift_clock;
	
	clk_out <= temp_clk;
	clk_out_shift <= temp_clk_shift;

end Behavioral;

