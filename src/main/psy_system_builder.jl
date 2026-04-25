#####################################################################################
# Direct PSY system construction from parsed EGRET data.
# Replaces the CSV → PSY.PowerSystemTableData → PSY.System pipeline.
#####################################################################################

import TimeSeries

#####################################################################################
# PSY enum mappings
#####################################################################################

const _FUEL_TO_PSY = Dict{String, PSY.ThermalFuels}(
    "Coal"      => PSY.ThermalFuels.COAL,
    "NG"        => PSY.ThermalFuels.NATURAL_GAS,
    "Nuclear"   => PSY.ThermalFuels.NUCLEAR,
    "Oil"       => PSY.ThermalFuels.DISTILLATE_FUEL_OIL,
    "Sync_Cond" => PSY.ThermalFuels.OTHER,
    "Hydro"     => PSY.ThermalFuels.OTHER,
    "Solar"     => PSY.ThermalFuels.OTHER,
    "Wind"      => PSY.ThermalFuels.OTHER,
    "OTHER"     => PSY.ThermalFuels.OTHER,
)

const _UNIT_TYPE_TO_PRIME_MOVER = Dict{String, PSY.PrimeMovers}(
    "CC"       => PSY.PrimeMovers.CC,
    "CT"       => PSY.PrimeMovers.CT,
    "STEAM"    => PSY.PrimeMovers.ST,
    "NUCLEAR"  => PSY.PrimeMovers.ST,
    "HYDRO"    => PSY.PrimeMovers.HY,
    "ROR"      => PSY.PrimeMovers.HY,
    "PV"       => PSY.PrimeMovers.PVe,
    "RTPV"     => PSY.PrimeMovers.PVe,
    "WIND"     => PSY.PrimeMovers.WT,
    "SYNC_COND"=> PSY.PrimeMovers.OT,
    "THERMAL"  => PSY.PrimeMovers.ST,
    "OT"       => PSY.PrimeMovers.OT,
)

const _BUSTYPE_MAP = Dict{String, PSY.ACBusTypes}(
    "PQ"       => PSY.ACBusTypes.PQ,
    "PV"       => PSY.ACBusTypes.PV,
    "ref"      => PSY.ACBusTypes.REF,
    "isolated" => PSY.ACBusTypes.ISOLATED,
    "SLACK"    => PSY.ACBusTypes.SLACK,
)

#####################################################################################
# Determine PSY generator type from fuel / fuel_code / unit_type / model_type / generator_type
#####################################################################################
function _gen_psy_type(gen)::String
    fu = uppercase(gen.fuel)
    fc = uppercase(gen.fuel_code)
    ut = uppercase(gen.unit_type)
    mt = uppercase(gen.model_type)
    gt = lowercase(gen.generator_type)

    if gen.p_max_mw < 0
        return "HydroPumpedStorage"
    elseif fu == "HYDRO" || fc == "HYDRO" || ut in ("HYDRO", "ROR") || mt in ("HYDRO", "ROR", "HY")
        return "HydroDispatch"
    elseif fu in ("SOLAR", "WIND") || fc in ("SOLAR", "WIND") ||
           ut in ("PV", "RTPV", "WIND", "SOLAR") ||
           mt in ("PV", "RTPV", "WT", "PVF", "PVE") ||
           gt in ("renewable", "solar", "wind", "pv")
        return mt == "RTPV" || ut == "RTPV" ? "RenewableNonDispatch" : "RenewableDispatch"
    elseif fu == "STORAGE" || mt in ("STORAGE", "BATTERY")
        return "EnergyReservoirStorage"
    else
        return "ThermalStandard"
    end
end

const _MODEL_TYPE_TO_PRIME_MOVER = Dict{String, PSY.PrimeMovers}(
    "WT"   => PSY.PrimeMovers.WT,
    "PV"   => PSY.PrimeMovers.PVe,
    "PVE"  => PSY.PrimeMovers.PVe,
    "PVF"  => PSY.PrimeMovers.PVe,
    "RTPV" => PSY.PrimeMovers.PVe,
    "HYDRO" => PSY.PrimeMovers.HY,
    "ROR"   => PSY.PrimeMovers.HY,
    "PS"    => PSY.PrimeMovers.PS,
)

