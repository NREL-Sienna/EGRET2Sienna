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
    "LFG"       => PSY.ThermalFuels.OTHER_GAS,   # landfill gas
    "Nuclear"   => PSY.ThermalFuels.NUCLEAR,
    "Uranium"   => PSY.ThermalFuels.NUCLEAR,
    "Oil"       => PSY.ThermalFuels.DISTILLATE_FUEL_OIL,
    "FO2"       => PSY.ThermalFuels.DISTILLATE_FUEL_OIL,   # fuel oil #2
    "Sync_Cond" => PSY.ThermalFuels.OTHER,
    "Hydro"     => PSY.ThermalFuels.OTHER,
    "Solar"     => PSY.ThermalFuels.OTHER,
    "Wind"      => PSY.ThermalFuels.OTHER,
    "OTHER"     => PSY.ThermalFuels.OTHER,
)

# Resolve an EGRET fuel string (which may carry a regional suffix like "Coal_Apache" or
# "NG_AZ South") to a PSY.ThermalFuels enum value.
# Strategy: exact match → prefix before first '_' → OTHER.
function _resolve_psy_fuel(fuel::String)::PSY.ThermalFuels
    haskey(_FUEL_TO_PSY, fuel) && return _FUEL_TO_PSY[fuel]
    prefix = split(fuel, "_"; limit=2)[1]
    return get(_FUEL_TO_PSY, prefix, PSY.ThermalFuels.OTHER)
end

# Determine the PSY.ThermalFuels for a generator, applying overrides before the
# generic fuel_code / fuel string lookup.
function _infer_thermal_fuel(gen)::PSY.ThermalFuels
    mt = uppercase(gen.model_type)
    gt = lowercase(gen.generator_type)
    # CC-OT: combined-cycle other technology — natural gas
    if mt == "CC-OT"
        return PSY.ThermalFuels.NATURAL_GAS
    # IC-OT: internal combustion other technology — other fuel (e.g. diesel, waste gas)
    elseif mt == "IC-OT"
        return PSY.ThermalFuels.OTHER
    # DC intertie — treated as an import with no specific fuel
    elseif mt == "DC"
        return PSY.ThermalFuels.OTHER
    # Combustion turbine / IC engine tagged as renewable = landfill gas / biogas
    elseif mt in ("GT-OT", "IC", "GT") && gt == "renewable"
        return PSY.ThermalFuels.OTHER_GAS
    end
    fc = _resolve_psy_fuel(gen.fuel_code)
    return fc == PSY.ThermalFuels.OTHER ? _resolve_psy_fuel(gen.fuel) : fc
