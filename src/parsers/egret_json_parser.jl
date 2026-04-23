#####################################################################################
# Surya / NLR — refactored by C. Barrows
# Parses EGRET JSON into structured Julia data for direct PSY system construction.
# Replaces egret_json_to_csv.jl — no CSV output.
#####################################################################################

#####################################################################################
# Fuel / unit-type string normalization dicts
#####################################################################################
fuel_mapping = Dict(
    "Coal"              => "Coal",
    "Hydro"             => "Hydro",
    "NG"                => "NG",
    "Nuclear"           => "Nuclear",
    "Oil"               => "Oil",
    "Solar"             => "Solar",
    "Wind"              => "Wind",
    "Sync_Cond"         => "Sync_Cond",
    "PrimarySource.HYDRO"   => "Hydro",
    "PrimarySource.COAL"    => "Coal",
    "PrimarySource.GAS"     => "NG",
    "PrimarySource.SOLAR"   => "Solar",
    "PrimarySource.NUCLEAR" => "Nuclear",
    "PrimarySource.OIL"     => "Oil",
    "PrimarySource.WIND"    => "Wind",
)

fuel_pm_mapping = Dict(
    "PrimarySource.HYDRO"   => "HYDRO",
    "PrimarySource.COAL"    => "STEAM",
    "PrimarySource.GAS"     => "CC",
    "PrimarySource.SOLAR"   => "PV",
    "PrimarySource.NUCLEAR" => "NUCLEAR",
    "PrimarySource.OIL"     => "CT",
    "PrimarySource.WIND"    => "WIND",
    "Coal"      => "STEAM",
    "Hydro"     => "HYDRO",
    "NG"        => "CC",
    "Nuclear"   => "NUCLEAR",
    "Oil"       => "CT",
    "Solar"     => "PV",
    "Wind"      => "WIND",
    "Sync_Cond" => "SYNC_COND",
)

#####################################################################################
# Utility helpers
#####################################################################################

# Resolve a generator bus field to a single bus name.
# Handles plain strings and distributed_bus dicts (picks highest participation factor).
function _resolve_bus(bus_field)
    if bus_field isa AbstractString
        return bus_field
    elseif bus_field isa AbstractDict
        values_dict = get(bus_field, "values", nothing)
        if values_dict isa AbstractDict && !isempty(values_dict)
            return string(argmax(Dict(k => Float64(v) for (k, v) in values_dict)))
        end
    end
    return nothing
end

# Resolve fuel string against a mapping dict with prefix-matching fallback.
# Caches new entries in the dict.
function _resolve_fuel!(mapping::Dict{String,String}, fuel::String, default::String)
    haskey(mapping, fuel) && return mapping[fuel]
    for sep in ('_', ' ')
        prefix = split(fuel, sep; limit=2)[1]
        if prefix != fuel && haskey(mapping, prefix)
            @info "Mapping unknown fuel \"$fuel\" → \"$(mapping[prefix])\" via prefix \"$prefix\"."
            mapping[fuel] = mapping[prefix]
            return mapping[fuel]
        end
    end
    @warn "Could not resolve fuel \"$fuel\"; using default \"$default\"."
    mapping[fuel] = default
    return default
end

# Return a scalar or max-of-time-series from a p_load/q_load field.
function _load_max(load_dict::AbstractDict, key::String)
    val = get(load_dict, key, nothing)
    if val isa Number
        return Float64(val)
    elseif val isa AbstractDict
        return maximum(Float64.(get(val, "values", [0.0])))
    else
        return 0.0
    end
end

# Return the time-series values vector from a p_load field.
# Scalar loads are broadcast to a constant vector of length n_timesteps.
function _load_ts_values(p_load_field, n_timesteps::Int)
    if p_load_field isa Number
        return fill(Float64(p_load_field), n_timesteps)
    elseif p_load_field isa AbstractDict
        return Float64.(get(p_load_field, "values", zeros(n_timesteps)))
    else
        return zeros(Float64, n_timesteps)
    end
end

isjson(path::String) = endswith(path, ".json") || endswith(path, ".json.gz")
json_parsing_kwargs = (allownan = true, ninf = "-Inf", inf = "Inf", nan = "NaN")

