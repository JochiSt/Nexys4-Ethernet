----------------------------------------------------------------------------------
-- Company: The Hong Kong Polytechnic University
-- Engineer: Alexandr Melnikov
-- 
-- Create Date:    14:58:05 02/19/2017 
-- Design Name: 
-- Module Name:    debounce_switch - Behavioral 
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
-- This module is responsible for debouncing Hardware Reset button
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

entity debounce_switch is
	 Generic (N : integer);
    Port ( clk100mhz : in  STD_LOGIC;
           btn : in  STD_LOGIC;
           db_sw : out  STD_LOGIC);
end debounce_switch;

architecture Behavioral of debounce_switch is

	type state_type is (zero, one, wait0, wait1, init);
	signal state : state_type := init;
	signal timer : unsigned (N-1 downto 0) := (others => '0');
	signal sw : std_logic;

begin
	
	debouncer: process (clk100mhz,btn)
	begin
		if (rising_edge(clk100mhz)) then
			case state is
			
				when init =>
					timer <= (others => '1');
					db_sw <= btn;
					sw <= btn;
					if (btn = '0') then
						state <= zero;
					elsif (btn = '1') then
						state <= one;
					end if;
				
				when zero =>
					sw <= btn;
					db_sw <= '0';
					if (sw /= btn) then
						state <= wait1;
					elsif (sw = btn) then
						state <= zero;
					end if;
				
				when wait1 =>
					sw <= btn;
					if (timer > 0) then
						timer <= timer-1;
						db_sw <= '0';
						state <= wait1;
					elsif (timer = 0) then
						db_sw <= btn;
						state <= init;
					end if;
				
				when one =>
					sw <= btn;
					db_sw <= '1';
					if (sw /= btn) then
						state <= wait0;
					elsif (sw = btn) then
						state <= one;
					end if;
				
				when wait0 =>
					sw <= btn;
					if (timer > 0) then
						timer <= timer-1;
						db_sw <= '1';
						state <= wait0;
					elsif (timer = 0) then
						db_sw <= btn;
						state <= init;
					end if;
						
					
			end case;
		end if;
	end process debouncer;

end Behavioral;

