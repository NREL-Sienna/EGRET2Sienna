#####################################################
# Surya
# NREL
# October 2021
# Script to generate csv's from EGRET System JSON
# Generate component CSV SIIP tabular parser expects from EGRET System JSON
#####################################################################################
# Helper Functions
# Function to get p_max and p_min of Generator
# p_max and p_min for Hydro and Renewable. For these types, p_max is a 
# time series and not an Int64. Currently, assigning max of time series values
# as for these types of Generator
#####################################################################################
function parse_p_minmax!(comp_values::Base.ValueIterator, comp_dict::Dict{Any, Any})
    p_max_values = []
    p_min_values = []
    ts_flag = 0
    for val in comp_values
        p_max_val = get(val,"p_max","None")
        if p_max_val isa Number
            push!(p_max_values,p_max_val)
        else
            push!(p_max_values,maximum(get(p_max_val,"values","None")))
            ts_flag +=1
        end

        p_min_val = get(val,"p_min","None")
        if p_min_val isa Number
            push!(p_min_values,p_min_val)
        else
            if (get(val,"fuel","None") =="Hydro")
                push!(p_min_values,maximum(get(p_min_val ,"values","None")))
            else
                push!(p_min_values,0)
            end 
        end
    end

    push!(comp_dict,"p_max" => p_max_values)
    push!(comp_dict,"p_min" => p_min_values)

    # Time series availability
    flag = false
    if (ts_flag >0)
        flag = true
    else
        flag = false
    end

    return flag
end
#####################################################################################
# Functions to parse the EGRET Dict 'fuel_type'
# EGRET Code (https://github.com/grid-parity-exchange/Egret/blob/main/egret/parsers/rts_gmlc/parser.py#L560-L590)
# f[0] = (float(row['HR_avg_0'])*1000./ 1000000.)*x[0]
# for HR_0 : float(row['HR_avg_0'] = (f[0]/x[0])*1000
# f[i] = (((x[i]-x[i-1])*(float(row[f'HR_incr_{i}'])*1000. / 1000000.))) + f[i-1]
# Others: float(row[f'HR_incr_{i}'] = ((f[i] - f[i-1])/(x[i] - x[i-1]))*1000
#####################################################################################
function parse_fuel_dict!(comp_values::Base.ValueIterator, comp_dict::Dict{Any, Any},num_data_points::Int64)
    for i in 1:num_data_points
        push!(comp_dict,"output_pct_$(i-1)" =>[])
        push!(comp_dict,"HR_avg_$(i-1)" =>[])
    end

    for (comp_p_max,fuel_dict) in zip(get(comp_dict,"p_max","None"),get.(comp_values,"p_fuel","None"))
        if (fuel_dict != "None")
            if (length(fuel_dict["values"]) < num_data_points)
                for i in 1:length(fuel_dict["values"])
                    push!(comp_dict["output_pct_$(i-1)"],fuel_dict["values"][i][1]/comp_p_max)
                    if (i==1)
                        HR_temp= (fuel_dict["values"][i][2]/fuel_dict["values"][i][1])*1000
                        push!(comp_dict["HR_avg_$(i-1)"],HR_temp)
                    else
                        HR_temp= ((fuel_dict["values"][i][2] - fuel_dict["values"][i][2])/(fuel_dict["values"][i][1] - fuel_dict["values"][i-1][1]))*1000
                        push!(comp_dict["HR_avg_$(i-1)"],fuel_dict["values"][i][2])
                    end  
                end
                for i in 1+length(fuel_dict["values"]):num_data_points
                    push!(comp_dict["output_pct_$(i-1)"],0)
                    push!(comp_dict["HR_avg_$(i-1)"],0)
                end
            else
                for i in 1:num_data_points
                    push!(comp_dict["output_pct_$(i-1)"],fuel_dict["values"][i][1]/comp_p_max)
                    if (i==1)
                        HR_temp= (fuel_dict["values"][i][2]/fuel_dict["values"][i][1])*1000
                        push!(comp_dict["HR_avg_$(i-1)"],HR_temp)
                    else
                        HR_temp= ((fuel_dict["values"][i][2] - fuel_dict["values"][i][2])/(fuel_dict["values"][i][1] - fuel_dict["values"][i-1][1]))*1000
                        push!(comp_dict["HR_avg_$(i-1)"],fuel_dict["values"][i][2])
                    end  
                end
            end 
        else
            for i in 1:num_data_points
                push!(comp_dict["output_pct_$(i-1)"],0)
                push!(comp_dict["HR_avg_$(i-1)"],0)
            end
        end
    end
