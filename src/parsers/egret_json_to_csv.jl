#####################################################
# Surya
# NREL
# October 2023
# Script to generate csv's from EGRET System JSON
# Generate component CSV Sienna tabular parser expects from EGRET System JSON
#####################################################################################
# Auxilary Function
# Convert DataFrames.DataFrame to JSON
# Convert timeseries_pointers.csv to timeseries_pointers.JSON
#####################################################################################
function df_to_json(df::DataFrames.DataFrame,dir_name::String)
    df[!,"normalization_factor"] .= "max"
    pointers_dict = []
    for row in eachrow(df)
        push!(pointers_dict,Dict(fn=>get(row, fn,nothing) for fn ∈ DataFrames.names(df)))
    end
    
    ts_json_location = joinpath(dir_name,"timeseries_pointers.json")
    
    open(ts_json_location,"w") do f
        JSON.print(f, pointers_dict, 4)
    end
end
# Check if a file passed is JSON file
isjson = endswith(".json");
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
                        HR_temp= ((fuel_dict["values"][i][2] - fuel_dict["values"][i-1][2])/(fuel_dict["values"][i][1] - fuel_dict["values"][i-1][1]))*1000
                        push!(comp_dict["HR_avg_$(i-1)"],HR_temp)
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
                        HR_temp= ((fuel_dict["values"][i][2] - fuel_dict["values"][i-1][2])/(fuel_dict["values"][i][1] - fuel_dict["values"][i-1][1]))*1000
                        push!(comp_dict["HR_avg_$(i-1)"],HR_temp)
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

    lookup_dict = Dict([(1, ("Start Time Cold Hr","Start Heat Cold MBTU")), (2, ("Start Time Warm Hr","Start Heat Warm MBTU")),
                       (3, ("Start Time Hot Hr","Start Heat Hot MBTU"))]);

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
# Common function to make CSV's related to generator time series data
#####################################################################################
function make_gen_time_series!(time_stamps_DA::Vector{Dates.DateTime},dir_name::String,components_DA::Vector{Any},df_ts_pointer::DataFrames.DataFrame,gen_type::String;
                                time_stamps_RT::Union{Nothing, Vector{Dates.DateTime}} = nothing,components_RT::Union{Nothing, Vector{Any}} = nothing)

    ts_resolution_DA = (Dates.Second(last(time_stamps_DA) - first(time_stamps_DA)))/(length(time_stamps_DA)-1)
    if (time_stamps_RT !== nothing)
        ts_resolution_RT = (Dates.Second(last(time_stamps_RT) - first(time_stamps_RT)))/(length(time_stamps_RT)-1)
    end

    # Check if RT components are passed
    comps_dict = Dict("DAY_AHEAD" => (components_DA,time_stamps_DA,ts_resolution_DA.value))
    if (components_RT !== nothing)
        push!(comps_dict,"REAL_TIME" => (components_RT,time_stamps_RT,ts_resolution_RT.value))
    end
    for comp_key in keys(comps_dict)
        df = DataFrames.DataFrame()

        df[!,"DateTime"] = comps_dict[comp_key][2]
        comp_names = []
        comp_p_max = []
        for idx in 1:length(comps_dict[comp_key][1])
            df[!,comps_dict[comp_key][1][idx][1]] =  get(comps_dict[comp_key][1][idx][2],"p_max","None")["values"]
            push!(comp_names,comps_dict[comp_key][1][idx][1])
            push!(comp_p_max,maximum(df[!,comps_dict[comp_key][1][idx][1]]))
        end
        # Export CSV
        csv_path = joinpath(dir_name,comp_key*"_"*gen_type*".csv")
        CSV.write(csv_path, df,writeheader = true)

        # Pointers Dict
        num_components = length(comp_names)
        pointers_dict = Dict()
        push!(pointers_dict,"simulation" =>fill(comp_key,num_components))
        push!(pointers_dict,"resolution" =>fill(comps_dict[comp_key][3],num_components))
        push!(pointers_dict,"category" =>"Generator")
        push!(pointers_dict,"component_name" =>comp_names)
        push!(pointers_dict,"module" =>"PowerSystems")
        push!(pointers_dict,"type" =>"SingleTimeSeries")
        push!(pointers_dict,"name" =>"max_active_power")
        push!(pointers_dict,"scaling_factor_multiplier" =>"get_max_active_power")
        push!(pointers_dict,"scaling_factor_multiplier_module" =>"PowerSystems")
        push!(pointers_dict,"normalization_factor" =>comp_p_max)
        push!(pointers_dict,"data_file" =>fill(csv_path,num_components))
        
        append!(df_ts_pointer,pointers_dict)
    end
