defmodule CpuInfo do
  def os_type do
    case :os.type() do
      {:unix, :linux} -> :linux
      {:unix, :darwin} -> :macos
      {:win32, _} -> :windows
      _ -> :other
    end
  end

  def cpu_type do
    os_type() |> cpu_type_sub()
  end

  def confirm_executable(command) do
    if is_nil(System.find_executable(command)) do
      raise RuntimeError, message: "#{command} isn't found."
    end
  end

  defp cpu_type_sub(:linux) do
    confirm_executable("cat")
    confirm_executable("grep")
    confirm_executable("sort")
    confirm_executable("wc")
    confirm_executable("uname")

    kernel_release =
      case System.cmd("uname", ["-r"]) do
        {result, 0} -> result |> String.trim()
        _ -> raise RuntimeError, message: "uname don't work."
      end

    system_version =
      case System.cmd("cat", ["/etc/issue"]) do
        {result, 0} -> result |> String.trim()
        _ -> ""
      end

    kernel_version =
      case System.cmd("uname", ["-v"]) do
        {result, 0} -> result |> String.trim()
        _ -> raise RuntimeError, message: "uname don't work."
      end

    cpu_type =
      case System.cmd("uname", ["-p"]) do
        {result, 0} -> result |> String.trim()
        _ -> raise RuntimeError, message: "uname don't work."
      end

    cpu_models =
      :os.cmd('grep model.name /proc/cpuinfo | sort -u')
      |> List.to_string()
      |> String.split("\n")
      |> Enum.map(&String.trim(&1))
      |> Enum.reject(&(String.length(&1) == 0))
      |> Enum.map(&String.split(&1))
      |> Enum.map(&Enum.slice(&1, 3..-1))
      |> Enum.map(&Enum.join(&1, " "))

    cpu_model = hd(cpu_models)

    num_of_processors =
      :os.cmd('grep physical.id /proc/cpuinfo | sort -u | wc -l')
      |> List.to_string()
      |> String.trim()
      |> String.to_integer()

    num_of_cores_of_a_processor =
      :os.cmd('grep cpu.cores /proc/cpuinfo | sort -u')
      |> List.to_string()
      |> String.trim()
      |> match_to_integer()

    total_num_of_cores = num_of_cores_of_a_processor * num_of_processors

    total_num_of_threads =
      :os.cmd('grep processor /proc/cpuinfo | wc -l')
      |> List.to_string()
      |> String.trim()
      |> String.to_integer()

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

    kernel_release =
      case System.cmd("uname", ["-r"]) do
        {result, 0} -> result |> String.trim()
        _ -> raise RuntimeError, message: "uname don't work."
      end

    cpu_type =
      case System.cmd("uname", ["-p"]) do
        {result, 0} -> result |> String.trim()
        _ -> raise RuntimeError, message: "uname don't work."
      end

    %{
      kernel_release: kernel_release,
      cpu_type: cpu_type
    }
    |> Map.merge(
      case System.cmd("system_profiler", ["SPSoftwareDataType"]) do
        {result, 0} -> result |> detect_system_and_kernel_version()
        _ -> raise RuntimeError, message: "uname don't work."
      end
    )
    |> Map.merge(
      case System.cmd("system_profiler", ["SPHardwareDataType"]) do
        {result, 0} -> result |> parse_macos
        _ -> raise RuntimeError, message: "system_profiler don't work."
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

    m_ht = Enum.filter(trimmed_message, &String.match?(&1, ~r/Hyper-Threading Technology/)) |> hd

    ht =
      if String.match?(m_ht, ~r/Enabled/) do
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
