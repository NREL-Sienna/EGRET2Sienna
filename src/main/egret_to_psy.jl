#####################################################
# Surya
# NREL
# November 2021
# Main function for EGRET JSON --> CSV files formatted according to SIIP Tabular Data Parser Requirements --> SIIP PSY System
#####################################################################################
function EGRET_TO_PSY(EGRET_json::Dict{String, Any};EGRET_json_RT::Union{Nothing, Dict{String, Any}} = nothing,location::Union{Nothing, String} = nothing)
    location, base_MVA,rt_flag =
    if (EGRET_json_RT !== nothing)
        parse_EGRET_JSON(EGRET_json,EGRET_json_RT=EGRET_json_RT)
    else
        parse_EGRET_JSON(EGRET_json)
    end
   
    if (rt_flag)
        sys_DA,sys_RT = parse_tabular_data(location,base_MVA,rt_flag)
        return sys_DA,sys_RT
    else
        sys_DA = parse_tabular_data(location,base_MVA,rt_flag)
        return sys_DA
    end
end