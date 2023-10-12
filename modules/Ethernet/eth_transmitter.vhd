----------------------------------------------------------------------------------
-- Company: The Hong Kong Polytechnic University
-- Engineer: Alexandr Melnikov 
-- 
-- Create Date:    15:13:44 02/24/2017 
-- Design Name: 
-- Module Name:    eth_transmitter - Behavioral 
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
-- Ethernet transmitter module hadles transmission of data packets back to the data
-- server and performs all necessary operations, related to packet assembly, based
-- on the data passed from receiver. It includes 4 processes and 1 sub-module:
-- - process to write data out;
-- - process to receive data from Receiver module;
-- - process to create protocol headers (Ethernet, ARP, IP4, UDP) for the packet to be transmitted;
-- - process for IP header checksum calculations;
-- - sub-module for crc calculations;
-- Data to be trasnmitted is retrieved from RAM block by the main Transmit process.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_unsigned.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity eth_transmitter is
	 Generic (ADDR_WIDTH : integer;
				 DATA_WIDTH : integer);
    Port ( clk100mhz : in  STD_LOGIC;     -- clock for crc calculator
			  clk50mhz_shift : in STD_LOGIC; -- provides required set-up and hold time for TX signals with respect to reference clock
			  rstn : in STD_LOGIC;
           txd : inout  STD_LOGIC_VECTOR (1 downto 0);
           txen : out  STD_LOGIC;
			  -- RAM signals
			  rd_data_ram : in STD_LOGIC_VECTOR (DATA_WIDTH-1 downto 0);
			  rd_addr_ram : out STD_LOGIC_VECTOR (ADDR_WIDTH-1 downto 0);
			  rd_enable_ram : out STD_LOGIC;
			  -- Addresses
			  fpga_mac : in STD_LOGIC_VECTOR (47 downto 0);
			  fpga_ip : in STD_LOGIC_VECTOR (31 downto 0);
			  fpga_port : in STD_LOGIC_VECTOR (15 downto 0);
			  pc_mac : in STD_LOGIC_VECTOR (47 downto 0);
			  pc_ip : in  STD_LOGIC_VECTOR (31 downto 0);
			  pc_port : in STD_LOGIC_VECTOR (15 downto 0);
			  -- Data from Rx
			  datacm : in STD_LOGIC_VECTOR (ADDR_WIDTH downto 0);
			  udpl : in STD_LOGIC_VECTOR (15 downto 0);
			  udpc : in STD_LOGIC_VECTOR (15 downto 0);
			  send_arp_reply : in STD_LOGIC;
			  send_ethernet_protocol: in STD_LOGIC;
			  data_in_valid : in STD_LOGIC);
end eth_transmitter;

