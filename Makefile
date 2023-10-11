
PROJECTNAME=Nexys4Ethernet
TOP_MODULE=top

DEVICE=xc7a100tcsg324-1

# location of the precompiles unisim files
UNISIM_DIR=/home/jochen/ghdl_simulations/xilinx-ise/

# PATH to nextpnr-xilinx
NEXTPNR_XILINX=$(shell which nextpnr-xilinx)
NEXTPNR_XILINX_PATH=$(dir $(NEXTPNR_XILINX))

###############################################################################
# GHDL options
GHDL_OPTIONS+=--std=93
GHDL_OPTIONS+=--workdir=work
GHDL_OPTIONS+=-fsynopsys -fexplicit 
GHDL_OPTIONS+=--syn-binding
#GHDL_OPTIONS+=--latches
GHDL_OPTIONS+=-P$(UNISIM_DIR)

###############################################################################
# source files
SRCFILES+=src/top.vhdl

###############################################################################
# get .o from .vdh and .vdhl
OBJFILES=$(SRCFILES:.vhd=.o)
OBJFILES+=$(SRCFILES:.vhdl=.o)


CONSTRAINT=constraints/Nexys-4-Master.xdc

###############################################################################

.PHONY: all prog clean total_clean postsim sim

.SECONDARY: $(PROJECTNAME).bin #$(PROJECT)_tb $(PROJECT)_tb.vcd

all: $(PROJECTNAME).rpt $(PROJECTNAME).bin

# Program FPGA
prog: $(PROJECTNAME).bin
	iceprog $<

###############################################################################
# CLEANING
clean:
	rm -f *.o *.cf

total_clean: clean
	rm -f $(PROJECTNAME).{asc,bin,rpt,json}
	rm -f *.vcd *.fst

###############################################################################
# Synthesis
$(PROJECTNAME).json: $(OBJFILES) unisim-obj93.cf
	yosys -Q -T -qq -L $(PROJECTNAME)_synth.log -m ghdl \
		-p 'ghdl $(GHDL_OPTIONS) $(TOP_MODULE)' \
		-p 'synth_xilinx -flatten -abc9 -arch xc7  -top $(TOP_MODULE)' \
		-p 'write_json $@'

# Place and Route
$(PROJECTNAME)_routed.json: $(PROJECTNAME).json $(CONSTRAINT) $(DEVICE).bin
	nextpnr-xilinx --xdc $(CONSTRAINT) --json $< --top $(TOP_MODULE) --fasm $(PROJECTNAME).fasm --chipdb $(DEVICE).bin

#yosys -p "synth_xilinx -flatten -abc9 -nobram -arch xc7 -top top; write_json blinky.json" blinky.v
#../../../nextpnr-xilinx --chipdb ../../xc7a35t.bin --xdc arty.xdc --json blinky.json --write blinky_routed.json --fasm blinky.fasm

#source "${XRAY_DIR}/utils/environment.sh"

#${XRAY_UTILS_DIR}/fasm2frames.py --part xc7a35tcsg324-1 --db-root ${XRAY_UTILS_DIR}/../database/artix7 blinky.fasm > blinky.frames
#${XRAY_TOOLS_DIR}/xc7frames2bit --part_file ${XRAY_UTILS_DIR}/../database/artix7/xc7a35tcsg324-1/part.yaml --part_name xc7a35tcsg324-1  --frm_file blinky.frames --output_file blinky.bit


$(PROJECTNAME).bin: $(PROJECTNAME).asc
	icepack $< $@

$(PROJECTNAME).rpt: $(PROJECTNAME).asc
	icetime -d up5k -c 12 -mtr $@ $<

###############################################################################

sim: $(PROJECTNAME)_tb.vcd

simview: $(PROJECTNAME)_tb.vcd
	# alternative:
	# gtkwave --optimize $<
	gtkwave -g $<

#%_tb: %_tb.v %.v
#	iverilog -o $@ $^
#
#%_tb.vcd: %_tb
#	vvp -N $< +vcd=$@

%_tb.cpp: $(OBJECT_FILES)
	yosys -m ghdl -p " \
			ghdl $(GHDL_OPTIONS) $(TOP_MODULE); \
			hierarchy -check -top PLLtest; \
			write_cxxrtl -header $@"
	sed -i '1s/^/#include <iostream>\n/' $@

%_tb: %_tb.cpp %_tb_main.cpp
	clang++ -g -O3 -I`yosys-config --datdir`/include -std=c++14 $^ -o $@

%_tb.vcd: %_tb
	./$< $@

# POST synthesis simulation
# inspired and adapted
# 		from https://github.com/YosysHQ/icestorm/blob/master/examples/icestick/
postsim: $(PROJECTNAME)_syntb.vcd

# create VERILOG file from synthesized JSON design file
%_syn.v: %.json
	yosys -p 'read_json $^; write_verilog $@'
# create syntb using iverilog
%_syntb: %_tb.v %_syn.v
	iverilog -g2012 -o $@ $^ `yosys-config --datdir/ice40/cells_sim.v`
# simulate the design
%_syntb.vcd: %_syntb
	vvp -v -n $< +vcd=$@

###############################################################################
# 'compile' VHDL files
%.o: %.vhdl
	ghdl -a $(GHDL_OPTIONS) $<

%.o: %.vhd
	ghdl -a $(GHDL_OPTIONS) $<

##############################################################################
# Xilinx UNISIM
unisim-obj93.cf:
	ghdl -a --work=unisim /opt/Xilinx/13.2/ISE_DS/ISE/vhdl/src/unisims/unisim_VCOMP.vhd


#############################################################################
# 
#.PHONY: $(DEVICE).bba
$(DEVICE).bin: $(DEVICE).bba
	$(NEXTPNR_XILINX_PATH)/bba/bbasm --l $< $@

$(DEVICE).bba:
	python3 $(NEXTPNR_XILINX_PATH)/xilinx/python/bbaexport.py --device $(DEVICE) --bba $@

