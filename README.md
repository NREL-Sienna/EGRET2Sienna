# EGRET2SIIP.jl
## A Julia Package to convert EGRET System JSON to tabular data (RTS-GMLC format) and make a SIIP PSY System.

## Introduction
**Module Capabilities**
* The module has functionality to convert a EGRET System JSON (currently DA Is supported) to tabular data formatted for the SIIP PSY tabular data parser.
* The module also has a capability to build a SIIP PSY System from the converted tabular data. 

## Usage at a Glance

The test folder has a test script on how to use the module. A basic usage of this module would look something like this.

**Function Specifications**

* parse_EGRET_JSON() - takes two arguments (one optional), the EGRET System JSON and location to save converted CSV files (optional) 

This function converts the EGRET System JSON to a tabular data format which can be used with SIIP tabular data parser. It follows a similar folder organization to RTS-GMLC SourceData. 
```
parse_EGRET_JSON((EGRET_json::Dict{String, Any};location::Union{Nothing, String} = nothing)) 
```
**NOTE: If location to save the converted CSV files isn't specified, the module will use the 'Converted_CSV_Files' folder in the 'Data' folder of the repo.

* parse_tabular_data() - takes two arguments, the folder with converted tabular data and base MVA of the System.

This function makes SIIP PSY System from converted tabular data.
```
parse_tabular_data(csv_dir::String,base_MVA::Float64) 
```
**NOTE: csv_dir and base MVA are the outputs of parse_EGRET_JSON().
* EGRET_TO_PSY() - takes two arguments (one optional), the EGRET System JSON and location to save converted CSV files (optional) 

This function combines the functionality of both the functions above.
```
EGRET_TO_PSY(EGRET_json::Dict{String, Any};location::Union{Nothing, String} = nothing)
```

## Acknowledgments
This code was developed as part of North American Energy Resiliency Project (NAERM). We would like to thank DOE for the support and Clayton Barrows, Daniel Thom, JP Watson, Amelia Musselman and Darryl Melander for their guidance!

The developers are : [Surya Dhulipala](https://github.nrel.gov/sdhulipa).

Please reach out if you have any questions on how to use the module, need assistance or need some more information on modeling assumptions.