# Infer prime mover using model_type first, then unit_type, then name heuristics.
function _infer_prime_mover(gen)::PSY.PrimeMovers
    mt = uppercase(gen.model_type)
    haskey(_MODEL_TYPE_TO_PRIME_MOVER, mt) && return _MODEL_TYPE_TO_PRIME_MOVER[mt]
    ut = uppercase(gen.unit_type)
    haskey(_UNIT_TYPE_TO_PRIME_MOVER, ut) && return _UNIT_TYPE_TO_PRIME_MOVER[ut]
    fc = titlecase(gen.fuel_code)
    haskey(_UNIT_TYPE_TO_PRIME_MOVER, uppercase(fc)) && return _UNIT_TYPE_TO_PRIME_MOVER[uppercase(fc)]
    # Name-based fallback for renewables with generic metadata
    name_up = uppercase(gen.name)
    bus_up  = uppercase(something(gen.bus_name, ""))
    if occursin("WIND", name_up) || occursin("WIND", bus_up)
        return PSY.PrimeMovers.WT
    elseif occursin("PV", name_up) || occursin("SOLAR", name_up) ||
           occursin("PV", bus_up) || occursin("SOLAR", bus_up)
        return PSY.PrimeMovers.PVe
    end
    return PSY.PrimeMovers.OT
end

#####################################################################################
# Build ThermalGenerationCost from generator named tuple
#####################################################################################
function _build_thermal_cost(gen)
    fc = gen.fuel_cost_per_mmbtu

    # Build heat rate InputOutputCurve (MW → MMBTU/hr)
    variable_cost = if length(gen.heat_rate_io) >= 2
        pts = [PSY.IS.PiecewiseLinearData([(x=p.x, y=p.y) for p in gen.heat_rate_io])]
        curve = PSY.IS.InputOutputCurve(PSY.IS.PiecewiseLinearData([(x=p.x, y=p.y) for p in gen.heat_rate_io]))
        PSY.FuelCurve(curve, fc)
    elseif length(gen.heat_rate_io) == 1
        # Single point — use linear through origin
        slope = gen.heat_rate_io[1].y / max(gen.heat_rate_io[1].x, 1.0)
        PSY.FuelCurve(PSY.IS.InputOutputCurve(PSY.IS.LinearFunctionData(slope, 0.0)), fc)
    else
        # No heat rate data — zero cost
        PSY.FuelCurve(PSY.IS.InputOutputCurve(PSY.IS.LinearFunctionData(0.0, 0.0)), fc)
    end

    # Startup cost
    nfc = gen.non_fuel_startup_cost
    start_up = if gen.startup_hot_heat_mmbtu > 0 || gen.startup_warm_heat_mmbtu > 0 || gen.startup_cold_heat_mmbtu > 0
        (
            hot  = fc * gen.startup_hot_heat_mmbtu  + nfc,
            warm = fc * gen.startup_warm_heat_mmbtu + nfc,
            cold = fc * gen.startup_cold_heat_mmbtu + nfc,
        )
    else
        nfc
    end

    return PSY.ThermalGenerationCost(
        variable  = variable_cost,
        fixed     = 0.0,
        start_up  = start_up,
        shut_down = gen.shutdown_cost,
    )
end

#####################################################################################
# Build Areas and LoadZones (must be added before buses)
#####################################################################################
function _build_areas_zones!(sys::PSY.System, buses)
    area_names = unique(filter(!isnothing, [b.area_name for b in buses]))
    zone_names = unique(filter(!isnothing, [b.zone_name for b in buses]))

    for name in area_names
        if isnothing(PSY.get_component(PSY.Area, sys, name))
            PSY.add_component!(sys, PSY.Area(name))
        end
    end
    for name in zone_names
        if isnothing(PSY.get_component(PSY.LoadZone, sys, name))
            PSY.add_component!(sys, PSY.LoadZone(name, 0.0, 0.0))
        end
    end
end

