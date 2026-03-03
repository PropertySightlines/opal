defmodule Opal.Config.ProviderModels do
  @moduledoc """
  Module for loading and accessing provider-model configurations.

  This module provides functions to retrieve provider configurations,
  list available providers, and access all provider-model mappings.
  """

  @config_path Path.join([:code.priv_dir(:opal), "config/provider_models.exs"])

  @doc """
  Gets the configuration for a specific provider.

  ## Parameters
    - provider: The provider name as a string (e.g., "openrouter", "groq")

  ## Returns
    - `{:ok, config}` with the provider configuration map if found
    - `{:error, :not_found}` if the provider is not configured

  ## Examples

      iex> Opal.Config.ProviderModels.get_provider_config("openrouter")
      {:ok, %{model: "meta-llama/llama-3-8b-instruct", endpoint: "https://openrouter.ai/api/v1/chat/completions"}}

      iex> Opal.Config.ProviderModels.get_provider_config("unknown")
      {:error, :not_found}

  """
  def get_provider_config(provider) when is_binary(provider) do
    config = load_config()

    case Map.get(config, provider) do
      nil -> {:error, :not_found}
      provider_config -> {:ok, provider_config}
    end
  end

  @doc """
  Lists all available providers.

  ## Returns
    - A list of provider names as strings

  ## Examples

      iex> Opal.Config.ProviderModels.list_providers()
      ["cerebras", "groq", "nvidia", "openrouter"]

  """
  def list_providers do
    config = load_config()
    Map.keys(config) |> Enum.sort()
  end

  @doc """
  Gets all provider configurations.

  ## Returns
    - A map of all provider configurations

  ## Examples

      iex> Opal.Config.ProviderModels.get_all_configs()
      %{
        "openrouter" => %{model: "meta-llama/llama-3-8b-instruct", ...},
        "groq" => %{model: "llama-3.1-8b-instant", ...},
        ...
      }

  """
  def get_all_configs do
    load_config()
  end

  defp load_config do
    @config_path
    |> Code.eval_file()
    |> case do
      {config, _binding} -> config
    end
  rescue
    _ -> %{}
  end
end