function parse_json_file(path::String)
    if endswith(path, ".json.gz")
        GZip.open(path, "r") do io
            JSON.parse(read(io);json_parsing_kwargs...)
        end
    else
        JSON.parsefile(path;json_parsing_kwargs...)
    end
end
#####################################################################################
# Extract timestamps from an EGRET system dict
#####################################################################################
function _parse_timestamps(system_dict::AbstractDict)
    date_format = Dates.DateFormat("Y-m-d H:M")
    try
        return Dates.DateTime.(system_dict["time_keys"], date_format)
    catch
        n = length(system_dict["time_keys"])
        @warn "System timestamps in EGRET JSON are not formatted correctly. Assuming default hourly timestamps."
        start = Dates.DateTime("2024-01-01", Dates.DateFormat("Y-m-d"))
        return collect(StepRange(start, Dates.Hour(1), start + Dates.Hour(n - 1)))
    end
end

#####################################################################################
# Parse EGRET Bus elements → Vector of NamedTuples + mapping dicts
#####################################################################################
function _parse_buses(components::DICT, loads::AbstractDict, elements::AbstractDict;
                      shunt::Union{Nothing, AbstractDict} = nothing) where {DICT <: AbstractDict}

    # Ensure every bus has an integer id
    if !all(haskey.(values(components), "id"))
        for (bus_key, bus) in components
            bus["id"] = parse(Int, filter(isdigit, bus_key))
        end
    end

    comp_names = collect(keys(components))

    # Build bus_type vector (may not be in JSON)
    if !haskey(first(values(components)), "matpower_bustype")
        gens_dict  = get(elements, "generator", Dict())
        loads_dict = get(elements, "load",      Dict())
        bus_types  = String[]
        for (i, bus_name) in enumerate(comp_names)
            load_idx = findfirst(get.(values(loads_dict), "bus", nothing) .== bus_name)
            gen_idx  = findfirst(get.(values(gens_dict),  "bus", nothing) .== bus_name)
            t = if i == 1
                "ref"
            elseif isnothing(load_idx) && isnothing(gen_idx)
                "PQ"
            else
                "PQ"
            end
            push!(bus_types, t)
        end
        for (bus_name, t) in zip(comp_names, bus_types)
            components[bus_name]["matpower_bustype"] = t
        end
    end

    # Map load bus → load record
    load_ts_flag = 0
    bus_mw_load  = Dict{String, Float64}()
    bus_mvar_load = Dict{String, Float64}()
    bus_load_ts  = Dict{String, AbstractDict}()  # bus_name => raw load dict (if time-series)
    q_available  = all(haskey.(values(loads), "q_load"))

    for bus_name in comp_names
        idx = findfirst(get.(values(loads), "bus", nothing) .== bus_name)
        if !isnothing(idx)
            load_rec = collect(values(loads))[idx]
            bus_mw_load[bus_name]  = _load_max(load_rec, "p_load")
            bus_mvar_load[bus_name] = q_available ? _load_max(load_rec, "q_load") : 0.0
            p_load_val = get(load_rec, "p_load", nothing)
            if p_load_val isa AbstractDict
                load_ts_flag += 1
                bus_load_ts[bus_name] = load_rec
            end
        else
            bus_mw_load[bus_name]  = 0.0
            bus_mvar_load[bus_name] = 0.0
        end
    end

    # Build per-bus named tuples
    buses = map(comp_names) do bus_name
        bus = components[bus_name]
        shunt_b = 0.0
        if shunt !== nothing && haskey(shunt, bus_name)
            shunt_b = Float64(get(shunt[bus_name], "bs", 0.0))
        end
        (
            number     = Int(get(bus, "id", 0)),
            name       = bus_name,
            bustype    = string(get(bus, "matpower_bustype", "PQ")),
            angle_deg  = Float64(get(bus, "va", 0.0)),
            magnitude  = Float64(get(bus, "vm", 1.0)),
            base_voltage = Float64(get(bus, "base_kv", 100.0)),
            area_name  = let a = get(bus, "area", nothing); isnothing(a) ? nothing : string(a) end,
            zone_name  = let z = get(bus, "zone", nothing); isnothing(z) ? nothing : string(z) end,
            mw_load    = bus_mw_load[bus_name],
            mvar_load  = bus_mvar_load[bus_name],
            shunt_b    = shunt_b,
            shunt_g    = 0.0,
            load_ts    = get(bus_load_ts, bus_name, nothing),  # raw load dict or nothing
        )
    end

    # Area → bus names mapping
    area_bus_mapping = Dict{String, Vector{String}}()
    for bus in buses
        area = something(bus.area_name, "None")
        push!(get!(area_bus_mapping, area, String[]), bus.name)
    end

    # Zone → bus names mapping
    zone_bus_mapping = Dict{String, Vector{String}}()
    for bus in buses
        zone = something(bus.zone_name, "None")
        push!(get!(zone_bus_mapping, zone, String[]), bus.name)
    end

    # Bus name → integer id
    bus_name_to_id = Dict{String, Int}(b.name => b.number for b in buses)

    @info "Successfully parsed buses in the JSON."
    return buses, bus_name_to_id, area_bus_mapping, zone_bus_mapping, load_ts_flag > 0