end
#####################################################################################
# Parse time series data
# **TODO: Need to be generaized to handle RT Systems and reserves
#####################################################################################
function time_series_processing(dir_name::String,areas_DA::Dict{String, Any},system_DA::Dict{String, Any};loads_DA::Union{Nothing, Dict{String, Any}} = nothing,
                                area_bus_mapping_dict::Union{Nothing, Dict{Any, Any}} = nothing,gen_components_DA::Union{Nothing, Dict{String, Any}} = nothing,
                                areas_RT::Union{Nothing, Dict{String, Any}} = nothing,system_RT::Union{Nothing, Dict{String, Any}} = nothing,
                                loads_RT::Union{Nothing, Dict{String, Any}} = nothing,gen_components_RT::Union{Nothing, Dict{String, Any}} = nothing)
    #Time stamp processing
    # Day-Ahead
    rt_flag = false

    date_format = Dates.DateFormat("Y-m-d H:M")
    time_stamps_DA = Dates.DateTime.(system_DA["time_keys"],date_format)
    ts_resolution_DA = (Dates.Second(last(time_stamps_DA) - first(time_stamps_DA)))/(length(time_stamps_DA)-1)

    # Real-Time
    if (system_RT !== nothing)
        time_stamps_RT = Dates.DateTime.(system_RT["time_keys"],date_format)
        ts_resolution_RT = (Dates.Second(last(time_stamps_RT) - first(time_stamps_RT)))/(length(time_stamps_RT)-1)
    end

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
    #**TODO - This currently assumes every EGRET JSON passed has all the reserve products RTS_GMLC has. There is an easy fix for this.
    gen_fuel_unit_types = [u_t for u_t in unique(get.(values(gen_components_DA),"fuel","None").*" ".*get.(values(gen_components_DA),"unit_type","None")) 
                                if ~(u_t in ["Sync_Cond SYNC_COND","Nuclear NUCLEAR", "Solar RTPV"])]
    gen_fuel_unit_types = "("*join(gen_fuel_unit_types,",")*")"

    all_areas_DA = "("*join(collect(keys(areas_DA)),",")*")"

    # Spinning Reserves
    folder_name = joinpath(ts_dir_name,"RESERVES")
    mkpath(folder_name)
    # Check if RT System is passed
    areas_dict = Dict("DAY_AHEAD" => (areas_DA,time_stamps_DA,ts_resolution_DA.value))
    if (areas_RT !== nothing)
        push!(areas_dict,"REAL_TIME" => (areas_RT,time_stamps_RT,ts_resolution_RT.value))
    end

    for area_key in keys(areas_dict)
        object_names = []
        data_files = []
        region_max_values = []
        for (idx,key) in enumerate(keys(areas_dict[area_key][1]))
            df = DataFrames.DataFrame()
            df[!,"DateTime"] = areas_dict[area_key][2]
            column_name = "Spin_Up_R"*"$idx"
            push!(object_names,column_name)
            df[!,column_name] = areas_dict[area_key][1][key]["spinning_reserve_requirement"]["values"]
            push!(region_max_values,maximum(areas_dict[area_key][1][key]["spinning_reserve_requirement"]["values"]))

            # Export CSV
            csv_name = area_key*"_regional_Spin_Up_R"* "$idx" *".csv"
            csv_path = joinpath(folder_name,csv_name)
            push!(data_files,csv_path)
            CSV.write(csv_path, df,writeheader = true)
        end
        # Pointers Dict
        num_areas = length(keys(area_bus_mapping_dict))
        # Timeseries pointers Dict to build the necessary CSV
        pointers_dict = Dict()
        push!(pointers_dict,"simulation" =>fill(area_key,num_areas))
        push!(pointers_dict,"resolution" =>fill(areas_dict[area_key][3],num_areas))
        push!(pointers_dict,"category" =>"Reserve")
        push!(pointers_dict,"component_name" =>object_names)
        push!(pointers_dict,"module" =>"PowerSystems")
        push!(pointers_dict,"type" =>"SingleTimeSeries")
        push!(pointers_dict,"name" =>"requirement")
        push!(pointers_dict,"scaling_factor_multiplier" =>"get_requirement")
        push!(pointers_dict,"scaling_factor_multiplier_module" =>"PowerSystems")
        push!(pointers_dict,"normalization_factor" =>region_max_values)
        push!(pointers_dict,"data_file" =>data_files)

        append!(df_ts_pointer,pointers_dict)

        # Reserves Metadata Dict
        if (area_key =="DAY_AHEAD")
            # Reserves Metadata Dict to build the necessary CSV
            reserves_metadata_dict = Dict()

            push!(reserves_metadata_dict, "Reserve Product"=>object_names)
            push!(reserves_metadata_dict, "Timeframe (sec)"=>fill(600,num_areas)) 
            push!(reserves_metadata_dict, "Requirement (MW)"=>region_max_values)
            push!(reserves_metadata_dict, "Eligible Regions"=>collect(keys(areas_DA)))
            push!(reserves_metadata_dict, "Eligible Device Categories"=>fill("Generator",num_areas))
            push!(reserves_metadata_dict, "Eligible Device SubCategories"=>fill(gen_fuel_unit_types,num_areas))
            push!(reserves_metadata_dict, "Direction"=>fill("Up",num_areas))

            append!(df_reserves_metadata,reserves_metadata_dict)
        end
    end

    # Regulation Up & Down
    # Up & Down
    # Check if RT System is passed
    reg_dir_dict = Dict([("Up", ("regulation_up_requirement","_regional_Reg_Up.csv","Reg_Up")), ("Down", ("regulation_down_requirement","_regional_Reg_Down.csv","Reg_Down"))]);
    
    regulation_dict = Dict("DAY_AHEAD" => (system_DA,time_stamps_DA,24,ts_resolution_DA.value))
    if (system_RT !== nothing)
        push!(regulation_dict,"REAL_TIME" => (system_RT,time_stamps_RT,288,ts_resolution_RT.value))
    end
    for dir in keys(reg_dir_dict)
        for reg_up_key in keys(regulation_dict)
            df = DataFrames.DataFrame()
            max_reserve_vals = []
            for i in 1:length(regulation_dict[reg_up_key][2])÷ regulation_dict[reg_up_key][3]
                reserve_dict = Dict()
                start_data_range = ((i-1)*regulation_dict[reg_up_key][3] +1)
                data_range = range(start_data_range,length=regulation_dict[reg_up_key][3])
                start_ts = regulation_dict[reg_up_key][2][start_data_range]
                for (idx,val) in enumerate(regulation_dict[reg_up_key][1][reg_dir_dict[dir][1]]["values"][data_range])
                    push!(reserve_dict, string(idx) => val)
                end
                max_reserve_val = maximum(values(reserve_dict))
                push!(max_reserve_vals,max_reserve_val)
                year_value = Dates.Year(start_ts).value
                month_value = Dates.Month(start_ts).value
                day_value = Dates.Day(start_ts).value
                push!(reserve_dict,"Year" =>year_value)
                push!(reserve_dict,"Month" => month_value)
                push!(reserve_dict,"Day" =>day_value)

                append!(df,reserve_dict)
            end
            csv_path = joinpath(folder_name,reg_up_key*reg_dir_dict[dir][2])
            CSV.write(csv_path, df,writeheader = true)

            # Pointers Dict
            pointers_dict = Dict()
            push!(pointers_dict,"simulation" =>reg_up_key)
            push!(pointers_dict,"resolution" =>regulation_dict[reg_up_key][4])
            push!(pointers_dict,"category" =>"Reserve")
            push!(pointers_dict,"component_name" =>reg_dir_dict[dir][3])
            push!(pointers_dict,"module" =>"PowerSystems")
            push!(pointers_dict,"type" =>"SingleTimeSeries")
            push!(pointers_dict,"name" =>"requirement")
            push!(pointers_dict,"scaling_factor_multiplier" =>"get_requirement")
            push!(pointers_dict,"scaling_factor_multiplier_module" =>"PowerSystems")
            push!(pointers_dict,"normalization_factor" =>maximum(max_reserve_vals))
            push!(pointers_dict,"data_file" =>csv_path)

            append!(df_ts_pointer,pointers_dict)
            if (reg_up_key =="DAY_AHEAD")
                # Reserves Metadata Dict
                reserves_metadata_dict = Dict()
                push!(reserves_metadata_dict, "Reserve Product"=>reg_dir_dict[dir][3])
                push!(reserves_metadata_dict, "Timeframe (sec)"=>300) 
                push!(reserves_metadata_dict, "Requirement (MW)"=>maximum(max_reserve_vals))
                push!(reserves_metadata_dict, "Eligible Regions"=>all_areas_DA)
                push!(reserves_metadata_dict, "Eligible Device Categories"=>"Generator")
                push!(reserves_metadata_dict, "Eligible Device SubCategories"=>gen_fuel_unit_types)
                push!(reserves_metadata_dict, "Direction"=>dir)

                append!(df_reserves_metadata,reserves_metadata_dict)
            end
        end
    end

    # Flexible Ramp Up & Down
    # Not available for RT System (must be handled)
    # Up
    flex_dir_dict = Dict([("Up", ("flexible_ramp_up_requirement","_regional_Flex_Up.csv","Flex_Up")), ("Down", ("flexible_ramp_down_requirement","_regional_Flex_Down.csv","Flex_Down"))]);

    for dir in keys(flex_dir_dict)
        df = DataFrames.DataFrame()
        max_reserve_vals = []
        for i in 1:length(time_stamps_DA)÷ 24
            reserve_dict = Dict()
            start_data_range = ((i-1)*24 +1)
            data_range = range(start_data_range,length=24)
            start_ts = time_stamps_DA[start_data_range]
            for (idx,val) in enumerate(system_DA[flex_dir_dict[dir][1]]["values"][data_range])
                push!(reserve_dict, string(idx) => val)
            end
            max_reserve_val = maximum(values(reserve_dict))
            push!(max_reserve_vals,max_reserve_val)
            year_value = Dates.Year(start_ts).value
            month_value = Dates.Month(start_ts).value
            day_value = Dates.Day(start_ts).value
            push!(reserve_dict,"Year" =>year_value)
            push!(reserve_dict,"Month" => month_value)
            push!(reserve_dict,"Day" =>day_value)

            append!(df,reserve_dict)
        end
        csv_path = joinpath(folder_name,"DAY_AHEAD"*flex_dir_dict[dir][2])
        CSV.write(csv_path, df,writeheader = true)

        # Pointers Dict
        pointers_dict = Dict()
        push!(pointers_dict,"simulation" =>"DAY_AHEAD")
        push!(pointers_dict,"resolution" =>ts_resolution_DA.value)
        push!(pointers_dict,"category" =>"Reserve")
        push!(pointers_dict,"component_name" =>flex_dir_dict[dir][3])
        push!(pointers_dict,"module" =>"PowerSystems")
        push!(pointers_dict,"type" =>"SingleTimeSeries")
        push!(pointers_dict,"name" =>"requirement")
        push!(pointers_dict,"scaling_factor_multiplier" =>"get_requirement")
        push!(pointers_dict,"scaling_factor_multiplier_module" =>"PowerSystems")
        push!(pointers_dict,"normalization_factor" =>maximum(max_reserve_vals))
        push!(pointers_dict,"data_file" =>csv_path)

        append!(df_ts_pointer,pointers_dict)

        # Reserves Metadata Dict
        reserves_metadata_dict = Dict()
        push!(reserves_metadata_dict, "Reserve Product"=>flex_dir_dict[dir][3])
        push!(reserves_metadata_dict, "Timeframe (sec)"=>1200) 
        push!(reserves_metadata_dict, "Requirement (MW)"=>maximum(max_reserve_vals))
        push!(reserves_metadata_dict, "Eligible Regions"=>all_areas_DA)
        push!(reserves_metadata_dict, "Eligible Device Categories"=>"Generator")
        push!(reserves_metadata_dict, "Eligible Device SubCategories"=>gen_fuel_unit_types)
        push!(reserves_metadata_dict, "Direction"=>dir)

        append!(df_reserves_metadata,reserves_metadata_dict)
    end

    # Generator
    # Filtering components with time series data
    if (gen_components_DA !== nothing)
        #DA
        hydro_components_DA = []
        pv_components_DA = []
        rtpv_components_DA =[]
        wind_components_DA =[]
        #RT
        hydro_components_RT = []
        pv_components_RT = []
        rtpv_components_RT =[]
        wind_components_RT =[]
        for gen_key in keys(gen_components_DA)
            gen_unit_type = get(gen_components_DA[gen_key],"unit_type","None")

            if (gen_unit_type == "HYDRO")
                push!(hydro_components_DA,gen_key => gen_components_DA[gen_key])
            end
            if (gen_unit_type == "PV")
                push!(pv_components_DA,gen_key => gen_components_DA[gen_key])
            end
            if (gen_unit_type == "RTPV")
                push!(rtpv_components_DA,gen_key => gen_components_DA[gen_key])
            end
            if (gen_unit_type == "WIND")
                push!(wind_components_DA,gen_key => gen_components_DA[gen_key])
            end
        end
        if (gen_components_RT!== nothing)
            for gen_key in keys(gen_components_RT)
                gen_unit_type = get(gen_components_RT[gen_key],"unit_type","None")

                if (gen_unit_type == "HYDRO")
                    push!(hydro_components_RT,gen_key => gen_components_RT[gen_key])
                end
                if (gen_unit_type == "PV")
                    push!(pv_components_RT,gen_key => gen_components_RT[gen_key])
                end
                if (gen_unit_type == "RTPV")
                    push!(rtpv_components_RT,gen_key => gen_components_RT[gen_key])
                end
                if (gen_unit_type == "WIND")
                    push!(wind_components_RT,gen_key => gen_components_RT[gen_key])
                end
            end
        end
        # Call functions for different types of Generator
        gen_unit_dict = Dict([("HYDRO", (hydro_components_DA,hydro_components_RT)), ("PV", (pv_components_DA,pv_components_RT)),
                             ("RTPV", (rtpv_components_DA,rtpv_components_RT)),("WIND", (wind_components_DA,wind_components_RT))]);
    
        for u_t_key in keys(gen_unit_dict) # in.(keys(gen_unit_dict), Ref(get.(values(gen_components),"unit_type","None")))
            u_t_avail = in(u_t_key, get.(values(gen_components_DA),"unit_type","None"))
            if (u_t_avail)
                folder_name = joinpath(ts_dir_name,u_t_key)
                mkpath(folder_name)
                if (length(gen_unit_dict[u_t_key][2]) > 0)
                    make_gen_time_series!(time_stamps_DA,folder_name,gen_unit_dict[u_t_key][1],df_ts_pointer,u_t_key,time_stamps_RT= time_stamps_RT,components_RT = gen_unit_dict[u_t_key][2])
                else
                    make_gen_time_series!(time_stamps_DA,folder_name,gen_unit_dict[u_t_key][1],df_ts_pointer,u_t_key)
                end
            end
        end
    end
    # Loads
    if (loads_DA !== nothing)
        folder_name = joinpath(ts_dir_name,"LOAD")
        mkpath(folder_name)

        loads_dict = Dict("DAY_AHEAD" => (loads_DA,time_stamps_DA,ts_resolution_DA.value))
        if (loads_RT !== nothing)
            push!(loads_dict,"REAL_TIME" => (loads_RT,time_stamps_RT,ts_resolution_RT.value))
        end
        for load_key in keys(loads_dict)
            df = DataFrames.DataFrame()
            df[!,"DateTime"] = loads_dict[load_key][2]
            reg_load_max_vals = []
            for key in keys(area_bus_mapping_dict)
                area_loads = filter(!isnothing,get.(Ref(loads_dict[load_key][1]),area_bus_mapping_dict[key],nothing)) # cannot directly broacast without filter because not all buses have loads
                filtered_area_load_vals  = get.(get.(area_loads,"p_load",0),"values",0)
                sum_area_load = sum(filtered_area_load_vals)
                push!(reg_load_max_vals, maximum(sum_area_load))

                df[!,key] = sum_area_load
            end
            
            # Export CSV
            csv_path = joinpath(folder_name,load_key*"_regional_Load.csv")
            CSV.write(csv_path, df,writeheader = true)

            # Pointers Dict
            num_areas = length(keys(area_bus_mapping_dict))
            pointers_dict = Dict()
            push!(pointers_dict,"simulation" =>fill(load_key,num_areas))
            push!(pointers_dict,"resolution" =>fill(loads_dict[load_key][3],num_areas))
            push!(pointers_dict,"category" =>"Area")
            push!(pointers_dict,"component_name" =>collect(keys(area_bus_mapping_dict)))
            push!(pointers_dict,"module" =>"PowerSystems")
            push!(pointers_dict,"type" =>"SingleTimeSeries")
            push!(pointers_dict,"name" =>"max_active_power")
            push!(pointers_dict,"scaling_factor_multiplier" =>"get_max_active_power")
            push!(pointers_dict,"scaling_factor_multiplier_module" =>"PowerSystems")
            push!(pointers_dict,"normalization_factor" =>reg_load_max_vals)
            push!(pointers_dict,"data_file" =>fill(csv_path,num_areas))

            append!(df_ts_pointer,pointers_dict)
        end
    end

    # Export timeseries_pointers CSV
    csv_path = joinpath(dir_name,"timeseries_pointers.csv")
    CSV.write(csv_path, df_ts_pointer,writeheader = true)

    # Export timeseries_pointers JSON
    df_to_json(df_ts_pointer,dir_name)

    # Export reserves metadata CSV
    csv_path = joinpath(dir_name,"reserves.csv")
    CSV.write(csv_path, df_reserves_metadata,writeheader = true)
    
    # Export simulation objects CSV
    simulation_objects_dict = Dict()
    push!(simulation_objects_dict, "Simulation_Parameters" => ["Periods_per_Step","Period_Resolution","Date_From","Date_To","Look_Ahead_Periods_per_Step",
                                   "Look_Ahead_Resolution","Reserve_Products"])
    reserve_types_DA = ["Flex_Up", "Flex_Down", "Spin_Up", "Reg_Up", "Reg_Down"]
    reserve_types_DA = "("*join(reserve_types_DA,",")*")"

    reserve_types_RT = ["Spin_Up", "Reg_Up", "Reg_Down"]
    reserve_types_RT = "("*join(reserve_types_RT,",")*")"

    push!(simulation_objects_dict,"DAY_AHEAD" => [24, ts_resolution_DA.value,first(time_stamps_DA),last(time_stamps_DA),24, ts_resolution_DA.value,reserve_types_DA])
    if (system_RT !== nothing)
        push!(simulation_objects_dict,"REAL_TIME" => [1, ts_resolution_RT.value,first(time_stamps_DA),last(time_stamps_DA),2, ts_resolution_RT.value,reserve_types_RT])
        rt_flag = true
    end

    append!(df_simulation_objects,simulation_objects_dict)
    
    csv_path = joinpath(dir_name,"simulation_objects.csv")
    CSV.write(csv_path, df_simulation_objects,writeheader = true)

    if(rt_flag == true)
        @info "Successfully parsed DA and RT Systems time series data."
    else
        @info "Successfully parsed DA System time series data."
    end
    return rt_flag
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
    
    @info "Successfully parsed buses in the JSON."
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

    @info "Successfully parsed branches in the JSON."
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

        if(comp_field in ["agc_capable","area","bus","fuel","generator_type","in_service","mbase","ramp_q","unit_type","zone"]) # These should return 'nothing' if not available
            push!(comp_dict, comp_field => get.(comp_dict_values,comp_field,nothing))
        end
    
        if(comp_field in ["fuel_cost", "initial_p_output","initial_q_output","initial_status","min_down_time","min_up_time", "non_fuel_startup_cost","p_max_agc","p_min_agc",
                         "pg", "qg","ramp_agc","ramp_down_60min","ramp_up_60min","shutdown_capacity","shutdown_cost","startup_capacity"]) # These should return '0' if not available
            push!(comp_dict, comp_field => get.(comp_dict_values,comp_field,0))
        end
    end

    # Change the "initial_status" and "initial_p_output" columns so tabular data can understand
    comp_dict["initial_status"] = floor.(Int64,abs.(comp_dict["initial_status"]))
    gen_initial_p = Bool[]
    for p in comp_dict["initial_p_output"]
        p>0 ? push!(gen_initial_p,true) : push!(gen_initial_p,false) 
    end
    delete!(comp_dict,"initial_p_output")
    push!(comp_dict,"initial_p_output" =>gen_initial_p)

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
    
    @info "Successfully parsed generators in the JSON."
    return gen_ts_flag
