defmodule Opal.Auth do
  @moduledoc """
  Credential detection for Opal providers.

  Checks whether valid credentials exist for:
  - GitHub Copilot (OAuth token)
  - OpenAI-compatible providers (API keys from environment)

  Returns a summary the client can use to decide authentication flow.
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

    * `status` — `"ready"` if credentials exist, `"setup_required"` if not
    * `provider` — First available provider name, `nil` if none
    * `available_providers` — List of providers with valid credentials

  Checks in order:
  1. Copilot OAuth token
  2. API key environment variables
  """
  @spec probe() :: probe_result()
  def probe do
    copilot_ready = copilot_ready?()
    api_providers = api_key_providers_ready()

    cond do
      copilot_ready ->
        %{status: "ready", provider: "copilot", available_providers: ["copilot"]}

      api_providers != [] ->
        [first | _] = api_providers
        %{status: "ready", provider: first, available_providers: api_providers}

      true ->
        %{status: "setup_required", provider: nil, available_providers: []}
    end
  end

  @doc """
  Checks whether Copilot credentials are available.
  """
  @spec ready?() :: boolean()
  def ready? do
    probe().status == "ready"
  end

  @doc """
  Checks whether Copilot OAuth token is available.
  """
  @spec copilot_ready?() :: boolean()
  def copilot_ready? do
    case Opal.Auth.Copilot.get_token() do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Returns list of API key providers that have keys configured.

  Checks environment variables for each configured provider.
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
end
