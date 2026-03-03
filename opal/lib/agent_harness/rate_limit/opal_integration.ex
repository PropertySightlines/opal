defmodule AgentHarness.RateLimit.OpalIntegration do
  @moduledoc """
  Integration module for wrapping Opal provider calls with rate limit routing.

  This module provides convenient wrappers around `Opal.Provider.OpenAICompatible.stream/4`
  that automatically handle rate limiting through the `AgentHarness.RateLimit.Router`.

  ## Usage

  ### Basic Integration

      # Wrap a stream call with automatic rate limit handling
      {:ok, response} = AgentHarness.RateLimit.OpalIntegration.stream_with_rate_limit(
        :groq,
        model,
        messages,
        tools,
        opts
      )

  ### In an Agent Module

      defmodule MyAgent do
        def stream_response(provider, model, messages, tools, opts) do
          AgentHarness.RateLimit.OpalIntegration.stream_with_rate_limit(
            provider,
            model,
            messages,
            tools,
            opts
          )
        end
      end

  ### With Custom Retry Configuration

      {:ok, response} = AgentHarness.RateLimit.OpalIntegration.stream_with_rate_limit(
        :groq,
        model,
        messages,
        tools,
        opts,
        max_retries: 5,
        retry_delay_ms: 2000
      )

  ## Provider Mapping

  Provider atoms are mapped to Opal provider modules:

    * `:groq` -> Groq API endpoint
    * `:cerebras` -> Cerebras API endpoint
    * `:nvidia` -> Nvidia NIM endpoint
    * `:openrouter` -> OpenRouter API endpoint

  ## Rate Limit Strategy

  Uses "queue & sleep" strategy:
    1. Check rate limit via `AgentHarness.RateLimit.Tracker`
    2. If allowed, execute immediately
    3. If rate limited, queue the request
    4. Retry after delay using `Process.send_after/3`
    5. Never switch providers on rate limit - wait for the same provider

  ## Integration Points

    * `stream_with_rate_limit/6` - Main streaming integration
    * `request_with_queue/6` - Queue-based request with callback
    * `execute_provider_call/3` - Low-level execution wrapper
  """

  alias AgentHarness.RateLimit.Router
  alias Opal.Provider.OpenAICompatible

  @type provider :: atom()
  @type stream_result :: {:ok, Req.Response.t()} | {:error, term()}

  @doc """
  Streams a response from an Opal provider with automatic rate limit handling.

  This is the primary integration point for wrapping `Opal.Provider.OpenAICompatible.stream/4`.

  ## Parameters

    * `provider` - Provider atom (`:groq`, `:cerebras`, `:nvidia`, `:openrouter`)
    * `model` - `Opal.Provider.Model` struct
    * `messages` - List of `Opal.Message` structs
    * `tools` - List of tool modules (or `[]`)
    * `opts` - Options for the stream call
    * `rate_limit_opts` - Rate limit options:
      * `:max_retries` - Maximum retry attempts (default: 3)
      * `:retry_delay_ms` - Delay between retries (default: 1000)
      * `:config` - Provider config (endpoint, api_key, etc.)

  ## Returns

    * `{:ok, %Req.Response{}}` - Successful stream response
    * `{:error, :rate_limit_exceeded}` - Max retries exceeded
    * `{:error, term()}` - Provider error

  ## Examples

      # Basic usage
      {:ok, response} = AgentHarness.RateLimit.OpalIntegration.stream_with_rate_limit(
        :groq,
        model,
        messages,
        [],
        []
      )

      # With tools and custom retry
      {:ok, response} = AgentHarness.RateLimit.OpalIntegration.stream_with_rate_limit(
        :groq,
        model,
        messages,
        [MyTool],
        [],
        max_retries: 5
      )

      # Handle rate limit exceeded
      case AgentHarness.RateLimit.OpalIntegration.stream_with_rate_limit(:groq, model, messages, [], []) do
        {:ok, response} -> process_stream(response)
        {:error, :rate_limit_exceeded} -> fallback_handler()
        {:error, reason} -> error_handler(reason)
      end
  """
  @spec stream_with_rate_limit(
          provider(),
          Opal.Provider.Model.t(),
          [Opal.Message.t()],
          [module()],
          keyword(),
          keyword()
        ) :: stream_result()
  def stream_with_rate_limit(provider, model, messages, tools, opts, rate_limit_opts \\ []) do
    max_retries = Keyword.get(rate_limit_opts, :max_retries, 3)
    retry_delay_ms = Keyword.get(rate_limit_opts, :retry_delay_ms, 1000)
    config = Keyword.get(rate_limit_opts, :config, %{})

    # Merge config into opts for the stream call
    stream_opts = Keyword.put(opts, :config, config)

    Router.execute_with_retry(provider, fn ->
      OpenAICompatible.stream(model, messages, tools, stream_opts)
    end, max_retries: max_retries, retry_delay_ms: retry_delay_ms)
  end

  @doc """
  Queues a request for later execution with a callback.

  Returns immediately with a reference. The callback is invoked when the request executes.

  ## Parameters

    * `provider` - Provider atom
    * `model` - `Opal.Provider.Model` struct
    * `messages` - List of `Opal.Message` structs
    * `tools` - List of tool modules
    * `opts` - Options for the stream call
    * `callback_opts` - Callback and queue options:
      * `:callback` - Function to call with result `fn {:ok, response} | {:error, reason} -> ... end`
      * `:max_retries` - Maximum retry attempts

  ## Returns

    * `{:executing, ref}` - Request executing now, callback will be invoked
    * `{:queued, ref}` - Request queued, callback will be invoked when executed

  ## Examples

      # Queue with callback
      {:queued, ref} = AgentHarness.RateLimit.OpalIntegration.request_with_queue(
        :groq,
        model,
        messages,
        [],
        [],
        callback: fn
          {:ok, _response} -> IO.puts("Got response!")
          {:error, _reason} -> IO.puts("Error occurred")
        end
      )

      # Cancel if needed
      AgentHarness.RateLimit.Router.cancel_request(ref)
  """
  @spec request_with_queue(
          provider(),
          Opal.Provider.Model.t(),
          [Opal.Message.t()],
          [module()],
          keyword(),
          keyword()
        ) :: {:executing, reference()} | {:queued, reference()}
  def request_with_queue(provider, model, messages, tools, opts, callback_opts \\ []) do
    callback = Keyword.get(callback_opts, :callback)
    max_retries = Keyword.get(callback_opts, :max_retries, 3)
    config = Keyword.get(callback_opts, :config, %{})

    stream_opts = Keyword.put(opts, :config, config)

    payload = %{
      model: model,
      messages: messages,
      tools: tools,
      opts: stream_opts
    }

    callback_fn =
      if callback do
        fn _request_data ->
          result =
            try do
              OpenAICompatible.stream(model, messages, tools, stream_opts)
            rescue
              e -> {:error, e}
            end

          callback.(result)
        end
      end

    Router.request(provider, payload, callback: callback_fn, max_retries: max_retries)
  end

  @doc """
  Executes a provider call with rate limit checking.

  Lower-level function for custom integration scenarios.

  ## Parameters

    * `provider` - Provider atom
    * `call_fn` - Function that makes the provider call
    * `opts` - Rate limit options

  ## Examples

      result = AgentHarness.RateLimit.OpalIntegration.execute_provider_call(:groq, fn ->
        Req.post(url: endpoint, json: body)
      end, max_retries: 3)
  """
  @spec execute_provider_call(provider(), fun(), keyword()) :: term()
  def execute_provider_call(provider, call_fn, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, 3)
    retry_delay_ms = Keyword.get(opts, :retry_delay_ms, 1000)

    Router.execute_with_retry(provider, call_fn, max_retries: max_retries, retry_delay_ms: retry_delay_ms)
  end

  @doc """
  Gets the provider configuration for a provider atom.

  Helper function to build provider config from environment or application config.

  ## Examples

      config = AgentHarness.RateLimit.OpalIntegration.get_provider_config(:groq)
      # => %{endpoint: "...", api_key: "..."}
  """
  @spec get_provider_config(provider()) :: map()
  def get_provider_config(provider) do
    base_config =
      case provider do
        :groq -> %{
          endpoint: "https://api.groq.com/openai/v1/chat/completions",
          api_key_env: "GROQ_API_KEY"
        }

        :cerebras -> %{
          endpoint: "https://api.cerebras.ai/v1/chat/completions",
          api_key_env: "CEREBRAS_API_KEY"
        }

        :nvidia -> %{
          endpoint: "https://integrate.api.nvidia.com/v1/chat/completions",
          api_key_env: "NVIDIA_API_KEY"
        }

        :openrouter -> %{
          endpoint: "https://openrouter.ai/api/v1/chat/completions",
          api_key_env: "OPENROUTER_API_KEY"
        }

        _ -> %{}
      end

    # Load API key from environment
    api_key_env = Map.get(base_config, :api_key_env)
    api_key = if api_key_env, do: System.get_env(api_key_env), else: nil

    base_config
    |> Map.delete(:api_key_env)
    |> Map.put(:api_key, api_key)
  end

  @doc """
  Creates a complete streaming call with all configuration.

  Convenience function that combines provider config lookup with rate-limited streaming.

  ## Examples

      {:ok, response} = AgentHarness.RateLimit.OpalIntegration.complete_stream(
        :groq,
        "llama-3.1-8b-instant",
        messages,
        tools,
        max_retries: 3
      )
  """
  @spec complete_stream(
          provider(),
          String.t(),
          [Opal.Message.t()],
          [module()],
          keyword()
        ) :: stream_result()
  def complete_stream(provider, model_id, messages, tools, opts \\ []) do
    config = get_provider_config(provider)
    max_retries = Keyword.get(opts, :max_retries, 3)

    model = %Opal.Provider.Model{
      id: model_id,
      provider: provider,
      thinking_level: Keyword.get(opts, :thinking_level, :off)
    }

    stream_with_rate_limit(provider, model, messages, tools, [],
      max_retries: max_retries,
      config: config
    )
  end
end