end
#####################################################################################
# Functions to parse the EGRET Dict 'startup_fuel'
# EGRET Code (https://github.com/grid-parity-exchange/Egret/blob/main/egret/parsers/rts_gmlc/parser.py#L593-L624)
#=
startup_heat = (float(row['Start Heat Hot MBTU']),
                float(row['Start Heat Warm MBTU']),
                float(row['Start Heat Cold MBTU']))
startup_time = (float(row['Start Time Hot Hr']),
                float(row['Start Time Warm Hr']),
                float(row['Start Time Cold Hr']))
=#
#####################################################################################
function parse_startup_fuel_dict!(comp_values::Base.ValueIterator, comp_dict::Dict{Any, Any})

    lookup_dict = Dict([(1, ("Start Time Cold Hr","Start Heat Cold MBTU")), (2, ("Start Time Warm Hr","Start Heat Warm MBTU")),(3, ("Start Time Hot Hr","Start Heat Hot MBTU"))]);

    push!(comp_dict,"Start Heat Hot MBTU" =>[])
    push!(comp_dict,"Start Heat Warm MBTU" =>[])
    push!(comp_dict,"Start Heat Cold MBTU" =>[])
    push!(comp_dict,"Start Time Hot Hr" =>[])
    push!(comp_dict,"Start Time Warm Hr" =>[])
    push!(comp_dict,"Start Time Cold Hr" =>[])
   
    for startup_dict in get.(comp_values,"startup_fuel","None")
        if (startup_dict != "None")
            for i in 1:3
                try
                    push!(comp_dict[lookup_dict[i][1]],startup_dict[i][1])
                    push!(comp_dict[lookup_dict[i][2]],startup_dict[i][2])
                catch ex
                    push!(comp_dict[lookup_dict[i][1]],0)
                    if (startup_dict[1][2] !=0)
                        push!(comp_dict[lookup_dict[i][2]],startup_dict[1][2])
                    else
                        push!(comp_dict[lookup_dict[i][2]],0)
                    end
                end
            end
        else
            for i in 1:3
                push!(comp_dict[lookup_dict[i][1]],0)
                push!(comp_dict[lookup_dict[i][2]],0)
            end 
        end
    end
end
#####################################################################################
# Make HYDRO time series CSV
#####################################################################################
function make_HYDRO_time_series(time_stamps::Vector{Dates.DateTime},dir_name::String,components::Vector{Any})
   
    df = DataFrames.DataFrame()

    df[!,"DateTime"] = time_stamps
    comp_names = []
    for idx in 1:length(components)
        df[!,components[idx][1]] =  get(components[idx][2],"p_max","None")["values"]
        push!(comp_names,components[idx][1])
    end
    # Export CSV
    csv_path = joinpath(dir_name,"DAY_AHEAD_hydro.csv")
    CSV.write(csv_path, df,writeheader = true)

    # Pointers Dict
    num_components = length(comp_names)
    pointers_dict = Dict()
    push!(pointers_dict,"Simulation" =>fill("DAY_AHEAD",num_components))
    push!(pointers_dict,"Category" =>fill("Generator",num_components))
    push!(pointers_dict,"Object" =>comp_names)
    push!(pointers_dict,"Parameter" =>fill("p_max",num_components))
    push!(pointers_dict,"Scaling Factor" =>fill(1,num_components))
    push!(pointers_dict,"Data File" =>fill(csv_path,num_components))

    return pointers_dict
end
#####################################################################################
# Make PV time series CSV
#####################################################################################
function make_PV_time_series(time_stamps::Vector{Dates.DateTime},dir_name::String,components::Vector{Any})
    
    df = DataFrames.DataFrame()

    df[!,"DateTime"] = time_stamps
    comp_names = []
    for idx in 1:length(components)
        df[!,components[idx][1]] =  get(components[idx][2],"p_max","None")["values"]
        push!(comp_names,components[idx][1])
    end
    # Export CSV
    csv_path = joinpath(dir_name,"DAY_AHEAD_pv.csv")
    CSV.write(csv_path, df,writeheader = true)

    # Pointers Dict
    num_components = length(comp_names)
    pointers_dict = Dict()
    push!(pointers_dict,"Simulation" =>fill("DAY_AHEAD",num_components))
    push!(pointers_dict,"Category" =>fill("Generator",num_components))
    push!(pointers_dict,"Object" =>comp_names)
    push!(pointers_dict,"Parameter" =>fill("p_max",num_components))
    push!(pointers_dict,"Scaling Factor" =>fill(1,num_components))
    push!(pointers_dict,"Data File" =>fill(csv_path,num_components))

    return pointers_dict
