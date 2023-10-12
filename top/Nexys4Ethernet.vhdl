----------------------------------------------------------------------------------
-- Company: The Hong Kong Polytechnic University
-- Engineer: Alexandr Melnikov
-- 
-- Create Date:    16:19:30 02/20/2017 
-- Design Name: 
-- Module Name:    ethernet_transceiver - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created

-- UDP echo-server design uses on-board Ethernet port to create a data-link between FPGA board
-- Nexys 4 DDR and MatLAB. Echo-server is capable of reception and transmission data packets
-- using ARP and UDP protocols.
-- MAC address of FPGA board: 00:18:3e:01:ff:71
-- IP4 address of FPGA board: 192.168.1.10
-- Port number used in the design: 58210
-- The echo server will reply back to any data server, which uses correct IP4 address and Port number.
-- MAC address of the board is made discoverable for the data server via ARP protocol
-- This Echo-server design doesn't use any input or output FIFO's as elesticity buffers,
-- both in- and outgoing data packets are parsed/assembled in parallel with Rx/Tx processes,
-- which allows better resource utilisation at the price of more complex design architecture. 

-- Additional Comments: 
-- Transceiver block is the Top-level block of the Ethernet transceiver design, implementing 
-- the VHDL UDP echo-server.
-- Transceiver block itself handles the Power-On Reset operation along with subsequent Hardware Resets
-- on request from the user.
-- Apart from that it incorporates lower-level modules handling different functions required for the echo-server
-- operations: Receiver, Transmitter, Serial Management Interface, Memory and Clock Modules
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

entity Nexys4Ethernet is
	Generic (
		M_clk2_5mhz1	: integer := 20; 	-- divisor for 2.5MHz clock
		M_clk2_5mhz2	: integer := 10; 	-- divisor for shifted 2.5MHz clock 
		N 				: integer := 22;    -- divisor for debouncing circuit 
		ADDR_WIDTH 		: integer := 10;	-- RAM's address width
		DATA_WIDTH 		: integer := 8  	-- RAM's data width (1024x1byte)
	);
    Port ( 	
		CLK100MHz 	: in  		STD_LOGIC;
		-- Ethernet connection
		eth_rxd 	: inout  	STD_LOGIC_VECTOR (1 downto 0);
		eth_txd 	: inout  	STD_LOGIC_VECTOR (1 downto 0);
		eth_crsdv 	: inout  	STD_LOGIC;
		eth_txen 	: inout  	STD_LOGIC;
		eth_rxerr 	: inout  	STD_LOGIC;
		eth_mdc 	: out  		STD_LOGIC;
		eth_mdio 	: inout  	STD_LOGIC;
		eth_refclk 	: out  		STD_LOGIC;
		eth_rstn 	: inout  	STD_LOGIC;
		-- display signals for ARP and UDP packets
		led16_b 	: out  		STD_LOGIC;
		led16_g 	: out  		STD_LOGIC;
		led16_r 	: out  		STD_LOGIC;
		led17_b 	: out  		STD_LOGIC;
		led17_g 	: out  		STD_LOGIC;
		led17_r 	: out  		STD_LOGIC;
		-- outputs for debugging
--		mode0 		: out 		std_logic;
--		mode1 		: out 		std_logic;
--		mode2 		: out		std_logic;
--		refclk 		: out		std_logic;
--		rxerr 		: out		std_logic;
--		txd 		: out 		STD_LOGIC_VECTOR (1 downto 0);
--		txen 		: out  		STD_LOGIC;
		-- Reset and SMI inputs/outputs
		btn_reset 	: in		std_logic;
		led 		: out 		std_logic_vector (15 downto 0);
		sw 			: in 		std_logic_vector (15 downto 0)
	);
end Nexys4Ethernet;

