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
Location_1 = dirname(pwd())*"/test/Day_Ahead_Model_2020-01-01.json"; 
EGRET_json = JSON.parsefile(Location_1);
#####################################################################################
# Convert EGRET JSON to CSV in a format SIIP Tabular Data understands
#####################################################################################
location = EGRET2SIIP.parse_EGRET_JSON(EGRET_json)