end
#####################################################################################
# Make RTPV time series CSV
#####################################################################################
function make_RTPV_time_series(time_stamps::Vector{Dates.DateTime},dir_name::String,components::Vector{Any})
    df = DataFrames.DataFrame()

    df[!,"DateTime"] = time_stamps
    comp_names = []
    
    for idx in 1:length(components)
        df[!,components[idx][1]] =  get(components[idx][2],"p_max","None")["values"]
        push!(comp_names,components[idx][1])
    end
    # Export CSV
    csv_path = joinpath(dir_name,"DAY_AHEAD_rtpv.csv")
    CSV.write(csv_path, df,writeheader = true)

    # Pointers Dict
    num_components = length(comp_names)
    pointers_dict = Dict()
    push!(pointers_dict,"Simulation" =>fill("DAY_AHEAD",num_components))
    push!(pointers_dict,"Category" =>fill("Generator",num_components))
    push!(pointers_dict,"Object" =>comp_names)
    push!(pointers_dict,"Parameter" =>fill("p_max",num_components))
    push!(pointers_dict,"Scaling Factor" =>fill(1,num_components))
    push!(pointers_dict,"Data File" =>fill(csv_path,num_components))

    return pointers_dict
end
#####################################################################################
# Make WIND time series CSV
#####################################################################################
function make_WIND_time_series(time_stamps::Vector{Dates.DateTime},dir_name::String,components::Vector{Any})

    df = DataFrames.DataFrame()

    df[!,"DateTime"] = time_stamps
    comp_names = []
    for idx in 1:length(components)
        df[!,components[idx][1]] =  get(components[idx][2],"p_max","None")["values"]
        push!(comp_names,components[idx][1])
    end
    # Export CSV
    csv_path = joinpath(dir_name,"DAY_AHEAD_wind.csv")
    CSV.write(csv_path, df,writeheader = true)

     # Pointers Dict
     num_components = length(comp_names)
     pointers_dict = Dict()
     push!(pointers_dict,"Simulation" =>fill("DAY_AHEAD",num_components))
     push!(pointers_dict,"Category" =>fill("Generator",num_components))
     push!(pointers_dict,"Object" =>comp_names)
     push!(pointers_dict,"Parameter" =>fill("p_max",num_components))
     push!(pointers_dict,"Scaling Factor" =>fill(1,num_components))
     push!(pointers_dict,"Data File" =>fill(csv_path,num_components))
 
     return pointers_dict
