#####################################################
# Surya
# NREL
# November 2021
# NAERM Threats
# Testing of EGRET2SIIP module
#######################################################
# Loading the required packages
#######################################################
# Load EGRET2SIIP module here
#####################################################################################
# Read EGRET System JSON
#####################################################################################
import JSON
Location_1 = dirname(pwd())*"/test/DAY_AHEAD_Model_2020-07-01_2020-07-14.json"; 
Location_2 = dirname(pwd())*"/test/REAL_TIME_Model_2020-07-01_2020-07-14.json";
EGRET_json_DA = JSON.parsefile(Location_1);
EGRET_json_RT = JSON.parsefile(Location_2);
#####################################################################################
# Convert EGRET JSON to CSV in a format SIIP Tabular Data understands
#####################################################################################
location, base_MVA,rt_flag = EGRET2SIIP.parse_EGRET_JSON(EGRET_json_DA,EGRET_json_RT=EGRET_json_RT);

if (rt_flag)
    sys_DA,sys_RT = EGRET2SIIP.parse_tabular_data(location,base_MVA,rt_flag);
else
    sys_DA = EGRET2SIIP.parse_tabular_data(location,base_MVA,rt_flag);
end

#           (or)
sys_DA, sys_RT = EGRET2SIIP.EGRET_TO_PSY(EGRET_json,EGRET_json_RT=EGRET_json_RT)
