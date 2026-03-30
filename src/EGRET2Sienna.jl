#######################################################
"""
Copyright 2021 Alliance for Sustainable Energy and other
NAERM Project Developers. See the top-level COPYRIGHT file for details.

Author: Surya Chandan Dhulipala
Email: suryachandan.dhulipala@nrel.gov
"""
# October 2023
# EGRET --> Sienna Linkage Module
# EGRET JSON --> CSV files formatted according to Sienna Tabular Data Parser Requirements --> Sienna PSY System
#######################################################
module EGRET2Sienna
#################################################################################
# Exports
#################################################################################
export parse_egretjson
export egret_to_sienna
#################################################################################
# Imports
#################################################################################
import GZip
import JSON
import Dates
import TimeSeries
import PowerSystems
const PSY = PowerSystems
#################################################################################
# Includes
#################################################################################
include("parsers/egret_json_parser.jl")
include("main/psy_system_builder.jl")
include("main/egret_to_psy.jl")
end