end
#####################################################################################
# Parse time series data
# **TODO: Need to be generaized to handle RT Systems and reserves
#####################################################################################
function time_series_processing(dir_name::String,areas::Dict{String, Any},system::Dict{String, Any};loads::Union{Nothing, Dict{String, Any}} = nothing,
                                 area_bus_mapping_dict::Union{Nothing, Dict{Any, Any}} = nothing,gen_components::Union{Nothing, Dict{String, Any}} = nothing)
    
    #Time stamp processing
    date_format = Dates.DateFormat("Y-m-d H:M")
    time_stamps = Dates.DateTime.(system["time_keys"],date_format)
    # Make time series data folder
    
    ts_dir_name = joinpath(dir_name,"timeseries_data_files")

    if (~isdir(ts_dir_name))
        mkpath(ts_dir_name)
    end

    # Time series pointer CSV
    df_ts_pointer = DataFrames.DataFrame()

    # Reserves Metadata CSV
    df_reserves_metadata = DataFrames.DataFrame()
    
    # Reserves Metadata CSV
    df_simulation_objects = DataFrames.DataFrame()

    #Reserves
    # Spinning Reserves
    folder_name = joinpath(ts_dir_name,"RESERVES")
    mkpath(folder_name)
    object_names = []
    data_files = []
    region_max_values = []
    for (idx,key) in enumerate(keys(areas))
        df = DataFrames.DataFrame()
        df[!,"DateTime"] = time_stamps
        column_name = "Spin_Up_R"*"$idx"
        push!(object_names,column_name)
        df[!,column_name] = areas[key]["spinning_reserve_requirement"]["values"]
        push!(region_max_values,maximum(areas[key]["spinning_reserve_requirement"]["values"]))

        # Export CSV
        csv_name = "DAY_AHEAD_regional_Spin_Up_R"* "$idx" *".csv"
        csv_path = joinpath(folder_name,csv_name)
        push!(data_files,csv_path)
        CSV.write(csv_path, df,writeheader = true)
    end
    # Pointers Dict
    num_areas = length(keys(area_bus_mapping_dict))
    pointers_dict = Dict()
    push!(pointers_dict,"Simulation" =>fill("DAY_AHEAD",num_areas))
    push!(pointers_dict,"Category" =>fill("Reserve",num_areas))
    push!(pointers_dict,"Object" =>object_names)
    push!(pointers_dict,"Parameter" =>fill("Requirement",num_areas))
    push!(pointers_dict,"Scaling Factor" =>fill(1,num_areas))
    push!(pointers_dict,"Data File" =>data_files)

    append!(df_ts_pointer,pointers_dict)

    # Reserves Metadata Dict
    reserves_metadata_dict = Dict()
    gen_fuel_unit_types = [u_t for u_t in unique(get.(values(gen_components),"fuel","None").*" ".*get.(values(gen_components),"unit_type","None")) if ~(u_t in ["Sync_Cond SYNC_COND","Nuclear NUCLEAR", "Solar RTPV"])]
    push!(reserves_metadata_dict, "Reserve Product"=>object_names)
    push!(reserves_metadata_dict, "Timeframe (sec)"=>fill(600,num_areas)) 
    push!(reserves_metadata_dict, "Requirement (MW)"=>region_max_values)
    push!(reserves_metadata_dict, "Eligible Regions"=>collect(keys(areas)))
    push!(reserves_metadata_dict, "Eligible Device Categories"=>fill("Generator",num_areas))
    push!(reserves_metadata_dict, "Eligible Device SubCategories"=>fill(gen_fuel_unit_types,num_areas))
    push!(reserves_metadata_dict, "Direction"=>fill("Up",num_areas))

    append!(df_reserves_metadata,reserves_metadata_dict)
    # Regulation Up & Down
    # Need to be generalized
    # Up
    reserve_dict = Dict()
    for (idx,val) in enumerate(system["regulation_up_requirement"]["values"])
        push!(reserve_dict, string(idx) => val)
    end
    max_reserve_val = maximum(values(reserve_dict))
    push!(reserve_dict,"DateTime" =>time_stamps[1])
    df = DataFrames.DataFrame(reserve_dict)
    csv_path = joinpath(folder_name,"DAY_AHEAD_regional_Reg_Up.csv")
    CSV.write(csv_path, df,writeheader = true)

    # Pointers Dict
    pointers_dict = Dict()
    push!(pointers_dict,"Simulation" =>"DAY_AHEAD")
    push!(pointers_dict,"Category" =>"Reserve")
    push!(pointers_dict,"Object" =>"Reg_Up")
    push!(pointers_dict,"Parameter" =>"Requirement")
    push!(pointers_dict,"Scaling Factor" =>1)
    push!(pointers_dict,"Data File" =>csv_path)

    append!(df_ts_pointer,pointers_dict)

    # Reserves Metadata Dict
    reserves_metadata_dict = Dict()
    push!(reserves_metadata_dict, "Reserve Product"=>"Reg_Up")
    push!(reserves_metadata_dict, "Timeframe (sec)"=>300) 
    push!(reserves_metadata_dict, "Requirement (MW)"=>max_reserve_val)
    temp = collect(keys(areas))
    push!(reserves_metadata_dict, "Eligible Regions"=>join(temp,","))
    push!(reserves_metadata_dict, "Eligible Device Categories"=>"Generator")
    push!(reserves_metadata_dict, "Eligible Device SubCategories"=>fill(gen_fuel_unit_types,1))
    push!(reserves_metadata_dict, "Direction"=>"Up")

    append!(df_reserves_metadata,reserves_metadata_dict)
    #Down
    reserve_dict = Dict()
    for (idx,val) in enumerate(system["regulation_down_requirement"]["values"])
        push!(reserve_dict, string(idx) => val)
    end
    max_reserve_val = maximum(values(reserve_dict))
    push!(reserve_dict,"DateTime" =>time_stamps[1])
    df = DataFrames.DataFrame(reserve_dict)
    csv_path = joinpath(folder_name,"DAY_AHEAD_regional_Reg_Down.csv")
    CSV.write(csv_path, df,writeheader = true)

    # Pointers Dict
    pointers_dict = Dict()
    push!(pointers_dict,"Simulation" =>"DAY_AHEAD")
    push!(pointers_dict,"Category" =>"Reserve")
    push!(pointers_dict,"Object" =>"Reg_Down")
    push!(pointers_dict,"Parameter" =>"Requirement")
    push!(pointers_dict,"Scaling Factor" =>1)
    push!(pointers_dict,"Data File" =>csv_path)

    append!(df_ts_pointer,pointers_dict)

    # Reserves Metadata Dict
    reserves_metadata_dict = Dict()
    push!(reserves_metadata_dict, "Reserve Product"=>"Reg_Down")
    push!(reserves_metadata_dict, "Timeframe (sec)"=>300) 
    push!(reserves_metadata_dict, "Requirement (MW)"=>max_reserve_val)
    push!(reserves_metadata_dict, "Eligible Regions"=>join(temp,","))
    push!(reserves_metadata_dict, "Eligible Device Categories"=>"Generator")
    push!(reserves_metadata_dict, "Eligible Device SubCategories"=>fill(gen_fuel_unit_types,1))
    push!(reserves_metadata_dict, "Direction"=>"Down")

    append!(df_reserves_metadata,reserves_metadata_dict)

    # Flexible Ramp Up & Down
    # Need to be generalized
    # Up
    reserve_dict = Dict()
    for (idx,val) in enumerate(system["flexible_ramp_up_requirement"]["values"])
        push!(reserve_dict, string(idx) => val)
    end
    max_reserve_val = maximum(values(reserve_dict))
    push!(reserve_dict,"DateTime" =>time_stamps[1])
    df = DataFrames.DataFrame(reserve_dict)
    csv_path = joinpath(folder_name,"DAY_AHEAD_regional_Flex_Up.csv")
    CSV.write(csv_path, df,writeheader = true)

    # Pointers Dict
    pointers_dict = Dict()
    push!(pointers_dict,"Simulation" =>"DAY_AHEAD")
    push!(pointers_dict,"Category" =>"Reserve")
    push!(pointers_dict,"Object" =>"Flex_Up")
    push!(pointers_dict,"Parameter" =>"Requirement")
    push!(pointers_dict,"Scaling Factor" =>1)
    push!(pointers_dict,"Data File" =>csv_path)

    append!(df_ts_pointer,pointers_dict)

    # Reserves Metadata Dict
    reserves_metadata_dict = Dict()
    push!(reserves_metadata_dict, "Reserve Product"=>"Flex_Up")
    push!(reserves_metadata_dict, "Timeframe (sec)"=>1200) 
    push!(reserves_metadata_dict, "Requirement (MW)"=>max_reserve_val)
    push!(reserves_metadata_dict, "Eligible Regions"=>join(temp,","))
    push!(reserves_metadata_dict, "Eligible Device Categories"=>"Generator")
    push!(reserves_metadata_dict, "Eligible Device SubCategories"=>fill(gen_fuel_unit_types,1))
    push!(reserves_metadata_dict, "Direction"=>"Up")

    append!(df_reserves_metadata,reserves_metadata_dict)

    #Down
    reserve_dict = Dict()
    for (idx,val) in enumerate(system["flexible_ramp_down_requirement"]["values"])
        push!(reserve_dict, string(idx) => val)
    end
    max_reserve_val = maximum(values(reserve_dict))
    push!(reserve_dict,"DateTime" =>time_stamps[1])
    df = DataFrames.DataFrame(reserve_dict)
    csv_path = joinpath(folder_name,"DAY_AHEAD_regional_Flex_Down.csv")
    CSV.write(csv_path, df,writeheader = true)

    # Pointers Dict
    pointers_dict = Dict()
    push!(pointers_dict,"Simulation" =>"DAY_AHEAD")
    push!(pointers_dict,"Category" =>"Reserve")
    push!(pointers_dict,"Object" =>"Flex_Down")
    push!(pointers_dict,"Parameter" =>"Requirement")
    push!(pointers_dict,"Scaling Factor" =>1)
    push!(pointers_dict,"Data File" =>csv_path)

    append!(df_ts_pointer,pointers_dict)

    # Reserves Metadata Dict
    reserves_metadata_dict = Dict()
    push!(reserves_metadata_dict, "Reserve Product"=>"Flex_Down")
    push!(reserves_metadata_dict, "Timeframe (sec)"=>1200) 
    push!(reserves_metadata_dict, "Requirement (MW)"=>max_reserve_val)
    push!(reserves_metadata_dict, "Eligible Regions"=>join(temp,","))
    push!(reserves_metadata_dict, "Eligible Device Categories"=>"Generator")
    push!(reserves_metadata_dict, "Eligible Device SubCategories"=>fill(gen_fuel_unit_types,1))
    push!(reserves_metadata_dict, "Direction"=>"Down")

    append!(df_reserves_metadata,reserves_metadata_dict)

    # Generator
    # Filtering components with time series data
    if (gen_components !== nothing)
        hydro_components = []
        pv_components = []
        rtpv_components =[]
        wind_components =[]
        for gen_key in keys(gen_components)
            gen_unit_type = get(gen_components[gen_key],"unit_type","None")

            if (gen_unit_type == "HYDRO")
                push!(hydro_components,gen_key => gen_components[gen_key])
            end
            if (gen_unit_type == "PV")
                push!(pv_components,gen_key => gen_components[gen_key])
            end
            if (gen_unit_type == "RTPV")
                push!(rtpv_components,gen_key => gen_components[gen_key])
            end
            if (gen_unit_type == "WIND")
                push!(wind_components,gen_key => gen_components[gen_key])
            end
        end
        # Call functions for different types of Generator
        gen_unit_dict = Dict([("HYDRO", (hydro_components,make_HYDRO_time_series)), ("PV", (pv_components,make_PV_time_series)),
                            ("RTPV", (rtpv_components, make_RTPV_time_series)),("WIND", (wind_components,make_WIND_time_series))]);
    
        for u_t_key in keys(gen_unit_dict) # in.(keys(gen_unit_dict), Ref(get.(values(gen_components),"unit_type","None")))
            u_t_avail = in(u_t_key, get.(values(gen_components),"unit_type","None"))
            if (u_t_avail)
                folder_name = joinpath(ts_dir_name,u_t_key)
                mkpath(folder_name)
                pointers_dict = gen_unit_dict[u_t_key][2](time_stamps,folder_name,gen_unit_dict[u_t_key][1])
                append!(df_ts_pointer,pointers_dict)
            end
        end
    end
    # Loads
    if (loads !== nothing)
        df = DataFrames.DataFrame()
        df[!,"DateTime"] = time_stamps 

        for key in keys(area_bus_mapping_dict)
            area_loads = filter(!isnothing,get.(Ref(loads),area_bus_mapping_dict[key],nothing)) # cannot directly broacast without filter because not all buses have loads
            sum_area_load = sum(get.(get.(area_loads,"p_load",0),"values",0))

            df[!,key] = sum_area_load
        end
        folder_name = joinpath(ts_dir_name,"LOAD")
        mkpath(folder_name)
        # Export CSV
        csv_path = joinpath(folder_name,"DAY_AHEAD_regional_Load.csv")
        CSV.write(csv_path, df,writeheader = true)

        # Pointers Dict
        num_areas = length(keys(area_bus_mapping_dict))
        pointers_dict = Dict()
        push!(pointers_dict,"Simulation" =>fill("DAY_AHEAD",num_areas))
        push!(pointers_dict,"Category" =>fill("Area",num_areas))
        push!(pointers_dict,"Object" =>collect(keys(area_bus_mapping_dict)))
        push!(pointers_dict,"Parameter" =>fill("p_load",num_areas))
        push!(pointers_dict,"Scaling Factor" =>fill(1,num_areas))
        push!(pointers_dict,"Data File" =>fill(csv_path,num_areas))

        append!(df_ts_pointer,pointers_dict)
    end

    # Export timeseries_pointers CSV
    csv_path = joinpath(dir_name,"timeseries_pointers.csv")
    CSV.write(csv_path, df_ts_pointer,writeheader = true)

    # Export reserves metadata CSV
    csv_path = joinpath(dir_name,"reserves.csv")
    CSV.write(csv_path, df_reserves_metadata,writeheader = true)
    
    # Export simulation objects CSV
    simulation_objects_dict = Dict()
    push!(simulation_objects_dict, "Simulation_Parameters" => ["Periods_per_Step","Period_Resolution","Date_From","Date_To","Look_Ahead_Periods_per_Step","Look_Ahead_Resolution","Reserve_Products"])
    period_resolution = (Dates.Second(last(time_stamps) - first(time_stamps)))/(length(time_stamps)-1)
    reserve_types = ["Flex_Up", "Flex_Down", "Spin_Up", "Reg_Up", "Reg_Down"]
    push!(simulation_objects_dict,"DAY_AHEAD" => [length(time_stamps), period_resolution.value,first(time_stamps),last(time_stamps),length(time_stamps), period_resolution.value,reserve_types])

    append!(df_simulation_objects,simulation_objects_dict)
    
    csv_path = joinpath(dir_name,"simulation_objects.csv")
    CSV.write(csv_path, df_simulation_objects,writeheader = true)
