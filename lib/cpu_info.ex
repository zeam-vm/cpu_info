defmodule CpuInfo do
  @moduledoc """

  **CpuInfo:** get CPU information, including a type, number of processors, number of physical cores and logical threads of a processor, and status of simultaneous multi-threads (hyper-threading).

  """

  @latest_versions %{gcc: 9, clang: 9}

  defp os_type do
    case :os.type() do
      {:unix, :linux} -> :linux
      {:unix, :darwin} -> :macos
      {:unix, :freebsd} -> :freebsd
      {:win32, _} -> :windows
      _ -> :other
    end
  end

  @doc """
    Show all profile information on CPU and the system.
  """
  def all_profile do
    os_type = os_type()
    cpu_type = cpu_type_sub(os_type)
    cuda_info = cuda(os_type)

    elixir_version = %{
      otp_version: :erlang.system_info(:otp_release) |> List.to_string() |> String.to_integer(),
      elixir_version: System.version()
    }

    compilers =
      %{gcc: cc(:gcc)}
      |> Map.merge(%{clang: cc(:clang)})
      |> Map.merge(%{cc: cc_env()})

    compilers =
      if os_type == :macos do
        compilers
        |> Map.merge(%{apple_clang: cc(:apple_clang)})
      else
        compilers
      end

    Map.merge(cpu_type, cuda_info)
    |> Map.merge(elixir_version)
    |> Map.merge(compilers)
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
    os_info =
      File.read!("/etc/os-release")
      |> String.split("\n")
      |> Enum.reverse()
      |> tl
      |> Enum.reverse()
      |> Enum.map(&String.split(&1, "="))
      |> Enum.map(fn [k, v] -> {k, v |> String.trim("\"")} end)
      |> Map.new()

    kernel_release =
      case File.read("/proc/sys/kernel/osrelease") do
        {:ok, result} -> result
        _ -> nil
      end

    system_version = Map.get(os_info, "PRETTY_NAME")

    kernel_version =
      case File.read("/proc/sys/kernel/version") do
        {:ok, result} -> result
        _ -> nil
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

    t1 =
      Enum.map(info, &Map.get(&1, "processor"))
      |> Enum.uniq()
      |> Enum.reject(&is_nil(&1))
      |> length

    t =
      Enum.map(info, &Map.get(&1, "cpu cores"))
      |> Enum.uniq()
      |> Enum.reject(&is_nil(&1))
      |> Enum.map(&(&1 |> hd |> String.to_integer()))
      |> Enum.sum()

    total_num_of_cores = if t == 0, do: t1, else: t

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

  defp cpu_type_sub(:freebsd) do
    confirm_executable("uname")
    confirm_executable("sysctl")

    kernel_release =
      case System.cmd("uname", ["-r"]) do
        {result, 0} -> result |> String.trim()
        _ -> raise RuntimeError, message: "uname don't work."
      end

    system_version =
      case System.cmd("uname", ["-r"]) do
        {result, 0} -> result |> String.trim()
        _ -> ""
      end

    kernel_version =
      case System.cmd("uname", ["-r"]) do
        {result, 0} -> result |> String.trim()
        _ -> raise RuntimeError, message: "uname don't work."
      end

    cpu_type =
      case System.cmd("uname", ["-m"]) do
        {result, 0} -> result |> String.trim()
        _ -> raise RuntimeError, message: "uname don't work."
      end

    cpu_model =
      case System.cmd("sysctl", ["-n", "hw.model"]) do
        {result, 0} -> result |> String.trim()
        _ -> raise RuntimeError, message: "sysctl don't work."
      end

    cpu_models = [cpu_model]

    total_num_of_cores =
      case System.cmd("sysctl", ["-n", "kern.smp.cores"]) do
        {result, 0} -> result |> String.trim() |> String.to_integer()
        _ -> raise RuntimeError, message: "sysctl don't work."
      end

    total_num_of_threads =
      case System.cmd("sysctl", ["-n", "kern.smp.cpus"]) do
        {result, 0} -> result |> String.trim() |> String.to_integer()
        _ -> raise RuntimeError, message: "sysctl don't work."
      end

    ht =
      case System.cmd("sysctl", ["-n", "machdep.hyperthreading_allowed"]) do
        {"1\n", 0} -> :enabled
        {"0\n", 0} -> :disabled
        _ -> raise RuntimeError, message: "sysctl don't work."
      end

    %{
      kernel_release: kernel_release,
      kernel_version: kernel_version,
      system_version: system_version,
      cpu_type: cpu_type,
      os_type: :freebsd,
      cpu_model: cpu_model,
      cpu_models: cpu_models,
      num_of_processors: :unknown,
      num_of_cores_of_a_processor: :unknown,
      total_num_of_cores: total_num_of_cores,
      num_of_threads_of_a_processor: :unknown,
      total_num_of_threads: total_num_of_threads,
      hyper_threading: ht
    }
  end

  defp cpu_type_sub(:macos) do
    confirm_executable("uname")
    confirm_executable("system_profiler")

    kernel_release =
      try do
        case System.cmd("uname", ["-r"]) do
          {result, 0} -> result |> String.trim()
          _ -> :os.version() |> Tuple.to_list() |> Enum.join(".")
        end
      rescue
        _e in ErlangError -> nil
      end

    cpu_type =
      try do
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

  def cc_env() do
    cc = System.get_env("CC")

    if is_nil(cc) do
      []
    else
      exe = System.find_executable(cc)

      cond do
        is_nil(exe) ->
          %{
            bin: cc,
            type: :undefined
          }

        String.match?(exe, ~r/clang/) ->
          cc_sub([exe], :clang)

        String.match?(exe, ~r/gcc/) ->
          cc_sub([exe], :gcc)

        true ->
          [
            %{
              bin: exe,
              type: :unknown
            }
          ]
      end
    end
  end

  def cc(:apple_clang) do
    exe = "/usr/bin/clang"

    [System.find_executable(exe)]
    |> cc_sub(:apple_clang)
  end

  def cc(type) do
    exe = Atom.to_string(type)
    latest_version = Map.get(@latest_versions, type)

    list_executable_versions(exe, 1, latest_version)
    |> cc_sub(type)
  end

  defp cc_sub(exes, type) do
    Enum.map(
      exes,
      &(%{bin: &1}
        |> Map.merge(
          execute_to_get_version(&1)
          |> parse_versions(type)
          |> parse_version_number()
        ))
    )
  end

  defp list_executable_versions(exe, from, to) do
    ([System.find_executable(exe)] ++
       Enum.map(from..to, &System.find_executable(exe <> "-" <> Integer.to_string(&1))))
    |> Enum.filter(&(&1 != nil))
  end

  defp execute_to_get_version(exe) do
    System.cmd(exe, ["--version"], stderr_to_stdout: true)
    |> elem(0)
  end

  defp parse_versions(result, :gcc) do
    if String.match?(result, ~r/Copyright \(C\) [0-9]+ Free Software Foundation, Inc\./) do
      versions = String.split(result, "\n") |> Enum.at(0)
      %{type: :gcc, versions: versions}
    else
      parse_versions(result, :apple_clang)
    end
  end

  defp parse_versions(result, :clang) do
    if String.match?(result, ~r/Apple clang version/) do
      parse_versions(result, :apple_clang)
    else
      versions = String.split(result, "\n") |> Enum.at(0)
      %{type: :clang, versions: versions}
    end
  end

  defp parse_versions(result, :apple_clang) do
    %{type: :apple_clang}
    |> Map.merge(
      Regex.named_captures(~r/(?<versions>Apple clang version [0-9.]+ .*)\n/, result)
      |> key_string_to_atom()
    )
  end

  defp key_string_to_atom(map) do
    if is_nil(map) do
      %{versions: ""}
    else
      Map.keys(map)
      |> Enum.map(
        &{
          String.to_atom(&1),
          Map.get(map, &1)
        }
      )
      |> Map.new()
    end
  end

  defp parse_version_number(map) do
    Map.merge(
      map,
      Regex.named_captures(~r/(?<version>[0-9]+\.[0-9.]+)/, Map.get(map, :versions))
      |> key_string_to_atom()
    )
  end

  defp cuda(:linux) do
    case File.read("/proc/driver/nvidia/version") do
      {:ok, _result} ->
        smi = execute_nvidia_smi(:linux)

        %{cuda: true}
        |> Map.merge(parse_cuda_version(smi))
        |> Map.merge(%{
          cuda_bin: find_path("/usr/local/cuda/bin"),
          cuda_include: find_path("/usr/local/cuda/include"),
          cuda_lib: find_path("/usr/local/cuda/lib64"),
          nvcc: System.find_executable("/usr/local/cuda/bin/nvcc")
        })

      {:error, _reason} ->
        %{cuda: false}
    end
  end

  defp cuda(_) do
    %{cuda: false}
  end

  defp execute_nvidia_smi(:linux, options \\ []) do
    if is_nil(System.find_executable("nvidia-smi")) do
      ""
    else
      {result, _code} = System.cmd("nvidia-smi", options)
      result
    end
  end

  defp parse_cuda_version(smi) do
    Regex.named_captures(~r/CUDA Version: (?<cuda_version>[0-9.]+)/, smi)
    |> key_string_to_atom()
  end

  defp find_path(path) do
    if File.exists?(path) do
      path
    else
      nil
    end
  end
end
