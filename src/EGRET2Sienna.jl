#######################################################
"""
Copyright 2021 Alliance for Sustainable Energy and other
NAERM Project Developers. See the top-level COPYRIGHT file for details.

Author: Surya Chandan Dhulipala & Clayton Barrows
Email: suryachandan.dhulipala@nlr.gov & Clayton.Barrows@nlr.gov
"""
# March 2026
# EGRET --> Sienna Linkage Module
# EGRET JSON --> EGRETData Intermediate Format --> Sienna PSY System
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
import HDF5
import UUIDs
const PSY = PowerSystems
#################################################################################
# Includes
#################################################################################
include("parsers/egret_json_parser.jl")
include("parsers/EGRETData.jl")
include("main/psy_system_builder.jl")
include("main/egret_to_psy.jl")
end