end

#####################################################################################
# Parse EGRET Branch elements → Vector of NamedTuples
#####################################################################################
function _parse_branches(components::DICT) where {DICT <: AbstractDict}
    branches = map(collect(pairs(components))) do (branch_name, branch)
        tap = get(branch, "transformer_tap_ratio", nothing)
        tap_val = (tap isa Number && tap != 0) ? Float64(tap) : 0.0
        (
            name         = branch_name,
            from_bus     = string(get(branch, "from_bus", "")),
            to_bus       = string(get(branch, "to_bus", "")),
            r            = Float64(get(branch, "resistance", 0.0)),
            x            = Float64(get(branch, "reactance", 0.001)),
            b            = Float64(get(branch, "charging_susceptance", 0.0)),
            rating_mva   = something(get(branch, "rating_long_term", nothing), 0.0) isa Number ?
                            Float64(something(get(branch, "rating_long_term", nothing), 0.0)) :
                            minimum(Float64.(something.(get(get(branch, "rating_long_term", Dict()), "values", [0.0]),0.0))),
            tap          = tap_val,
            angle_shift  = Float64(get(branch, "transformer_phase_shift", 0.0)),
            in_service   = Bool(get(branch, "in_service", true)),
        )
    end
    @info "Successfully parsed branches in the JSON."
    return branches
end

#####################################################################################
# Parse heat-rate / fuel-cost curve from an EGRET generator component
# Returns Vector of (x_mw, y_mmbtu_per_hr) named tuples, or empty if not available.
#####################################################################################
function _parse_heat_rate_points(comp_fields::AbstractDict, p_max_mw::Float64)
    fuel_dict_key = haskey(comp_fields, "p_fuel") ? "p_fuel" :
                    haskey(comp_fields, "p_cost") ? "p_cost" : nothing
    isnothing(fuel_dict_key) && return NamedTuple{(:x, :y), Tuple{Float64, Float64}}[]

    fuel_dict = get(comp_fields, fuel_dict_key, nothing)
    (isnothing(fuel_dict) || fuel_dict == "None") && return NamedTuple{(:x, :y), Tuple{Float64, Float64}}[]

    raw_vals = get(fuel_dict, "values", nothing)
    isnothing(raw_vals) && return NamedTuple{(:x, :y), Tuple{Float64, Float64}}[]

    points = NamedTuple{(:x, :y), Tuple{Float64, Float64}}[]
    for v in raw_vals
        x = Float64(v[1])
        y = Float64(v[2])
        isfinite(x) && isfinite(y) && push!(points, (x=x, y=y))
    end
    return points
end