#####################################################################################
# Build ACBus + PowerLoad components
#####################################################################################
function _build_buses!(sys::PSY.System, buses, base_MVA::Float64)
    for bus in buses
        area_obj = isnothing(bus.area_name) ? nothing :
                   PSY.get_component(PSY.Area, sys, bus.area_name)
        zone_obj = isnothing(bus.zone_name) ? nothing :
                   PSY.get_component(PSY.LoadZone, sys, bus.zone_name)
        bustype  = get(_BUSTYPE_MAP, bus.bustype, PSY.ACBusTypes.PQ)

        psy_bus = PSY.ACBus(
            bus.number,
            bus.name,
            true,
            bustype,
            bus.angle_deg * π / 180.0,
            bus.magnitude,
            (min=0.9, max=1.1),
            bus.base_voltage,
            area_obj,
            zone_obj,
        )
        PSY.add_component!(sys, psy_bus)

        # Add PowerLoad if bus has static load
        if !isempty(bus.load_ids)
            for id in bus.load_ids
                load = PSY.PowerLoad(
                "Load_" * bus.name * "_" * string(id),
                true,
                psy_bus,
                maximum(bus.load_ts[id])   / base_MVA,
                bus.mvar_load / base_MVA, # TODO: Need to fix this to get Q for corresponding load, not an issue for now
                base_MVA,
                maximum(bus.load_ts[id])   / base_MVA,
                bus.mvar_load / base_MVA, # TODO: Need to fix this to get Q for corresponding load, not an issue for now
                )
                PSY.add_component!(sys, load)
            end
        end
    end
end

#####################################################################################
# Build Line / Transformer2W branches
#####################################################################################
function _build_branches!(sys::PSY.System, branches, base_MVA::Float64)
    for br in branches
        br.in_service || continue

        @debug "Parsing branch \"$(br.name)\":",  br
        from_bus = PSY.get_component(PSY.ACBus, sys, br.from_bus)
        to_bus   = PSY.get_component(PSY.ACBus, sys, br.to_bus)
        if isnothing(from_bus) || isnothing(to_bus)
            @warn "Branch \"$(br.name)\": bus not found ($(br.from_bus) → $(br.to_bus)); skipping."
            continue
        end
        arc = PSY.Arc(from=from_bus, to=to_bus)

        rating_pu = br.rating_mva > 0 ? br.rating_mva / base_MVA : 0.0

        if PSY.get_base_voltage(from_bus) != PSY.get_base_voltage(to_bus)
            PSY.add_component!(sys,
                PSY.Transformer2W(
                    br.name,
                    true,
                    0.0, 0.0,
                    arc,
                    br.r,
                    br.x,
                    Complex(0.0, br.b),
                    rating_pu,
                    base_MVA,
                ))
        else
            line = PSY.Line(
                br.name,
                true,
                0.0, 0.0,
                arc,
                br.r,
                br.x,
                (from=br.b/2, to=br.b/2),
                rating_pu,
                (min=-π/2, max=π/2),
            )
            if rating_pu == 0.0
                line.rating = PSY.line_rating_calculation(line)
            end
            PSY.add_component!(sys, line)
        end
    end
end