architecture Behavioral of eth_transmitter is
-- SIGNALS
-- ******* process transmit (responsible for handling Tx) ********--
type state_type is (idle, tx_preamble, tx_sfd, tx_eth_frame_header, tx_protocol_header, tx_data, tx_zero_padding, tx_crc);
signal state : state_type := idle;
signal bit_count : integer range 0 to 3 := 0;								-- counts number of nibbles transmitted
signal byte_count : integer range 0 to 1499 := 0;							-- counts number of bytes transmitted
constant preamble : std_logic_vector (7 downto 0) := x"55";          -- preamble
constant sfd : std_logic_vector (7 downto 0) := x"d5";               -- SFD
signal dest_mac : std_logic_vector (47 downto 0) := (others => '0'); -- destination MAC address
signal dest_ip : std_logic_vector (31 downto 0) := (others => '0');  -- destination IP4 address
signal dest_port : std_logic_vector (15 downto 0) := (others => '0');-- destination Mport number
signal eth_type : std_logic_vector(15 downto 0) := (others => '0');  -- upper layer type of protocol
signal byte0, byte1, byte2, byte3, byte4, byte5, byte6, byte7, byte8,
byte9, byte10, byte11, byte12, byte13, byte14, byte15, byte16, byte17, byte18,
byte19, byte20, byte21, byte22, byte23, byte24, byte25, byte26, byte27 : std_logic_vector (7 downto 0);-- registers to store parsed headers
signal data_counter_max : integer range 0 to 1471 := 0; -- defines length of data field in bytes without zero padding
signal zero_counter : integer range 0 to 18 := 0;       -- defines length of zero-padded data field
signal temp_data : std_logic_vector (DATA_WIDTH-1 downto 0) := x"00"; -- register to store data read from RAM before transmission
signal start_crc : std_logic := '0'; -- enable crc calculator 
signal stop_crc : std_logic := '0';  -- reset crc calculator
signal tx_ready : std_logic := '0';  -- flag indicating that packet is ready for transmission
signal tx_done : std_logic := '0';   -- flag indicating completion of packet transmission 
signal crc_calculated : std_logic_vector (31 downto 0) := (others => '0'); -- calculated crc value for packet being transmitted
-- ******* process set_tx_format (responsible for setting format of the packet to be transmitted) ********--
signal arp_reply : std_logic := '0';    -- sets ARP as higher layer protocol
signal eth_protocol : std_logic := '0'; -- flag sets IP as higher layer protocol       
signal ip_total_length : std_logic_vector (15 downto 0) := (others => '0'); -- stores IP header+data length in bytes (from receiver)
signal udp_length :std_logic_vector (15 downto 0) := (others => '0');       -- stores UDP header+data length in bytes (from receiver)
signal udp_checksum : std_logic_vector (15 downto 0) := (others => '0');    -- stores UDP checksum value (from receiver)
signal id_counter : unsigned (15 downto 0) := (others => '0');              -- Identification parameter for the outgoing packet
-- ******* process ip_header_checksum_calc (responsible for IP header checksum calculation) ********--
signal ip_header_checksum : std_logic_vector (15 downto 0) := (others => '0'); -- calculated IP header checksum
signal temp_iphc1 : unsigned (23 downto 0) := (others => '0');	-- sum of all header's fields
signal temp_iphc2 : unsigned (15 downto 0) := (others => '0');	-- sum of the carry-out with main checksum body
signal ip_header_calc_done : std_logic := '0';						-- flag set when checksum calculation completed
type s_type is (s1,s2,s3);													-- states of the IP header's checksum FSM
signal s : s_type := s1;
-- ******* constants for process set_tx_data (responsible for setting registers storing parsed headers) ********--
constant ip_version : std_logic_vector (3 downto 0) := "0100";       -- code for IP version = 4 
constant ip_header_length : std_logic_vector (3 downto 0) := "0101"; -- code for IP header length = 5 -> 20 bytes 
constant ipl : unsigned (15 downto 0) := x"0014";                      -- IP header length - fixed = 20 bytes
constant flags_offset : std_logic_vector (15 downto 0) := x"0000";   -- flags, offsets and fragmentation
constant ttl : std_logic_vector (7 downto 0) := x"80";               -- time to live for the datagram
constant ds : std_logic_vector (7 downto 0) := x"00";                -- differentiated services
constant ip_protocol : std_logic_vector (7 downto 0) := x"11";       -- code of UDP protocol type
constant arp_operation : std_logic_vector(15 downto 0) := x"0002";   -- code of ARP reply operation
constant arp_hw_type : std_logic_vector (15 downto 0) := x"0001";    -- code of ARP hardware type
constant arp_protocol_type : std_logic_vector (15 downto 0) := x"0800"; -- code of protocol type (IP4)
constant arp_hw_length : std_logic_vector (7 downto 0) := x"06"; 			-- code of ARP hardware length
constant arp_protocol_length : std_logic_vector (7 downto 0) := x"04";  -- code of ARP protocol length
constant arp : std_logic_vector (15 downto 0) := x"0806"; 					-- code of ARP protocol type
constant ethernet : std_logic_vector (15 downto 0) := x"0800";				-- code of IP4 protocol type

-- CRC checker declaration
component crc32_parallel
			 port (clk100mhz : in  STD_LOGIC;
					 data_valid : in  STD_LOGIC;
					 data_in : in  STD_LOGIC_VECTOR (1 downto 0);
					 rstn : in STD_LOGIC;
					 crc : inout  STD_LOGIC_VECTOR (31 downto 0));
end component;

