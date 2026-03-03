defmodule Opal.Provider.OpenAICompatible do
  @moduledoc """
  OpenAI-compatible provider for Opal.

  Works with any OpenAI-compatible API endpoint:
    * OpenRouter (https://openrouter.ai)
    * Nvidia NIM (https://integrate.api.nvidia.com)
    * Groq (https://api.groq.com)
    * Cerebras (https://api.cerebras.ai)
    * Any OpenAI-compatible endpoint

  ## Usage

      # Start a session with OpenRouter
      {:ok, agent} = Opal.start_session(%{
        provider: Opal.Provider.OpenAICompatible,
        model: "openrouter/meta-llama/llama-3-8b-instruct:free",
        config: %{
          endpoint: "https://openrouter.ai/api/v1/chat/completions",
          api_key: System.get_env("OPENROUTER_API_KEY")
        }
      })

      # Or with Groq
      {:ok, agent} = Opal.start_session(%{
        provider: Opal.Provider.OpenAICompatible,
        model: "llama-3.1-8b-instant",
        config: %{
          endpoint: "https://api.groq.com/openai/v1/chat/completions",
          api_key: System.get_env("GROQ_API_KEY")
        }
      })

  ## Configuration

  The following options can be passed in the `:config` map:

    * `:endpoint` - API endpoint URL (required)
    * `:api_key` - API key for authentication (required)
    * `:model` - Model ID to use (optional, defaults to the model from session config)
    * `:headers` - Additional headers (optional)

  ## Streaming

  Uses SSE streaming via `Req.post/2` with `into: :self`, routing events
  to the calling process's mailbox for incremental processing.
  """

  @behaviour Opal.Provider

  # ── Callbacks ──────────────────────────────────────────────────────

  @impl true
  def stream(model, messages, tools, opts \\ []) do
    # Get provider config from Opal.Config.provider_config
    config =
      case Keyword.get(opts, :config) do
        %Opal.Config{provider_config: provider_config} -> provider_config
        %{} = cfg -> cfg
        _ -> %{}
      end

    endpoint = Map.get(config, :endpoint, "https://api.openai.com/v1/chat/completions")
    api_key = Map.fetch!(config, :api_key)
    model_id = Map.get(config, :model, model.id)

    # Convert Opal messages to OpenAI format
    openai_messages = convert_messages(model, messages)

    # Build the request body
    body = %{
      model: model_id,
      messages: openai_messages,
      stream: true,
      stream_options: %{include_usage: true}
    }

    # Add tools if provided
    body =
      if tools && length(tools) > 0 do
        Map.put(body, :tools, convert_tools(tools, Keyword.get(opts, :tool_context, %{})))
      else
        body
      end

    # Add reasoning_effort for thinking models
    body = maybe_add_reasoning(body, model)

    # Build headers
    headers = build_headers(config)

    # Make the streaming request
    Req.post(
      url: endpoint,
      headers: headers,
      auth: {:bearer, api_key},
      json: body,
      into: :self,
      receive_timeout: 120_000
    )
  end

  @impl true
  def parse_stream_event(data) do
    # Decode JSON string first, then parse
    case Jason.decode(data) do
      {:ok, %{"choices" => _} = event} -> Opal.Provider.parse_chat_event(event)
      {:ok, %{"error" => error}} -> [{:error, error}]
      {:ok, _} -> []
      {:error, _} -> []
    end
  end

  @impl true
  def convert_messages(model, messages) do
    # Reuse Opal's built-in converter with thinking support
    include_thinking = model.thinking_level != :off
    Opal.Provider.convert_messages_openai(messages, include_thinking: include_thinking)
  end

  @impl true
  defdelegate convert_tools(tools), to: Opal.Provider

  @doc false
  def convert_tools(tools, ctx), do: Opal.Provider.convert_tools(tools, ctx)

  # ── Helpers ────────────────────────────────────────────────────────

  defp maybe_add_reasoning(body, %{thinking_level: :off}), do: body

  defp maybe_add_reasoning(body, %{thinking_level: level}) do
    effort = Opal.Provider.reasoning_effort(level)
    Map.put(body, :reasoning_effort, effort)
  end

  defp build_headers(config) do
    base = %{
      "Content-Type" => "application/json"
    }

    # Add any custom headers from config
    custom_headers = Map.get(config, :headers, %{})

    Map.merge(base, custom_headers)
  end
end