architecture Behavioral of Nexys4Ethernet is
	-- CLOCKS
	-- main clock
	signal b_clk100mhz 		: std_logic;
	signal clk50mhz 		: std_logic;	-- inner signal for ETH_REFCLK (read Rx on falling edge)
	signal b_clk50mhz 		: std_logic; 	-- inner signal for ETH_REFCLK (read Rx on falling edge)
	signal clk50mhz_shift 	: std_logic; 	-- shifted 50mhz clock signal for write Tx operation
	signal b_clk50mhz_shift : std_logic; 	-- shifted 50mhz clock signal for write Tx operation

	-- mdio clock
	signal clk2_5mhz 		: std_logic;    -- MDC clock
	signal b_clk2_5mhz 		: std_logic;    -- MDC clock
	signal clk2_5mhz_shift 	: std_logic; 	-- shifted mdio clock for read and write MDIO
	signal b_clk2_5mhz_shift : std_logic; 	-- shifted mdio clock for read and write MDIO

	-- SIGNALS
	-- ******* process transceiver (only responsible for Hardware Reset) ********--
	type state_type is (idle, power_on, reset);
	signal state 			: state_type := idle;
	constant MODE 			: std_logic_vector (2 downto 0) := "111";	-- all capable; auto-negotiation enabled
	constant PHYAD 			: std_logic := '1'; 						-- physical address of the transciever
	signal rstn_counter 	: integer range 0 to 5010 := 0;     		-- count 100us+220ns (5000+11 50mhz clock cycles)
	signal po_counter 		: integer range 0 to 2499999:= 0;     		-- count 50ms - power supply turn on time (2,500,000 50mhz clock cycles)
	signal hw_reset 		: std_logic;         						-- button attached to this signal via debouncing circuit: hardware reset
	signal hw_resetn		: std_logic;         						-- button attached to this signal via debouncing circuit: hardware reset
	signal init_proc 		: std_logic := '0'; 						-- flag indicating wether power-on reset was done or not

	-- ******** Ethernet Signals ********--
	--*^*^*^*^*^*^* PC's and FPGA's MAC, IP4 addresses and Port numbers *^*^*^*^*^*^*--
	signal pc_mac 			: std_logic_vector (47 downto 0); 					-- PC's MAC address (configured on PC's side)
	signal pc_ip 			: std_logic_vector (31 downto 0);  					-- PC's IP4 address (configured on PC's side)
	signal pc_port 			: std_logic_vector (15 downto 0);					-- PC's port (configured on PC's side)
	constant fpga_mac 		: std_logic_vector (47 downto 0) := x"00183e01ff71";-- FPGA's MAC address
	constant fpga_ip 		: std_logic_vector (31 downto 0) := x"C0A8010A";    -- FPGA's IP4 address 192.168.1.10
	constant fpga_port 		: std_logic_vector (15 downto 0) := x"E362";       	-- FPGA's port 58210
	-- data transfer between Rx and Tx
	signal send_arp_reply 	: std_logic := '0';        	-- ARP protocol flag
	signal send_ethernet_protocol : std_logic := '0';	-- Ethernet protocol flag
	signal data_out_valid 	: std_logic := '0';        	-- data valid flag
	signal datacm 			: STD_LOGIC_VECTOR (ADDR_WIDTH downto 0) := (others => '0'); -- length of data in UDP datagram
	signal udpl 			: STD_LOGIC_VECTOR (15 downto 0) := (others => '0'); -- length of IP datagram data field in bytes
	signal udpc 			: STD_LOGIC_VECTOR (15 downto 0) := (others => '0'); -- UDP checksum
	-- data to and from RAM
	signal rx_data 			: std_logic_vector (DATA_WIDTH-1 downto 0) := (others => '0'); -- data from Rx to RAM
	signal tx_data 			: std_logic_vector (DATA_WIDTH-1 downto 0) := (others => '0'); -- data from RAM to Tx
	signal wrt_addr_ram 	: std_logic_vector (ADDR_WIDTH-1 downto 0) := (others => '0'); -- address to write data to RAM
	signal rd_addr_ram 		: std_logic_vector (ADDR_WIDTH-1 downto 0) := (others => '0'); -- address to read data from RAM
	signal we_ram 			: std_logic := '0'; -- enable write RAM operation  
	signal re_ram 			: std_logic := '0'; -- enable read RAM operation 

	--signal refclk: std_logic;

	-- ******** COMPONENTS DECLARATION ********--
	component debounce_switch -- for Hardware Reset switch debouncing
		generic (N : integer);
			port (clk100mhz : in std_logic;
					btn : in std_logic;
					db_sw : out std_logic);
	end component;

	component clock_mod -- RMII clocks
		--generic (M_clk : integer);
		port (clk100mhz : in std_logic;
				clk_out : out std_logic;
				clk_out_shift : out std_logic);
	end component;

	component clock_mod2 -- MDC clocks
		generic (M_clk1 : integer;
					M_clk2 : integer);
		port (clk100mhz : in std_logic;
				clk_out1 : out std_logic; 
				clk_out2 : out std_logic);
	end component;

	component md_interface -- MDIO interface
		port (mdc_shift : in STD_LOGIC;
				mdio : inout  STD_LOGIC;
				eth_rstn : in  STD_LOGIC;
				led : out  STD_LOGIC_VECTOR (15 downto 0);
				sw : in  STD_LOGIC_VECTOR (4 downto 0));
	end component;

	component eth_receiver -- RMII Rx Interface
		Generic (ADDR_WIDTH : integer;
					DATA_WIDTH : integer);
		port (clk100mhz : in STD_LOGIC;
				clk50mhz : in  STD_LOGIC;
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
	end component;

	component eth_transmitter -- RMII Tx Interface
		Generic (ADDR_WIDTH : integer;
				DATA_WIDTH : integer);
		port (clk100mhz : in  STD_LOGIC;
				clk50mhz_shift : in STD_LOGIC;
				rstn : in STD_LOGIC;
				txd : inout  STD_LOGIC_VECTOR (1 downto 0);
				txen : out  STD_LOGIC;
			-- Data from RAM
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
	end component;

	component single_port_RAM -- RAM block to store data from Ethernet packets
		generic (ADDR_WIDTH : integer;
					DATA_WIDTH : integer);
		port (clk50mhz : in  STD_LOGIC;
				we : in  STD_LOGIC;
				re : in STD_LOGIC;
				addr_r : in  STD_LOGIC_VECTOR (ADDR_WIDTH-1 downto 0);
				addr_w : in  STD_LOGIC_VECTOR (ADDR_WIDTH-1 downto 0);
				din : in  STD_LOGIC_VECTOR (DATA_WIDTH-1 downto 0);
				dout : out  STD_LOGIC_VECTOR (DATA_WIDTH-1 downto 0));
	end component;

	component led1 -- Display module for incoming ARP and UDP packets
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
	end component;


-------------------------------------------------------------------------------
begin

	-- ******** COMPONENTS INSTANTIATION ********--
	-- clock buffers
	U1: BUFG port map (I=>clk100mhz,O=>b_clk100mhz);
	U2: BUFG port map (I=> clk2_5mhz, O=>b_clk2_5mhz);
	U3: BUFG port map (I=>clk2_5mhz_shift,O=>b_clk2_5mhz_shift);
	U4: BUFG port map (I=> clk50mhz,O=>b_clk50mhz);
	U5: BUFG port map (I=> clk50mhz_shift,O=>b_clk50mhz_shift);
	--	pull-ups on multiplexed MODE pins
	PULLUP_MODE0: PULLUP PORT MAP (O => eth_rxd(0));
	PULLUP_MODE1: PULLUP PORT MAP (O => eth_rxd(1));
	PULLUP_MODE2: PULLUP PORT MAP (O => eth_crsdv);
	-- pull-up on multiplexed PHYAD pin
	PULLUP_PHYAD0: PULLUP PORT MAP (O => eth_rxerr);
	
	-- pull-up on I2C MDIO pin is implemented in md_interface module

	-- MDIO interface
	MDIO_Interface: md_interface
		port map (
			mdc_shift => b_clk2_5mhz_shift,--clk2_5mhz_shift,
			mdio => eth_mdio,
			eth_rstn => eth_rstn,
			led => led,
			sw => sw(4 downto 0)
		);
									  
	--Ethernet receiver
	Ethernet_receiver: eth_receiver
		generic map (
			ADDR_WIDTH => ADDR_WIDTH,
			DATA_WIDTH => DATA_WIDTH
		)
		port map (
			clk100mhz => b_clk100mhz,
			clk50mhz => b_clk50mhz,
			rxd => eth_rxd,
			crsdv => eth_crsdv,
			rstn => eth_rstn,
			rxerr => eth_rxerr,
			---
			wrt_data_ram => rx_data,
			wrt_addr_ram => wrt_addr_ram,
			wrt_enable_ram => we_ram,
			---
			fpga_mac => fpga_mac,
			fpga_ip => fpga_ip,
			fpga_port => fpga_port,
			pc_mac => pc_mac,
			pc_ip => pc_ip,
			pc_port => pc_port,
			---
			datacm => datacm,
			udpl => udpl,
			udpc => udpc,
			send_arp_reply => send_arp_reply,
			send_ethernet_protocol => send_ethernet_protocol,
			data_out_valid => data_out_valid
		);

	--Ethernet transmitter
	Ethernet_transmitter: eth_transmitter
		generic map (
			ADDR_WIDTH => ADDR_WIDTH,
			DATA_WIDTH => DATA_WIDTH
		)
		port map (
			clk100mhz => b_clk100mhz,
			clk50mhz_shift => b_clk50mhz_shift,
			rstn => eth_rstn,
			txd => eth_txd,
			txen => eth_txen,
			---
			rd_data_ram => tx_data,
			rd_addr_ram => rd_addr_ram,
			rd_enable_ram => re_ram,
			---
			fpga_mac => fpga_mac,
			fpga_ip => fpga_ip,
			fpga_port => fpga_port,
			pc_mac => pc_mac,
			pc_ip => pc_ip,
			pc_port => pc_port,
			---
			datacm => datacm,
			udpl => udpl,
			udpc => udpc,
			send_arp_reply => send_arp_reply,
			send_ethernet_protocol => send_ethernet_protocol,
			data_in_valid => data_out_valid
		);

	-- Block RAM
	RAM1: single_port_RAM
		generic map (
			ADDR_WIDTH => ADDR_WIDTH,
			DATA_WIDTH => DATA_WIDTH
		)
		port map (
			clk50mhz => b_clk50mhz,
			we => we_ram,
			re => re_ram,
			addr_w => wrt_addr_ram,
			addr_r => rd_addr_ram,
			din => rx_data,
			dout => tx_data
		);

	-- ARP and UDP LED's
	LED_count : led1 -- Display module for incoming ARP and UDP packets
		port map (
			clk50mhz => b_clk50mhz,
			rstn => eth_rstn,
			dv_arp => send_arp_reply,
			dv_eth => send_ethernet_protocol,
			led16_b => led16_b,
			led16_g => led16_g,
			led16_r => led16_r,
			led17_b => led17_b,
			led17_g => led17_g,
			led17_r => led17_r
		);

	-- Debouncing circuit
	Switch: debounce_switch
		generic map (N => N)
		port map (
			clk100mhz => b_clk100mhz,
			btn => btn_reset,
			db_sw => hw_resetn
		);
	-- CPU reset pin is inverted
	hw_reset <= not hw_resetn;

	-- RMII clocks	
	CLOCK_50MHz: clock_mod
		--generic map (M_clk => M_clk50mhz)
		port map (
			clk100mhz => b_clk100mhz,
			clk_out => clk50mhz,
			clk_out_shift => clk50mhz_shift
		); 
	-- MDIO clocks
	CLOCK_2_5MHz: clock_mod2
		generic map (
			M_clk1 => M_clk2_5mhz1,
			M_clk2 => M_clk2_5mhz2
		)
		port map (
			clk100mhz => b_clk100mhz,
			clk_out1 => clk2_5mhz,
			clk_out2 => clk2_5mhz_shift
		);
	
	transceiver: process (b_clk50mhz, hw_reset)
	begin
		if (hw_reset = '1') then
			eth_rstn <= '0';
			--MODE <= "111"; -- configure MODES here (if MODE is other than 1's)
			--PHYAD <= '1';  -- configure PHYAD here (if PHYAD is other than 1's)
			rstn_counter <= 0;
			state <= reset;
		elsif (rising_edge(b_clk50mhz)) then
			case state is
			
			when idle =>
				if (init_proc = '0') then -- if Power-ON Reset (POR) hasn't been completed
					eth_rstn <= '1';
					--MODE <= "111"; -- configure MODES here (if MODES is other than 1's)
					--PHYAD <= '1';  -- configure PHYAD here (if PHYAD is other than 1's)
					state <= power_on;
				else	
					eth_rstn <= '1';
					--MODE <= "111"; -- release (set to 1's) MODES here (if configure them)
					--PHYAD <= '1';  -- release (set to 1) PHYAD here (if configure it)
					state <= idle;
				end if;
			
			when power_on => -- wait for 50 ms before POR
				--MODE <= "111"; -- configure MODES here (if MODES is other than 1's)
				--PHYAD <= '1';  -- configure PHYAD here (if PHYAD is other than 1's)
				if (po_counter < 2499999) then  
					eth_rstn <= '1';
					po_counter <= po_counter+1;
					state <= power_on;
				elsif (po_counter = 2499999) then
					eth_rstn <= '0';
					init_proc <= '1';
					po_counter <= 0;
					state <= reset;
				end if;
			
			when reset => -- POR
				if (rstn_counter <= 4999) then -- 100 us before releasing eth_rstn
					--MODE <= "111"; -- configure MODES here (if MODES is other than 1's)
					--PHYAD <= '1';  -- configure PHYAD here (if PHYAD is other than 1's)
					rstn_counter <= rstn_counter+1;
					eth_rstn <= '0';
					state <= reset;
				elsif (rstn_counter > 4999 and rstn_counter <= 5009) then -- 220 ns hold on time after releasing eth_rstn
					--MODE <= "111"; -- configure MODES here (if MODES is other than 1's)
					--PHYAD <= '1';  -- configure PHYAD here (if PHYAD is other than 1's)
					rstn_counter <= rstn_counter+1;
					eth_rstn <= '1';
					state <= reset;
				elsif (rstn_counter = 5010) then -- POR done, go back to idle state
					--MODE <= "111"; -- release (set to 1's) MODES here (if configure them)
					--PHYAD <= '1';  -- release (set to 1) PHYAD here (if configure it)
					rstn_counter <= 0;
					eth_rstn <= '1';
					state <= idle;
				end if;
					
			end case;
		end if;
	end process transceiver;

-- tri-state buffers
eth_rxd(0) <= '0' when MODE(0) = '0' else 'Z';
eth_rxd(1) <= '0' when MODE(1) = '0' else 'Z';
eth_crsdv <= '0' when MODE(2) = '0' else 'Z';
eth_rxerr <= '0' when PHYAD = '0' else 'Z';
-- RMII and MDC clocks
eth_refclk <= b_clk50mhz;
eth_mdc <= b_clk2_5mhz;--clk2_5mhz;

-- outputs for debugging
--mode0 <= eth_rxd(0);
--mode1 <= eth_rxd(1);
--mode2 <= eth_crsdv;
--refclk <= b_clk50mhz;
--rxerr <= eth_rxerr;
--txd <= eth_txd;
--txen <= eth_txen;

end Behavioral;

