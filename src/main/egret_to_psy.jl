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
