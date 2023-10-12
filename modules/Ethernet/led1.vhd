----------------------------------------------------------------------------------
-- Company: The Hong Kong Polytechnic University
-- Engineer: Alexandr Melnikov 
-- 
-- Create Date:    14:15:42 03/30/2017 
-- Design Name: 
-- Module Name:    led1 - Behavioral 
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
-- LED module visualise inflow of the valid data packets changing the colour of the 
-- tri-colour LED's every time when valid ARP or UDP packet arrives
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

entity led1 is
    Port ( clk50mhz : in  STD_LOGIC;
			  rstn : in STD_LOGIC;
           dv_arp : in  STD_LOGIC;
			  dv_eth : in  STD_LOGIC;
           led16_b : out  STD_LOGIC;
			  led16_g : out  STD_LOGIC;
			  led16_r : out  STD_LOGIC;
			  led17_b : out  STD_LOGIC;
			  led17_g : out  STD_LOGIC;
			  led17_r : out  STD_LOGIC);
end led1;

architecture Behavioral of led1 is
type state_type is (idle,arp_signal,eth_signal);
signal state : state_type := idle;
signal count_arp : integer range 0 to 3 := 0;
signal count_eth : integer range 0 to 3 := 0;

begin
	led: process (clk50mhz,rstn,dv_arp,dv_eth)
	begin
		if (rstn = '0') then -- if Hardware Reset refresh counters and turn off led's
			led16_b <= '0'; led16_g <= '0'; led16_r <= '0';
			led17_b <= '0'; led17_g <= '0'; led17_r <= '0';
			count_arp <= 0;
			count_eth <= 0;
		elsif (rising_edge(clk50mhz)) then
			if (dv_arp ='1') then 			-- if valid ARP packet received
				count_arp <= count_arp+1;  -- increment ARP counter 
				if(count_arp+1 > 3) then
					count_arp <= 1;
				end if;
			else
				count_arp <= count_arp;
			end if;
				case count_arp is -- change ARP's led colour depending on the packet number 
					when 0 => led16_b <= '0'; led16_g <= '0'; led16_r <= '0';
					when 1 => led16_b <= '1'; led16_g <= '0'; led16_r <= '0';
					when 2 => led16_b <= '0'; led16_g <= '1'; led16_r <= '0';
					when 3 => led16_b <= '0'; led16_g <= '0'; led16_r <= '1';
				end case;
			
			if (dv_eth ='1') then       -- if valid UDP packet received
				count_eth <= count_eth+1;-- increment UDP counter 
				if(count_eth+1 > 3) then
					count_eth <= 1;
				end if;
			else
				count_eth <= count_eth;
			end if;
				case count_eth is -- change UDP's led colour depending on the packet number 
					when 0 => led17_b <= '0'; led17_g <= '0'; led17_r <= '0';
					when 1 => led17_b <= '1'; led17_g <= '0'; led17_r <= '0';
					when 2 => led17_b <= '0'; led17_g <= '1'; led17_r <= '0';
					when 3 => led17_b <= '0'; led17_g <= '0'; led17_r <= '1';
				end case;
		end if;
	end process led;

end Behavioral;

