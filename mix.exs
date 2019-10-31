defmodule CpuInfo.MixProject do
  use Mix.Project

  def project do
    [
      app: :cpu_info,
      version: "0.0.1",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      docs: [
        api_reference: false,
        main: "CpuInfo"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:earmark, "~> 1.4", only: :dev},
      {:ex_doc, "~> 0.21", only: :dev}
    ]
  end

  defp description() do
    "CpuInfo: get CPU information, including a type, number of processors, number of physical cores and logical threads of a processor, and status of simultaneous multi-threads (hyper-threading)."
  end

  defp package() do
    [
      name: "cpu_info",
      maintainers: [
        "Susumu Yamazaki"
      ],
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/zeam-vm/cpu_info"}
    ]
  end
end
