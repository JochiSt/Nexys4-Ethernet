--------------------------------------------------------------------------------
-- Company: The Hong Kong Polytechnic University
-- Engineer: Alexandr Melnikov
--
-- Create Date:   14:39:20 04/06/2017
-- Design Name:   
-- Module Name:   C:/Users/AM/Documents/ISE_projects/Nexyx4DDR/Ethernet/Ethernet_arp_udp_ram/eth_transceiver/tb_eth_rxtx_arp_udp_ram.vhd
-- Project Name:  eth_transceiver
-- Target Device:  
-- Tool versions:  
-- Description:   
-- 
-- VHDL Test Bench Created by ISE for module: ethernet_transciever
-- 
-- Dependencies:
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- This testbench file is used to test functionality of the UDP echo-server.
-- First packet is ARP request being sent to echo-server from external
-- data server to resolve the board's MAC address.
-- 2nd and 4th packets are valid UDP messages of diffrent length and
-- 3rd packet is invalid UDP message designated to the wrong port number.
--
-- Notes: 
-- This testbench has been automatically generated using types std_logic and
-- std_logic_vector for the ports of the unit under test.  Xilinx recommends
-- that these types always be used for the top-level I/O of a design in order
-- to guarantee that the testbench will bind correctly to the post-implementation 
-- simulation model.
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
 
-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--USE ieee.numeric_std.ALL;
 
ENTITY tb_eth_rxtx_arp_udp_ram IS
END tb_eth_rxtx_arp_udp_ram;
 
ARCHITECTURE behavior OF tb_eth_rxtx_arp_udp_ram IS 
 
    -- Component Declaration for the Unit Under Test (UUT)
 
    COMPONENT ethernet_transciever
    PORT(
         clk100mhz : IN  std_logic;
         eth_rxd : INOUT  std_logic_vector(1 downto 0);
         eth_txd : INOUT  std_logic_vector(1 downto 0);
         eth_crsdv : INOUT  std_logic;
         led16_b : OUT  std_logic;
         led16_g : OUT  std_logic;
         led16_r : OUT  std_logic;
         led17_b : OUT  std_logic;
         led17_g : OUT  std_logic;
         led17_r : OUT  std_logic;
         eth_mdc : OUT  std_logic;
         eth_mdio : INOUT  std_logic;
         eth_refclk : OUT  std_logic;
         eth_rstn : INOUT  std_logic;
--         mode0 : OUT  std_logic;
--         mode1 : OUT  std_logic;
--         mode2 : OUT  std_logic;
--         refclk : OUT  std_logic;
--         rxerr : OUT  std_logic;
         btn_reset : IN  std_logic;
         led : OUT  std_logic_vector(15 downto 0);
         sw : IN  std_logic_vector(4 downto 0);
         eth_txen : OUT  std_logic;
         eth_rxerr : INOUT  std_logic
        );
    END COMPONENT;
    

   --Inputs
   signal clk100mhz : std_logic := '0';
   signal btn_reset : std_logic := '0';
   signal sw : std_logic_vector(4 downto 0) := (others => '0');

	--BiDirs
   signal eth_rxd : std_logic_vector(1 downto 0);
   signal eth_txd : std_logic_vector(1 downto 0);
   signal eth_crsdv : std_logic;
   signal eth_mdio : std_logic;
   signal eth_rstn : std_logic;
   signal eth_rxerr : std_logic;

 	--Outputs
   signal led16_b : std_logic;
   signal led16_g : std_logic;
   signal led16_r : std_logic;
   signal led17_b : std_logic;
   signal led17_g : std_logic;
   signal led17_r : std_logic;
   signal eth_mdc : std_logic;
   signal eth_refclk : std_logic;
--   signal mode0 : std_logic;
--   signal mode1 : std_logic;
--   signal mode2 : std_logic;
--   signal refclk : std_logic;
--   signal rxerr : std_logic;
   signal led : std_logic_vector(15 downto 0);
   signal eth_txen : std_logic;

   -- Clock period definitions
   constant clk100mhz_period : time := 10 ns;
   constant eth_refclk_period : time := 20 ns;
   ---
	signal data_arp : std_logic_vector(591 downto 0);
	signal data_udp1 : std_logic_vector(591 downto 0);
	signal data_udp2 : std_logic_vector(591 downto 0);
	signal data_udp_err : std_logic_vector(591 downto 0);
 