end

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

    # Non-conforming load (motor load) — create a PowerLoad, not a generator
    if mt == "MOTOR"
        return "ConstantLoad"
    #elseif ut == "THERMAL"
    #    return "ThermalStandard"
    # Imports/exports — represented as signed PowerLoad (negative = injection, positive = withdrawal)
    elseif mt == "IMP"
        return "ConstantLoad"
    # CSP (concentrated solar power) — dispatchable renewable with CP prime mover
    elseif mt == "ST-SUN"
        return "RenewableDispatch"
    # Battery storage — always EnergyReservoirStorage regardless of generator_type
    elseif mt == "BA"
        return "EnergyReservoirStorage"
    # CC-OT: combined-cycle other-fuel (natural gas) — always thermal regardless of generator_type
    elseif mt == "CC-OT"
        return "ThermalStandard"
    # IC-OT: internal combustion other-fuel — always thermal regardless of generator_type
    elseif mt == "IC-OT"
        return "ThermalStandard"
    # Combustion turbines / IC engines tagged as renewable = landfill gas → ThermalStandard
    elseif mt in ("GT-OT", "IC", "GT") && gt == "renewable"
        return "ThermalStandard"
    # Biomass/waste-to-energy: steam-other prime mover tagged as renewable → ThermalStandard
    elseif mt == "ST-OT" && gt == "renewable"
        return "ThermalStandard"
    # DC intertie — import/export modeled as dispatchable ThermalStandard with energy price cost
    elseif mt == "DC"
        return "ThermalStandard"
    # model_type = "PS" is an explicit pumped-storage tag
    elseif mt == "PS"
        return "HydroPumpedStorage"
    # Hydro: route on p_max sign — negative means pumped storage, non-negative means turbine
    elseif fu == "HYDRO" || fc == "HYDRO" || ut in ("HYDRO", "ROR") || mt in ("HYDRO", "ROR", "HY")
        return gen.p_max_mw < 0 ? "HydroPumpedStorage" : "HydroTurbine"
    # Non-hydro generators with negative p_max (e.g. untagged pumped storage)
    elseif gen.p_max_mw < 0
        return "HydroPumpedStorage"
    elseif fu in ("SOLAR", "WIND") || fc in ("SOLAR", "WIND") ||
           ut in ("PV", "RTPV", "WIND", "SOLAR") ||
           mt in ("PV", "RTPV", "WT", "PVF", "PVE") ||
           gt in ("renewable", "solar", "wind", "pv")
        return mt == "RTPV" || ut == "RTPV" ? "RenewableNonDispatch" : "RenewableDispatch"
    elseif fu == "STORAGE" || fc == "STORAGE" || mt in ("STORAGE", "BATTERY", "FC", "BA")
        return "EnergyReservoirStorage"
    else
        return "ThermalStandard"
    end
end