#####################################################################################
# Parse EGRET startup fuel/cost data
# Returns (cold_heat, warm_heat, hot_heat) in MMBTU, and (cold_time, warm_time, hot_time) in hr.
#####################################################################################
function _parse_startup(comp_fields::AbstractDict)
    key = haskey(comp_fields, "startup_fuel") ? "startup_fuel" :
          haskey(comp_fields, "startup_cost") ? "startup_cost" : nothing
    zero_val = (cold_heat=0.0, warm_heat=0.0, hot_heat=0.0,
                cold_time=0.0, warm_time=0.0, hot_time=0.0)
    isnothing(key) && return zero_val

    sd = get(comp_fields, key, nothing)
    (isnothing(sd) || sd == "None") && return zero_val

    # lookup_dict: 1=cold, 2=warm, 3=hot
    function _safe_get(arr, i, j)
        try; Float64(arr[i][j]); catch; 0.0; end
    end

    return (
        cold_time = _safe_get(sd, 1, 1),
        cold_heat = _safe_get(sd, 1, 2),
        warm_time = _safe_get(sd, 2, 1),
        warm_heat = _safe_get(sd, 2, 2),
        hot_time  = _safe_get(sd, 3, 1),
        hot_heat  = _safe_get(sd, 3, 2),
    )
end

#####################################################################################
# Parse EGRET Generator elements → Vector of NamedTuples
#####################################################################################
function _parse_generators(components::DICT, bus_name_to_id::Dict,
                            area_bus_mapping::Dict, zone_bus_mapping::Dict,
                            base_MVA::Float64) where {DICT <: AbstractDict}

    # ── Ensure unit_type is present ──────────────────────────────────────────────
    if !all(haskey.(values(components), "unit_type"))
        for (comp_name, comp_fields) in components
            fuel = get(comp_fields, "fuel", nothing)
            if fuel !== nothing
                comp_fields["unit_type"] = _resolve_fuel!(fuel_pm_mapping, string(fuel), "THERMAL")
            end
        end
    end

    # ── Normalize fuel / unit_type strings ───────────────────────────────────────
    for (comp_name, comp_fields) in components
        fuel = get(comp_fields, "fuel", nothing)
        if fuel !== nothing
            comp_fields["fuel"] = _resolve_fuel!(fuel_mapping, string(fuel), string(fuel))
        end
        if !haskey(comp_fields, "unit_type")
            raw_fuel = string(get(comp_fields, "fuel", "THERMAL"))
            comp_fields["unit_type"] = _resolve_fuel!(fuel_pm_mapping, raw_fuel, "THERMAL")
        end
    end

    gen_ts_flag = false

    generators = map(collect(pairs(components))) do (gen_name, comp_fields)
        @show gen_name
        # ── p_max / p_min ────────────────────────────────────────────────────────
        p_max_raw = get(comp_fields, "p_max", 0.0)
        if p_max_raw isa AbstractDict
            p_max_vals = Float64.(get(p_max_raw, "values", [0.0]))
            p_max_mw   = maximum(p_max_vals)
            p_max_ts   = p_max_raw  # keep raw for time series attachment
            gen_ts_flag = true
        else
            p_max_mw = Float64(p_max_raw)
            p_max_ts = nothing
        end

        p_min_raw = get(comp_fields, "p_min", 0.0)
        if p_min_raw isa AbstractDict
            p_min_mw = maximum(Float64.(get(p_min_raw, "values", [0.0])))
        else
            p_min_mw = Float64(p_min_raw)
        end

        # ── bus, area, zone ──────────────────────────────────────────────────────
        bus_raw  = get(comp_fields, "bus", nothing)
        bus_name = _resolve_bus(bus_raw)

        area_name = let a = get(comp_fields, "area", nothing)
            if !isnothing(a)
                string(a)
            else
                # Look up from bus → area mapping
                found = nothing
                if !isnothing(bus_name)
                    for (area, buses) in area_bus_mapping
                        if bus_name in buses; found = area; break; end
                    end
                end
                found
            end
        end

        zone_name = let z = get(comp_fields, "zone", nothing)
            if !isnothing(z)
                string(z)
            else
                found = nothing
                if !isnothing(bus_name)
                    for (zone, buses) in zone_bus_mapping
                        if bus_name in buses; found = zone; break; end
                    end
                end
                found
            end
        end

        # ── startup / shutdown ───────────────────────────────────────────────────
        su_data = _parse_startup(comp_fields)

        # ── heat rate curve ──────────────────────────────────────────────────────
        hr_points = _parse_heat_rate_points(comp_fields, p_max_mw)

        fuel_cost = Float64(get(comp_fields, "fuel_cost", 0.0))

        (
            name             = gen_name,
            bus_name         = bus_name,
            fuel             = string(get(comp_fields, "fuel", "OTHER")),
            fuel_code        = string(get(comp_fields, "fuel_code", "")),
            unit_type        = string(get(comp_fields, "unit_type", "THERMAL")),
            model_type       = string(get(comp_fields, "model_type", "")),
            p_max_mw         = p_max_mw,
            p_min_mw         = p_min_mw,
            p_max_ts         = p_max_ts,   # raw EGRET dict if time-varying, else nothing
            ramp_up_mw_per_hr   = Float64(get(comp_fields, "ramp_up_60min",   get(comp_fields, "ramp_agc", p_max_mw))),
            ramp_down_mw_per_hr = Float64(get(comp_fields, "ramp_down_60min", get(comp_fields, "ramp_agc", p_max_mw))),
            min_up_time_h    = Float64(get(comp_fields, "min_up_time",   0.0)),
            min_down_time_h  = Float64(get(comp_fields, "min_down_time", 0.0)),
            startup_cold_heat_mmbtu = su_data.cold_heat,
            startup_warm_heat_mmbtu = su_data.warm_heat,
            startup_hot_heat_mmbtu  = su_data.hot_heat,
            startup_cold_time_h     = su_data.cold_time,
            startup_warm_time_h     = su_data.warm_time,
            startup_hot_time_h      = su_data.hot_time,
            non_fuel_startup_cost   = Float64(get(comp_fields, "non_fuel_startup_cost", 0.0)),
            shutdown_cost    = Float64(get(comp_fields, "shutdown_cost", 0.0)),
            fuel_cost_per_mmbtu = fuel_cost,
            heat_rate_io     = hr_points,  # Vector of (x=MW, y=MMBTU/hr)
            mbase_mva        = Float64(get(comp_fields, "mbase", base_MVA)),
            pg_mw            = Float64(get(comp_fields, "pg", 0.0)),
            qg_mvar          = Float64(get(comp_fields, "qg", 0.0)),
            initial_status   = Bool(abs(get(comp_fields, "initial_status", 0)) > 0),
            in_service        = Bool(get(comp_fields, "in_service", true)),
            area_name        = area_name,
            zone_name        = zone_name,
            generator_type   = string(get(comp_fields, "generator_type", get(comp_fields, "unit_type", "thermal"))),
        )
    end

    @info "Successfully parsed generators in the JSON."
    return generators, gen_ts_flag