BEGIN
 
	-- Instantiate the Unit Under Test (UUT)
   uut: ethernet_transciever PORT MAP (
          clk100mhz => clk100mhz,
          eth_rxd => eth_rxd,
          eth_txd => eth_txd,
          eth_crsdv => eth_crsdv,
          led16_b => led16_b,
          led16_g => led16_g,
          led16_r => led16_r,
          led17_b => led17_b,
          led17_g => led17_g,
          led17_r => led17_r,
          eth_mdc => eth_mdc,
          eth_mdio => eth_mdio,
          eth_refclk => eth_refclk,
          eth_rstn => eth_rstn,
--          mode0 => mode0,
--          mode1 => mode1,
--          mode2 => mode2,
--          refclk => refclk,
--          rxerr => rxerr,
          btn_reset => btn_reset,
          led => led,
          sw => sw,
          eth_txen => eth_txen,
          eth_rxerr => eth_rxerr
        );

   -- Clock process definitions
   clk100mhz_process :process
   begin
		clk100mhz <= '0';
		wait for clk100mhz_period/2;
		clk100mhz <= '1';
		wait for clk100mhz_period/2;
   end process;
 
   -- Stimulus process
   stim_proc: process
   begin		
      eth_crsdv <= '0';
		eth_rxd <= "00";
		eth_rxerr <= '0';
		data_arp <= x"0000aaaaaaaaaaaaaaabffffffffffff0007326ce4a6106000801000602000800007326ce4a6031580e00000000000000315805000000000000000000000000000000000000076052b35";
		data_udp1 <= x"0000aaaaaaaaaaaaaaab00187c80ff8e0007326ce4a61000a20000a4e87e00000188f917031580e0031580506344c74600889d0b8040c020a060e0109000000000000000000014045003";
		data_udp2 <= x"0000aaaaaaaaaaaaaaab00187c80ff8e0007326ce4a61000a20000b44c2b000001882151031580e0031580506344c74600983828f70f8f4fcf2faf6fef1f9f5fdf3fbf7fff009e1a4c3a";
      data_udp_err <= x"0000aaaaaaaaaaaaaaab00187c80ff8e0007326ce4a61000a20000b44c2b000001882151031580e0031580506344c74500983829f60e8c3fce21af2def7f1a57df01b67bee009e1a4c3a";
		
		wait for 51 ms;
		wait for 5 ns;

		eth_crsdv <= '1';
		for j in 295 downto 0 loop
			eth_rxd(0) <= data_arp (2*j+1);
			eth_rxd(1) <= data_arp (2*j);
			if (j > 0) then
				wait for eth_refclk_period;
			elsif (j = 0) then
				wait for eth_refclk_period;
				eth_crsdv <= '0';
			end if;
		end loop;
		eth_crsdv <= '0';
      eth_rxd <= "00"; 
		
		wait for 200 us;
		eth_crsdv <= '1';
		for j in 295 downto 0 loop
			eth_rxd(0) <= data_udp1 (2*j+1);
			eth_rxd(1) <= data_udp1 (2*j);
			if (j > 0) then
				wait for eth_refclk_period;
			elsif (j = 0) then
				wait for eth_refclk_period;
				eth_crsdv <= '0';
			end if;
		end loop;
		eth_crsdv <= '0';
		eth_rxd <= "00";
		
		wait for 200 us;
		eth_crsdv <= '1';
		for j in 295 downto 0 loop
			eth_rxd(0) <= data_udp_err (2*j+1);
			eth_rxd(1) <= data_udp_err (2*j);
			if (j > 0) then
				wait for eth_refclk_period;
			elsif (j = 0) then
				wait for eth_refclk_period;
				eth_crsdv <= '0';
			end if;
		end loop;
		eth_crsdv <= '0';
		eth_rxd <= "00";
		
		wait for 200 us;
		eth_crsdv <= '1';
		for j in 295 downto 0 loop
			eth_rxd(0) <= data_udp2 (2*j+1);
			eth_rxd(1) <= data_udp2 (2*j);
			if (j > 0) then
				wait for eth_refclk_period;
			elsif (j = 0) then
				wait for eth_refclk_period;
				eth_crsdv <= '0';
			end if;
		end loop;
		eth_crsdv <= '0';
		eth_rxd <= "00";

      wait;
   end process;

END;
