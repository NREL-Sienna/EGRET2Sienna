#######################################################
"""
Copyright 2021 Alliance for Sustainable Energy and other
NAERM Project Developers. See the top-level COPYRIGHT file for details.

Author: Surya Chandan Dhulipala
Email: suryachandan.dhulipala@nrel.gov
"""
# November 2021
# EGRET --> SIIP Linkage Module
# EGRET JSON --> CSV files formatted according to SIIP Tabular Data Parser Requirements --> SIIP PSY System
#######################################################
module EGRET2Sienna
#################################################################################
# Exports
#################################################################################
export parse_EGRET_JSON
export parse_tabular_data
export EGRET_TO_PSY
#################################################################################
# Imports
#################################################################################
import JSON
import DataFrames
import CSV
import Dates
import PowerSystems
#################################################################################
# Includes
#################################################################################
include("parsers/egret_json_to_csv.jl")
include("main/parse_tabular_data.jl")
include("main/egret_to_psy.jl")
end
