#####################################################
# Surya
# NREL
# October 2023
# Call Sienna PSY Tabular Data Parser
#####################################################################################
const PSY = PowerSystems
#####################################################################################
# Main Function
#####################################################################################
function parse_sienna_tabular_data(csv_dir::String,base_MVA::Float64,rt_flag::Bool;ts_pointers_file::Union{Nothing, String} = nothing, serialize = false) 

    dir_name = @__DIR__
    user_descriptors_file = joinpath(dir_name,"Descriptors","user_descriptors.yaml") 
    generator_mapping_file = joinpath(dir_name,"Descriptors","generator_mapping.yaml")

    if (ts_pointers_file === nothing)
        @warn "Time series pointers file type wasn't passed. Using timeseries_pointers.csv"
        ts_pointers_file = "CSV"
    end

    if (ts_pointers_file == "CSV")
        @info "Using timeseries_pointers.csv as time series metadata file...."
        ts_pointers_file= "timeseries_pointers.csv"
    elseif (ts_pointers_file == "JSON")
        @info "Using timeseries_pointers.json as time series metadata file...."
        ts_pointers_file= "timeseries_pointers.json"
    else
        error("Unrecognized time series pointers file type")
    end
    timeseries_pointers_file = joinpath(csv_dir, ts_pointers_file)

    rawsys = PSY.PowerSystemTableData(
        csv_dir,
        base_MVA,
        user_descriptors_file,
        timeseries_metadata_file = timeseries_pointers_file,
        generator_mapping_file = generator_mapping_file,
    );

    sys_DA = PSY.System(rawsys; time_series_resolution = Dates.Hour(1));

    if (rt_flag)
        sys_RT = PSY.System(rawsys; time_series_resolution = Dates.Minute(5));
        @info "Successfully generated both DA and RT PSY Systems."
      
        if serialize
            sienna_sys_path = mkpath(joinpath(csv_dir, "Sienna_System"))

            # DA
            sienna_DA_sys_path = mkpath(joinpath(csv_dir, "Sienna_System", "DA"))
            @info "Serializing the DA Sienna System to $(sienna_DA_sys_path) ..."
            PSY.to_json(sys_DA,joinpath(sienna_DA_sys_path,"DA_sys.json"), force = true, runchecks = false)

            # RT
            sienna_RT_sys_path = mkpath(joinpath(csv_dir, "Sienna_System", "RT"))
            @info "Serializing the RT Sienna System to $(sienna_RT_sys_path) ..."
            PSY.to_json(sys_RT,joinpath(sienna_RT_sys_path,"RT_sys.json"), force = true, runchecks = false)
        end

        return sys_DA, sys_RT
    else
        @info "Successfully generated DA PSY System."

        if serialize
            sienna_sys_path = mkpath(joinpath(csv_dir, "Sienna_System"))

            # DA
            sienna_DA_sys_path = mkpath(joinpath(csv_dir, "Sienna_System", "DA"))
            @info "Serializing the DA Sienna System to $(sienna_DA_sys_path) ..."
            PSY.to_json(sys_DA,joinpath(sienna_DA_sys_path,"DA_sys.json"), force = true, runchecks = false)
        end
        
        return sys_DA
    end
end