begin
-- CRC checker instantiation
crc_calculator: crc32_parallel
					 port map (clk100mhz => clk100mhz,
								  data_valid => start_crc,
								  data_in => txd,
								  rstn => stop_crc,
								  crc => crc_calculated);

	transmit: process (clk50mhz_shift,rstn)
	begin
		if (rstn = '0') then -- if transciever is being reset transmitter becomes idle
			id_counter <= (others => '0'); -- reset ID counter on hardware reset
			state <= idle;
		elsif (rising_edge(clk50mhz_shift)) then
			case state is
			
			-- Idle state all Tx flags and registers reset and Tx waits until 
			-- tx_ready signal is asserted 
			when idle =>
				bit_count <= 0;
				byte_count <= 0;
				tx_done <= '0';
				start_crc <= '0';
				stop_crc <= '1';
				txen <= '0';
				txd <= "00";
				if (tx_ready = '0') then
					txen <= '0';
					rd_enable_ram <= '0';
					rd_addr_ram <= (others => '0');
					state <= idle;
				elsif (tx_ready = '1') then -- if tx_ready flag is set start transmission
					txen <= '1';
					txd <= preamble(2*bit_count+1 downto 2*bit_count);
					-- if IP/UDP protocol is to be transmitted pre-read the first data byte from RAM
					if (eth_protocol = '1') then
						rd_enable_ram <= '1'; -- enable read
						rd_addr_ram <= std_logic_vector(to_unsigned(byte_count,ADDR_WIDTH)); -- set address of RAM register to read from
					else -- if ARP protocol, there is no data to be transmtted 
						rd_enable_ram <= '0';
						rd_addr_ram <= (others => '0');
					end if;
					--
					byte_count <= 0;
					bit_count <= bit_count+1;
					state <= tx_preamble;
				end if;
			
			-- this state transmits preamble
			when tx_preamble =>
				txen <= '1';
				-- if IP/UDP protocol is to be transmitted pre-read the first data byte from RAM
				if (eth_protocol = '1') then
					temp_data <= rd_data_ram; 		  -- read data byte from RAM
					rd_enable_ram <= '0';           -- disable read operation from RAM
					rd_addr_ram <= (others => '0'); -- clear address bus
				else -- if ARP protocol, there is no data to be transmtted 
					temp_data <= (others => '0');
					rd_enable_ram <= '0';
					rd_addr_ram <= (others => '0');
				end if;
				--
				tx_done <= '0';
				if (byte_count <= 6 and bit_count < 3) then
					txd <= preamble(2*bit_count+1 downto 2*bit_count);
					bit_count <= bit_count+1;
					state <= tx_preamble;
				elsif (byte_count <= 6 and bit_count = 3) then
					txd <= preamble(2*bit_count+1 downto 2*bit_count);
					bit_count <= 0;
					byte_count <= byte_count+1;
					state <= tx_preamble;
				elsif (byte_count = 7) then
						txd <= sfd(2*bit_count+1 downto 2*bit_count);
						bit_count <= bit_count+1;
						byte_count <= 0;
						state <= tx_sfd;
				end if;
			
			-- this state transmits SFD
			when tx_sfd =>
				txen <= '1';
				tx_done <= '0';
				-- if IP/UDP protocol is to be transmitted pre-read the first data byte from RAM
				if (eth_protocol = '1') then
					temp_data <= rd_data_ram;
					rd_enable_ram <= '0';
					rd_addr_ram <= (others => '0');
				else -- if ARP protocol, there is no data to be transmtted 
					temp_data <= (others => '0');
					rd_enable_ram <= '0';
					rd_addr_ram <= (others => '0');
				end if;
				--
				if (byte_count = 0 and bit_count < 3) then
					txd <= sfd(2*bit_count+1 downto 2*bit_count);
					bit_count <= bit_count+1;
					state <= tx_sfd;
				elsif (byte_count = 0 and bit_count = 3) then
					txd <= sfd(2*bit_count+1 downto 2*bit_count);
					bit_count <= 0;
					byte_count <= byte_count+1;
					state <= tx_sfd;
				elsif (byte_count = 1) then
					byte_count <= 0;
					txd <= dest_mac((5-0)*8+2*bit_count+1 downto (5-0)*8+2*bit_count);
					bit_count <= bit_count+1;
					start_crc <= '1';
					stop_crc <= '0';
					state <= tx_eth_frame_header;
				end if;
			
			-- this state transmits Ethernet frame header (destination and source MAC addresses and upper layer protocol type)
			when tx_eth_frame_header =>
				txen <= '1';
				tx_done <= '0';
				-- if IP/UDP protocol is to be transmitted pre-read the first data byte from RAM
				if (eth_protocol = '1') then
					temp_data <= rd_data_ram;
					rd_enable_ram <= '0';
					rd_addr_ram <= (others => '0');
				else -- if ARP protocol, there is no data to be transmtted 
					temp_data <= (others => '0');
					rd_enable_ram <= '0';
					rd_addr_ram <= (others => '0');
				end if;
				-- destination MAC transmitted
				if (byte_count <= 5 and bit_count < 3) then
					txd <= dest_mac((5-byte_count)*8+2*bit_count+1 downto (5-byte_count)*8+2*bit_count);
					bit_count <= bit_count+1;
					state <= tx_eth_frame_header;
				elsif (byte_count <= 5 and bit_count = 3) then
					txd <= dest_mac((5-byte_count)*8+2*bit_count+1 downto (5-byte_count)*8+2*bit_count);
					bit_count <= 0;
					byte_count <= byte_count+1;
					state <= tx_eth_frame_header;
				-- source MAC transmitted
				elsif (byte_count > 5 and byte_count <= 11 and bit_count < 3) then
					txd <= fpga_mac((11-byte_count)*8+2*bit_count+1 downto (11-byte_count)*8+2*bit_count);
					bit_count <= bit_count+1;
					state <= tx_eth_frame_header;
				elsif (byte_count > 5 and byte_count <= 11 and bit_count = 3) then
					txd <= fpga_mac((11-byte_count)*8+2*bit_count+1 downto (11-byte_count)*8+2*bit_count);
					bit_count <= 0;
					byte_count <= byte_count+1;
					state <= tx_eth_frame_header;
				-- upper layer protocol type transmitted
				elsif (byte_count > 11 and byte_count <= 13 and bit_count < 3) then
					txd <= eth_type((13-byte_count)*8+2*bit_count+1 downto (13-byte_count)*8+2*bit_count);
					bit_count <= bit_count+1;
					state <= tx_eth_frame_header;
				elsif (byte_count > 11 and byte_count <= 13 and bit_count = 3) then
					txd <= eth_type((13-byte_count)*8+2*bit_count+1 downto (13-byte_count)*8+2*bit_count);
					bit_count <= 0;
					byte_count <= byte_count+1;
					state <= tx_eth_frame_header;
				elsif (byte_count = 14) then
						txd <= byte0(2*bit_count+1 downto 2*bit_count);
						bit_count <= bit_count+1;
						byte_count <= 0;
						state <= tx_protocol_header;
				end if;
			
			-- this state transmits ARP or IP/UDP protocol headers
			when tx_protocol_header =>
				txen <= '1';
				tx_done <= '0';
				-- if IP/UDP protocol is to be transmitted pre-read the first data byte from RAM
				if (eth_protocol = '1') then
					temp_data <= rd_data_ram;
					rd_enable_ram <= '0';
					rd_addr_ram <= (others => '0');
				else -- if ARP protocol, there is no data to be transmtted
					temp_data <= (others => '0');
					rd_enable_ram <= '0';
					rd_addr_ram <= (others => '0');
				end if;
				--
				if (byte_count <= 27 and bit_count < 3) then
					bit_count <= bit_count+1;
					state <= tx_protocol_header;
				elsif (byte_count <= 27 and bit_count = 3) then
					bit_count <= 0;
					byte_count <= byte_count+1;
					state <= tx_protocol_header;
				elsif (byte_count = 28 and data_counter_max = 0) then -- if there is no data to transmit, transmit zero-padding
						bit_count <= bit_count+1;
						byte_count <= 0;
						state <= tx_zero_padding;
				elsif (byte_count = 28 and data_counter_max > 0) then -- if there is data to transmit, transmit data
						byte_count <= 0;
						bit_count <= bit_count+1;
						state <= tx_data;
				end if;
				case byte_count is
					when 0 => txd <= byte0(2*bit_count+1 downto 2*bit_count);
					when 1 => txd <= byte1(2*bit_count+1 downto 2*bit_count);
					when 2 => txd <= byte2(2*bit_count+1 downto 2*bit_count);
					when 3 => txd <= byte3(2*bit_count+1 downto 2*bit_count);
					when 4 => txd <= byte4(2*bit_count+1 downto 2*bit_count);
					when 5 => txd <= byte5(2*bit_count+1 downto 2*bit_count);
					when 6 => txd <= byte6(2*bit_count+1 downto 2*bit_count);
					when 7 => txd <= byte7(2*bit_count+1 downto 2*bit_count);
					when 8 => txd <= byte8(2*bit_count+1 downto 2*bit_count);
					when 9 => txd <= byte9(2*bit_count+1 downto 2*bit_count);
					when 10 => txd <= byte10(2*bit_count+1 downto 2*bit_count);
					when 11 => txd <= byte11(2*bit_count+1 downto 2*bit_count);
					when 12 => txd <= byte12(2*bit_count+1 downto 2*bit_count);
					when 13 => txd <= byte13(2*bit_count+1 downto 2*bit_count);
					when 14 => txd <= byte14(2*bit_count+1 downto 2*bit_count);
					when 15 => txd <= byte15(2*bit_count+1 downto 2*bit_count);
					when 16 => txd <= byte16(2*bit_count+1 downto 2*bit_count);
					when 17 => txd <= byte17(2*bit_count+1 downto 2*bit_count);
					when 18 => txd <= byte18(2*bit_count+1 downto 2*bit_count);
					when 19 => txd <= byte19(2*bit_count+1 downto 2*bit_count);
					when 20 => txd <= byte20(2*bit_count+1 downto 2*bit_count);
					when 21 => txd <= byte21(2*bit_count+1 downto 2*bit_count);
					when 22 => txd <= byte22(2*bit_count+1 downto 2*bit_count);
					when 23 => txd <= byte23(2*bit_count+1 downto 2*bit_count);
					when 24 => txd <= byte24(2*bit_count+1 downto 2*bit_count);
					when 25 => txd <= byte25(2*bit_count+1 downto 2*bit_count);
					when 26 => txd <= byte26(2*bit_count+1 downto 2*bit_count);
					when 27 => txd <= byte27(2*bit_count+1 downto 2*bit_count);
					when others => 
						if (data_counter_max = 0) then
							txd <= "00"; -- preload zeros to Tx bus for zero-padding transmission
						elsif (data_counter_max > 0) then
							txd <= temp_data(2*bit_count+1 downto 2*bit_count); -- preload data to Tx bus for data transmission
						end if;
				end case;
			
			-- this state transmits data
			when tx_data =>
				txen <= '1';
				tx_done <= '0';
				if (byte_count <= data_counter_max-1 and bit_count < 3) then
					txd <= temp_data(2*bit_count+1 downto 2*bit_count);
					bit_count <= bit_count+1;
					-- keep read RAM enabled and have the address to read on the bus
					rd_enable_ram <= '1';
					rd_addr_ram <= std_logic_vector(to_unsigned(byte_count+1,ADDR_WIDTH));
					--
					state <= tx_data;
				elsif (byte_count <= data_counter_max-1 and bit_count = 3) then
					txd <= temp_data(2*bit_count+1 downto 2*bit_count);
					-- read the next data byte from RAM when the previous is transmitted
					temp_data <= rd_data_ram;
					rd_enable_ram <= '1';
					--
					bit_count <= 0;
					byte_count <= byte_count+1;
					state <= tx_data;
				elsif (byte_count > data_counter_max-1 and zero_counter = 0) then -- if no zero-padding required
					txd(0) <= crc_calculated((3-0)*8+(3-bit_count)*2+1); -- preload crc values on Tx bus
					txd(1) <= crc_calculated((3-0)*8+(3-bit_count)*2);   -- and start crc transmission
					-- when all the data was transmitted disable read from RAM operation and clear the RAM signals
					temp_data <= (others => '0');
					rd_enable_ram <= '0';
					rd_addr_ram <= (others => '0');
					--
					start_crc <= '0'; -- stop crc calculation 
					stop_crc <= '0';
					bit_count <= bit_count+1;
					byte_count <= 0;
					state <= tx_crc;
				elsif (byte_count > data_counter_max-1 and zero_counter > 0) then -- if zero-padding required
					txd <= "00"; -- preload zeros to Tx bus
					-- disable read from RAM operation and clear the RAM signals
					temp_data <= (others => '0');
					rd_enable_ram <= '0';
					rd_addr_ram <= (others => '0');
					--
					byte_count <= 0;
					bit_count <= bit_count+1;
					state <= tx_zero_padding;
				end if;
			
			-- this state transmits zero-padded data field
			when tx_zero_padding =>
				txen <= '1';
				tx_done <= '0';
				if (byte_count <= zero_counter-1 and bit_count < 3) then
					txd <= "00";
					bit_count <= bit_count+1;
					state <= tx_zero_padding;
				elsif (byte_count <= zero_counter-1 and bit_count = 3) then
					txd <= "00";
					bit_count <= 0;
					byte_count <= byte_count+1;
					state <= tx_zero_padding;
				elsif (byte_count+1 > zero_counter-1) then -- when required amount of zero-padding was transmitted
					txd(0) <= crc_calculated((3-0)*8+(3-bit_count)*2+1); -- preload crc values on Tx bus
					txd(1) <= crc_calculated((3-0)*8+(3-bit_count)*2);   -- and start crc transmission
					byte_count <= 0;
					bit_count <= bit_count+1;
					start_crc <= '0'; -- stop crc calculation
					stop_crc <= '0';
					state <= tx_crc;
				end if;
			
			-- this state transmits calculated crc value
			when tx_crc =>
				txen <= '1';
				tx_done <= '0';
				if (byte_count <= 3 and bit_count < 3) then
					txd(0) <= crc_calculated((3-byte_count)*8+(3-bit_count)*2+1);
					txd(1) <= crc_calculated((3-byte_count)*8+(3-bit_count)*2);
					bit_count <= bit_count+1;
					state <= tx_crc;
				elsif (byte_count <= 3 and bit_count = 3) then
					txd(0) <= crc_calculated((3-byte_count)*8+(3-bit_count)*2+1);
					txd(1) <= crc_calculated((3-byte_count)*8+(3-bit_count)*2);
					bit_count <= 0;
					byte_count <= byte_count+1;
					state <= tx_crc;
				elsif (byte_count > 3) then
					byte_count <= 0;
					tx_done <= '1'; -- if crc was transmitted - this is the end of the packet, go back to idle state
					txen <= '0';
					txd <= "00";
					-- make sure that no overflow of the ID parameter happens
					if (eth_protocol = '1' and id_counter+1 <= 65536) then
						id_counter <= id_counter+1;
					elsif (eth_protocol = '1' and id_counter+1 > 65536) then
						id_counter <= (others => '0');
					else 
						id_counter <= id_counter;
					end if;
					state <= idle;
				end if;
			
			
			end case;
		end if;
	end process transmit;
	
	-- this process receives data from Rx module and determines protocol type of the next packet to be transmitted
	set_tx_format: process (send_arp_reply,send_ethernet_protocol,data_in_valid,pc_mac,pc_ip,pc_port,tx_done,clk50mhz_shift,datacm,udpc)
	begin
		if (falling_edge(clk50mhz_shift)) then
			-- set registers when there is valid data from Receiver
			if (data_in_valid = '1' and tx_done = '0') then
				if (send_arp_reply = '1') then
					arp_reply <= '1';
				elsif (send_ethernet_protocol = '1') then
					eth_protocol <= '1';
				end if;
				dest_mac <= pc_mac;
				dest_ip <= pc_ip;
				dest_port <= pc_port;
				data_counter_max <= to_integer(unsigned(datacm));
				ip_total_length <= std_logic_vector(ipl+unsigned(udpl));
				udp_length <= udpl;
				udp_checksum <= udpc;
			-- keep value of these registers until packet is transmitted 
			elsif (data_in_valid = '0' and tx_done = '0') then
				arp_reply <= arp_reply;
				eth_protocol <= eth_protocol;
				dest_mac <= dest_mac;
				dest_ip <= dest_ip;
				dest_port <= dest_port;
				data_counter_max <= data_counter_max;
				ip_total_length <= ip_total_length;
				udp_length <= udp_length;
				udp_checksum <= udp_checksum;
			-- when the packet is transmitted, clear registers
			elsif (tx_done = '1') then
				arp_reply <= '0';
				eth_protocol <= '0';
				dest_mac <= (others => '0');
				dest_ip <= (others => '0');
				dest_port <= (others => '0');
				data_counter_max <= 0;
				ip_total_length <= (others => '0');
				udp_length <= (others => '0');
				udp_checksum <= (others => '0');
			end if;
		end if;
	end process set_tx_format;
	
	-- this process assembles headers of the data packet to be transmitted
	set_tx_data: process (arp_reply,eth_protocol,tx_done,clk50mhz_shift,ip_header_checksum)
	begin
		if (falling_edge(clk50mhz_shift)) then
			-- if ARP reply required load headers registers and set data and zero counters accordingly
			if (arp_reply = '1' and tx_done = '0') then
				eth_type <= arp;
				byte0 <= arp_hw_type(15 downto 8);
				byte1 <= arp_hw_type(7 downto 0);
				byte2 <= arp_protocol_type(15 downto 8);
				byte3 <= arp_protocol_type(7 downto 0);
				byte4 <= arp_hw_length;
				byte5 <= arp_protocol_length;
				byte6 <= arp_operation(15 downto 8);
				byte7 <= arp_operation(7 downto 0);
				byte8 <= fpga_mac(47 downto 40);
				byte9 <= fpga_mac(39 downto 32);
				byte10 <= fpga_mac(31 downto 24);
				byte11 <= fpga_mac(23 downto 16);
				byte12 <= fpga_mac(15 downto 8);
				byte13 <= fpga_mac(7 downto 0);
				byte14 <= fpga_ip(31 downto 24);
				byte15 <= fpga_ip(23 downto 16);
				byte16 <= fpga_ip(15 downto 8);
				byte17 <= fpga_ip(7 downto 0);
				byte18 <= dest_mac(47 downto 40);
				byte19 <= dest_mac(39 downto 32);
				byte20 <= dest_mac(31 downto 24);
				byte21 <= dest_mac(23 downto 16);
				byte22 <= dest_mac(15 downto 8);
				byte23 <= dest_mac(7 downto 0);
				byte24 <= dest_ip(31 downto 24);
				byte25 <= dest_ip(23 downto 16);
				byte26 <= dest_ip(15 downto 8);
				byte27 <= dest_ip(7 downto 0);
				--data_counter_max <= 0; -- arp request has 18 bytes of zero padding
				zero_counter <= 18;
				tx_ready <= '1';-- set flag indicating start of transmission
			-- if IP/UDP reply required load headers registers and set data and zero counters accordingly
			elsif (eth_protocol = '1' and tx_done = '0') then
				eth_type <= ethernet;
				byte0 <= ip_version&ip_header_length;
				byte1 <= ds; -- differentiated services
				-- total length of protocol in bytes
				byte2 <= ip_total_length(15 downto 8);
				byte3 <= ip_total_length(7 downto 0);
				-- identification: number of package
				byte4 <= std_logic_vector(id_counter(15 downto 8));
				byte5 <= std_logic_vector(id_counter(7 downto 0));
				byte6 <= flags_offset(15 downto 8); -- flags and 5 seniour bits from fragmentation offset
				byte7 <= flags_offset(7 downto 0); -- 8 juniour bits from fragmentation offset
				byte8 <= ttl; -- Time To Live
				byte9 <= ip_protocol; -- x"11" - for UDP
				-- header checksum (from process )
				byte10 <= ip_header_checksum(15 downto 8);
				byte11 <= ip_header_checksum(7 downto 0);
				-- source ip
				byte12 <= fpga_ip(31 downto 24);
				byte13 <= fpga_ip(23 downto 16);
				byte14 <= fpga_ip(15 downto 8);
				byte15 <= fpga_ip(7 downto 0);
				-- destination ip
				byte16 <= dest_ip(31 downto 24);
				byte17 <= dest_ip(23 downto 16);
				byte18 <= dest_ip(15 downto 8);
				byte19 <= dest_ip(7 downto 0);
				-- source port
				byte20 <= fpga_port(15 downto 8);
				byte21 <= fpga_port(7 downto 0);
				-- destination port
				byte22 <= dest_port(15 downto 8);
				byte23 <= dest_port(7 downto 0);
				-- udp length
				byte24 <= udp_length(15 downto 8);
				byte25 <= udp_length(7 downto 0);
				-- udp_checksum
				byte26 <= udp_checksum(15 downto 8);
				byte27 <= udp_checksum(7 downto 0);
				-- counters and flags
				--data_counter_max <= to_integer(unsigned(datacm));
				if (data_counter_max < 18) then -- 4<=18 - true
					zero_counter <= 18-data_counter_max; -- 18-4-1=13 (from 0 to 13) = 14 bytes of zeros
				else
					zero_counter <= 0;-- if data_counter_max=20 -> data_counter=19 (from 0 to 19) = 20 bytes of data
				end if;
				tx_ready <= '1'; -- set flag indicating start of transmission
			else -- if there is nothing to transmit keep all registers and counters clear
				tx_ready <= '0';
				eth_type <= (others => '0');
				byte0 <= (others => '0');
				byte1 <= (others => '0');
				byte2 <= (others => '0');
				byte3 <= (others => '0');
				byte4 <= (others => '0');
				byte5 <= (others => '0');
				byte6 <= (others => '0');
				byte7 <= (others => '0');
				byte8 <= (others => '0');
				byte9 <= (others => '0');
				byte10 <= (others => '0');
				byte11 <= (others => '0');
				byte12 <= (others => '0');
				byte13 <= (others => '0');
				byte14 <= (others => '0');
				byte15 <= (others => '0');
				byte16 <= (others => '0');
				byte17 <= (others => '0');
				byte18 <= (others => '0');
				byte19 <= (others => '0');
				byte20 <= (others => '0');
				byte21 <= (others => '0');
				byte22 <= (others => '0');
				byte23 <= (others => '0');
				byte24 <= (others => '0');
				byte25 <= (others => '0');
				byte26 <= (others => '0');
				byte27 <= (others => '0');
				--data_counter_max <= 0;
				zero_counter <= 0;
			end if;
		end if;
	end process set_tx_data;
	
	-- this process calculates IP header checksum
	ip_header_checksum_calc: process (clk50mhz_shift,tx_ready,id_counter,dest_ip)
	begin
		if (falling_edge(clk50mhz_shift)) then
			-- only for IP/UDP packets
			if (eth_protocol = '1' and tx_ready = '1') then
				-- if checksum hasn't been calculated yet, calculate it
				if (ip_header_calc_done = '0') then
					case s is
						when s1 =>
							temp_iphc1 <= temp_iphc1+unsigned(ip_version&ip_header_length&ds)+unsigned(ip_total_length)+id_counter+
							unsigned(flags_offset)+unsigned(ttl&ip_protocol)+unsigned(fpga_ip(31 downto 16))+
							unsigned(fpga_ip(15 downto 0))+unsigned(dest_ip(31 downto 16))+unsigned(dest_ip(15 downto 0)); -- sum of all header fields
							s <= s2;
						when s2 =>
							temp_iphc2 <= not(temp_iphc2+temp_iphc1(15 downto 0)+temp_iphc1(23 downto 16)); -- sum of the main checksum body with carry-out
							s <= s3;
						when s3 =>
							ip_header_checksum <= std_logic_vector(temp_iphc2); -- calculated checksum
							ip_header_calc_done <= '1';                         -- checksum calculation done
							s <= s3;
					end case;
				else -- if checksum hasn been calculated, keep it
					temp_iphc1 <= temp_iphc1;
					temp_iphc2 <= temp_iphc2;
					ip_header_checksum <= ip_header_checksum;
					ip_header_calc_done <= ip_header_calc_done;
				end if;
			else -- keep checksum registers clear when they are not used
				temp_iphc1 <= (others => '0');
				temp_iphc2 <= (others => '0');
				ip_header_checksum <= (others => '0');
				ip_header_calc_done <= '0';
				s <= s1;
			end if;
		end if;
	end process ip_header_checksum_calc;
	
end Behavioral;

