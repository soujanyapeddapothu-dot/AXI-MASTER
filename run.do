vlib work
vlog axi_master.v
vsim -novopt -suppress 12110 work.top +test_name=test_nwr_nrd
add wave -position insertpoint sim:/top/*
run -all