end
#####################################################################################
# Main Function to parse EGRET JSON
#####################################################################################
function parse_egretjson(EGRET_json_DA_location::String;EGRET_json_RT_location::Union{Nothing, String} = nothing,export_location::Union{Nothing, String} = nothing) 
    # Initial Checks
    if (~isjson(EGRET_json_DA_location))
        error("Please check the EGRET DA System JSON location passed, make sure it is a JSON file.")
    end

    EGRET_json_DA = 
    try 
        JSON.parsefile(EGRET_json_DA_location)
    catch
        error("Cannot parse the EGRET DA System JSON.")
    end
       
    if (~(haskey(EGRET_json_DA, "elements")) || ~(haskey(EGRET_json_DA, "system")))
        error("Please check the EGRET DA System JSON")
    end

    EGRET_json_RT = nothing
    if (EGRET_json_RT_location !== nothing)

        if (~isjson(EGRET_json_RT_location))
            error("Please check the EGRET RT System JSON location passed, make sure it is a JSON file.")
        end

        EGRET_json_RT = 
        try 
            JSON.parsefile(EGRET_json_RT_location)
        catch
            error("Cannot parse the EGRET RT System JSON.")
        end

        if (~(haskey(EGRET_json_RT, "elements")) || ~(haskey(EGRET_json_RT, "system")))
            error("Please check the EGRET RT System JSON")
        end
    end

    #kwargs handling
    if (export_location === nothing)
        export_location =dirname(dirname(@__DIR__))
        @warn  "Location to save the exported tabular data not specified. Using the Converted_CSV_Files folder of the module."
    end
    
    dt_now = Dates.format(Dates.now(),"dd-u-yy-H-M-S");
    dir_name = joinpath(export_location,"data","Converted_CSV_Files",dt_now,EGRET_json_DA["system"]["name"])

    if (~isdir(dir_name))
        mkpath(dir_name)
    end
    
    # Parsing different elements in EGRET System
    # Bus
    bus_mapping_dict, area_mapping_dict, load_ts_flag = 
    if haskey(EGRET_json_DA["elements"], "bus")
        @info "Parsing buses in EGRET JSON..."
        if (haskey(EGRET_json_DA["elements"], "shunt"))
            parse_EGRET_bus(EGRET_json_DA["elements"]["bus"],EGRET_json_DA["elements"]["load"],dir_name,shunt = EGRET_json_DA["elements"]["shunt"])
        else
            parse_EGRET_bus(EGRET_json_DA["elements"]["bus"],EGRET_json_DA["elements"]["load"],dir_name)
        end
    else
        error("No buses in the EGRET DA System JSON")
    end

    # Branch
    if haskey(EGRET_json_DA["elements"], "branch")
        @info "Parsing branches in EGRET JSON..."
        parse_EGRET_branch(EGRET_json_DA["elements"]["branch"],bus_mapping_dict,dir_name)
    else
        error("No branches in the EGRET DA System JSON")
    end

    # Generator
    gen_ts_flag = 
    if haskey(EGRET_json_DA["elements"], "generator")
        @info "Parsing generators in EGRET JSON..."
        parse_EGRET_generator(EGRET_json_DA["elements"]["generator"],bus_mapping_dict,dir_name)
    else
        error("No generators in the EGRET DA System JSON")
    end

    # Calling time series processing functions
    rt_flag = 
    if (load_ts_flag && gen_ts_flag)
        if (EGRET_json_RT !== nothing)
            @info "Parsing time series of loads and generators and generating time series metadata for DA and RT Systems..."
            time_series_processing(dir_name,EGRET_json_DA["elements"]["area"],EGRET_json_DA["system"],loads_DA = EGRET_json_DA["elements"]["load"],
                                   gen_components_DA=EGRET_json_DA["elements"]["generator"],area_bus_mapping_dict=area_mapping_dict,
                                   areas_RT = EGRET_json_RT["elements"]["area"],system_RT=EGRET_json_RT["system"],loads_RT = EGRET_json_RT["elements"]["load"],
                                   gen_components_RT=EGRET_json_RT["elements"]["generator"])
        else
            @info "Parsing time series of loads and generators and generating time series metadata for DA System..."
            time_series_processing(dir_name,EGRET_json_DA["elements"]["area"],EGRET_json_DA["system"],loads_DA = EGRET_json_DA["elements"]["load"],
                                   gen_components_DA=EGRET_json_DA["elements"]["generator"],area_bus_mapping_dict=area_mapping_dict)
        end
    elseif load_ts_flag
        if (EGRET_json_RT !== nothing)
            @info "Parsing time series of loads and generating time series metadata for DA and RT Systems..."
            time_series_processing(dir_name,EGRET_json_DA["elements"]["area"],EGRET_json_DA["system"],loads_DA = EGRET_json_DA["elements"]["load"],
                                   area_bus_mapping_dict=area_mapping_dict,areas_RT = EGRET_json_RT["elements"]["area"],
                                   system_RT=EGRET_json_RT["system"],loads_RT = EGRET_json_RT["elements"]["load"])
        else
            @info "Parsing time series of loads and generating time series metadata for DA System..."
            time_series_processing(dir_name,EGRET_json_DA["elements"]["area"],EGRET_json_DA["system"],loads_DA = EGRET_json_DA["elements"]["load"],
                                   area_bus_mapping_dict=area_mapping_dict)
        end
    elseif gen_ts_flag
        if (EGRET_json_RT !== nothing)
            @info "Parsing time series of generators and generating time series metadata for DA and RT Systems..."
            time_series_processing(dir_name,EGRET_json_DA["elements"]["area"],EGRET_json_DA["system"],gen_components_DA=EGRET_json_DA["elements"]["generator"],
                                   areas_RT = EGRET_json_RT["elements"]["area"],system_RT=EGRET_json_RT["system"],gen_components_RT=EGRET_json_RT["elements"]["generator"])
        else
            @info "Parsing time series of generators and generating time series metadata for DA System..."
            time_series_processing(dir_name,EGRET_json_DA["elements"]["area"],EGRET_json_DA["system"],gen_components_DA=EGRET_json_DA["elements"]["generator"])
        end
    else
        @warn "No generator and load time series data available in the EGRET DA JSON"
    end

    @info "Successfully generated CSV files compatible with Sienna PSY tabular data parser here : $(dir_name)."

    return dir_name, EGRET_json_DA["system"]["baseMVA"],rt_flag
end
