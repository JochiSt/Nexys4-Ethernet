action = "simulation"

sim_tool = "ghdl"
sim_top = "tb_i2s"

sim_post_cmd = "ghdl -r tb_i2s --stop-time=6us --vcd=tb_i2s.vcd && gtkwave tb_i2s.vcd"

files =[
    "TB_I2S.vhdl",
]

modules = {
    "local" : [ "../../modules/I2S" ],
}

