defmodule Specter.MixProject do
  use Mix.Project

  @scm_url "https://github.com/livinginthepast/specter"
  @version "0.2.1"

  def project do
    [
      app: :specter,
      deps: deps(),
      description: description(),
      dialyzer: dialyzer(),
      docs: [
        extras: doc_extras(),
        source_ref: "v#{@version}",
        main: "readme"
      ],
      elixir: "~> 1.13",
      elixirc_paths: elixirc_paths(Mix.env()),
      homepage_url: @scm_url,
      package: package(),
      preferred_cli_env: [credo: :test, dialyzer: :test, docs: :dev],
      source_url: @scm_url,
      start_permanent: Mix.env() == :prod,
      version: @version
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.28", only: [:dev], runtime: false},
      {:jason, "~> 1.3"},
      {:mix_audit, "~> 1.0", only: [:dev], runtime: false},
      {:rustler, "~> 0.23"},
      {:uuid, "~> 1.1", only: [:test]}
    ]
  end

  defp description,
    do: """
    A rustler nif wrapping webrtc.rs.
    """

  defp dialyzer do
    [
      plt_add_apps: [:ex_unit, :mix],
      plt_add_deps: :app_tree,
      plt_file: {:no_warn, "priv/plts/#{otp_version()}/dialyzer.plt"}
    ]
  end

  defp doc_extras() do
    [
      "guides/lifecycle.md",
      "README.md"
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp otp_version do
    Path.join([:code.root_dir(), "releases", :erlang.system_info(:otp_release), "OTP_VERSION"])
    |> File.read!()
    |> String.trim()
  end

  defp package do
    [
      licenses: ["MIT"],
      maintainers: ["Eric Saxby"],
      links: %{"GitHub" => @scm_url},
      files: ~w(
        LICENSE.md
        README.md
        config
        lib
        mix.exs
        native/specter_nif/src
        native/specter_nif/Cargo.toml
        native/specter_nif/Cargo.lock
      )
    ]
  end
end