const _MODEL_TYPE_TO_PRIME_MOVER = Dict{String, PSY.PrimeMovers}(
    # Renewable
    "WT"    => PSY.PrimeMovers.WT,
    "PV"    => PSY.PrimeMovers.PVe,
    "PVE"   => PSY.PrimeMovers.PVe,
    "PVF"   => PSY.PrimeMovers.PVe,
    "RTPV"   => PSY.PrimeMovers.PVe,
    "ST-SUN" => PSY.PrimeMovers.CP,
    # Hydro
    "HYDRO" => PSY.PrimeMovers.HY,
    "ROR"   => PSY.PrimeMovers.HY,
    "HY"    => PSY.PrimeMovers.HY,
    "PS"    => PSY.PrimeMovers.PS,
    # Thermal
    "CC"       => PSY.PrimeMovers.CC,
    "CC-OT"    => PSY.PrimeMovers.CC,
    "CT"       => PSY.PrimeMovers.CT,
    "GT"       => PSY.PrimeMovers.CT,
    "GT-OT"    => PSY.PrimeMovers.CT,
    "STEAM"    => PSY.PrimeMovers.ST,
    "ST-OT"    => PSY.PrimeMovers.ST,
    "NUCLEAR"  => PSY.PrimeMovers.ST,
    "IC"       => PSY.PrimeMovers.IC,
    "IC-OT"    => PSY.PrimeMovers.IC,
    "ICE"      => PSY.PrimeMovers.IC,
    "SYNC_COND"=> PSY.PrimeMovers.OT,
    "DC"       => PSY.PrimeMovers.OT,
    "OT"       => PSY.PrimeMovers.OT,
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
        if bus.mw_load > 0
            load = PSY.PowerLoad(
                "Load_" * bus.name,
                true,
                psy_bus,
                bus.mw_load   / base_MVA,
                bus.mvar_load / base_MVA,
                base_MVA,
                bus.mw_load   / base_MVA,
                bus.mvar_load / base_MVA,
            )
            PSY.add_component!(sys, load)
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
# Store EGRET classification metadata in a component's ext dict
#####################################################################################
function _store_egret_metadata!(component, gen)
    ext = PSY.get_ext(component)
    ext["generator_type"] = gen.generator_type
    ext["model_type"]     = gen.model_type
    ext["unit_type"]      = gen.unit_type
    ext["fuel_code"]      = gen.fuel_code
    # Normalize geothermal fuel to a canonical string regardless of source spelling
    ext["fuel"] = if uppercase(gen.fuel_code) in ("GEOTHERMAL", "GEO") ||
                     uppercase(gen.fuel)      in ("GEOTHERMAL", "GEO")
        "GEOTHERMAL"
    else
        gen.fuel
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

        if psy_type == "ThermalStandard" && (gen.rating_mw < 0 || isnothing(gen.p_max_mw) || gen.p_max_mw <= 0)
            @warn "Generator \"$(gen.name)\": invalid rating or p_max_mw; skipping."
            continue
        end

        if psy_type == "ConstantLoad"
            # IMP: positive p_max = injection → negative load; negative = withdrawal → positive load.
            # MOTOR: always consuming → abs value.
            load_pu = if uppercase(gen.model_type) == "IMP"
                -gen.p_max_mw / base_MVA
            else
                abs(gen.p_max_mw) / base_MVA
            end
            load_name = "Load_" * gen.name
            if isnothing(PSY.get_component(PSY.PowerLoad, sys, load_name))
                load_comp = PSY.PowerLoad(load_name, true, bus,
                                          load_pu, 0.0, base_MVA, load_pu, 0.0)
                PSY.add_component!(sys, load_comp)
                _store_egret_metadata!(load_comp, gen)
            end
            continue

        elseif psy_type == "ThermalStandard"
            fuel = _infer_thermal_fuel(gen)
            # DC interties use a flat energy price (~$30/MWh average central US wholesale)
            # rather than a heat-rate curve, since they represent power imports.
            op_cost = if uppercase(gen.model_type) == "DC"
                PSY.ThermalGenerationCost(
                    variable  = PSY.CostCurve(PSY.IS.InputOutputCurve(PSY.IS.LinearFunctionData(30.0, 0.0))),
                    fixed     = 0.0,
                    start_up  = 0.0,
                    shut_down = 0.0,
                )
            else
                _build_thermal_cost(gen)
            end
            comp = PSY.ThermalStandard(
                gen.name, true, gen.initial_status, bus,
                pg_pu, qg_pu, p_max_pu,
                (min=p_min_pu, max=p_max_pu),
                nothing, ramp_limits, op_cost, gen.mbase_mva,
                time_limits, false, prime_mover, fuel,
            )
            PSY.add_component!(sys, comp)
            _store_egret_metadata!(comp, gen)

        elseif psy_type == "HydroTurbine"
            # Build one HydroTurbine per bus (>1 only for distributed-bus generators).
            # All turbines from the same EGRET generator share a single HydroReservoir.
            bus_map = !isnothing(gen.distributed_buses) ?
                      gen.distributed_buses :
                      Dict{String, Float64}(gen.bus_name => 1.0)
            total_pf = sum(values(bus_map))

            turbines = PSY.HydroTurbine[]
            for (b_name, pf) in bus_map
                pf_norm  = pf / total_pf
                b_bus    = PSY.get_component(PSY.ACBus, sys, b_name)
                isnothing(b_bus) && continue

                turbine_name = length(bus_map) > 1 ? gen.name * "_" * b_name : gen.name
                turbine = PSY.HydroTurbine(
                    turbine_name,
                    true,
                    b_bus,
                    pg_pu * pf_norm,
                    qg_pu * pf_norm,
                    p_max_pu * pf_norm,
                    (min=p_min_pu * pf_norm, max=p_max_pu * pf_norm),
                    nothing,
                    gen.mbase_mva * pf_norm,
                    PSY.HydroGenerationCost(nothing),
                    0.0,      # powerhouse_elevation
                    ramp_limits,
                    time_limits,
                )
                PSY.add_component!(sys, turbine)
                _store_egret_metadata!(turbine, gen)
                push!(turbines, turbine)
            end

            # Shared HydroReservoir — all turbines draw from the same upper reservoir
            reservoir = PSY.HydroReservoir(
                gen.reservoir_name * "_reservoir",
                true,
                (min=0.0, max=0.0),     # storage_level_limits (unknown from EGRET)
                0.5,                    # initial_level (50% of max)
                nothing,                # spillage_limits
                0.0,                    # inflow
                0.0,                    # outflow
                nothing,                # level_targets
                0.0,                    # intake_elevation
                PSY.LinearCurve(1.0),   # head_to_volume_factor
                PSY.HydroUnit[],        # upstream_turbines
                turbines,               # downstream_turbines
            )
            PSY.add_component!(sys, reservoir)

        elseif psy_type == "HydroPumpedStorage"
            # Build one HydroPumpTurbine per bus (>1 only for distributed-bus generators).
            # All turbines from the same EGRET generator share a single HydroReservoir.
            bus_map = !isnothing(gen.distributed_buses) ?
                      gen.distributed_buses :
                      Dict{String, Float64}(gen.bus_name => 1.0)
            total_pf = sum(values(bus_map))

            turbines = PSY.HydroPumpTurbine[]
            for (b_name, pf) in bus_map
                pf_norm   = pf / total_pf
                b_bus     = PSY.get_component(PSY.ACBus, sys, b_name)
                isnothing(b_bus) && continue

                pump_max_pu = abs(gen.p_min_mw) * pf_norm / base_MVA
                pump_min_pu = abs(gen.p_max_mw) * pf_norm / base_MVA
                turbine_name = length(bus_map) > 1 ? gen.name * "_" * b_name : gen.name

                turbine = PSY.HydroPumpTurbine(
                    turbine_name,
                    true,
                    b_bus,
                    0.0, 0.0,
                    0.0,                                      # rating (turbine) — pure pump
                    (min=0.0, max=0.0),                       # active_power_limits (turbine)
                    nothing,                                  # reactive_power_limits
                    (min=pump_min_pu, max=pump_max_pu),       # active_power_limits_pump
                    nothing,                                  # outflow_limits
                    0.0,                                      # powerhouse_elevation
                    ramp_limits,
                    time_limits,
                    gen.mbase_mva * pf_norm,
                )
                PSY.add_component!(sys, turbine)
                _store_egret_metadata!(turbine, gen)
                push!(turbines, turbine)
            end

            # Shared HydroReservoir — all turbines draw from the same upper reservoir.
            # Default storage capacity = 10 hours at max pump rate (MWh); this is used
            # by HPS's store_energy_capacity_multiplier_in_ext! when building the model.
            default_storage_mwh = abs(gen.p_min_mw) * 10.0
            reservoir = PSY.HydroReservoir(
                gen.reservoir_name * "_reservoir",
                true,
                (min=0.0, max=default_storage_mwh),   # storage_level_limits (MWh)
                0.5,                    # initial_level (50% of max)
                nothing,                # spillage_limits
                0.0,                    # inflow
                0.0,                    # outflow
                nothing,                # level_targets
                0.0,                    # intake_elevation
                PSY.LinearCurve(1.0),   # head_to_volume_factor
                PSY.HydroUnit[],        # upstream_turbines (none — pure pump plants)
                turbines,               # downstream_turbines (draw from this reservoir)
            )
            PSY.add_component!(sys, reservoir)

        elseif psy_type == "EnergyReservoirStorage"
            charge_max_pu = gen.p_min_mw < 0 ? abs(gen.p_min_mw) / base_MVA : p_max_pu
            # Default storage capacity: 4 hours at max discharge rate (MWh)
            storage_mwh = gen.p_max_mw * 4.0
            comp = PSY.EnergyReservoirStorage(
                gen.name,
                true,
                bus,
                PSY.PrimeMovers.BA,
                PSY.StorageTech.LIB,
                storage_mwh,
                (min=0.0, max=1.0),           # storage_level_limits (pu of capacity)
                0.5,                           # initial_storage_capacity_level
                p_max_pu,                      # rating
                pg_pu,                         # active_power
                (min=0.0, max=charge_max_pu),  # input_active_power_limits
                (min=0.0, max=p_max_pu),       # output_active_power_limits
                (in=0.9, out=0.9),             # efficiency
                qg_pu,
                nothing,                       # reactive_power_limits
                gen.mbase_mva,
                PSY.StorageCost(),
            )
            PSY.add_component!(sys, comp)
            _store_egret_metadata!(comp, gen)

        elseif psy_type == "RenewableDispatch"
            op_cost = PSY.RenewableGenerationCost(PSY.CostCurve(PSY.IS.InputOutputCurve(PSY.IS.LinearFunctionData(0.0, 0.0))))
            comp = PSY.RenewableDispatch(
                gen.name, true, bus, pg_pu, qg_pu, p_max_pu,
                prime_mover, nothing, 1.0, op_cost, gen.mbase_mva,
            )
            PSY.add_component!(sys, comp)
            _store_egret_metadata!(comp, gen)

        elseif psy_type == "RenewableNonDispatch"
            comp = PSY.RenewableNonDispatch(
                gen.name, true, bus, pg_pu, qg_pu, p_max_pu,
                prime_mover, 1.0, gen.mbase_mva,
            )
            PSY.add_component!(sys, comp)
            _store_egret_metadata!(comp, gen)

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
        psy_type in ("ThermalStandard", "HydroTurbine", "HydroPumpedStorage") || continue
        # For distributed-bus generators, multiple components were created with suffixed names
        names = if !isnothing(gen.distributed_buses)
            [gen.name * "_" * b for b in keys(gen.distributed_buses)]
        else
            [gen.name]
        end
        for name in names
            component = PSY.get_component(PSY.Generator, sys, name)
            isnothing(component) && continue
            for reserve in up_reserves
                PSY.add_service!(component, reserve, sys)
            end
            for reserve in down_reserves
                PSY.add_service!(component, reserve, sys)
            end
        end
    end
end

#####################################################################################
# Attach generator time series (max_active_power for HYDRO/PV/RTPV/WIND)
#####################################################################################
function _attach_gen_timeseries!(sys::PSY.System, generators,
                                  timestamps::Vector{Dates.DateTime})
    n_ts = length(timestamps)

    for gen in generators
        psy_type = _gen_psy_type(gen)
        psy_type in ("HydroTurbine", "RenewableDispatch", "RenewableNonDispatch",
                     "HydroPumpedStorage") || continue

        # For distributed-bus generators, turbines were created with suffixed names
        names = if !isnothing(gen.distributed_buses)
            [gen.name * "_" * b for b in keys(gen.distributed_buses)]
        else
            [gen.name]
        end

        for comp_name in names
            # HydroPumpTurbine may not subtype Generator in PSY 5.5; look it up by its own type.
            component = if psy_type == "HydroPumpedStorage"
                PSY.get_component(PSY.HydroPumpTurbine, sys, comp_name)
            else
                PSY.get_component(PSY.Generator, sys, comp_name)
            end
            isnothing(component) && continue

            if psy_type == "HydroPumpedStorage"
                # Pure pump turbines have zero turbine generation capacity.
                # HydroPumpEnergyDispatch requires two time series:
                #   "max_active_power" — turbine output capacity (zero for pure pumps)
                #   "capacity"         — reservoir energy capacity (constant full = 1.0)
                ta_zero = TimeSeries.TimeArray(timestamps, zeros(Float64, n_ts))
                PSY.add_time_series!(sys, component,
                    PSY.SingleTimeSeries(
                        name = "max_active_power",
                        data = ta_zero,
                        scaling_factor_multiplier = PSY.get_max_active_power,
                    ))
                ta_ones = TimeSeries.TimeArray(timestamps, ones(Float64, n_ts))
                PSY.add_time_series!(sys, component,
                    PSY.SingleTimeSeries(
                        name = "capacity",
                        data = ta_ones,
                    ))
                continue
            end

            gen.p_max_ts === nothing && continue

            raw_vals = Float64.(get(gen.p_max_ts, "values", Float64[]))
            isempty(raw_vals) && continue

            n = min(length(raw_vals), n_ts)
            vals = raw_vals[1:n]
            ts_stamps = timestamps[1:n]

            # Use the component's max_active_power * base_power as the normalizer.
            # Fall back to the time series maximum if the component value is zero.
            scale = PSY.get_max_active_power(component) * PSY.get_base_power(sys)
            if scale == 0.0
                scale = maximum(vals)
                scale == 0.0 && continue
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
end

#####################################################################################
# Attach load time series to PowerLoad components, sharing one time series per area.
#
# Strategy: all buses in the same area share a single SingleTimeSeries object (same
# UUID → one HDF5 dataset).  The area-level time series is the normalized area-total
# shape (area_total_t / area_peak).  Each PowerLoad's max_active_power is set to its
# own bus peak in pu, which acts as the distribution factor.  At solve time PSI
# recovers per-bus demand as:
#   ts_value_t  ×  get_max_active_power(load)  =  area_shape_t × bus_peak_pu
#####################################################################################
function _attach_load_timeseries!(sys::PSY.System, buses, loads_dict::AbstractDict,
                                   area_bus_mapping::Dict,
                                   timestamps::Vector{Dates.DateTime},
                                   base_MVA::Float64)
    n_ts = length(timestamps)

    # Build bus_name → load record lookup
    bus_to_load_rec = Dict{String, Any}()
    for (_, rec) in loads_dict
        bus_name = get(rec, "bus", nothing)
        isnothing(bus_name) || (bus_to_load_rec[bus_name] = rec)
    end

    # Group buses by area (buses without an area go into "__none__")
    area_to_buses = Dict{String, Vector}()
    for bus in buses
        area = something(bus.area_name, "__none__")
        push!(get!(area_to_buses, area, []), bus)
    end

    for (_, area_buses) in area_to_buses
        # Resolve per-bus raw load profiles
        bus_profiles = Dict{String, Vector{Float64}}()
        for bus in area_buses
            rec = get(bus_to_load_rec, bus.name, nothing)
            isnothing(rec) && continue
            vals = _load_ts_values(get(rec, "p_load", nothing), n_ts)
            isempty(vals) && continue
            maximum(vals) > 0.0 && (bus_profiles[bus.name] = vals)
        end
        isempty(bus_profiles) && continue

        # Area aggregate and normalized shape
        area_total = zeros(Float64, n_ts)
        for (_, vals) in bus_profiles
            n_v = min(length(vals), n_ts)
            area_total[1:n_v] .+= vals[1:n_v]
        end
        area_peak = maximum(area_total)
        area_peak == 0.0 && continue
        area_normalized = area_total ./ area_peak

        # ONE shared SingleTimeSeries for every load in this area.
        # Passing the same object to multiple add_time_series! calls keeps the UUID
        # constant → InfrastructureSystems writes only one HDF5 dataset.
        area_ts = PSY.SingleTimeSeries(
            name = "max_active_power",
            data = TimeSeries.TimeArray(timestamps, area_normalized),
            scaling_factor_multiplier = PSY.get_max_active_power,
        )

        for bus in area_buses
            haskey(bus_profiles, bus.name) || continue
            bus_peak_pu = maximum(bus_profiles[bus.name]) / base_MVA

            load_obj = PSY.get_component(PSY.PowerLoad, sys, "Load_" * bus.name)
            if isnothing(load_obj)
                psy_bus = PSY.get_component(PSY.ACBus, sys, bus.name)
                isnothing(psy_bus) && continue
                load_obj = PSY.PowerLoad("Load_" * bus.name, true, psy_bus,
                                         bus_peak_pu, 0.0, base_MVA, bus_peak_pu, 0.0)
                PSY.add_component!(sys, load_obj)
            else
                PSY.set_max_active_power!(load_obj, bus_peak_pu)
            end

            PSY.add_time_series!(sys, load_obj, area_ts)
        end
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
