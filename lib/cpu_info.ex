defmodule CpuInfo do

  def os_type do
  	case :os.type do
  		{:unix, :linux} -> :linux
  		{:unix, :darwin} -> :macos
  		{:win32, _} -> :windows
  	end
  end

  def cpu_type do
  	os_type() |> cpu_type_sub()
  end

  defp cpu_type_sub :macos do
  	if is_nil(System.find_executable("system_profiler")) do
  		raise RuntimeError, message: "system_profiler isn't found."
  	end

  	case System.cmd("system_profiler", ["SPHardwareDataType"]) do
  		{result, 0} -> result |> parse_macos
  		{_, _} -> raise RuntimeError, message: "system_profiler don't work."
  	end
  end

  defp parse_macos message do
  	trimmed_message = message |> split_trim

  	cpu_type = Enum.filter(trimmed_message, & String.match?(&1, ~r/Processor Name/)) |> hd |> String.split() |> Enum.slice(2..-1) |> Enum.join(" ")

  	num_of_processors = Enum.filter(trimmed_message, & String.match?(&1, ~r/Number of Processors/)) |> hd |> match_to_integer()

  	total_num_of_cores = Enum.filter(trimmed_message, & String.match?(&1, ~r/Total Number of Cores/)) |> hd |> match_to_integer()

  	num_of_cores_of_a_processor = div(total_num_of_cores, num_of_processors)

  	m_ht = Enum.filter(trimmed_message, & String.match?(&1, ~r/Hyper-Threading Technology/)) |> hd

  	ht = if String.match?(m_ht, ~r/Enabled/) do
  		:enabled
  	else
  		:disabled
  	end

  	total_num_of_threads = total_num_of_cores * case ht do
  		:enabled -> 2
  		:disabled -> 1
  	end

  	num_of_threads_of_a_processor = div(total_num_of_threads, num_of_processors)

  	%{
  		os_type: :macos,
  		cpu_type: cpu_type,
  		num_of_processors: num_of_processors,
  		num_of_cores_of_a_processor: num_of_cores_of_a_processor, 
  		total_num_of_cores: total_num_of_cores,
  		num_of_threads_of_a_processor: num_of_threads_of_a_processor,
  		total_num_of_threads: total_num_of_threads,
  		hyper_threading: ht
  	}
  end

  defp split_trim(message) do
  	message |> String.split("\n") |> Enum.map(& String.trim(&1))
  end

  defp match_to_integer(message) do
  	Regex.run(~r/[0-9]+/, message) |> hd |> String.to_integer
  end
end