end
#####################################################################################
# Functions to parse EGRET Bus
# Note: Load MW and Load MVAR assigned as max of the time series data.
#####################################################################################
function parse_EGRET_bus(components::Dict{String,Any},loads::Dict{String, Any},dir_name::String;shunt::Union{Nothing, Dict{String, Any}} = nothing)
    comp_dict = Dict()
    comp_names = collect(keys(components))
    push!(comp_dict, "Name" => comp_names)
    comp_dict_values = values(components)

    for comp_field in keys(first(comp_dict_values))
        push!(comp_dict, comp_field => get.(comp_dict_values,comp_field,"None"))    
    end
    
    # Parse Shunt elements
    if (shunt !== nothing)
        branch_shunt_dicts = get.(Ref(shunt),comp_names,0)
        branch_shunt_vals = []
        for shunt_dict in branch_shunt_dicts
            if (shunt_dict != 0)
                push!(branch_shunt_vals, get(shunt_dict,"bs","None"))
            else
                push!(branch_shunt_vals, 0)
            end
        end 
        push!(comp_dict,"MVAR Shunt" => branch_shunt_vals) 
    end

    # Include MW Shunt G column
    push!(comp_dict,"MW Shunt G" => zeros(Int64, length(comp_dict_values)))

    # Parse loads
    ts_flag = 0
    load_dicts = get.(Ref(loads),comp_names,0)
    mw_load_vals = []
    mvar_load_vals = []

    for load_dict in load_dicts
        if (load_dict != 0)
            push!(mw_load_vals, maximum(get(get(load_dict,"p_load","None"),"values","None")))
            push!(mvar_load_vals, maximum(get(get(load_dict,"q_load","None"),"values","None")))
            ts_flag +=1
        else
            push!(mw_load_vals, 0)
            push!(mvar_load_vals, 0)
        end
    end 
    push!(comp_dict,"MW Load" => mw_load_vals) 
    push!(comp_dict,"MVAR Load" => mvar_load_vals) 

    df = DataFrames.DataFrame(comp_dict)
    
    # Export CSV
    csv_path = joinpath(dir_name,"bus.csv")
    CSV.write(csv_path, df,writeheader = true,transform = (col, val) -> something(val, missing))

    # Make a mapping Dict from Area => Bus Name
    area_names = unique(get.(comp_dict_values,"area","None"))
    area_bus_mapping_dict = Dict()
    for area_name in area_names
        push!(area_bus_mapping_dict,area_name =>String[])
    end
    for name in comp_names
        push!(area_bus_mapping_dict[get(components[name],"area","None")],name)
    end

    # Make a mapping Dict from Bus Name => Bus ID.
    bus_name_id_mapping_dict = Dict()
    for (name,id) in zip(get(comp_dict,"Name","None"),get(comp_dict,"id","None")) 
        push!(bus_name_id_mapping_dict, name => id) 
    end
    # Time series availability
    flag = false
    if (ts_flag >0)
        flag = true
    else
        flag = false
    end

    return bus_name_id_mapping_dict,area_bus_mapping_dict,flag
