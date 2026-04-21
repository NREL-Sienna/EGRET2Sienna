#####################################################################################
# NLR
# Struct to hold the data from EGRET in an intermediate format
#####################################################################################
mutable struct EGRETData
    # Metadata & Flags
    base_MVA::Float64
    rt_flag::Bool
    load_ts_flag::Bool
    gen_ts_flag::Bool

    # Infrastructure/Network (Assuming these are DataFrames or Dicts)
    buses::Any
    branches::Any
    generators::Any
    area_bus_mapping::Any
    zone_bus_mapping::Any

    # Day-Ahead (DA) Data
    system_DA::Any
    loads_DA::Any
    gen_elements_DA::Any
    areas_DA::Any
    timestamps_DA::Vector{Dates.DateTime}

    # Real-Time (RT) Data (Initialized as nothing, so we use Union)
    system_RT::Union{Nothing, Any}
    loads_RT::Union{Nothing, Any}
    gen_elements_RT::Union{Nothing, Any}
    areas_RT::Union{Nothing, Any}
    timestamps_RT::Union{Nothing, Vector{Dates.DateTime}}

    # Inner Constructor to set defaults
    function EGRETData(;
        base_MVA, rt_flag=false, load_ts_flag=false, gen_ts_flag=false,
        buses, branches, generators, area_bus_mapping, zone_bus_mapping,
        system_DA, loads_DA, gen_elements_DA, areas_DA, timestamps_DA,
        system_RT=nothing, loads_RT=nothing, gen_elements_RT=nothing,
        areas_RT=nothing, timestamps_RT=nothing # RT fields start as nothing
    )
        new(
            base_MVA, rt_flag, load_ts_flag, gen_ts_flag,
            buses, branches, generators, area_bus_mapping, zone_bus_mapping,
            system_DA, loads_DA, gen_elements_DA, areas_DA, timestamps_DA,
            system_RT, loads_RT, gen_elements_RT, areas_RT, timestamps_RT 
        )
    end
end
#####################################################################################
# Setters for SystemData
#####################################################################################
function update_rt_data!(data::EGRETData, sys, loads, gens, areas, ts)
    data.system_RT = sys
    data.loads_RT = loads
    data.gen_elements_RT = gens
    data.areas_RT = areas
    data.timestamps_RT = ts
    data.rt_flag = true  # Switch flag automatically when RT data is loaded
end

function set_base_mva!(data::EGRETData, val::Float64)
    data.base_MVA = val
end