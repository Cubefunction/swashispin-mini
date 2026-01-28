create_project pl ./pl -part xc7a35tftg256-1 -force

set_property include_dirs {../include} [get_filesets sources_1]
add_files [glob ../include/*.svh]
add_files [glob ../src/*.sv]
add_files [glob ../lib/*.sv]
add_files [glob ./*.sv]
add_files [glob ./*.xdc]
remove_files  ../lib/ad5541a.sv
remove_files  ../lib/ad5791.sv
update_compile_order -fileset sources_1

