target = "xilinx"
action = "synthesis"

syn_device = "xc7a100t"
syn_grade = "-1"
syn_package = "csg324"
syn_top = "Nexys4Ethernet"
syn_project = "Nexys4-Ethernet"
syn_tool = "vivado"

syn_properties = [
    #["steps.synth_design.args.more options", "-verbose"],
    ["steps.synth_design.args.retiming", "1"],
    ["steps.synth_design.args.assert", "1"],
    #["steps.opt_design.args.verbose", "1"],
    ["steps.opt_design.args.directive", "Explore"],
    ["steps.opt_design.is_enabled", "1"],
    ["steps.place_design.args.directive", "Explore"],
    #["steps.place_design.args.more options", "-verbose"],
    ["steps.phys_opt_design.args.directive", "AlternateFlowWithRetiming"],
    #["steps.phys_opt_design.args.more options", "-verbose"],
    ["steps.phys_opt_design.is_enabled", "1"],
    ["steps.route_design.args.directive", "Explore"],
    #["steps.route_design.args.more options", "-verbose"],
    ["steps.post_route_phys_opt_design.args.directive", "AddRetime"],
    #["steps.post_route_phys_opt_design.args.more options", "-verbose"],
    ["steps.post_route_phys_opt_design.is_enabled", "1"],
    ["steps.write_bitstream.args.verbose", "1"]]

files = [
    "../constraints/Nexys-4-Master.xdc",
]

modules = {
    "local" : [ "../top" ],
}