end
#####################################################################################
# Functions to parse EGRET Branch
# Add IDs for from and to and check with original source data
#####################################################################################
function parse_EGRET_branch(components::Dict{String,Any},mapping_dict::Dict{Any,Any},dir_name::String)
    comp_dict = Dict()
    comp_names = collect(keys(components))
    push!(comp_dict, "Name" => comp_names)
    comp_dict_values = values(components)

    for comp_field in keys(first(comp_dict_values))
        push!(comp_dict, comp_field => get.(comp_dict_values,comp_field,"None"))    
    end

    # Replace bus names with Bus IDs using mapping dict
    from_bus_ids = getindex.(Ref(mapping_dict),comp_dict["from_bus"])
    to_bus_ids = getindex.(Ref(mapping_dict),comp_dict["to_bus"])
    delete!(comp_dict,"from_bus")
    delete!(comp_dict,"to_bus")
    push!(comp_dict,"from_bus" => from_bus_ids)
    push!(comp_dict,"to_bus" => to_bus_ids)

    # Handle Transformers
    Tr_Ratio_vals = []
    for comp_dict_value in comp_dict_values
        tap = get(comp_dict_value,"transformer_tap_ratio","None")
        if tap isa Number
            push!(Tr_Ratio_vals,tap)
        else
            push!(Tr_Ratio_vals,0)
        end
    end

    if ("transformer_tap_ratio" in keys(comp_dict))
        delete!(comp_dict,"transformer_tap_ratio")
    end
    push!(comp_dict,"Tr Ratio" => Tr_Ratio_vals)

    df = DataFrames.DataFrame(comp_dict)
    
    # Export CSV
    csv_path = joinpath(dir_name,"branch.csv")
    CSV.write(csv_path, df,writeheader = true,transform = (col, val) -> something(val, missing))
