defmodule Opal.Auth do
  @moduledoc """
  Credential detection for Opal providers.

  Checks whether valid credentials exist for OpenAI-compatible providers
  via API keys from environment variables.

  Returns a summary the client can use to determine authentication status.

  ## Auto-Authentication

  If any API keys are configured in environment variables, the system
  automatically authenticates without any OAuth flow or user interaction.
  """

  @type probe_result :: %{
          status: String.t(),
          provider: String.t() | nil,
          available_providers: [String.t()]
        }

  @api_key_providers %{
    "openrouter" => "OPENROUTER_API_KEY",
    "groq" => "GROQ_API_KEY",
    "nvidia" => "NVIDIA_API_KEY",
    "cerebras" => "CEREBRAS_API_KEY",
    "openai" => "OPENAI_API_KEY",
    "anthropic" => "ANTHROPIC_API_KEY"
  }

  @doc """
  Probes for available credentials and returns auth readiness.

  Returns a map with:

    * `status` — `"ready"` if API keys exist, `"setup_required"` if not
    * `provider` — First available provider name (for backwards compatibility), `nil` if none
    * `available_providers` — List of ALL providers with valid API keys configured

  Authentication is automatic - if any API keys are present in environment
  variables, the system is ready to use immediately without OAuth.
  """
  @spec probe() :: probe_result()
  def probe do
    api_providers = api_key_providers_ready()

    case api_providers do
      [] ->
        %{status: "setup_required", provider: nil, available_providers: []}

      [first | _rest] ->
        # Auto-authenticated: API keys are present
        %{status: "ready", provider: first, available_providers: api_providers}
    end
  end

  @doc """
  Checks whether any API key credentials are available.
  """
  @spec ready?() :: boolean()
  def ready? do
    probe().status == "ready"
  end

  @doc """
  Returns list of API key providers that have keys configured.

  Checks environment variables for each configured provider.
  Returns ALL providers that have keys, not just the first one.
  """
  @spec api_key_providers_ready() :: [String.t()]
  def api_key_providers_ready do
    @api_key_providers
    |> Enum.filter(fn {_provider, env_var} ->
      key = System.get_env(env_var)
      key != nil and key != ""
    end)
    |> Enum.map(fn {provider, _env_var} -> provider end)
  end

  @doc """
  Returns map of all API key providers and their env var names.
  """
  @spec api_key_providers() :: map()
  def api_key_providers, do: @api_key_providers

  @doc """
  Returns the API key for a specific provider from environment.

  ## Parameters

    * `provider` - Provider name (e.g., "openrouter", "groq", "nvidia")

  ## Examples

      iex> Opal.Auth.get_api_key("openrouter")
      {:ok, "sk-or-v1-..."}

      iex> Opal.Auth.get_api_key("unknown")
      {:error, :not_configured}
  """
  @spec get_api_key(String.t()) :: {:ok, String.t()} | {:error, :not_configured}
  def get_api_key(provider) when is_binary(provider) do
    case Map.get(@api_key_providers, provider) do
      nil ->
        {:error, :not_configured}

      env_var ->
        case System.get_env(env_var) do
          nil -> {:error, :not_configured}
          "" -> {:error, :not_configured}
          key -> {:ok, key}
        end
    end
  end

  @doc """
  Returns provider configuration for OpenAICompatible provider.

  Builds the endpoint URL and includes the API key for a given provider.

  ## Parameters

    * `provider` - Provider name (e.g., "openrouter", "groq", "nvidia", "cerebras")

  ## Examples

      iex> Opal.Auth.get_provider_config("openrouter")
      {:ok, %{endpoint: "https://openrouter.ai/api/v1/chat/completions", api_key: "..."}}
  """
  @spec get_provider_config(String.t()) :: {:ok, map()} | {:error, term()}
  def get_provider_config(provider) when is_binary(provider) do
    with {:ok, api_key} <- get_api_key(provider),
         {:ok, endpoint} <- get_endpoint_for_provider(provider) do
      {:ok, %{endpoint: endpoint, api_key: api_key}}
    end
  end

  @doc """
  Returns the API endpoint URL for a provider.
  """
  @spec get_endpoint_for_provider(String.t()) :: {:ok, String.t()} | {:error, :unknown_provider}
  def get_endpoint_for_provider(provider) do
    endpoints = %{
      "openrouter" => "https://openrouter.ai/api/v1/chat/completions",
      "groq" => "https://api.groq.com/openai/v1/chat/completions",
      "nvidia" => "https://integrate.api.nvidia.com/v1/chat/completions",
      "cerebras" => "https://api.cerebras.ai/v1/chat/completions",
      "openai" => "https://api.openai.com/v1/chat/completions",
      "anthropic" => "https://api.anthropic.com/v1/messages"
    }

    case Map.get(endpoints, provider) do
      nil -> {:error, :unknown_provider}
      url -> {:ok, url}
    end
  end
end