#####################################################################################
# Build generator components
#####################################################################################
function _build_generators!(sys::PSY.System, generators, base_MVA::Float64)
    for gen in generators
        gen.in_service || continue

        bus = PSY.get_component(PSY.ACBus, sys, something(gen.bus_name, ""))
        if isnothing(bus)
            @warn "Generator \"$(gen.name)\": bus \"$(gen.bus_name)\" not found; skipping."
            continue
        end
        @debug "Parsing generator \"$(gen.name)\":", gen

        p_max_pu = gen.p_max_mw / base_MVA
        p_min_pu = gen.p_min_mw / base_MVA
        pg_pu    = gen.initial_status ? gen.pg_mw   / base_MVA : 0.0
        qg_pu    = gen.initial_status ? gen.qg_mvar / base_MVA : 0.0
        ramp_pu_per_min = (gen.ramp_up_mw_per_hr / 60.0) / base_MVA
        ramp_limits = ramp_pu_per_min > 0 ? (up=ramp_pu_per_min, down=ramp_pu_per_min) : nothing
        time_limits = (gen.min_up_time_h > 0 || gen.min_down_time_h > 0) ?
                      (up=gen.min_up_time_h, down=gen.min_down_time_h) : nothing

        psy_type = _gen_psy_type(gen)
        prime_mover = _infer_prime_mover(gen)
        @debug "Determined $(gen.name) as $psy_type with pm $prime_mover"

        if psy_type == "ThermalStandard"
            fuel = get(_FUEL_TO_PSY, gen.fuel, PSY.ThermalFuels.OTHER)
            op_cost = _build_thermal_cost(gen)
            PSY.add_component!(sys, PSY.ThermalStandard(
                gen.name,
                true,
                gen.initial_status,
                bus,
                pg_pu,
                qg_pu,
                p_max_pu,
                (min=p_min_pu, max=p_max_pu),
                nothing,
                ramp_limits,
                op_cost,
                gen.mbase_mva,
                time_limits,
                false,
                prime_mover,
                fuel,
            ))

        elseif psy_type == "HydroDispatch"
            PSY.add_component!(sys, PSY.HydroDispatch(
                gen.name,
                true,
                bus,
                pg_pu,
                qg_pu,
                p_max_pu,
                prime_mover,
                (min=p_min_pu, max=p_max_pu),
                nothing,
                ramp_limits,
                time_limits,
                gen.mbase_mva,
            ))

        elseif psy_type == "HydroPumpedStorage"
            # Negative p_max_mw means this unit only consumes power (pump mode).
            # Generation-side limits are zero; pump limits come from the magnitude of the negative ratings.
            pump_max_pu = abs(gen.p_min_mw) / base_MVA   # most negative = max pump load
            pump_min_pu = abs(gen.p_max_mw) / base_MVA   # least negative = min pump load
            PSY.add_component!(sys, PSY.HydroPumpTurbine(
                gen.name,
                true,
                bus,
                0.0, 0.0,                                 # active_power (turbine), reactive_power
                0.0,                                      # rating (turbine) — pure pump, no generation
                (min=0.0, max=0.0),                       # active_power_limits (turbine)
                nothing,                                  # reactive_power_limits
                (min=pump_min_pu, max=pump_max_pu),       # active_power_limits_pump
                nothing,                                  # outflow_limits
                0.0,                                      # powerhouse_elevation
                ramp_limits,
                time_limits,
                gen.mbase_mva,
            ))

        elseif psy_type == "RenewableDispatch"
            op_cost = PSY.RenewableGenerationCost(PSY.CostCurve(PSY.IS.InputOutputCurve(PSY.IS.LinearFunctionData(0.0, 0.0))))
            PSY.add_component!(sys, PSY.RenewableDispatch(
                gen.name,
                true,
                bus,
                pg_pu,
                qg_pu,
                p_max_pu,
                prime_mover,
                nothing,
                1.0,
                op_cost,
                gen.mbase_mva,
            ))

        elseif psy_type == "RenewableNonDispatch"
            PSY.add_component!(sys, PSY.RenewableNonDispatch(
                gen.name,
                true,
                bus,
                pg_pu,
                qg_pu,
                p_max_pu,
                prime_mover,
                1.0,
                gen.mbase_mva,
            ))

        else
            @warn "Generator \"$(gen.name)\": unhandled PSY type \"$psy_type\"; skipping."
        end
    end
end

#####################################################################################
# Build VariableReserve products
#####################################################################################
function _build_reserves!(sys::PSY.System, system_dict::AbstractDict,
                           gen_elements::AbstractDict, area_bus_mapping::Dict,
                           generators)
    # Spinning reserves — one per area with area-specific data
    if !isa(area_bus_mapping, Vector) && haskey(system_dict, "spinning_reserve_requirement")
        for (i, area_name) in enumerate(sort(collect(keys(area_bus_mapping))))
            PSY.add_component!(sys, PSY.VariableReserve{PSY.ReserveUp}(
                "Spin_Up_R$i", true, 600.0 / 60.0, 0.1))  # 10 min frame
        end
    end

    # Regulation Up / Down
    if haskey(system_dict, "regulation_up_requirement")
        PSY.add_component!(sys, PSY.VariableReserve{PSY.ReserveUp}(
            "Reg_Up", true, 300.0 / 60.0, 0.05))
    end
    if haskey(system_dict, "regulation_down_requirement")
        PSY.add_component!(sys, PSY.VariableReserve{PSY.ReserveDown}(
            "Reg_Down", true, 300.0 / 60.0, 0.05))
    end

    # Flexible ramp
    if haskey(system_dict, "flexible_ramp_up_requirement")
        PSY.add_component!(sys, PSY.VariableReserve{PSY.ReserveUp}(
            "Flex_Up", true, 1200.0 / 60.0, 0.05))
    end
    if haskey(system_dict, "flexible_ramp_down_requirement")
        PSY.add_component!(sys, PSY.VariableReserve{PSY.ReserveDown}(
            "Flex_Down", true, 1200.0 / 60.0, 0.05))
    end

    # Add thermal + hydro generators as contributors to all Up reserves
    up_reserves = collect(PSY.get_components(PSY.VariableReserve{PSY.ReserveUp}, sys))
    down_reserves = collect(PSY.get_components(PSY.VariableReserve{PSY.ReserveDown}, sys))
    for gen in generators
        psy_type = _gen_psy_type(gen)
        psy_type in ("ThermalStandard", "HydroDispatch", "HydroPumpedStorage") || continue
        component = PSY.get_component(PSY.Generator, sys, gen.name)
        isnothing(component) && continue
        for reserve in up_reserves
            PSY.add_service!(component, reserve, sys)
        end
        for reserve in down_reserves
            PSY.add_service!(component, reserve, sys)
        end
    end
