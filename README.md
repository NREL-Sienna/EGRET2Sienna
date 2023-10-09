# EGRET2Sienna.jl
## A Julia Package to convert EGRET System JSON to tabular data (RTS-GMLC format) and make a Sienna PSY System.

## Introduction
**Module Capabilities**
* The module has functionality to convert a EGRET System JSON (currently DA Is supported) to tabular data formatted for the SIIP PSY tabular data parser.
* The module also has a capability to build a Sienna PSY System from the converted tabular data. 

## Usage at a Glance

The test folder has a test script on how to use the module. A basic usage of this module would look something like this.

**Function Specifications**

* parse_egretjson() - takes three arguments (two optional), the EGRET System JSON location/s and location to save converted CSV files (optional) 

This function converts the EGRET System JSON to a tabular data format which can be used with SIIP tabular data parser. It follows a similar folder organization to RTS-GMLC SourceData. 
```
parse_egretjson(EGRET_json_DA_location::String;EGRET_json_RT_location::Union{Nothing, String} = nothing,
                export_location::Union{Nothing, String} = nothing)
```
**NOTE: If location to save the converted CSV files isn't specified, the module will use the 'Converted_CSV_Files' folder in the 'Data' folder of the repo.

* parse_sienna_tabular_data() - takes five arguments, the folder with converted tabular data, base MVA of the System and others.

This function makes Sienna PSY System from converted tabular data.
```
parse_sienna_tabular_data(csv_dir::String,base_MVA::Float64,rt_flag::Bool;ts_pointers_file::Union{Nothing, String} = nothing, serialize = false) 
```
**NOTE: csv_dir and base MVA are the outputs of parse_egretjson().
* egret_to_sienna() - takes five arguments (four optional), the EGRET System JSON location and location to save converted CSV files among others (optional) 

This function combines the functionality of both the functions above.
```
egret_to_sienna(EGRET_json_location::String;EGRET_json_RT_location::Union{Nothing, String} = nothing,
                export_location::Union{Nothing, String} = nothing,ts_pointers_file::Union{Nothing, String} = nothing, serialize = false)
```

## Acknowledgments
This code was developed as part of North American Energy Resiliency Project (NAERM). We would like to thank DOE for the support and Clayton Barrows, Daniel Thom, JP Watson, Amelia Musselman and Darryl Melander for their guidance!

The developers are : [Surya Dhulipala](https://github.nrel.gov/sdhulipa).

Please reach out if you have any questions on how to use the module, need assistance or need some more information on modeling assumptions.
