defmodule AgentHarness.RateLimit.Config do
  @moduledoc """
  Configuration loader for rate limit settings.

  Loads provider rate limits from:
    1. Explicit configuration passed to Tracker.start_link/1
    2. Application config (:agent_harness, :rate_limits)
    3. Environment variables (e.g., GROQ_RPM, GROQ_TPM)
    4. Default values

  ## Environment Variables

  Provider limits can be configured via environment variables:

      GROQ_RPM=30
      GROQ_TPM=60000
      CEREBRAS_RPM=20
      CEREBRAS_TPM=60000
      NVIDIA_RPM=100
      NVIDIA_TPM=500000
      OPENROUTER_RPM=60
      OPENROUTER_TPM=100000

  ## Application Config

      config :agent_harness, :rate_limits, %{
        groq: %{rpm: 30, tpm: 60_000},
        cerebras: %{rpm: 20, tpm: 60_000},
        nvidia: %{rpm: 100, tpm: 500_000},
        openrouter: %{rpm: 60, tpm: 100_000}
      }
  """

  @default_limits %{
    groq: %{rpm: 30, tpm: 60_000},
    cerebras: %{rpm: 20, tpm: 60_000},
    nvidia: %{rpm: 100, tpm: 500_000},
    openrouter: %{rpm: 60, tpm: 100_000}
  }

  @providers [:groq, :cerebras, :nvidia, :openrouter]

  @doc """
  Loads rate limit configuration for all providers.

  Merges defaults with environment variables and application config.
  """
  @spec load() :: map()
  def load do
    base_limits = @default_limits

    # Merge with environment variables
    env_limits = load_from_env()
    merged = deep_merge(base_limits, env_limits)

    # Merge with application config (highest priority)
    app_limits = Application.get_env(:agent_harness, :rate_limits, %{})
    deep_merge(merged, app_limits)
  end

  @doc """
  Gets the rate limit for a specific provider.

  ## Examples

      iex> AgentHarness.RateLimit.Config.get_provider_limit(:groq)
      %{rpm: 30, tpm: 60_000}
  """
  @spec get_provider_limit(atom()) :: map()
  def get_provider_limit(provider) do
    limits = load()
    Map.get(limits, provider, %{rpm: 0, tpm: 0})
  end

  @doc """
  Parses a provider name from a string.

  ## Examples

      iex> AgentHarness.RateLimit.Config.parse_provider("groq")
      :groq

      iex> AgentHarness.RateLimit.Config.parse_provider("GROQ")
      :groq
  """
  @spec parse_provider(String.t()) :: atom()
  def parse_provider(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.to_atom()
  end

  @doc """
  Returns the list of configured providers.
  """
  @spec providers() :: [atom()]
  def providers, do: @providers

  # ── Private Functions ──────────────────────────────────────────────

  defp load_from_env do
    Enum.reduce(@providers, %{}, fn provider, acc ->
      provider_str = Atom.to_string(provider)
      rpm_var = "#{provider_str}_RPM" |> String.upcase()
      tpm_var = "#{provider_str}_TPM" |> String.upcase()

      rpm = System.get_env(rpm_var) |> parse_int()
      tpm = System.get_env(tpm_var) |> parse_int()

      cond do
        rpm != nil and tpm != nil ->
          Map.put(acc, provider, %{rpm: rpm, tpm: tpm})

        rpm != nil ->
          Map.update(acc, provider, %{rpm: rpm}, &Map.put(&1, :rpm, rpm))

        tpm != nil ->
          Map.update(acc, provider, %{tpm: tpm}, &Map.put(&1, :tpm, tpm))

        true ->
          acc
      end
    end)
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp deep_merge(map1, map2) do
    Map.merge(map1, map2, fn _key, v1, v2 ->
      if is_map(v1) and is_map(v2) do
        deep_merge(v1, v2)
      else
        v2
      end
    end)
  end
end
