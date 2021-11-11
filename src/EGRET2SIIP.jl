#######################################################
"""
Copyright 2021 Alliance for Sustainable Energy and other
NAERM Project Developers. See the top-level COPYRIGHT file for details.

Author: Surya Chandan Dhulipala
Email: suryachandan.dhulipala@nrel.gov
"""
# April 2021
# EGRET --> SIIP Linkage Module
# EGRET JSON --> CSV files formatted according to SIIP Tabular Data Parser Requirements --> SIIP PSY System
#######################################################
module EGRET2SIIP
#################################################################################
# Exports
#################################################################################
export parse_EGRET_JSON
#################################################################################
# Imports
#################################################################################
import JSON
import DataFrames
import CSV
import Dates
#################################################################################
# Includes
#################################################################################
include("parsers/egret_json_to_csv.jl")
end