end

#####################################################################################
# Select the areas argument for time_series_processing
#####################################################################################
_areas_da(EGRET_json_DA::AbstractDict, area_bus_mapping::AbstractDict) =
    haskey(EGRET_json_DA["elements"], "area") ?
    EGRET_json_DA["elements"]["area"] :
    sort(string.(collect(keys(area_bus_mapping))))

#####################################################################################
# parse_egretjson — DA only (Dict)
#####################################################################################
function parse_egretjson(EGRET_json_DA::DICT;
                         export_location::Union{Nothing, String} = nothing) where {DICT <: AbstractDict}
    if !haskey(EGRET_json_DA, "elements") || !haskey(EGRET_json_DA, "system")
        error("Please check the EGRET DA System JSON — missing 'elements' or 'system' key.")
    end

    if !haskey(EGRET_json_DA["system"], "uuid")
        @warn "System doesn't have a UUID assigned. Assigning a random UUID for export purposes. Consider adding a persistent UUID to your EGRET system JSON."
        EGRET_json_DA["system"]["uuid"] = string(UUIDs.uuid4())
    end

    elements = EGRET_json_DA["elements"]
    base_MVA = Float64(EGRET_json_DA["system"]["baseMVA"])

    @info "Parsing buses in EGRET JSON..."
    shunt = get(elements, "shunt", nothing)
    buses, bus_to_id, area_bus_mapping, zone_bus_mapping, load_ts_flag =
        _parse_buses(elements["bus"], elements["load"], elements; shunt = shunt)

    @info "Parsing branches in EGRET JSON..."
    branches = _parse_branches(elements["branch"])

    @info "Parsing generators in EGRET JSON..."
    generators, gen_ts_flag = _parse_generators(
        elements["generator"], bus_to_id, area_bus_mapping, zone_bus_mapping, base_MVA)

    timestamps_DA = _parse_timestamps(EGRET_json_DA["system"])
    areas_DA      = _areas_da(EGRET_json_DA, area_bus_mapping)

    return EGRETData(
        base_MVA         = base_MVA,
        rt_flag          = false,
        buses            = buses,
        branches         = branches,
        generators       = generators,
        area_bus_mapping = area_bus_mapping,
        zone_bus_mapping = zone_bus_mapping,
        system_DA        = EGRET_json_DA["system"],
        loads_DA         = elements["load"],
        gen_elements_DA  = elements["generator"],
        areas_DA         = areas_DA,
        timestamps_DA    = timestamps_DA,
        system_RT        = nothing,
        loads_RT         = nothing,
        gen_elements_RT  = nothing,
        areas_RT         = nothing,
        timestamps_RT    = nothing,
        load_ts_flag     = load_ts_flag,
        gen_ts_flag      = gen_ts_flag,
    )
