#####################################################
# Surya
# NREL
# November 2021
# Call SIIP PSY Tabular Data Parser
#####################################################################################
const PSY = PowerSystems
#####################################################################################
# Main Function
#####################################################################################
function parse_tabular_data(csv_dir::String,base_MVA::Float64,rt_flag::Bool) 

    dir_name = @__DIR__
    user_descriptors_file = joinpath(dir_name,"Descriptors","user_descriptors.yaml") 
    generator_mapping_file = joinpath(dir_name,"Descriptors","generator_mapping.yaml")
    timeseries_pointers_file = joinpath(csv_dir, "timeseries_pointers.csv")

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
        return sys_DA, sys_RT
    else
        @info "Successfully generated DA PSY System."
        return sys_DA
    end
end