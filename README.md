# CpuInfo

**CpuInfo:** get CPU information, including a type, number of processors, number of physical cores and logical threads of a processor, and status of simultaneous multi-threads (hyper-threading).

## Installation

This package can be installed
by adding `cpu_info` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:cpu_info, "~> 0.2.0"}
  ]
end
```

## Tested Platforms

* Linux (with or without CUDA, including Jetson Nano)
* macOS (with or without Metal)
* Nerves (compile time and execution time)

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/cpu_info](https://hexdocs.pm/cpu_info).