end
#####################################################################################
# Functions to parse EGRET Generator
# **Note EGRET doesn't handle CSP units. SO, if there are any CSP units in the root dataset,
# they will not show up in the converted PSY System!
#####################################################################################
function parse_EGRET_generator(components::Dict{String,Any},mapping_dict::Dict{Any,Any},dir_name::String)
    comp_dict = Dict()
    comp_names = collect(keys(components))
    push!(comp_dict, "Name" => comp_names)
    comp_dict_values = values(components)

    for comp_field in keys(first(comp_dict_values))
        if(~(comp_field in ["p_fuel" , "startup_fuel","p_max", "p_min"])) # These are handled differently.
            push!(comp_dict, comp_field => get.(comp_dict_values,comp_field,"None"))
        end
    end

    # Include Generator Category
    gen_categories = get.(comp_dict_values,"fuel","None").*" ".*get.(comp_dict_values,"unit_type","None")
    push!(comp_dict,"category" => gen_categories)

    # Replace bus names with Bus IDs using mapping dict
    bus_ids = getindex.(Ref(mapping_dict),comp_dict["bus"])
    delete!(comp_dict,"bus")
    push!(comp_dict,"bus" => bus_ids)

    # Parse p_max and p_min
    gen_ts_flag = parse_p_minmax!(comp_dict_values,comp_dict)
    
    # Parse fuel_dict
    fuel_dicts = get.(comp_dict_values,"p_fuel","None");
    num_data_points = maximum([length(fuel_dict["values"]) for fuel_dict in fuel_dicts if fuel_dict !="None"])
    parse_fuel_dict!(comp_dict_values,comp_dict,num_data_points)
    
    # Parse startupfuel_dict
    parse_startup_fuel_dict!(comp_dict_values,comp_dict)

    df = DataFrames.DataFrame(comp_dict)
    
    # Export CSV
    csv_path = joinpath(dir_name,"gen.csv")
    CSV.write(csv_path, df,writeheader = true,transform = (col, val) -> something(val, missing))

    return gen_ts_flag
