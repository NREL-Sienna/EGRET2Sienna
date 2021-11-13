#####################################################
# Surya
# NREL
# November 2021
# Main function for EGRET JSON --> CSV files formatted according to SIIP Tabular Data Parser Requirements --> SIIP PSY System
#####################################################################################
function EGRET_TO_PSY(EGRET_json::Dict{String, Any};location::Union{Nothing, String} = nothing)
    location, base_MVA = parse_EGRET_JSON(EGRET_json)
    sys = parse_tabular_data(location,base_MVA) 

    return sys
end