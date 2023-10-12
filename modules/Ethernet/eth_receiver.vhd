----------------------------------------------------------------------------------
-- Company: The Hong Kong Polytechnic University
-- Engineer: Alexandr Melnikov
-- 
-- Create Date:    11:16:51 02/24/2017 
-- Design Name: 
-- Module Name:    eth_rexeiver - Behavioral 
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
-- Ethernet receiver module handles reception of data packets from the data server.
-- Only 2 sorts of packets are accepted: ARP requests and UDP packets.
-- This module doesn't use any elasticity buffer to store incoming packets. The data is 
-- being parsed in parallel with read operation. ARP and UDP packets designated to
-- this echo-server are accepted and the rest is rejected.
-- Receiver module includs 7 processes and 1 sub-module:
-- - process to read data in;
-- - process to parse Ethernet headers of the incoming packets;
-- - process to parse headers of the higher-level protocols (ARP, IP4, UDP);
-- - process to do IP header checksum check;
-- - process to do UDP header checksum check;
-- - process to handle data write operation to RAM block;
-- - process to handle data pass to Transmitter block for echo-reply;
-- - lower-level module, performing crc check of the incoming packets.
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

entity eth_receiver is
	 Generic (ADDR_WIDTH : integer;
				 DATA_WIDTH : integer);
    Port ( clk100mhz : in STD_LOGIC; -- clock for crc checker
			  clk50mhz : in  STD_LOGIC; -- reference clock, read rx bus on falling edge
           rxd : in  STD_LOGIC_VECTOR (1 downto 0);
           crsdv : in  STD_LOGIC;
           rstn : in  STD_LOGIC;
			  rxerr : in STD_LOGIC;
			  -- RAM signals
			  wrt_data_ram : inout STD_LOGIC_VECTOR (DATA_WIDTH-1 downto 0);
			  wrt_addr_ram : inout STD_LOGIC_VECTOR (ADDR_WIDTH-1 downto 0);
			  wrt_enable_ram : out STD_LOGIC;
			  -- Addresses
           fpga_mac : in STD_LOGIC_VECTOR (47 downto 0);
			  fpga_ip : in STD_LOGIC_VECTOR (31 downto 0);
			  fpga_port : in STD_LOGIC_VECTOR (15 downto 0);
			  pc_mac : out STD_LOGIC_VECTOR (47 downto 0);
			  pc_ip : out  STD_LOGIC_VECTOR (31 downto 0);
			  pc_port : out STD_LOGIC_VECTOR (15 downto 0);
			  -- Data to Tx
			  datacm : out STD_LOGIC_VECTOR (ADDR_WIDTH downto 0);
			  udpl : out STD_LOGIC_VECTOR (15 downto 0);
			  udpc : out STD_LOGIC_VECTOR (15 downto 0);
			  send_arp_reply : out STD_LOGIC;
			  send_ethernet_protocol: out STD_LOGIC;
			  data_out_valid : out STD_LOGIC);
end eth_receiver;

