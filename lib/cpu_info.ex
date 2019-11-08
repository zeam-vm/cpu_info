defmodule CpuInfo do
  @moduledoc """

  **CpuInfo:** get CPU information, including a type, number of processors, number of physical cores and logical threads of a processor, and status of simultaneous multi-threads (hyper-threading).

  """

  defp os_type do
    case :os.type() do
      {:unix, :linux} -> :linux
      {:unix, :darwin} -> :macos
      {:win32, _} -> :windows
      _ -> :other
    end
  end

  @doc """
    Show all profile information on CPU and the system.
  """
  def all_profile do
    os_type()
    |> cpu_type_sub()
    |> Map.merge(%{
      otp_version: :erlang.system_info(:otp_release) |> List.to_string() |> String.to_integer(),
      elixir_version: System.version()
    })
  end

  defp confirm_executable(command) do
    if is_nil(System.find_executable(command)) do
      raise RuntimeError, message: "#{command} isn't found."
    end
  end

  defp cpu_type_sub(:other) do
    %{
      kernel_release: :unknown,
      kernel_version: :unknown,
      system_version: :unknown,
      cpu_type: :unknown,
      os_type: :other,
      cpu_model: :unknown,
      cpu_models: :unknown,
      num_of_processors: :unknown,
      num_of_cores_of_a_processor: :unknown,
      total_num_of_cores: :unknown,
      num_of_threads_of_a_processor: :unknown,
      total_num_of_threads: System.schedulers_online(),
      hyper_threading: :unknown
    }
  end

  defp cpu_type_sub(:windows) do
    %{
      kernel_release: :unknown,
      kernel_version: :unknown,
      system_version: :unknown,
      cpu_type: :unknown,
      os_type: :windows,
      cpu_model: :unknown,
      cpu_models: :unknown,
      num_of_processors: :unknown,
      num_of_cores_of_a_processor: :unknown,
      total_num_of_cores: :unknown,
      num_of_threads_of_a_processor: :unknown,
      total_num_of_threads: System.schedulers_online(),
      hyper_threading: :unknown
    }
  end

  defp cpu_type_sub(:linux) do
    kernel_release = try do
      case System.cmd("uname", ["-r"]) do
        {result, 0} -> result |> String.trim()
        _ -> :os.version |> Tuple.to_list |> Enum.join(".")
      end
    rescue
      _e in ErlangError -> nil
    end

    system_version = case File.read("/etc/issue") do
      {:ok, result} -> result |> String.trim()
      _ -> nil
    end

    kernel_version = try do
      case System.cmd("uname", ["-v"]) do
        {result, 0} -> result |> String.trim()
        _ -> nil
      end
    rescue
      _e in ErlangError -> nil
    end

    cpu_type =
      :erlang.system_info(:system_architecture) |> List.to_string() |> String.split("-") |> hd

    info =
      File.read!("/proc/cpuinfo")
      |> String.split("\n\n")
      # drop last (emtpy) item
      |> Enum.reverse()
      |> tl()
      |> Enum.reverse()
      |> Enum.map(fn cpuinfo ->
        String.split(cpuinfo, "\n")
        |> Enum.map(fn item ->
          [k | v] = String.split(item, ~r"\t+: ")
          {k, v}
        end)
        |> Map.new()
      end)

    cpu_models = Enum.map(info, &Map.get(&1, "model name")) |> List.flatten()

    cpu_model = hd(cpu_models)

    num_of_processors =
      Enum.map(info, &Map.get(&1, "physical id"))
      |> Enum.uniq()
      |> Enum.count()

    total_num_of_cores =
      Enum.map(info, &Map.get(&1, "cpu cores"))
      |> Enum.uniq()
      |> Enum.reject(& is_nil(&1))
      |> Enum.map(&(&1 |> hd |> String.to_integer()))
      |> Enum.sum()

    num_of_cores_of_a_processor = div(total_num_of_cores, num_of_processors)

    total_num_of_threads =
      Enum.map(info, &Map.get(&1, "processor"))
      |> Enum.count()

    num_of_threads_of_a_processor = div(total_num_of_threads, num_of_processors)

    ht =
      if total_num_of_cores < total_num_of_threads do
        :enabled
      else
        :disabled
      end

    %{
      kernel_release: kernel_release,
      kernel_version: kernel_version,
      system_version: system_version,
      cpu_type: cpu_type,
      os_type: :linux,
      cpu_model: cpu_model,
      cpu_models: cpu_models,
      num_of_processors: num_of_processors,
      num_of_cores_of_a_processor: num_of_cores_of_a_processor,
      total_num_of_cores: total_num_of_cores,
      num_of_threads_of_a_processor: num_of_threads_of_a_processor,
      total_num_of_threads: total_num_of_threads,
      hyper_threading: ht
    }
  end

  defp cpu_type_sub(:macos) do
    confirm_executable("uname")
    confirm_executable("system_profiler")

    kernel_release = try do
      case System.cmd("uname", ["-r"]) do
        {result, 0} -> result |> String.trim()
        _ -> :os.version |> Tuple.to_list |> Enum.join(".")
      end
    rescue
      _e in ErlangError -> nil
    end

    cpu_type = try do
      case System.cmd("uname", ["-m"]) do
        {result, 0} -> result |> String.trim()
        _ -> nil
      end
    rescue
      _e in ErlangError -> nil
    end

    %{
      kernel_release: kernel_release,
      cpu_type: cpu_type
    }
    |> Map.merge(
      try do
        case System.cmd("system_profiler", ["SPSoftwareDataType"]) do
          {result, 0} -> result |> detect_system_and_kernel_version()
          _ -> nil
        end
      rescue
        _e in ErlangError -> nil
      end
    )
    |> Map.merge(
      try do
        case System.cmd("system_profiler", ["SPHardwareDataType"]) do
          {result, 0} -> result |> parse_macos
          _ -> nil
        end
      rescue
        _e in ErlangError -> nil
      end
    )
  end

  defp detect_system_and_kernel_version(message) do
    trimmed_message = message |> split_trim

    %{
      kernel_version:
        trimmed_message
        |> Enum.filter(&String.match?(&1, ~r/Kernel Version/))
        |> hd
        |> String.split()
        |> Enum.slice(2..-1)
        |> Enum.join(" "),
      system_version:
        trimmed_message
        |> Enum.filter(&String.match?(&1, ~r/System Version/))
        |> hd
        |> String.split()
        |> Enum.slice(2..-1)
        |> Enum.join(" ")
    }
  end

  defp parse_macos(message) do
    trimmed_message = message |> split_trim

    cpu_model =
      Enum.filter(trimmed_message, &String.match?(&1, ~r/Processor Name/))
      |> hd
      |> String.split()
      |> Enum.slice(2..-1)
      |> Enum.join(" ")

    cpu_models = [cpu_model]

    num_of_processors =
      Enum.filter(trimmed_message, &String.match?(&1, ~r/Number of Processors/))
      |> hd
      |> match_to_integer()

    total_num_of_cores =
      Enum.filter(trimmed_message, &String.match?(&1, ~r/Total Number of Cores/))
      |> hd
      |> match_to_integer()

    num_of_cores_of_a_processor = div(total_num_of_cores, num_of_processors)

    m_ht = Enum.filter(trimmed_message, &String.match?(&1, ~r/Hyper-Threading Technology/))

    ht =
      if length(m_ht) > 0 and String.match?(hd(m_ht), ~r/Enabled/) do
        :enabled
      else
        :disabled
      end

    total_num_of_threads =
      total_num_of_cores *
        case ht do
          :enabled -> 2
          :disabled -> 1
        end

    num_of_threads_of_a_processor = div(total_num_of_threads, num_of_processors)

    %{
      os_type: :macos,
      cpu_model: cpu_model,
      cpu_models: cpu_models,
      num_of_processors: num_of_processors,
      num_of_cores_of_a_processor: num_of_cores_of_a_processor,
      total_num_of_cores: total_num_of_cores,
      num_of_threads_of_a_processor: num_of_threads_of_a_processor,
      total_num_of_threads: total_num_of_threads,
      hyper_threading: ht
    }
  end

  defp split_trim(message) do
    message |> String.split("\n") |> Enum.map(&String.trim(&1))
  end

  defp match_to_integer(message) do
    Regex.run(~r/[0-9]+/, message) |> hd |> String.to_integer()
  end
end
