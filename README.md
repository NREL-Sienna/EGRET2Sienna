# EGRET2Sienna.jl

## A Julia Package to convert EGRET System JSON directly to a Sienna PowerSystems.jl System

## Introduction

**Module Capabilities**

* Parses EGRET System JSON (day-ahead and/or real-time) and directly constructs `PowerSystems.System` objects — no intermediate CSV files required.
* Supports DA-only and DA+RT workflows, with optional JSON serialization of the resulting systems.
* Handles distributed buses, time-varying generator capacity, and area-aggregated load time series.

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/NREL/EGRET2SIIP")
```

## Usage

### One-step: EGRET JSON → PSY System

```julia
using EGRET2Sienna

# DA only
sys = egret_to_sienna("path/to/da_system.json")

# DA + RT
sys_DA, sys_RT = egret_to_sienna("path/to/da_system.json", "path/to/rt_system.json")

# With serialization (writes <label>_system.json to export_location)
sys = egret_to_sienna("path/to/da_system.json";
                      serialize=true,
                      export_location="path/to/output/")
```

You can also pass pre-loaded dicts instead of file paths:

```julia
import JSON
da_dict = JSON.parsefile("path/to/da_system.json")
sys = egret_to_sienna(da_dict)

da_dict = JSON.parsefile("path/to/da_system.json")
rt_dict = JSON.parsefile("path/to/rt_system.json")
sys_DA, sys_RT = egret_to_sienna(da_dict, rt_dict)
```

### Two-step: parse then build

```julia
# Parse EGRET JSON into an intermediate data structure
data = parse_egretjson("path/to/da_system.json")
# or: data = parse_egretjson("path/to/da_system.json", "path/to/rt_system.json")

# Build PSY System(s) from parsed data
using EGRET2Sienna: build_psy_system
sys_DA = build_psy_system(data; ts_label="DAY_AHEAD")
sys_RT = build_psy_system(data; ts_label="REAL_TIME")  # only if rt_flag is set
```

## Function Reference

### `egret_to_sienna`

Parses EGRET JSON and returns a `PowerSystems.System` (DA only) or a `(sys_DA, sys_RT)` tuple.

```julia
egret_to_sienna(EGRET_json_location::String;
                export_location::Union{Nothing, String} = nothing,
                serialize::Bool = false)

egret_to_sienna(EGRET_json_DA::String, EGRET_json_RT::String;
                export_location::Union{Nothing, String} = nothing,
                serialize::Bool = false)
```

Dict variants accept any `AbstractDict` in place of file path strings.

### `parse_egretjson`

Parses one or two EGRET JSON files (or dicts) and returns a `NamedTuple` containing all static and time-series data needed to build a `PSY.System`. Useful when you want to inspect the parsed data before building.

```julia
parse_egretjson(EGRET_json_location::String)
parse_egretjson(EGRET_json_DA::String, EGRET_json_RT::String)
```

## Acknowledgments
This code was developed as part of the North American Energy Resiliency Project (NAERM). We would like to thank DOE for the support and Clayton Barrows, Daniel Thom, JP Watson, Amelia Musselman and Darryl Melander for their guidance!

The developers are: [Surya Dhulipala](https://github.nrel.gov/sdhulipa).

Please reach out if you have any questions on how to use the module, need assistance, or need more information on modeling assumptions.