end

#####################################################################################
# Attach generator time series (max_active_power for HYDRO/PV/RTPV/WIND)
#####################################################################################
function _attach_gen_timeseries!(sys::PSY.System, generators,
                                  timestamps::Vector{Dates.DateTime})
    for gen in generators
        gen.p_max_ts === nothing && continue
        psy_type = _gen_psy_type(gen)
        psy_type in ("HydroDispatch", "RenewableDispatch", "RenewableNonDispatch") || continue

        component = PSY.get_component(PSY.Generator, sys, gen.name)
        isnothing(component) && continue

        raw_vals = Float64.(get(gen.p_max_ts, "values", Float64[]))
        isempty(raw_vals) && continue

        n = min(length(raw_vals), length(timestamps))
        vals = raw_vals[1:n]
        ts_stamps = timestamps[1:n]

        # Use the component's max_active_power * base_power as the normalizer.
        # If it is zero (e.g. p_max_mw was 0 for a time-varying generator),
        # fall back to the maximum value in the time series itself.
        scale = PSY.get_max_active_power(component) * PSY.get_base_power(sys)
        if scale == 0.0
            scale = maximum(vals)
            scale == 0.0 && continue   # all-zero time series — skip
            PSY.set_max_active_power!(component, scale / PSY.get_base_power(sys))
        end

        normalized = vals ./ scale
        ta = TimeSeries.TimeArray(ts_stamps, normalized)
        ts = PSY.SingleTimeSeries(
            name = "max_active_power",
            data = ta,
            scaling_factor_multiplier = PSY.get_max_active_power,
        )
        PSY.add_time_series!(sys, component, ts)
    end
end

#####################################################################################
# Attach load time series directly to PowerLoad components
#####################################################################################
function _attach_load_timeseries!(sys::PSY.System, buses, loads_dict::AbstractDict,
                                   area_bus_mapping::Dict,
                                   timestamps::Vector{Dates.DateTime},
                                   base_MVA::Float64)
    n_ts = length(timestamps)

    for bus in buses
        # Find the load record for this bus
        load_rec = nothing
        for (_, rec) in loads_dict
            if get(rec, "bus", nothing) == bus.name
                load_rec = rec
                break
            end
        end
        isnothing(load_rec) && continue

        load_ts = getfield(bus,Symbol("load_ts"))
        load_id = load_rec["id"]
        vals = load_ts[load_id] isa Number ? fill(load_ts[load_id], n_ts) : Float64.(load_ts[load_id])

        max_val = maximum(vals)
        max_val == 0.0 && continue

        peak_pu = max_val / base_MVA
        load_obj = PSY.get_component(PSY.PowerLoad, sys, "Load_" * bus.name * "_" * string(load_id))
        PSY.set_max_active_power!(load_obj, peak_pu)
        
        normalized = vals ./ max_val
        ta = TimeSeries.TimeArray(timestamps, normalized)
        ts = PSY.SingleTimeSeries(
            name = "max_active_power",
            data = ta,
            scaling_factor_multiplier = PSY.get_max_active_power,
        )
        PSY.add_time_series!(sys, load_obj, ts)
    end
end


