defmodule CpuInfoTest do
  use ExUnit.Case
  doctest CpuInfo

  test "greets the world" do
    assert CpuInfo.hello() == :world
  end
end
