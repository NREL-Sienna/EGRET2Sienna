#####################################################################################
# Top-level egret_to_sienna entry points.
# Parses EGRET JSON and directly constructs PSY.System objects.
#####################################################################################

function _maybe_serialize(sys::PSY.System, label::String,
                           export_location::Union{Nothing, String})
    isnothing(export_location) && return
    out_path = joinpath(export_location, label * "_system.json")
    mkpath(dirname(out_path))
    PSY.to_json(sys, out_path; force=true, runchecks=false)
    @info "Serialized $label system to $out_path"
end

function _build_systems(data; serialize::Bool=false,
                         export_location::Union{Nothing, String}=nothing)
    @info "Building DA PowerSystems.System..."
    sys_DA = build_psy_system(data; ts_label="DAY_AHEAD")

    if serialize
        _maybe_serialize(sys_DA, "DAY_AHEAD", export_location)
    end

    if data.rt_flag
        @info "Building RT PowerSystems.System..."
        sys_RT = build_psy_system(data; ts_label="REAL_TIME")
        if serialize
            _maybe_serialize(sys_RT, "REAL_TIME", export_location)
        end
        return sys_DA, sys_RT
    else
        return sys_DA
    end
end

#####################################################################################
# egret_to_sienna — DA only (String path)
#####################################################################################
function egret_to_sienna(EGRET_json_location::String;
                         export_location::Union{Nothing, String} = nothing,
                         serialize = false)
    data = parse_egretjson(EGRET_json_location)
    return _build_systems(data; serialize=serialize, export_location=export_location)
end

#####################################################################################
# egret_to_sienna — DA + RT (String paths)
#####################################################################################
function egret_to_sienna(EGRET_json_location::String, EGRET_json_RT_location::String;
                         export_location::Union{Nothing, String} = nothing,
                         serialize = false)
    data = parse_egretjson(EGRET_json_location, EGRET_json_RT_location)
    return _build_systems(data; serialize=serialize, export_location=export_location)
end

#####################################################################################
# egret_to_sienna — DA only (Dict)
#####################################################################################
function egret_to_sienna(EGRET_json_DA::DICT;
                         export_location::Union{Nothing, String} = nothing,
                         serialize = false) where {DICT <: AbstractDict}
    data = parse_egretjson(EGRET_json_DA)
    return _build_systems(data; serialize=serialize, export_location=export_location)
end

#####################################################################################
# egret_to_sienna — DA + RT (Dicts)
#####################################################################################
function egret_to_sienna(EGRET_json_DA::DICT, EGRET_json_RT::DICT;
                         export_location::Union{Nothing, String} = nothing,
                         serialize = false) where {DICT <: AbstractDict}
    data = parse_egretjson(EGRET_json_DA, EGRET_json_RT)
    return _build_systems(data; serialize=serialize, export_location=export_location)
end

#=
load_file = HDF5.h5open(reeds_load_location, "r");
load_data = read(load_file);
HDF5.close(load_file)
BigHornWindP_850838d3

import HDF5

# 1. Open the file once and keep it in a variable
fid = HDF5.h5open("raw_data.h5", "r")

# 2. You can pull handles to specific datasets
# Note: This is a pointer, NOT the data itself. It's very lightweight.
ds_measurements = fid["measurements"]
ds_timestamps = fid["timestamps"]

# 3. Create a function that uses the open handle
function get_chunk(dataset, start_idx, end_idx)
    # This reads only the requested slice from disk
    return dataset[:, start_idx:end_idx]
end

# 4. Fetch data multiple times without re-opening the file
chunk1 = get_chunk(ds_measurements, 1, 1000)
chunk2 = get_chunk(ds_measurements, 1001, 2000)

# 5. Close it when you are completely finished
close(fid)
=#