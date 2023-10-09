#####################################################
# Surya
# NREL
# October 2023
# Main function for EGRET JSON --> CSV files formatted according to Sienna Tabular Data Parser Requirements --> Sienna PSY System
#####################################################################################
function egret_to_sienna(EGRET_json_location::String;EGRET_json_RT_location::Union{Nothing, String} = nothing,
                         export_location::Union{Nothing, String} = nothing,ts_pointers_file::Union{Nothing, String} = nothing, serialize = false)

    if (ts_pointers_file === nothing)
    @warn "Time series pointers file type wasn't passed. Using timeseries_pointers.csv"
    ts_pointers_file = "CSV"
    end

    location, base_MVA,rt_flag =
    if (EGRET_json_RT_location !== nothing)
        parse_egretjson(EGRET_json_location,EGRET_json_RT_location=EGRET_json_RT_location, export_location = export_location)
    else
        parse_egretjson(EGRET_json_location, export_location = export_location)
    end

    if (rt_flag)
        sys_DA,sys_RT = parse_sienna_tabular_data(location,base_MVA,rt_flag,ts_pointers_file=ts_pointers_file, serialize = serialize)
        return sys_DA,sys_RT
    else
        sys_DA = parse_sienna_tabular_data(location,base_MVA,rt_flag,ts_pointers_file=ts_pointers_file, serialize = serialize)
        return sys_DA
    end
end