end
#####################################################################################
# Main Function to parse EGRET JSON
# Questions:
# 1) Scaling factor for time series
# 2) Missing CSP, Storage etc.
# 3) Qualifying generators for reserves
# 4) read in CSV we exported and make a EGRET System and compare
# 5) Other ways to store time series. 
# 6) Startup fuel dict values (322_CT_6 example).
#####################################################################################
function parse_EGRET_JSON(EGRET_json::Dict{String, Any};location::Union{Nothing, String} = nothing) 
    # Initial Checks

    if (~("elements" in keys(EGRET_json)) || ~("system" in keys(EGRET_json)))
        error("Please check the EGRET System JSON")
    end

    #kwargs handling
    if (location === nothing)
        location =dirname(dirname(@__DIR__))
        @warn  "Location to save the exported tabular data not specified. Using the Converted_CSV_Files folder of the module."
    end
    
    dt_now = Dates.format(Dates.now(),"dd-u-yy-H-M-S");
    dir_name = joinpath(location,"data","Converted_CSV_Files",dt_now,EGRET_json["system"]["name"])

    if (~isdir(dir_name))
        mkpath(dir_name)
    end
    
    # Parsing different elements in EGRET System
    # Bus
    bus_mapping_dict, area_mapping_dict, load_ts_flag = 
    if ("bus" in keys(EGRET_json["elements"]))
        if ("shunt" in keys(EGRET_json["elements"]))
            parse_EGRET_bus(EGRET_json["elements"]["bus"],EGRET_json["elements"]["load"],dir_name,shunt = EGRET_json["elements"]["shunt"])
        else
            parse_EGRET_bus(EGRET_json["elements"]["bus"],EGRET_json["elements"]["load"],dir_name)
        end
    else
        error("No buses in the EGRET System JSON")
    end

    # Branch
    if ("branch" in keys(EGRET_json["elements"]))
        parse_EGRET_branch(EGRET_json["elements"]["branch"],bus_mapping_dict,dir_name)
    else
        error("No branches in the EGRET System JSON")
    end

    # Generator
    gen_ts_flag = 
    if ("generator" in keys(EGRET_json["elements"]))
        parse_EGRET_generator(EGRET_json["elements"]["generator"],bus_mapping_dict,dir_name)
    else
        error("No generators in the EGRET System JSON")
    end

    # Calling time series processing functions
    if (load_ts_flag && gen_ts_flag)
        time_series_processing(dir_name,EGRET_json["elements"]["area"],EGRET_json["system"],loads = EGRET_json["elements"]["load"],gen_components=EGRET_json["elements"]["generator"],
                                  area_bus_mapping_dict=area_mapping_dict)
    elseif load_ts_flag
        time_series_processing(dir_name,EGRET_json["elements"]["area"],EGRET_json["system"],loads = EGRET_json["elements"]["load"],area_bus_mapping_dict=area_mapping_dict)
    elseif gen_ts_flag
        time_series_processing(dir_name,EGRET_json["elements"]["area"],EGRET_json["system"],gen_components=EGRET_json["elements"]["generator"])
    else
        @warn "No generator and load time series data available in the EGRET JSON"
    end

    @info "Successfully generated CSV files compatible with SIIP PSY tabular data parser here : $(dir_name)."

    return dir_name
end

