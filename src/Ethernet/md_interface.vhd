----------------------------------------------------------------------------------
-- Company: The Hong Kong Polytechnic University
-- Engineer: Alexandr Melnikov 
-- 
-- Create Date:    10:34:00 02/22/2017 
-- Design Name: 
-- Module Name:    md_interface - Behavioral 
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
-- MDIO interface reads content of the SMI registers selected by input sw<4:0> and displays 
-- their content using 16 on-board LED's
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
library UNISIM;
use UNISIM.VComponents.all;

entity md_interface is
    Port ( mdc_shift : in STD_LOGIC; -- clock for read/write SMI
           mdio : inout  STD_LOGIC;  -- SMI data in/out line
           eth_rstn : in  STD_LOGIC; -- reset
           led : out  STD_LOGIC_VECTOR (15 downto 0); -- display for SMI registers
           sw : in  STD_LOGIC_VECTOR (4 downto 0));   -- SMI register address
end md_interface;

architecture Behavioral of md_interface is

signal mdio_prime : std_logic;
constant preamble : std_logic_vector (31 downto 0) := x"FFFFFFFF"; -- preamble 32 1's
constant start : std_logic_vector (1 downto 0) := "01";            -- start-of-frame
constant wrt_mdio : std_logic_vector (1 downto 0) := "01";         -- code of write operation
constant phy_addr : std_logic_vector (4 downto 0) := "00001";      -- physical address of chip
signal reg_addr : std_logic_vector (4 downto 0);                   -- SMI register's address
signal reg_data : std_logic_vector (15 downto 0);                  -- content of the SMI register
type state_type is (idle, read_mdio);--, write_mdio);
signal state : state_type := idle;
signal counter : integer range  0 to 63 := 0;

begin
-- pull-up on I2C MDIO pin
	PULLUP_MDIO: PULLUP PORT MAP (O => mdio);

	mdio_interface: process (mdc_shift, eth_rstn)
	begin
		if (eth_rstn = '0') then
			counter <= 0;
			state <= idle;
		elsif (rising_edge(mdc_shift)) then
			case state is
			
			-- SMI module remains idle during reset
			when idle =>
				counter <= 0;
				state <= read_mdio;
			
			-- in this state the SMI register, selected by sw<4:0> is read
			when read_mdio =>
				-- write preamble
				if (counter <= 31) then
					mdio_prime <= preamble(counter);
					counter <= counter+1;
					state <= read_mdio;
				-- write start-of-frame bits
				elsif (counter > 31 and counter <= 33)then
					mdio_prime <= start(33-counter);
					counter <= counter+1;
					state <= read_mdio;
				-- write operation code (read)
				elsif (counter > 33 and counter <= 35) then
					mdio_prime <= not(wrt_mdio(35-counter)); -- not(write) is read
					counter <= counter+1;
					state <= read_mdio;
				-- write physical address of the device
				elsif (counter > 35 and counter <=40) then
					mdio_prime <= phy_addr(40-counter);
					counter <= counter+1;
					state <= read_mdio;
				-- write register address to be read (sw<4:0>)
				elsif (counter > 40 and counter <= 45) then
					mdio_prime <= reg_addr(45-counter);
					counter <= counter+1;
					state <= read_mdio;
				-- release line for turnaround bits
				elsif (counter = 46 or counter = 47) then
					mdio_prime <= '1'; --
					counter <= counter+1;
					state <= read_mdio;
				-- read register's content
				elsif (counter > 47 and counter < 63) then
					reg_data(63-counter) <= mdio;
					counter <= counter+1;
					state <= read_mdio;
				elsif (counter = 63) then
					reg_data(63-counter) <= mdio;
					counter <= 0;
					state <= idle; -- go back to idle
				end if;
			
			-- this state handles write SMI operation (not used in this design)
--			when write_mdio =>
--				read_done <= '0';
--				if (counter <= 31) then
--					mdio_prime <= preamble(counter);
--					counter <= counter+1;
--					state <= write_mdio;
--				elsif (counter > 31 and counter <= 33)then
--					mdio_prime <= start(33-counter);
--					counter <= counter+1;
--					state <= write_mdio;
--				elsif (counter > 33 and counter <= 35) then
--					mdio_prime <= wrt_mdio(35-counter);
--					counter <= counter+1;
--					state <= write_mdio;
--				elsif (counter > 35 and counter <=40) then
--					mdio_prime <= phy_addr(40-counter);
--					counter <= counter+1;
--					state <= write_mdio;
--				elsif (counter > 40 and counter <= 45) then
--					mdio_prime <= reg_addr_wrt(45-counter);
--					counter <= counter+1;
--					state <= write_mdio;
--				elsif (counter = 46 or counter = 47) then -- turnaround bits
--					mdio_prime <= '1';--
--					counter <= counter+1;
--					state <= write_mdio;
--				elsif (counter > 47 and counter < 63) then
--					mdio_prime <= reg_data_wrt(63-counter);
--					counter <= counter+1;
--					state <= write_mdio;
--				elsif (counter = 63) then
--					mdio_prime <= reg_data_wrt(63-counter);
--					counter <= 0;
--					write_done <= '1';
--					state <= idle;
--				end if;
			
			end case;
		end if;
	end process mdio_interface;
	

led <= reg_data; -- display content of the SMI register
reg_addr <= sw;  -- read this register's content
mdio <= '0' when mdio_prime = '0' else 'Z';

end Behavioral;