#####################################################################################
# Attach reserve time series
#####################################################################################
function _attach_reserve_timeseries!(sys::PSY.System, system_dict::AbstractDict,
                                      areas_dict::Union{AbstractDict, Vector, Nothing},
                                      timestamps::Vector{Dates.DateTime},
                                      area_bus_mapping::Dict)
    n_ts = length(timestamps)

    # Spinning reserve — per area
    if !isa(areas_dict, Nothing) && !isa(areas_dict, Vector)
        for (i, (area_name, area_data)) in enumerate(pairs(areas_dict))
            reserve = PSY.get_component(PSY.VariableReserve{PSY.ReserveUp}, sys, "Spin_Up_R$i")
            isnothing(reserve) && continue
            spin_data = get(area_data, "spinning_reserve_requirement", nothing)
            isnothing(spin_data) && continue
            vals = Float64.(get(spin_data, "values", Float64[]))
            isempty(vals) && continue
            n = min(length(vals), n_ts)
            max_val = maximum(vals[1:n])
            max_val == 0.0 && continue
            normalized = vals[1:n] ./ max_val
            ta = TimeSeries.TimeArray(timestamps[1:n], normalized)
            ts = PSY.SingleTimeSeries(
                name = "requirement",
                data = ta,
                scaling_factor_multiplier = PSY.get_requirement,
            )
            reserve.requirement = max_val
            PSY.add_time_series!(sys, reserve, ts)
        end
    end

    # Regulation Up
    _attach_reserve_ts_by_key!(sys, system_dict, timestamps,
                                "regulation_up_requirement",
                                PSY.VariableReserve{PSY.ReserveUp}, "Reg_Up")
    # Regulation Down
    _attach_reserve_ts_by_key!(sys, system_dict, timestamps,
                                "regulation_down_requirement",
                                PSY.VariableReserve{PSY.ReserveDown}, "Reg_Down")
    # Flexible Ramp Up
    _attach_reserve_ts_by_key!(sys, system_dict, timestamps,
                                "flexible_ramp_up_requirement",
                                PSY.VariableReserve{PSY.ReserveUp}, "Flex_Up")
    # Flexible Ramp Down
    _attach_reserve_ts_by_key!(sys, system_dict, timestamps,
                                "flexible_ramp_down_requirement",
                                PSY.VariableReserve{PSY.ReserveDown}, "Flex_Down")
end

function _attach_reserve_ts_by_key!(sys, system_dict, timestamps, key, ReserveType, name)
    reserve = PSY.get_component(ReserveType, sys, name)
    isnothing(reserve) && return
    data = get(system_dict, key, nothing)
    isnothing(data) && return
    vals = Float64.(get(data, "values", Float64[]))
    isempty(vals) && return
    n = min(length(vals), length(timestamps))
    max_val = maximum(vals[1:n])
    max_val == 0.0 && return
    normalized = vals[1:n] ./ max_val
    ta = TimeSeries.TimeArray(timestamps[1:n], normalized)
    ts = PSY.SingleTimeSeries(
        name = "requirement",
        data = ta,
        scaling_factor_multiplier = PSY.get_requirement,
    )
    reserve.requirement = max_val
    PSY.add_time_series!(sys, reserve, ts)
end

#####################################################################################
# Main entry point: build a PSY.System from parsed EGRET data
#####################################################################################
function build_psy_system(data;
                           ts_label::String = "DAY_AHEAD",
                           time_series_directory::Union{Nothing, String} = nothing)
    sys = PSY.System(
        data.base_MVA;
        time_series_directory = time_series_directory,
        name = data.system_DA["uuid"], description = "Generated by EGRET2Sienna"
    )

    timestamps = ts_label == "DAY_AHEAD" ? data.timestamps_DA : data.timestamps_RT
    loads      = ts_label == "DAY_AHEAD" ? data.loads_DA      : data.loads_RT
    gen_elements = ts_label == "DAY_AHEAD" ? data.gen_elements_DA : data.gen_elements_RT
    system_dict  = ts_label == "DAY_AHEAD" ? data.system_DA    : data.system_RT
    areas        = ts_label == "DAY_AHEAD" ? data.areas_DA     : data.areas_RT

    # Build static topology (order matters: areas/zones → buses → branches → generators)
    _build_areas_zones!(sys, data.buses)
    _build_buses!(sys, data.buses, data.base_MVA)
    _build_branches!(sys, data.branches, data.base_MVA)
    _build_generators!(sys, data.generators, data.base_MVA)
    _build_reserves!(sys, system_dict, gen_elements, data.area_bus_mapping, data.generators)

    # Attach time series
    if data.gen_ts_flag && !isnothing(timestamps) && !isempty(timestamps)
        _attach_gen_timeseries!(sys, data.generators, timestamps)
    end

    if !isnothing(timestamps) && !isempty(timestamps) && !isnothing(loads)
        _attach_load_timeseries!(sys, data.buses, loads, data.area_bus_mapping,
                                  timestamps, data.base_MVA)
    end

    if !isnothing(timestamps) && !isempty(timestamps)
        _attach_reserve_timeseries!(sys, system_dict, areas, timestamps,
                                     data.area_bus_mapping)
    end

    return sys
end