architecture Behavioral of eth_receiver is
-- SIGNALS
-- ******* process receive (responsible for handling Rx) ********--
type state_type is (idle,wait_rx,read_eth_header,read_protocol_header,read_extra_ip_header,read_data,read_zero_padding,read_crc,check_crc);
signal state : state_type := idle;
signal bit_count : integer range 0 to 3 := 0;    							     -- counts number of nibbles read
signal byte_count : integer range 0 to 1499 := 0;							     -- counts number of bytes read
signal dest_mac : std_logic_vector (47 downto 0) := (others => '0');      -- register to store destination MAC address (from Ethernet header)
signal source_mac : std_logic_vector (47 downto 0) := (others => '0');    -- register to store source MAC address (from Ethernet header)
signal eth_prot_type : std_logic_vector (15 downto 0) := (others => '0'); -- register to store Ethernet Protocol Type
signal bytes00, bytes01, bytes02, bytes03, bytes04, bytes05, bytes06, bytes07,
bytes08, bytes09, bytes10, bytes11, bytes12, bytes13 : std_logic_vector (15 downto 0) := (others => '0'); -- registers to store IP/UDP headers
signal byte_read_done : std_logic_vector (13 downto 0) := (others => '0'); -- flags for IP/UDP registers 
signal read_eth_header_done : std_logic := '0';                            -- flag to indicate end of the Ethernet Header
signal start_crc : std_logic := '0';       -- enable crc checking
signal stop_crc : std_logic := '0';  		 -- disable crc checking
signal unknown_request : std_logic := '0'; -- other unknown requests ORed
-- ******* process eth_packet_type (responsible for parsing Ethernet header) ********--
signal arp_request_expected : std_logic := '0';  -- flag set if Ethernet header matches ARP protocol
signal eth_protocol_expected : std_logic := '0'; -- flag set if Ethernet header matches UDP protocol
signal unknown_request1 : std_logic := '0';      -- Ethernet header matches neither ARP nor UDP protocols
-- ******* process headers_parse (responsible for parsing ARP/UDP header) ********--
signal ip_header_length : std_logic_vector (3 downto 0) := (others => '0');-- length in bytes of IP header (for UDP packet)
signal ip_options_count_max : integer range 0 to 40 := 0;                  -- counter for UDP header's extra options (from 21 to 40 bytes)
signal ip_extra_options : std_logic := '0'; 											-- set if UDP header has extra options
signal ip_total_length : std_logic_vector (15 downto 0) := (others => '0');-- total length of datagram in bytes (IP header+payload (payload=UDP header+data)))
signal data_counter_max : integer range 0 to 1471 := 0;							-- defines length of data field in bytes (without zero padding)
signal zero_counter : integer range 0 to 18 := 0; 									-- defines length in bytes of zero padding
signal identification : std_logic_vector (15 downto 0) := (others => '0'); -- ID number of the incoming packet
signal flags_offset : std_logic_vector (15 downto 0) := (others => '0');   -- flags and fragmentation offset
signal ip_header_checksum : std_logic_vector (15 downto 0) := (others => '0'); -- IP header's checksum
signal ip_header_options : std_logic_vector (319 downto 0) := (others => '0'); -- vector to store IP header's optional fields
signal byte_count_extra : integer range 0 to 39 := 0; 							-- byte counter for IP header's optional fields
signal source_ip : std_logic_vector (31 downto 0) := (others => '0'); 		-- IP address of the sender
signal source_port : std_logic_vector (15 downto 0) := (others => '0'); 	-- port number of the sender
signal udp_length :std_logic_vector (15 downto 0) := (others => '0'); 		-- total length of UDP datagram (UDP header+data)
signal udp_checksum :std_logic_vector (15 downto 0) := (others => '0'); 	-- UDP header's checksum
signal temp_data : std_logic_vector (DATA_WIDTH-1 downto 0) := x"00"; 		-- register to temporarily save received data byte
signal valid_data_byte_read : std_logic := '0'; -- flag indicateing that another data byte was read
signal read_frame_done : std_logic := '0'; 		-- flag set when valid frame was read, cleared in idle state
signal unknown_request2 : std_logic := '0'; 		-- set in case of any mismatch between incoming data and expected headers' structures
-- ******* process ip_header_checksum_check (responsible for checking IP header's checksum) ********--
signal ip_hcs_calc_temp1 : unsigned (23 downto 0) := (others => '0');   -- sum of all header's fields
signal ip_hcs_calc_temp2 : unsigned (15 downto 0) := (others => '0');   -- sum of the carry-out with main checksum body
signal ip_hcs_calc_extra : unsigned (23 downto 0) := (others => '0');   -- sum of IP header's extra options field
signal edge_count_header : std_logic := '0'; 							      -- used to set correct format of the extra header field in checksum calculations 
signal ip_hcs_calc : std_logic_vector (15 downto 0) := (others => '1'); -- calculated IP header's checksum
signal ip_hcs_done : std_logic := '0';      -- flag set when checksum calculation completed
type sip_type is (sip1,sip2,sip3);          -- states of the IP header's checksum FSM
signal sip : sip_type := sip1;
signal unknown_request3 : std_logic := '0'; -- flag set when calculated IP header's checksum is not equal to zero
-- ******* process udp_header_checksum_check (responsible for checking UDP header's checksum) ********--
signal udp_presum : unsigned (23 downto 0) := (others => '0');   -- sum of the UDP header's fields
signal udp_presum_done : std_logic := '0'; 							  -- flag set when sum of the UDP header's fields calculated
signal udp_data_sum : unsigned (23 downto 0) := (others => '0'); -- sum of all data fields
signal udp_datasum_done : std_logic := '0'; 							  -- flag set when sum of all data fields calculated
signal edge_count_data : std_logic := '0'; 							  -- used to set correct format of the current data field in checksum calculations 
signal udp_hcs_calc_temp1 : unsigned (23 downto 0) := (others => '0');   -- sum of the sums of UDP header's fields and all data fields
signal udp_hcs_calc_temp2 : unsigned (15 downto 0) := (others => '0');   -- sum of the carry-out with main checksum body
signal udp_hcs_calc : std_logic_vector (15 downto 0) := (others => '1'); -- calculated UDP header's checksum
signal udp_hcs_done : std_logic := '0';     -- flag set when UDP header's checksum calculated
type sudp_type is (sudp1,sudp2,sudp3);      -- states of the UDP header's checksum FSM
signal sudp : sudp_type := sudp1;
signal unknown_request4 : std_logic := '0'; -- flag set when calculated UDP header's checksum is not equal to zero
-- ******* process data_out_ram (responsible for saving valid data into RAM) ********--
type s_ram_type is (s_ram1, s_ram2, s_ram3, s_ram4);                              -- states of the write RAM FSM
signal s_ram : s_ram_type := s_ram1;
signal addr_count : unsigned (ADDR_WIDTH-1 downto 0) := (others => '0'); 			 -- address to write RAM counter
signal data_to_ram : std_logic_vector (DATA_WIDTH-1 downto 0) := (others => '0'); -- data to write to RAM register
signal we_ram : std_logic := '0';  -- enable write RAM
signal rst_ram : std_logic := '0'; -- reset input signals to RAM
-- ******* crc checker's signals ********--
signal crc_rx : std_logic_vector (31 downto 0) := (others => '0');         -- received crc value
signal crc_calculated : std_logic_vector (31 downto 0) := (others => '0'); -- calculated crc value
signal crc_pass : std_logic := '0';                                        -- flag set if read crc = calculated crc
--*************** constants ********************--
constant arp_request : std_logic_vector (15 downto 0) := x"0001";       -- code of ARP request operation
constant arp_hw_type : std_logic_vector (15 downto 0) := x"0001";       -- code of ARP hardware type
constant arp_protocol_type : std_logic_vector (15 downto 0) := x"0800"; -- code of ARP protocol type
constant arp_hw_length : std_logic_vector (7 downto 0) := x"06";        -- code of ARP hardware length for Ethernet
constant arp_protocol_length : std_logic_vector (7 downto 0) := x"04";  -- code of ARP protocol length for IP4
constant ip_protocol : std_logic_vector (7 downto 0) := x"11";          -- code of transport layer protocol for UDP
constant arp : std_logic_vector (15 downto 0) := x"0806";               -- code for the upper layer protocol that uses service of Internet (ARP)
constant ethernet : std_logic_vector (15 downto 0) := x"0800";          -- code for the upper layer protocol that uses service of Internet (IP4)
--***********************************--

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
	crc_checker: crc32_parallel
					 port map (clk100mhz => clk100mhz,
								  data_valid => start_crc,
								  data_in => rxd,
								  rstn => stop_crc,
								  crc => crc_calculated);
								  

	receive: process (clk50mhz,rstn)
	begin
		if (rstn = '0') then -- if transciever is being reset receiver becomes idle
			state <= idle;
		elsif (falling_edge(clk50mhz)) then
			case state is
			
			-- Idle state all Rx flags and registers reset and Rx waits until
			-- crsdv signal is and Preamble's nibbles appear on rxd bus
			when idle =>
				---flags
				byte_read_done <= (others => '0');
				crc_pass <= '0';
				read_frame_done <= '0';
				rst_ram <= '0';
				start_crc <= '0';
				stop_crc <= '1';
				read_eth_header_done <= '0';
				--- header registers
				dest_mac <= (others => '0');
				source_mac <= (others => '0');
				eth_prot_type <= (others => '0');
				--- counters
				byte_count <= 0;
				bit_count <= 0;
				--- data registers
				temp_data <= (others => '0');
				crc_rx <= (others => '0');
				--crc_calculated <= (others => '0');
				bytes00 <= (others => '0');
				bytes01 <= (others => '0');
				bytes02 <= (others => '0');
				bytes03 <= (others => '0');
				bytes04 <= (others => '0');
				bytes05 <= (others => '0');
				bytes06 <= (others => '0');
				bytes07 <= (others => '0');
				bytes08 <= (others => '0');
				bytes09 <= (others => '0');
				bytes10 <= (others => '0');
				bytes11 <= (others => '0');
				bytes12 <= (others => '0');
				bytes13 <= (others => '0');
				-- if data valid signal is asserted, no error symbol is detected and
				-- the first Preamble's nibbles appear on rxd bus receiver goes into the next state
				if (crsdv = '1' and rxerr = '0' and rxd = "01") then 
					state <= wait_rx;
				else -- else it remains idle
					state <= idle;
				end if;
			
			-- in this state receiver waits for the last nibble of SFD
			-- and goes into the next state where it reads Ethernet header
			when wait_rx =>
				-- if data valid signal deasserted or error symbol detected
				-- receiver becomes idle
				if (crsdv = '0' or rxerr = '1') then 
					bit_count <= 0;
					byte_count <= 0;
					stop_crc <= '1';
					start_crc <= '0';
					rst_ram <= '1';
					state <= idle;
				else -- else wait for the "11" nibble - last nibble of SFD
					rst_ram <= '0';
					if (crsdv = '1' and rxd = "01") then
						state <= wait_rx;
					elsif (crsdv = '1' and rxd = "11") then
						start_crc <= '1'; -- start crc check immediately after SFD
						stop_crc <= '0';
						state <= read_eth_header;
					end if;
				end if;
			
			-- read first 14 bytes (destination mac,source mac and protocol type) in this state
			when read_eth_header => 
				-- if data valid signal deasserted or error symbol detected
				-- receiver becomes idle and stops crc check
				if (crsdv = '0' or rxerr = '1') then
					bit_count <= 0;
					byte_count <= 0;
					stop_crc <= '1'; 
					start_crc <= '0';
					rst_ram <= '1';
					state <= idle;
				else
					rst_ram <= '0';
					-- read destination MAC address
					if (byte_count <= 5 and bit_count < 3) then
						dest_mac((5-byte_count)*8+2*bit_count+1 downto (5-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= bit_count+1;
						state <= read_eth_header;
					elsif (byte_count <= 5 and bit_count = 3) then
						dest_mac((5-byte_count)*8+2*bit_count+1 downto (5-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= 0;
						byte_count <= byte_count+1;
						state <= read_eth_header;
					-- read source MAC address
					elsif (byte_count > 5 and byte_count <= 11 and bit_count < 3) then
						source_mac((11-byte_count)*8+2*bit_count+1 downto (11-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= bit_count+1;
						state <= read_eth_header;
					elsif (byte_count > 5 and byte_count <= 11 and bit_count = 3) then
						source_mac((11-byte_count)*8+2*bit_count+1 downto (11-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= 0;
						byte_count <= byte_count+1;
						state <= read_eth_header;
					-- read upper layer protocol type
					elsif (byte_count > 11 and byte_count <= 13 and bit_count < 3) then
						eth_prot_type((13-byte_count)*8+2*bit_count+1 downto (13-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= bit_count+1;
						state <= read_eth_header;
					elsif (byte_count > 11 and byte_count <= 13 and bit_count = 3) then
						eth_prot_type((13-byte_count)*8+2*bit_count+1 downto (13-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= 0;
						byte_count <= byte_count+1;
						if (byte_count = 13) then
							byte_count <= 0;
							read_eth_header_done <= '1'; -- set flag indicating end of read Ethernet header operation
							-- this flag also starts eth_packet_type process
							state <= read_protocol_header; -- go to next state and read Payload fields
						else
							state <= read_eth_header;
						end if;
					end if;
				end if;
			
			-- read next 28 bytes here (both ARP and IP4 have 28-byte long headers (when there are no extra fields in IP header))
			when read_protocol_header => 
				-- if data valid signal deasserted or error symbol detected
				-- receiver becomes idle and stops crc check
				if (crsdv = '0' or rxerr = '1' or unknown_request = '1') then
					bit_count <= 0;
					byte_count <= 0;
					byte_read_done <= (others => '0');
					stop_crc <= '1';
					start_crc <= '0';
					rst_ram <= '1';
					state <= idle;
				-- bytes 00 to 13 store the headers' data; 
				-- byte_read_done flags register is being set as receiver keeps reading the header's fields
				-- every individual flag triggers separate header parse operations in headers_parse process
				else 
					rst_ram <= '0';
					-- bytes 0 and 1
					if (byte_count <= 1 and bit_count < 3) then
						bytes00((1-byte_count)*8+2*bit_count+1 downto (1-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= bit_count+1;
						state <= read_protocol_header;
					elsif (byte_count <= 1 and bit_count = 3) then
						bytes00((1-byte_count)*8+2*bit_count+1 downto (1-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= 0;
						byte_count <= byte_count+1;
						if (byte_count = 1) then
							byte_read_done(0) <= '1';
						end if;
						state <= read_protocol_header;
					-- bytes 2 and 3	
					elsif (byte_count > 1 and byte_count <= 3 and bit_count < 3) then
						bytes01((3-byte_count)*8+2*bit_count+1 downto (3-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= bit_count+1;
						state <= read_protocol_header;
					elsif (byte_count > 1 and byte_count <= 3 and bit_count = 3) then
						bytes01((3-byte_count)*8+2*bit_count+1 downto (3-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= 0;
						byte_count <= byte_count+1;
						if (byte_count = 3) then
							byte_read_done(1) <= '1';
						end if;
						state <= read_protocol_header;
					-- bytes 4 and 5	
					elsif (byte_count > 3 and byte_count <= 5 and bit_count < 3) then
						bytes02((5-byte_count)*8+2*bit_count+1 downto (5-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= bit_count+1;
						state <= read_protocol_header;
					elsif (byte_count > 3 and byte_count <= 5 and bit_count = 3) then
						bytes02((5-byte_count)*8+2*bit_count+1 downto (5-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= 0;
						byte_count <= byte_count+1;
						if (byte_count = 5) then
							byte_read_done(2) <= '1';
						end if;
						state <= read_protocol_header;
					-- bytes 6 and 7
					elsif (byte_count > 5 and byte_count <= 7 and bit_count < 3) then
						bytes03((7-byte_count)*8+2*bit_count+1 downto (7-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= bit_count+1;
						state <= read_protocol_header;
					elsif (byte_count > 5 and byte_count <= 7 and bit_count = 3) then
						bytes03((7-byte_count)*8+2*bit_count+1 downto (7-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= 0;
						byte_count <= byte_count+1;
						if (byte_count = 7) then
							byte_read_done(3) <= '1';
						end if;
						state <= read_protocol_header;
					-- bytes 8 and 9
					elsif (byte_count > 7 and byte_count <= 9 and bit_count < 3) then
						bytes04((9-byte_count)*8+2*bit_count+1 downto (9-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= bit_count+1;
						state <= read_protocol_header;
					elsif (byte_count > 7 and byte_count <= 9 and bit_count = 3) then
						bytes04((9-byte_count)*8+2*bit_count+1 downto (9-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= 0;
						byte_count <= byte_count+1;
						if (byte_count = 9) then
							byte_read_done(4) <= '1';
							-- if this is IP4 packet and its header contain extra field
							-- go and read them and come back to this state to finish
							-- reading the regular fields
							if (ip_extra_options = '1') then 
								byte_count_extra <= 0;
								state <= read_extra_ip_header;
							else -- keep reading the header
								state <= read_protocol_header;
							end if;
						end if;
					-- bytes 10 and 11
					elsif (byte_count > 9 and byte_count <= 11 and bit_count < 3) then
						bytes05((11-byte_count)*8+2*bit_count+1 downto (11-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= bit_count+1;
						state <= read_protocol_header;
					elsif (byte_count > 9 and byte_count <= 11 and bit_count = 3) then
						bytes05((11-byte_count)*8+2*bit_count+1 downto (11-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= 0;
						byte_count <= byte_count+1;
						if (byte_count = 11) then
							byte_read_done(5) <= '1';
						end if;
						state <= read_protocol_header;
					-- bytes 12 and 13
					elsif (byte_count > 11 and byte_count <= 13 and bit_count < 3) then
						bytes06((13-byte_count)*8+2*bit_count+1 downto (13-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= bit_count+1;
						state <= read_protocol_header;
					elsif (byte_count > 11 and byte_count <= 13 and bit_count = 3) then
						bytes06((13-byte_count)*8+2*bit_count+1 downto (13-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= 0;
						byte_count <= byte_count+1;
						if (byte_count = 13) then
							byte_read_done(6) <= '1';
						end if;
						state <= read_protocol_header;
					-- bytes 14 and 15
					elsif (byte_count > 13 and byte_count <= 15 and bit_count < 3) then
						bytes07((15-byte_count)*8+2*bit_count+1 downto (15-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= bit_count+1;
						state <= read_protocol_header;
					elsif (byte_count > 13 and byte_count <= 15 and bit_count = 3) then
						bytes07((15-byte_count)*8+2*bit_count+1 downto (15-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= 0;
						byte_count <= byte_count+1;
						if (byte_count = 15) then
							byte_read_done(7) <= '1';
						end if;
						state <= read_protocol_header;
					-- bytes 16 and 17
					elsif (byte_count > 15 and byte_count <= 17 and bit_count < 3) then
						bytes08((17-byte_count)*8+2*bit_count+1 downto (17-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= bit_count+1;
						state <= read_protocol_header;
					elsif (byte_count > 15 and byte_count <= 17 and bit_count = 3) then
						bytes08((17-byte_count)*8+2*bit_count+1 downto (17-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= 0;
						byte_count <= byte_count+1;
						if (byte_count = 17) then
							byte_read_done(8) <= '1';
						end if;
						state <= read_protocol_header;
					-- bytes 18 and 19
					elsif (byte_count > 17 and byte_count <= 19 and bit_count < 3) then
						bytes09((19-byte_count)*8+2*bit_count+1 downto (19-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= bit_count+1;
						state <= read_protocol_header;
					elsif (byte_count > 17 and byte_count <= 19 and bit_count = 3) then
						bytes09((19-byte_count)*8+2*bit_count+1 downto (19-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= 0;
						byte_count <= byte_count+1;
						if (byte_count = 19) then
							byte_read_done(9) <= '1'; -- this flag starts ip_header_checksum_check process
						end if;
						state <= read_protocol_header;
					-- bytes 20 and 21
					elsif (byte_count > 19 and byte_count <= 21 and bit_count < 3) then
						bytes10((21-byte_count)*8+2*bit_count+1 downto (21-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= bit_count+1;
						state <= read_protocol_header;
					elsif (byte_count > 19 and byte_count <= 21 and bit_count = 3) then
						bytes10((21-byte_count)*8+2*bit_count+1 downto (21-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= 0;
						byte_count <= byte_count+1;
						if (byte_count = 21) then
							byte_read_done(10) <= '1';
						end if;
						state <= read_protocol_header;
					-- bytes 22 and 23
					elsif (byte_count > 21 and byte_count <= 23 and bit_count < 3) then
						bytes11((23-byte_count)*8+2*bit_count+1 downto (23-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= bit_count+1;
						state <= read_protocol_header;
					elsif (byte_count > 21 and byte_count <= 23 and bit_count = 3) then
						bytes11((23-byte_count)*8+2*bit_count+1 downto (23-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= 0;
						byte_count <= byte_count+1;
						if (byte_count = 23) then
							byte_read_done(11) <= '1';
						end if;
						state <= read_protocol_header;
					-- bytes 24 and 25
					elsif (byte_count > 23 and byte_count <= 25 and bit_count < 3) then
						bytes12((25-byte_count)*8+2*bit_count+1 downto (25-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= bit_count+1;
						state <= read_protocol_header;
					elsif (byte_count > 23 and byte_count <= 25 and bit_count = 3) then
						bytes12((25-byte_count)*8+2*bit_count+1 downto (25-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= 0;
						byte_count <= byte_count+1;
						if (byte_count = 25) then
							byte_read_done(12) <= '1';
						end if;
						state <= read_protocol_header;
					-- bytes 26 and 27
					elsif (byte_count > 25 and byte_count <= 27 and bit_count < 3) then
						bytes13((27-byte_count)*8+2*bit_count+1 downto (27-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= bit_count+1;
						state <= read_protocol_header;
					elsif (byte_count > 25 and byte_count <= 27 and bit_count = 3) then
						bytes13((27-byte_count)*8+2*bit_count+1 downto (27-byte_count)*8+2*bit_count) <= rxd;
						bit_count <= 0;
						byte_count <= byte_count+1;
						if (byte_count = 27) then
							byte_read_done(13) <= '1';-- this flag starts udp_header_checksum_check process
							byte_count <= 0;
							-- if data field is empty in this packet go and read zero-padded fields
							if(data_counter_max = 0) then
								state <= read_zero_padding;
							else -- else read valid data
								state <= read_data;
							end if;
						else 
							state <= read_protocol_header;
						end if;
					end if;
				end if;
				
				-- read extra ip_options_count_max-1 bytes of ip header
				-- this design makes no use of extra fields, but they are important
				-- for correct packet parsing and checksum calculations!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
				when read_extra_ip_header => 
					-- if data valid signal deasserted or error symbol detected
					-- receiver becomes idle and stops crc check
					if (crsdv = '0' or rxerr = '1' or unknown_request = '1') then
						bit_count <= 0;
						byte_count <= 0;
						byte_read_done <= (others => '0');
						stop_crc <= '1';
						start_crc <= '0';
						rst_ram <= '1';
						state <= idle;
					else
						rst_ram <= '0';
						if (byte_count_extra <= ip_options_count_max-1 and bit_count < 3) then
							ip_header_options((ip_options_count_max-1-byte_count_extra)*8+2*bit_count+1 downto (ip_options_count_max-1-byte_count_extra)*8+2*bit_count) <= rxd;
							bit_count <= bit_count+1;
							state <= read_extra_ip_header;
						elsif (byte_count_extra <= ip_options_count_max-1 and bit_count = 3) then
							ip_header_options((ip_options_count_max-1-byte_count_extra)*8+2*bit_count+1 downto (ip_options_count_max-1-byte_count_extra)*8+2*bit_count) <= rxd;
							bit_count <= 0;
							if (byte_count_extra < ip_options_count_max-1) then
								byte_count_extra <= byte_count_extra+1;
								state <= read_extra_ip_header;
							elsif (byte_count_extra = ip_options_count_max-1) then
								byte_count_extra <= 0;
								state <= read_protocol_header; -- when done reading extra header's fields 
								-- go back and finish reading the regular ones
							end if;
						end if;
					end if;
				
				-- when packet contains valid data, read it here
				when read_data =>
					-- if data valid signal deasserted or error symbol detected
					-- receiver becomes idle and stops crc check
					if (crsdv = '0' or rxerr = '1' or unknown_request = '1') then
						bit_count <= 0;
						byte_count <= 0;
						byte_read_done <= (others => '0');
						stop_crc <= '1';
						start_crc <= '0';
						rst_ram <= '1';
						state <= idle;
					else 
					-- every data byte is stored into temporary register from where it is transfered to RAM
						rst_ram <= '0';
						if (byte_count <= data_counter_max-1 and bit_count < 3) then
							temp_data(2*bit_count+1 downto 2*bit_count) <= rxd;
							bit_count <= bit_count+1;
							valid_data_byte_read <= '0';
							state <= read_data;
						elsif (byte_count <= data_counter_max-1 and bit_count = 3) then
							temp_data(2*bit_count+1 downto 2*bit_count) <= rxd;
							bit_count <= 0;
							byte_count <= byte_count+1;
							valid_data_byte_read <= '1'; -- this flad triggers data transfer to RAM (process data_out_ram)
							if (byte_count = data_counter_max-1) then
								byte_count <= 0;
								if (zero_counter /= 0) then -- if packet contains any zero-padded data fields go and read them
									state <= read_zero_padding;
								else -- else if there is no zero-padding stop crc checker and read incoming crc 
									start_crc <= '0';
									state <= read_crc;
								end if;
							else
								state <= read_data;
							end if;
						end if;
					end if;
					
				-- when packet contains zero-padded data fields, read it here
				when read_zero_padding =>
					valid_data_byte_read <= '0'; -- clear the flag set when the last data byte was read
					-- if data valid signal deasserted or error symbol detected
					-- receiver becomes idle and stops crc check
					if (crsdv = '0' or rxerr = '1' or unknown_request = '1') then
						bit_count <= 0;
						byte_count <= 0;
						byte_read_done <= (others => '0');
						stop_crc <= '1'; --------------------------------------------crc
						start_crc <= '0';--------------------------------------------crc
						rst_ram <= '1';
						state <= idle;
					else -- zero-padding simply discarded, not stored
						rst_ram <= '0';
						if (byte_count <= zero_counter-1 and bit_count < 3) then
							bit_count <= bit_count+1;
							state <= read_zero_padding;
						elsif (byte_count <= zero_counter-1 and bit_count = 3) then
							bit_count <= 0;
							byte_count <= byte_count+1;
							if (byte_count+1 > zero_counter-1) then
								byte_count <= 0;
								start_crc <= '0';-- stop crc checker here
								state <= read_crc;
							else
								state <= read_zero_padding;
							end if;
						end if;
					end if;
				
				-- read crc field
				-- validity of Rx data isn't checked, since any problems on the bus/lines
				-- will be reflected on the crc field content and the packet will not pass crc check
				when read_crc =>
					valid_data_byte_read <= '0';-- clear the flag set when the last data byte was read
					if (byte_count <= 3 and bit_count < 3) then
						crc_rx((3-byte_count)*8+2*(3-bit_count)+1) <= rxd(0);
						crc_rx((3-byte_count)*8+2*(3-bit_count)) <= rxd(1);
						bit_count <= bit_count+1;
						state <= read_crc;
					elsif (byte_count <= 3 and bit_count = 3) then
						crc_rx((3-byte_count)*8+2*(3-bit_count)+1) <= rxd(0);
						crc_rx((3-byte_count)*8+2*(3-bit_count)) <= rxd(1);
						bit_count <= 0;
						byte_count <= byte_count+1;
						if (byte_count = 3) then
							byte_count <= 0;
							read_frame_done <= '1';-- flag indicating the end of frame; resets RAM's signals
							state <= check_crc; --
						else
							state <= read_crc;
						end if;
					end if;
				
				-- here calculated and received crc values are compared
				when check_crc =>
					if (crc_rx = crc_calculated) then
						crc_pass <= '1'; -- if they are the same - packet is valid
						rst_ram <= '0';
					else
						crc_pass <= '0'; -- else reject packet
						rst_ram <= '1';
					end if;
					-- clear flags here
					read_eth_header_done <= '0';
					read_frame_done <= '0';
					state <= idle;
						
			   end case;
		end if;		
	end process receive;
	
	-- this process start after Ethernet header is read and it decides whether to accept or
	-- reject packet (when it's not addressed to FPGA, for example) and determines
	-- the type of the upper layer protocol
	eth_packet_type: process (read_eth_header_done,dest_mac,eth_prot_type,
	fpga_mac,clk50mhz)
		begin
		if(rising_edge(clk50mhz)) then
				if (read_eth_header_done = '1') then -- decision is made immediately after Ethernet header
				-- has been read and it is maintained until the whole packet is read or any error is encountered
					if ((dest_mac = x"ffffffffffff" or dest_mac = fpga_mac) and eth_prot_type = arp) then -- ARP request
						arp_request_expected <= '1';
						eth_protocol_expected <= '0';
						unknown_request1 <= '0';
					elsif ((dest_mac = x"ffffffffffff" or dest_mac = fpga_mac) and eth_prot_type = ethernet) then -- IP4 protocol
						arp_request_expected <= '0';
						eth_protocol_expected <= '1';
						unknown_request1 <= '0';
					else -- none of the above - reject packet
						arp_request_expected <= '0';
						eth_protocol_expected <= '0';
						unknown_request1 <= '1'; -- flag indicating invalid packet set
					end if;
				else -- refresh protocol type registers
					arp_request_expected <= '0';
					eth_protocol_expected <= '0';
					unknown_request1 <= '0';
				end if;
		end if;
	end process eth_packet_type;
	
	-- this process parses headers based on the type of protocol detected by the process eth_packet_type
	-- in case of any mismatch between expected and actual headers' fields the packets are rejected
	headers_parse : process (byte_read_done,arp_request_expected,eth_protocol_expected,data_counter_max,source_mac,
	fpga_ip,fpga_port,ip_header_length,bytes00,bytes01,bytes02,bytes03,
	bytes04,bytes05,bytes06,bytes07,bytes08,bytes09,bytes10,bytes11,bytes12,bytes13,clk50mhz)
	begin
	if (rising_edge(clk50mhz)) then
			-- if Ethernet header corresponds to ARP request
			if (arp_request_expected = '1' and eth_protocol_expected = '0') then
				-- the following registers are set to zero, since they are for the IP4/UDP protocols, not for ARP
				ip_extra_options <= '0';
				source_ip <= (others => '0');
				source_port <= (others => '0');
				ip_options_count_max <= 0;
				udp_length <= (others => '0');
				udp_checksum <= (others => '0');
				ip_header_length <= (others => '0');
				ip_total_length <= (others => '0');
				ip_header_checksum <= (others => '0');
				-- bytes00
				if (byte_read_done(0)='1') then
					if (arp_hw_type = bytes00) then -- if ARP hardware type read matches expected value
						unknown_request2 <= '0'; 	  -- let packet pass
					else
						unknown_request2 <= '1';     -- else reject it
					end if;
				else
					unknown_request2 <= '0';
				end if;
				-- bytes01
				if (byte_read_done(1)='1') then
					if (arp_protocol_type = bytes01) then -- if ARP hardware type read matches expected value
						unknown_request2 <= '0';           -- let packet pass
					else
						unknown_request2 <= '1';           -- else reject it
					end if;
				else
					unknown_request2 <= '0';
				end if;
				-- bytes02
				if (byte_read_done(2)='1') then
					-- if ARP hardware length and protocol length read match expected values
					if (arp_hw_length = bytes02(15 downto 8) and arp_protocol_length = bytes02(7 downto 0)) then
						unknown_request2 <= '0';           -- let packet pass
					else
						unknown_request2 <= '1';			  -- else reject it
					end if;
				else
					unknown_request2 <= '0';
				end if;
				-- bytes03
				if (byte_read_done(3)='1') then
					if (arp_request = bytes03) then -- if ARP request received
						data_counter_max <= 0;  	  -- arp request has no data
						zero_counter <= 18;			  -- arp request has 18 bytes of zero padding
						unknown_request2 <= '0';	  -- let packet pass
					else
						data_counter_max <= 0; 
						zero_counter <= 0;
						unknown_request2 <= '1';	  -- else reject it
					end if;
				else 								        -- refresh data and zero count registers
					data_counter_max <= 0; 
					zero_counter <= 0;
					unknown_request2 <= '0';
				end if;
				-- bytes04, bytes05, bytes06
				if (byte_read_done(4)='1' and byte_read_done(5)='1' and byte_read_done(6)='1') then
					if (source_mac = bytes04&bytes05&bytes06) then -- if source MAC matches the one read in Ethernet header
						unknown_request2 <= '0';						  -- let packet pass
					else
						unknown_request2 <= '1';						  -- else reject it
					end if;
				else
					unknown_request2 <= '0';
				end if;
				-- bytes07, bytes08
				if (byte_read_done(7)='1' and byte_read_done(8)='1') then
					source_ip <= bytes07&bytes08; -- read source IP4 address
				else
					source_ip <= (others =>'0');  -- refresh source IP4 address register
				end if;
				-- bytes09, bytes10, bytes11
				if (byte_read_done(9)='1' and byte_read_done(10)='1' and byte_read_done(11)='1') then
					if (bytes09&bytes10&bytes11 = x"000000000000" or bytes09&bytes10&bytes11 = fpga_mac) then -- if target MAC address is zeros
						unknown_request2 <= '0';								 -- let packet pass
					else
						unknown_request2 <= '1';								 -- else reject it
					end if;
				else
					unknown_request2 <= '0';
				end if;
				-- bytes12, bytes13
				if (byte_read_done(12)='1' and byte_read_done(13)='1') then
					if (fpga_ip = bytes12&bytes13) then -- if destination IP4 address = FPGA IP4 address
						unknown_request2 <= '0';			-- let packet pass
					else
						unknown_request2 <= '1';			-- else reject it
					end if;
				else
					unknown_request2 <= '0';
				end if;
			-- if Ethernet header corresponds to IP4/UDP protocol
			elsif (arp_request_expected = '0' and eth_protocol_expected = '1') then
				-- bytes00
				if (byte_read_done(0)='1') then
					if (bytes00(15 downto 12) = "0100") then -- if IP version = 4 
						unknown_request2 <= '0';				  -- let packet pass
					else
						unknown_request2 <= '1';				  -- else reject it
					end if;
					ip_header_length <= bytes00(11 downto 8);-- read IP header's length
					if (4*to_integer(unsigned(ip_header_length)) > 20)then 						-- if it's greater than 20 bytes
						ip_options_count_max <= 4*to_integer(unsigned(ip_header_length))-20; -- set extra header's field counter
						ip_extra_options <= '1'; 															-- set flag indicating presence of extra header's fields
					else
						ip_options_count_max <= 0;                                           -- else thre are no extra header's fields
						ip_extra_options <= '0';
					end if;
					-- differentiated services are ignored (bits 7 to 0 of bytes00)
				else -- refresh registers
					unknown_request2 <= '0';
					ip_header_length <= x"0";
					ip_options_count_max <= 0;
					ip_extra_options <= '0';
				end if;
				-- bytes01
				if (byte_read_done(1)='1') then
					ip_total_length <= bytes01; -- read total length of IP datagram (header+data) in bytes
					data_counter_max <= to_integer(unsigned(bytes01))- 4*to_integer(unsigned(bytes00(11 downto 8)))-8;-- set counter for data here
					--example: 25(=37)-4*5-8=9 (from 0 to 8) = 9 bytes of data; 8 - is the UDP header length in bytes; 4*5 - is IP header length
					if (data_counter_max < 18) then -- 8<17 - true; if less than 18 there are zero-padded data fields
						zero_counter <= 18-data_counter_max; -- 18-9-1=8 (from 0 to 8) = 9 bytes of zeros
					else
						zero_counter <= 0;
					end if;
				else
					ip_total_length <= (others => '0');
					data_counter_max <= 0;
					zero_counter <= 0;
				end if;
				-- bytes02
				if (byte_read_done(2)='1') then
					identification <= bytes02; -- read Identification field
				else 
					identification <= (others => '0');
				end if;
				-- bytes03
				if (byte_read_done(3)='1') then
					flags_offset <= bytes03;   -- read Flags and Fragmentation offsets (not used in the design)
				else 
					flags_offset <= (others => '0');
				end if;
				-- bytes04
				if (byte_read_done(4)='1') then
					if (ip_protocol = bytes04(7 downto 0)) then -- if higher level protocol is UDP 
						unknown_request2 <= '0';					  -- let packet pass
					else
						unknown_request2 <= '1';					  -- else reject it
					end if;
				-- Time to Live parameter is ignored (bits 15 to 8 of bytes04)
				else
					unknown_request2 <= '0';
				end if;
				-- bytes05
				if (byte_read_done(5)='1') then
					ip_header_checksum <= bytes05; -- read IP header's checksum
				else
					ip_header_checksum <= (others => '0');
				end if;
				-- bytes06, bytes07
				if (byte_read_done(6)='1' and byte_read_done(7)='1') then
					source_ip <= bytes06&bytes07;  -- read source IP4 address
				else
					source_ip <= (others => '0');
				end if;
				-- bytes08, bytes09
				if (byte_read_done(8)='1' and byte_read_done(9)='1') then
					if (fpga_ip = bytes08&bytes09) then -- if destination IP4 address = FPGA IP4 address
						unknown_request2 <= '0';         -- let packet pass
					else
						unknown_request2 <= '1';			-- else reject it
					end if;
				else
					unknown_request2 <= '0';
				end if;
				-- bytes10
				if (byte_read_done(10)='1') then
					source_port <= bytes10; 				-- read source port number
				else
					source_port <= (others => '0');
				end if;
				-- bytes11
				if (byte_read_done(11)='1') then
					if (fpga_port = bytes11) then      -- if destination port number = FPGA port number
						unknown_request2 <= '0';		  -- let packet pass
					else
						unknown_request2 <= '1';        -- else reject it
					end if;
				else
					unknown_request2 <= '0';
				end if;
				-- bytes12
				if (byte_read_done(12)='1') then
					udp_length <= bytes12;				 -- read UDP protocol length
				else
					udp_length <= (others => '0');
				end if;
				-- bytes13
				if (byte_read_done(13)='1') then
					udp_checksum <= bytes13;		    -- read UDP checksum
				else
					udp_checksum <= (others => '0');
				end if;
			-- refresh headers' registers
			else
				unknown_request2 <= '0';
				ip_extra_options <= '0';
				source_ip <= (others => '0');
				source_port <= (others => '0');
				data_counter_max <= 0;
				zero_counter <= 0;
				ip_options_count_max <= 0;
				udp_length <= (others => '0');
				udp_checksum <= (others => '0');
				ip_header_length <= (others => '0');
				ip_total_length <= (others => '0');
				ip_header_checksum <= (others => '0');
			end if;
	end if;
	end process headers_parse;
	
	-- this process handles IP header checksum calculations, note checksum is not calculated for ARP protocol
	ip_header_checksum_check: process (clk50mhz,byte_read_done(9),ip_header_checksum,arp_request_expected,eth_protocol_expected,
	ip_extra_options,ip_options_count_max,ip_header_options)
	begin
	if (rising_edge(clk50mhz)) then
		-- if IP4 protocol received and IP header is read and checksum hasn't been calculated, calculate it here
		if (arp_request_expected = '0' and eth_protocol_expected = '1' and byte_read_done(9)='1' and ip_hcs_done = '0') then
			case sip is
				when sip1 =>
					if (ip_extra_options = '1') then                   -- take into account IP header extra field
						for j in 39 downto 0 loop                       -- 40-1=39 - max length of extra field in bytes
							edge_count_header <= not(edge_count_header); -- keeps track of senior/junior byte
							if (ip_header_options(j*8+7 downto j*8+0) = x"00") then
								ip_hcs_calc_extra <= ip_hcs_calc_extra; 	-- find first non-zero byte here
							else
								if (edge_count_header = '0') then            -- senior byte was received first
									ip_hcs_calc_extra <= ip_hcs_calc_extra+unsigned(ip_header_options(j*8+7 downto j*8+0)&x"00");
								elsif (edge_count_header = '1') then         -- junior byte was received second
									ip_hcs_calc_extra <= ip_hcs_calc_extra+unsigned(x"00"&ip_header_options(j*8+7 downto j*8+0));
								end if;
							end if;
						end loop;
					elsif (ip_extra_options = '0') then -- if no IP header extra options - it's just zero
						edge_count_header <= '0';
						ip_hcs_calc_extra <= (others => '0');
					end if;
					ip_hcs_calc_temp1 <= ip_hcs_calc_temp1+unsigned(bytes00)+unsigned(ip_total_length)+unsigned(identification)+
					unsigned(flags_offset)+unsigned(bytes04)+unsigned(ip_header_checksum)+unsigned(bytes06)+
					unsigned(bytes07)+unsigned(bytes08)+unsigned(bytes09)+ip_hcs_calc_extra; -- sum all the IP header's fields here
					sip <= sip2;
				when sip2 =>
					ip_hcs_calc_temp2 <= not(ip_hcs_calc_temp2+ip_hcs_calc_temp1(15 downto 0)+ip_hcs_calc_temp1(23 downto 16)); -- add carry-out to checksum
					sip <= sip3;
				when sip3 =>
					ip_hcs_calc <= std_logic_vector(ip_hcs_calc_temp2); -- complement the result
					ip_hcs_done <= '1';											 -- set flag indicating completion of IP header checksum calculations
					sip <= sip3;
			end case;
		-- if IP headers checksum has already been calculated keep the result
		elsif (arp_request_expected = '0' and eth_protocol_expected = '1' and byte_read_done(9)='1' and ip_hcs_done = '1') then
			ip_hcs_calc <= ip_hcs_calc;
			ip_hcs_done <= ip_hcs_done;
			ip_hcs_calc_temp1 <= ip_hcs_calc_temp1;
			ip_hcs_calc_temp2 <= ip_hcs_calc_temp2;
		else -- refresh IP headers checksum registers
			ip_hcs_calc <= (others => '1');
			ip_hcs_calc_temp1 <= (others => '0');
			ip_hcs_calc_temp2 <= (others => '0');
			ip_hcs_done <= '0';
			sip <= sip1;
		end if;
		-- verify ip header checksum
		if (ip_hcs_done = '1') then
			if (ip_hcs_calc = x"0000") then -- if calculated checksum = 0
				unknown_request3 <= '0';     -- let packet pass
			else
				unknown_request3 <= '1';     -- else reject it
			end if;
		else
			unknown_request3 <= '0';
		end if;
	end if;
	end process ip_header_checksum_check;
	
	-- this process handles UDP header checksum calculations, note checksum is not calculated for ARP protocol
	udp_header_checksum_check: process (clk50mhz,byte_read_done(13),bytes13,arp_request_expected,eth_protocol_expected,
	source_port,source_ip,fpga_ip,fpga_port,udp_length,temp_data,valid_data_byte_read,start_crc,stop_crc)
	begin
		if (rising_edge(clk50mhz)) then
		-- if IP4 protocol received and UDP header is read and checksum hasn't been calculated, calculate it here
			if (arp_request_expected = '0' and eth_protocol_expected = '1' and byte_read_done(13)='1' and udp_presum_done = '0') then
				udp_presum <= udp_presum+unsigned(source_ip(31 downto 16))+unsigned(source_ip(15 downto 0))+unsigned(fpga_ip(31 downto 16))+
				unsigned(fpga_ip(15 downto 0))+unsigned(x"00"&ip_protocol)+unsigned(udp_length)+unsigned(source_port)+unsigned(fpga_port)+
				unsigned(udp_length)+unsigned(bytes13); -- presum calculates the first summand of UDP checksum comprising only header's fields
				udp_presum_done <= '1';						 -- flag indicating the presum was calculated
			-- maintain presum value once it was calculated
			elsif (arp_request_expected = '0' and eth_protocol_expected = '1' and byte_read_done(13)='1' and udp_presum_done = '1') then
				udp_presum <= udp_presum;
				udp_presum_done <= udp_presum_done;
			else -- reset presum here
				udp_presum <= (others => '0');
				udp_presum_done <= '0';
			end if;
			-- the second summand of UDP checksum, conmprising data fields, is calculated here 
			if (valid_data_byte_read='1' and start_crc ='1' and stop_crc ='0') then -- once valid data byte was read and this is not the last data byte
				edge_count_data <= not(edge_count_data); 										-- add it to the second checksum summand
				if (edge_count_data = '0') then                                      -- edge count controls format of addition
					udp_data_sum <= udp_data_sum+unsigned(temp_data&x"00");
				elsif (edge_count_data = '1') then
					udp_data_sum <= udp_data_sum+unsigned(x"00"&temp_data);
				end if;
			elsif (valid_data_byte_read='0' and start_crc ='1' and stop_crc ='0') then
				edge_count_data <= edge_count_data;
				udp_data_sum <= udp_data_sum;
			elsif (start_crc ='0' and stop_crc ='0') then -- these flags defines the start of crc field on receive
				edge_count_data <= '0';
				udp_data_sum <= udp_data_sum;
				udp_datasum_done <= '1';						 -- calculation of the second summand is over
			elsif (stop_crc ='1') then							 -- refresh the second summand's register
				edge_count_data <= '0';
				udp_data_sum <= (others => '0');
				udp_datasum_done <= '0';
			end if;
			if (udp_presum_done = '1' and udp_datasum_done = '1' and udp_hcs_done = '0') then -- if both summands are calculated find checksum
				case sudp is
					when sudp1 =>
						udp_hcs_calc_temp1 <= udp_presum+udp_data_sum; 									 -- add 2 summand together
						sudp <= sudp2;
					when sudp2 =>
						udp_hcs_calc_temp2 <= not(udp_hcs_calc_temp2+udp_hcs_calc_temp1(15 downto 0)+udp_hcs_calc_temp1(23 downto 16)); -- add carry-out
						sudp <= sudp3;
					when sudp3 =>
						udp_hcs_calc <= std_logic_vector(udp_hcs_calc_temp2);							 -- find checksum
						udp_hcs_done <= '1';																		 -- set flag
						sudp <= sudp3;
				end case;
			elsif (udp_presum_done = '1' and udp_datasum_done = '1' and udp_hcs_done = '1') then -- maintain calculated checksum value
				udp_hcs_calc_temp1 <= udp_hcs_calc_temp1;
				udp_hcs_calc_temp2 <= udp_hcs_calc_temp2;
				udp_hcs_calc <= udp_hcs_calc;
				udp_hcs_done <= udp_hcs_done;
			else -- refresh UDP checksum registers
				udp_hcs_calc_temp1 <= (others => '0');
				udp_hcs_calc_temp2 <= (others => '0');
				udp_hcs_calc <= (others => '1');
				udp_hcs_done <= '0';
				sudp <= sudp1;
			end if;
			if (udp_hcs_done = '1') then
				if (udp_hcs_calc = x"0000") then -- if calculated checksum = 0
					unknown_request4 <= '0';		-- let packet pass
				else
					unknown_request4 <= '1';		-- else reject it
				end if;
			else
				unknown_request4 <= '0';
			end if;
		end if;
	end process udp_header_checksum_check;
	
	-- this process transfers data to transmitter for reply
	data_out: process (crc_pass,read_frame_done,source_mac,source_ip,source_port,arp_request_expected,eth_protocol_expected,clk50mhz)
	begin
	if(rising_edge(clk50mhz)) then
		if (crc_pass = '1') then -- if data packet passed crc check and it's a valid packet
			-- pass data required to assemble Tx packet to transmitter
			pc_mac <= source_mac;   			 -- PC's MAC address
			pc_ip <= source_ip;     			 -- PC's IP4 address
			pc_port <= source_port; 			 -- PC's port number
			datacm <= std_logic_vector(to_signed(data_counter_max, ADDR_WIDTH+1)); -- length of the data field
			udpl <= udp_length;    				 -- UDP header+data length
			udpc <= udp_checksum;   			 -- UDP checksum (same for Rx and Tx, since it's an echo server)
			data_out_valid <= '1';
			if (arp_request_expected = '1') then
				send_arp_reply <= '1';			 -- tell Tx to send ARP reply if ARP request was received
				send_ethernet_protocol <= '0';
			elsif (eth_protocol_expected = '1') then
				send_arp_reply <= '0';
				send_ethernet_protocol <= '1'; -- tell Tx to send UDP packet if UDP packet was received
			else 										 -- no valid packet has been received, no reply will be sent
				send_arp_reply <= '0';
				send_ethernet_protocol <= '0';
			end if;
		else -- until the received packet passes crc check no data transferred to transmitter
			pc_mac <= (others => '0');
			pc_ip <= (others => '0');
			pc_port <= (others => '0');
			datacm <= (others => '0');
			udpl <= (others => '0');
			udpc <= (others => '0');
			data_out_valid <= '0';
			send_arp_reply <= '0';
			send_ethernet_protocol <= '0';
		end if;
	end if;
	end process data_out;
	
	-- this process takes care of saving received data to RAM
	data_out_ram: process (clk50mhz,temp_data,valid_data_byte_read,addr_count,read_frame_done,data_to_ram,we_ram,rst_ram)
	begin -- don't forget to reset ram if invalid signal
		if(rising_edge(clk50mhz)) then
			case s_ram is
				when s_ram1 =>
					if (valid_data_byte_read = '1') then -- if valid data byte was read write it to RAM
						data_to_ram <= temp_data;
						we_ram <= '1';
						s_ram <= s_ram2;
					elsif (read_frame_done = '1' or rst_ram = '1') then -- at the end of the frame or in case of error reset RAM's signals
						data_to_ram <= (others => '0');
						addr_count <= (others => '0');
						we_ram <= '0';
						s_ram <= s_ram4;
					else
						data_to_ram <= data_to_ram;
						addr_count <= addr_count;
						we_ram <= '0';
						s_ram <= s_ram1;
					end if;
				when s_ram2 =>
					data_to_ram <= data_to_ram;
					we_ram <= '1';
					addr_count <= addr_count;
					s_ram <= s_ram3;
				when s_ram3 =>
					data_to_ram <= data_to_ram;
					we_ram <= '0';
					if (addr_count+1 > 2**ADDR_WIDTH-1) then
						addr_count <= (others => '0');
					else
						addr_count <= addr_count+1;
					end if;
					s_ram <= s_ram1;
				when s_ram4 =>
					data_to_ram <= (others => '0');
					addr_count <= (others => '0');
					we_ram <= '0';
					s_ram <= s_ram1;
				end case;
		end if;
		-- attach RAM signals to RAM ports
		wrt_data_ram <= data_to_ram;
		wrt_addr_ram <= std_logic_vector(addr_count);
		wrt_enable_ram <= we_ram;
	end process data_out_ram;

unknown_request <= unknown_request1 or unknown_request2 or unknown_request3 or unknown_request4; -- all flags indicating invalid packet formats are ORed here

end Behavioral;