end

#####################################################################################
# parse_egretjson — DA + RT (Dict)
#####################################################################################
function parse_egretjson(EGRET_json_DA::DICT, EGRET_json_RT::DICT;
                         export_location::Union{Nothing, String} = nothing) where {DICT <: AbstractDict}
    if !haskey(EGRET_json_RT, "elements") || !haskey(EGRET_json_RT, "system")
        error("Please check the EGRET RT System JSON — missing 'elements' or 'system' key.")
    end

    data = parse_egretjson(EGRET_json_DA; export_location = export_location)
    timestamps_RT = _parse_timestamps(EGRET_json_RT["system"])
    rt_elements   = EGRET_json_RT["elements"]

    return update_rt_data!(data, system_RT, loads_RT, gen_elements_RT, areas_RT, timestamps_RT)
    
end

#####################################################################################
# parse_egretjson — DA only (String path)
#####################################################################################
function parse_egretjson(EGRET_json_DA_location::String;
                         export_location::Union{Nothing, String} = nothing)
    if !isjson(EGRET_json_DA_location)
        error("DA System file must be a .json or .json.gz file: $EGRET_json_DA_location")
    end
   
    base_name = first(split(basename(EGRET_json_DA_location), "."))
    h5_path = joinpath(dirname(EGRET_json_DA_location), "$(base_name)_time_series.h5")

    if isfile(h5_path)
        @info "Found associated HDF5 time series file: $h5_path. Parsing available time series data from HDF5."
        fid, ds_ts, ds_uid, ds_values = parse_h5_timeseries(h5_path)
        h5_flag = true
    else
        # Set your defaults
        h5_flag = false
        fid = nothing
        ds_ts = nothing
        ds_uid = nothing
        ds_values = nothing
    end
    
    parse_egretjson(parse_json_file(EGRET_json_DA_location); export_location = export_location)

    if h5_flag
        close(fid)
    end
end

#####################################################################################
# parse_egretjson — DA + RT (String paths)
#####################################################################################
function parse_egretjson(EGRET_json_DA_location::String, EGRET_json_RT_location::String;
                         export_location::Union{Nothing, String} = nothing)
    if !isjson(EGRET_json_DA_location)
        error("DA System file must be a .json or .json.gz file: $EGRET_json_DA_location")
    end
    if !isjson(EGRET_json_RT_location)
        error("RT System file must be a .json or .json.gz file: $EGRET_json_RT_location")
    end
    parse_egretjson(
        parse_json_file(EGRET_json_DA_location),
        parse_json_file(EGRET_json_RT_location);
        export_location = export_location,
    )
end

#####################################################################################
# Parse h5 file and function to get chunks of data from the h5 file
#####################################################################################
function parse_h5_timeseries(path::String)
    fid = HDF5.h5open(path, "r")

    ds_ts = fid["timestamp"]
    ds_uid = fid["uid"]
    ds_values = fid["values"]

    return fid, ds_ts, ds_uid, ds_values

    close(fid)
end

function get_chunk(ds_uid, ds_values, ts_uid)
    asset_idx = findfirst(fid["uid"][:] .== ts_uid)
    return ds_values[asset_idx, :]
end