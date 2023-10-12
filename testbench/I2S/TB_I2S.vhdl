-- testbench for the I2S receiver

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
 
-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--USE ieee.numeric_std.ALL;
 
ENTITY tb_i2s IS
END tb_i2s;
 
ARCHITECTURE behavior OF tb_i2s IS 
    -- Component Declaration for the Unit Under Test (UUT)
    --COMPONENT i2s_recv
    --PORT(
    --);

    signal MCLK  : std_logic := '0';

begin

    MCLK <= not MCLK after 44 ns;

end;