----------------------------------------------------------------------------------
-- Company: The Hong Kong Polytechnic University
-- Engineer: Alexandr Melnikov
-- 
-- Create Date:    15:13:21 03/26/2017 
-- Design Name: 
-- Module Name:    crc32_parallel - Behavioral 
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
-- Cyclic Redundancy Check (CRC) module calculates the packet's crc and supplies 
-- it back to the higher-level module. It performs calculations in parallel (2-bit
-- wide) and uses 100mhz clock, whereas the rest of the server makes use of 50mhz clock.
-- This allows to do crc calculations in parallel with reception and transmission of data
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

entity crc32_parallel is
    Port ( clk100mhz : in  STD_LOGIC;
           data_valid : in  STD_LOGIC; -- crc_start
           rstn : in  STD_LOGIC;		   -- crc_stop
           data_in : in  STD_LOGIC_VECTOR (1 downto 0); -- connected to rxd bus
           crc : inout  STD_LOGIC_VECTOR (31 downto 0)); -- output for crc results
end crc32_parallel;

architecture Behavioral of crc32_parallel is
type state_type is (idle, calc);
signal state : state_type := idle;
signal crc32_temp : std_logic_vector (31 downto 0);
signal edge_count : std_logic;

begin
	-- because crc block works on 100mhz clock and processes the whole data nibble
	-- during the single 100mhz clock period it uses edge_count to keep track of whether
	-- the data on the bus has been processed already or not
	-- crc made this way to make sure that crc block can calculate the crc value for the
	-- packet being transmitted as this packed is actually being transmitted
	-- and the results of crc calculations are available before transmitter starts
	-- sending the crc results out
	-- so, in fact, crc calculations are done in parallel with packet transmission
	crc_32_2bit: process (clk100mhz,rstn)
	begin
		-- during reset state set all registers and flags to initial state
		if (rstn = '1') then
			crc32_temp <= (others => '1'); -- initial state of crc register
			edge_count <= '0'; 				 -- keeps track of incoming data
			state <= idle;
		elsif (rising_edge(clk100mhz)) then
			case state is
			
			-- in idle state crc block waits for the data_valid flag to be asserted 
			when idle =>
			crc32_temp <= (others => '1');
			edge_count <= '0';
			if (data_valid = '0') then
				state <= idle;
			-- once data_valid is asserted, calculate crc for the current data nibble
			-- and invert edge_count
			-- crc processes data nibbles on edge_count='0' only
			elsif(data_valid = '1') then
				crc32_temp(0) <= crc32_temp(30) xor data_in(1);
				crc32_temp(1) <= (crc32_temp(30) xor data_in(1)) xor (crc32_temp(31) xor data_in(0));
				crc32_temp(2) <= (crc32_temp(30) xor data_in(1)) xor (crc32_temp(31) xor data_in(0)) xor crc32_temp(0);
				crc32_temp(3) <= (crc32_temp(31) xor data_in(0)) xor crc32_temp(1);
				crc32_temp(4) <= (crc32_temp(30) xor data_in(1)) xor crc32_temp(2);
				crc32_temp(5) <= (crc32_temp(30) xor data_in(1)) xor (crc32_temp(31) xor data_in(0)) xor crc32_temp(3);
				crc32_temp(6) <= (crc32_temp(31) xor data_in(0)) xor crc32_temp(4);
				crc32_temp(7) <= (crc32_temp(30) xor data_in(1)) xor crc32_temp(5);
				crc32_temp(8) <= (crc32_temp(30) xor data_in(1)) xor (crc32_temp(31) xor data_in(0)) xor crc32_temp(6);
				crc32_temp(9) <= (crc32_temp(31) xor data_in(0)) xor crc32_temp(7);
				crc32_temp(10) <= (crc32_temp(30) xor data_in(1)) xor crc32_temp(8);
				crc32_temp(11) <= (crc32_temp(30) xor data_in(1)) xor (crc32_temp(31) xor data_in(0)) xor crc32_temp(9);
				crc32_temp(12) <= (crc32_temp(30) xor data_in(1)) xor (crc32_temp(31) xor data_in(0)) xor crc32_temp(10);
				crc32_temp(13) <= (crc32_temp(31) xor data_in(0)) xor crc32_temp(11);
				crc32_temp(14) <= crc32_temp(12);
				crc32_temp(15) <= crc32_temp(13);
				crc32_temp(16) <= (crc32_temp(30) xor data_in(1)) xor crc32_temp(14);
				crc32_temp(17) <= (crc32_temp(31) xor data_in(0)) xor crc32_temp(15);
				crc32_temp(18) <= crc32_temp(16);
				crc32_temp(19) <= crc32_temp(17);
				crc32_temp(20) <= crc32_temp(18);
				crc32_temp(21) <= crc32_temp(19);
				crc32_temp(22) <= (crc32_temp(30) xor data_in(1)) xor crc32_temp(20);
				crc32_temp(23) <= (crc32_temp(30) xor data_in(1)) xor (crc32_temp(31) xor data_in(0)) xor crc32_temp(21);
				crc32_temp(24) <= (crc32_temp(31) xor data_in(0)) xor crc32_temp(22);
				crc32_temp(25) <= crc32_temp(23);
				crc32_temp(26) <= (crc32_temp(30) xor data_in(1)) xor crc32_temp(24);
				crc32_temp(27) <= (crc32_temp(31) xor data_in(0)) xor crc32_temp(25);
				crc32_temp(28) <= crc32_temp(26);
				crc32_temp(29) <= crc32_temp(27);
				crc32_temp(30) <= crc32_temp(28);
				crc32_temp(31) <= crc32_temp(29);
				edge_count <= not(edge_count);
				state <= calc;
			end if;
		
			when calc => 
			-- if valid data present on the bus
			if (data_valid = '1') then
				-- do nothing if edge_count = '1', just keep current crc result = to past crc result
				if (edge_count = '1') then
					edge_count <= not(edge_count);
					crc32_temp <= crc32_temp;
					state <= calc;
				-- if edge_count = '0' calculate crc result for the new data nibble
				elsif (edge_count = '0') then
					edge_count <= not(edge_count);
					---
					crc32_temp(0) <= crc32_temp(30) xor data_in(1);
					crc32_temp(1) <= (crc32_temp(30) xor data_in(1)) xor (crc32_temp(31) xor data_in(0));
					crc32_temp(2) <= (crc32_temp(30) xor data_in(1)) xor (crc32_temp(31) xor data_in(0)) xor crc32_temp(0);
					crc32_temp(3) <= (crc32_temp(31) xor data_in(0)) xor crc32_temp(1);
					crc32_temp(4) <= (crc32_temp(30) xor data_in(1)) xor crc32_temp(2);
					crc32_temp(5) <= (crc32_temp(30) xor data_in(1)) xor (crc32_temp(31) xor data_in(0)) xor crc32_temp(3);
					crc32_temp(6) <= (crc32_temp(31) xor data_in(0)) xor crc32_temp(4);
					crc32_temp(7) <= (crc32_temp(30) xor data_in(1)) xor crc32_temp(5);
					crc32_temp(8) <= (crc32_temp(30) xor data_in(1)) xor (crc32_temp(31) xor data_in(0)) xor crc32_temp(6);
					crc32_temp(9) <= (crc32_temp(31) xor data_in(0)) xor crc32_temp(7);
					crc32_temp(10) <= (crc32_temp(30) xor data_in(1)) xor crc32_temp(8);
					crc32_temp(11) <= (crc32_temp(30) xor data_in(1)) xor (crc32_temp(31) xor data_in(0)) xor crc32_temp(9);
					crc32_temp(12) <= (crc32_temp(30) xor data_in(1)) xor (crc32_temp(31) xor data_in(0)) xor crc32_temp(10);
					crc32_temp(13) <= (crc32_temp(31) xor data_in(0)) xor crc32_temp(11);
					crc32_temp(14) <= crc32_temp(12);
					crc32_temp(15) <= crc32_temp(13);
					crc32_temp(16) <= (crc32_temp(30) xor data_in(1)) xor crc32_temp(14);
					crc32_temp(17) <= (crc32_temp(31) xor data_in(0)) xor crc32_temp(15);
					crc32_temp(18) <= crc32_temp(16);
					crc32_temp(19) <= crc32_temp(17);
					crc32_temp(20) <= crc32_temp(18);
					crc32_temp(21) <= crc32_temp(19);
					crc32_temp(22) <= (crc32_temp(30) xor data_in(1)) xor crc32_temp(20);
					crc32_temp(23) <= (crc32_temp(30) xor data_in(1)) xor (crc32_temp(31) xor data_in(0)) xor crc32_temp(21);
					crc32_temp(24) <= (crc32_temp(31) xor data_in(0)) xor crc32_temp(22);
					crc32_temp(25) <= crc32_temp(23);
					crc32_temp(26) <= (crc32_temp(30) xor data_in(1)) xor crc32_temp(24);
					crc32_temp(27) <= (crc32_temp(31) xor data_in(0)) xor crc32_temp(25);
					crc32_temp(28) <= crc32_temp(26);
					crc32_temp(29) <= crc32_temp(27);
					crc32_temp(30) <= crc32_temp(28);
					crc32_temp(31) <= crc32_temp(29);
					state <= calc;
				end if;
			-- if data valid is deasserted, that means that the last valid data nibble, protected by crc,
			-- has been already loaded to the Tx bus and the current crc result is the valid crc value for the
			-- packet being transmitted
			elsif (data_valid <= '0') then
				edge_count <= '0';
				state <= idle;
			end if;
		
		end case;
		end if;
	end process crc_32_2bit;
	
	-- this process outputs calculated crc value to the upper level module on every
	-- edge_count = '1' (i.e. on every 2nd 100mhz clock period)
	crc_out: process (clk100mhz,crc,crc32_temp,edge_count)
	begin
		if (rising_edge(clk100mhz) and edge_count = '1') then
			crc <= not(crc32_temp);
		else
			crc <= crc;
		end if;
	end process crc_out;

end Behavioral;

