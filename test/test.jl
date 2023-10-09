#####################################################
# Surya
# NREL
# October 2023
# NAERM UC/ED
# Testing of EGRET2Sienna module
#######################################################
# Loading the required packages
#######################################################
# Load EGRET2Sienna module here
#####################################################################################
# Read EGRET System JSON
#####################################################################################
DA_sys_location = joinpath(@__DIR__,"test", "DAY_AHEAD_Model_2020-07-01_2020-07-14.json");
RT_sys_location = joinpath(@__DIR__,"test", "REAL_TIME_Model_2020-07-01_2020-07-14.json");
#####################################################################################
# Convert EGRET JSON to CSV in a format SIIP Tabular Data understands
#####################################################################################
location, base_MVA,rt_flag = EGRET2Sienna.parse_egretjson(DA_sys_location,EGRET_json_RT_location=RT_sys_location);

if (rt_flag)
    sys_DA,sys_RT = EGRET2Sienna.parse_sienna_tabular_data(location,base_MVA,rt_flag,ts_pointers_file ="CSV");
else
    sys_DA = EGRET2Sienna.parse_sienna_tabular_data(location,base_MVA,rt_flag,ts_pointers_file="CSV");
end

#           (or)
sys_DA, sys_RT = EGRET2Sienna.egret_to_sienna(DA_sys_location,EGRET_json_RT_location=RT_sys_location,ts_pointers_file="CSV");
