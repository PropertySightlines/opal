defmodule AgentHarness.RateLimit.Router do
  @moduledoc """
  Rate Limit Router for Agent Harness Phase 2.

  Integrates with `AgentHarness.RateLimit.Tracker` to queue requests when rate limits are hit.
  Uses a "queue & sleep" strategy - waits for the same provider instead of switching providers.

  ## Features

    * Per-provider request queues
    * Non-blocking retry using `Process.send_after/3`
    * Integration with `Opal.Provider.OpenAICompatible.stream/4`
    * Registry-based queue process lookup
    * Priority queue support (for future enhancement)
    * Automatic retry after rate limit window resets

  ## Quick Start

      # Start the router (usually done in your application supervisor)
      {:ok, _} = AgentHarness.RateLimit.Router.start_link()

      # Queue a request - returns immediately with a reference
      {:queued, ref} = AgentHarness.RateLimit.Router.request(:groq, %{messages: [...]})

      # Or execute with automatic retry
      {:ok, result} = AgentHarness.RateLimit.Router.execute_with_retry(:groq, fn ->
        Opal.Provider.OpenAICompatible.stream(model, messages, tools, opts)
      end, max_retries: 3)

      # Get queue status
      status = AgentHarness.RateLimit.Router.get_queue_status()
      # => %{pending_requests: 5, providers_on_hold: [:groq, :cerebras]}

  ## Integration with Opal

  Wrap `Opal.Provider.OpenAICompatible.stream/4` calls:

      defmodule MyAgent do
        def stream_response(provider, model, messages, tools, opts) do
          AgentHarness.RateLimit.Router.execute_with_retry(provider, fn ->
            Opal.Provider.OpenAICompatible.stream(model, messages, tools, opts)
          end, max_retries: 3)
        end
      end

  ## Queue Behavior

  When a rate limit is hit:
    1. Request is queued with metadata (provider, payload, callback)
    2. A retry timer is set using `Process.send_after/3`
    3. When the timer fires, the request is re-checked against rate limits
    4. If allowed, the request executes; otherwise, it's re-queued

  ## Registry Usage

  Queue processes are registered in `Opal.Registry` for lookup:

      # Lookup a queue process by provider
      {:ok, pid} = Opal.Util.Registry.lookup({:rate_limit_queue, :groq})
  """

  use GenServer
  require Logger

  alias AgentHarness.RateLimit.Tracker

  # -- Configuration --

  @default_retry_interval_ms 1000
  @default_max_queue_size 100
  @registry_key_prefix :rate_limit_queue

  # -- Types --

  @type provider :: atom()

  @type request_ref :: reference()

  @type queue_request :: %{
          ref: request_ref(),
          provider: provider(),
          payload: map(),
          opts: keyword(),
          callback: fun() | nil,
          from: {pid(), term()} | nil,
          enqueued_at: non_neg_integer(),
          retries: non_neg_integer(),
          max_retries: non_neg_integer()
        }

  @type queue_status :: %{
          pending_requests: non_neg_integer(),
          providers_on_hold: [provider()],
          queue_lengths: %{provider() => non_neg_integer()}
        }

  @type execute_result :: {:ok, term()} | {:error, term()} | {:queued, request_ref()}

  # -- State --

  defstruct [
    :registry_prefix,
    :tracker_server,
    queues: %{},
    pending_count: 0,
    retry_interval_ms: @default_retry_interval_ms,
    max_queue_size: @default_max_queue_size
  ]

  @type t :: %__MODULE__{}

  # ── Public API ─────────────────────────────────────────────────────

  @doc """
  Starts the rate limit router GenServer.

  ## Options

    * `:name` - Registered name for the GenServer (default: `__MODULE__`)
    * `:registry_prefix` - Prefix for registry keys (default: `:rate_limit_queue`)
    * `:retry_interval_ms` - Default retry interval in milliseconds (default: 1000)
    * `:max_queue_size` - Maximum queue size per provider (default: 100)
    * `:tracker_server` - RateLimit.Tracker server name (default: `AgentHarness.RateLimit.Tracker`)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Queues a request for execution when rate limit allows.

  If the rate limit allows, executes immediately. Otherwise, queues the request
  and returns a reference for tracking.

  ## Parameters

    * `provider` - The provider atom (e.g., `:groq`, `:cerebras`)
    * `payload` - The request payload (messages, model, etc.)
    * `opts` - Options including:
      * `:callback` - Function to call when request executes
      * `:max_retries` - Maximum retry attempts (default: 3)
      * `:from` - Caller info for GenServer reply

  ## Returns

    * `{:executing, ref}` - Request is executing now
    * `{:queued, ref}` - Request is queued for later execution

  ## Examples

      # Simple queue
      {:queued, ref} = AgentHarness.RateLimit.Router.request(:groq, %{messages: [...]})

      # With callback
      {:queued, ref} = AgentHarness.RateLimit.Router.request(:groq, payload,
        callback: fn result -> IO.inspect(result) end
      )

      # With max retries
      {:queued, ref} = AgentHarness.RateLimit.Router.request(:groq, payload,
        max_retries: 5
      )
  """
  @spec request(provider(), map(), keyword()) :: {:executing, request_ref()} | {:queued, request_ref()}
  def request(provider, payload, opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    # Remove :server from opts before passing to GenServer
    opts_without_server = Keyword.delete(opts, :server)
    GenServer.call(server, {:request, provider, payload, opts_without_server})
  end

  @doc """
  Executes a function with automatic retry on rate limit.

  Blocks until the function can execute or max retries is exceeded.
  Uses `Process.send_after/3` for non-blocking waits between retries.

  ## Parameters

    * `provider` - The provider atom
    * `fun` - Function to execute (typically wraps provider stream call)
    * `opts` - Options including:
      * `:max_retries` - Maximum retry attempts (default: 3)
      * `:retry_delay_ms` - Delay between retries (default: from server config)

  ## Returns

    * `{:ok, result}` - Function executed successfully
    * `{:error, :rate_limit_exceeded}` - Max retries exceeded
    * `{:error, reason}` - Function execution error

  ## Examples

      # Execute with default retries
      {:ok, response} = AgentHarness.RateLimit.Router.execute_with_retry(:groq, fn ->
        Opal.Provider.OpenAICompatible.stream(model, messages, tools, opts)
      end)

      # Execute with custom retries
      {:ok, response} = AgentHarness.RateLimit.Router.execute_with_retry(:groq, fn ->
        make_api_call()
      end, max_retries: 5)

      # Handle rate limit exceeded
      case AgentHarness.RateLimit.Router.execute_with_retry(:groq, &do_request/0) do
        {:ok, result} -> handle_success(result)
        {:error, :rate_limit_exceeded} -> handle_rate_limit()
        {:error, reason} -> handle_error(reason)
      end
  """
  @spec execute_with_retry(provider(), fun(), keyword() | non_neg_integer()) :: execute_result()
  def execute_with_retry(provider, fun, opts \\ [])

  def execute_with_retry(provider, fun, max_retries) when is_integer(max_retries) do
    execute_with_retry(provider, fun, max_retries: max_retries)
  end

  def execute_with_retry(provider, fun, opts) do
    server = Keyword.get(opts, :server, __MODULE__)
    opts_without_server = Keyword.delete(opts, :server)
    GenServer.call(server, {:execute_with_retry, provider, fun, opts_without_server})
  end

  @doc """
  Gets the current queue status across all providers.

  ## Returns

    * `pending_requests` - Total number of queued requests
    * `providers_on_hold` - List of providers with rate-limited queues
    * `queue_lengths` - Map of provider to queue length

  ## Examples

      status = AgentHarness.RateLimit.Router.get_queue_status()
      # => %{
      #      pending_requests: 5,
      #      providers_on_hold: [:groq, :cerebras],
      #      queue_lengths: %{groq: 3, cerebras: 2}
      #    }

      status = AgentHarness.RateLimit.Router.get_queue_status(server)
  """
  @spec get_queue_status(GenServer.server()) :: queue_status()
  def get_queue_status(server \\ __MODULE__) do
    GenServer.call(server, :get_queue_status)
  end

  @doc """
  Gets the queue length for a specific provider.

  ## Examples

      length = AgentHarness.RateLimit.Router.get_queue_length(:groq)
      # => 3

      length = AgentHarness.RateLimit.Router.get_queue_length(:groq, server)
  """
  @spec get_queue_length(provider(), GenServer.server()) :: non_neg_integer()
  def get_queue_length(provider, server \\ __MODULE__) do
    GenServer.call(server, {:get_queue_length, provider})
  end

  @doc """
  Cancels a queued request by reference.

  ## Examples

      {:queued, ref} = AgentHarness.RateLimit.Router.request(:groq, payload)
      :ok = AgentHarness.RateLimit.Router.cancel_request(ref)
  """
  @spec cancel_request(request_ref(), GenServer.server()) :: :ok | {:error, :not_found}
  def cancel_request(ref, server \\ __MODULE__) do
    GenServer.call(server, {:cancel_request, ref})
  end

  @doc """
  Manually triggers processing of a provider's queue.

  Useful for testing or forcing a retry.

  ## Examples

      :ok = AgentHarness.RateLimit.Router.process_queue(:groq)
      :ok = AgentHarness.RateLimit.Router.process_queue(:groq, server)
  """
  @spec process_queue(provider(), GenServer.server()) :: :ok
  def process_queue(provider, server \\ __MODULE__) do
    GenServer.call(server, {:process_queue, provider})
  end

  @doc """
  Wraps an Opal provider stream call with rate limit routing.

  This is the primary integration point with Opal.

  ## Parameters

    * `provider` - Provider atom
    * `stream_fun` - Function that calls `Opal.Provider.OpenAICompatible.stream/4`
    * `opts` - Options passed to `execute_with_retry/3`

  ## Returns

    * `{:ok, %Req.Response{}}` - Stream response
    * `{:error, term()}` - Error from rate limit or provider

  ## Examples

      # Wrap OpenAICompatible.stream call
      {:ok, response} = AgentHarness.RateLimit.Router.stream_with_rate_limit(:groq, fn ->
        Opal.Provider.OpenAICompatible.stream(model, messages, tools, opts)
      end)

      # In an agent module
      defmodule MyAgent do
        def stream(provider, model, messages, tools, opts) do
          AgentHarness.RateLimit.Router.stream_with_rate_limit(provider, fn ->
            Opal.Provider.OpenAICompatible.stream(model, messages, tools, opts)
          end, max_retries: 3)
        end
      end
  """
  @spec stream_with_rate_limit(provider(), fun(), keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
  def stream_with_rate_limit(provider, stream_fun, opts \\ []) do
    execute_with_retry(provider, stream_fun, opts)
  end

  # ── GenServer Callbacks ────────────────────────────────────────────

  @impl true
  def init(opts) do
    Logger.debug("[RateLimit.Router] Initializing with opts: #{inspect(opts)}")

    registry_prefix = Keyword.get(opts, :registry_prefix, @registry_key_prefix)
    retry_interval_ms = Keyword.get(opts, :retry_interval_ms, @default_retry_interval_ms)
    max_queue_size = Keyword.get(opts, :max_queue_size, @default_max_queue_size)
    tracker_server = Keyword.get(opts, :tracker_server, Tracker)

    state = %__MODULE__{
      registry_prefix: registry_prefix,
      tracker_server: tracker_server,
      retry_interval_ms: retry_interval_ms,
      max_queue_size: max_queue_size
    }

    Logger.info(
      "[RateLimit.Router] Started with retry_interval: #{retry_interval_ms}ms, max_queue_size: #{max_queue_size}"
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:request, provider, payload, opts}, from, state) do
    {result, state} = do_request(provider, payload, opts, from, state)
    {:reply, result, state}
  end

  def handle_call({:execute_with_retry, provider, fun, opts}, _from, state) do
    {result, state} = do_execute_with_retry(provider, fun, opts, state)
    {:reply, result, state}
  end

  def handle_call(:get_queue_status, _from, state) do
    status = do_get_queue_status(state)
    {:reply, status, state}
  end

  def handle_call({:get_queue_length, provider}, _from, state) do
    length = do_get_queue_length(provider, state)
    {:reply, length, state}
  end

  def handle_call({:cancel_request, ref}, _from, state) do
    {result, state} = do_cancel_request(ref, state)
    {:reply, result, state}
  end

  def handle_call({:process_queue, provider}, _from, state) do
    {result, state} = do_process_queue(provider, state)
    {:reply, result, state}
  end

  @impl true
  def handle_info({:retry_request, provider, ref}, state) do
    {_result, state} = do_retry_request(provider, ref, state)
    {:noreply, state}
  end

  def handle_info({:execute_queued, provider}, state) do
    {_result, state} = do_execute_queued(provider, state)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Logger.debug("[RateLimit.Router] Terminating with #{state.pending_count} pending requests")
    :ok
  end

  # ── Internal Implementation ────────────────────────────────────────

  defp do_request(provider, payload, opts, from, state) do
    callback = Keyword.get(opts, :callback)
    max_retries = Keyword.get(opts, :max_retries, 3)
    ref = make_ref()

    # Check rate limit
    case Tracker.can_request?(provider, state.tracker_server) do
      :ok ->
        # Execute immediately
        Logger.debug("[RateLimit.Router] Request allowed for #{provider}, executing immediately")
        request_data = %{
          ref: ref,
          provider: provider,
          payload: payload,
          opts: opts,
          callback: callback,
          from: from,
          enqueued_at: current_time_ms(),
          retries: 0,
          max_retries: max_retries
        }

        # Record the request
        Tracker.record_request(provider, estimate_tokens(payload), state.tracker_server)

        # Execute callback if provided
        if callback do
          spawn(fn -> callback.(request_data) end)
        end

        {{:executing, ref}, state}

      {:wait, delay_ms} ->
        # Queue the request
        Logger.debug(
          "[RateLimit.Router] Rate limit hit for #{provider}, queueing request (delay: #{delay_ms}ms)"
        )

        queue_request = %{
          ref: ref,
          provider: provider,
          payload: payload,
          opts: opts,
          callback: callback,
          from: from,
          enqueued_at: current_time_ms(),
          retries: 0,
          max_retries: max_retries
        }

        state = enqueue_request(provider, queue_request, delay_ms, state)
        {{:queued, ref}, state}
    end
  end

  defp do_execute_with_retry(provider, fun, opts, state) do
    max_retries = Keyword.get(opts, :max_retries, 3)
    retry_delay_ms = Keyword.get(opts, :retry_delay_ms, state.retry_interval_ms)

    do_execute_with_retry_loop(provider, fun, max_retries, retry_delay_ms, 0, state)
  end

  defp do_execute_with_retry_loop(provider, fun, max_retries, retry_delay_ms, attempt, state) do
    case Tracker.can_request?(provider, state.tracker_server) do
      :ok ->
        # Execute the function
        Logger.debug(
          "[RateLimit.Router] Executing function for #{provider} (attempt #{attempt + 1}/#{max_retries + 1})"
        )

        Tracker.record_request(provider, 0, state.tracker_server)

        try do
          result = fun.()
          {{:ok, result}, state}
        rescue
          e ->
            Logger.error("[RateLimit.Router] Function execution error: #{inspect(e)}")
            {{:error, e}, state}
        end

      {:wait, delay_ms} ->
        if attempt >= max_retries do
          Logger.warning("[RateLimit.Router] Max retries exceeded for #{provider} after #{attempt + 1} attempts")

          {{:error, :rate_limit_exceeded}, state}
        else
          # Wait and retry using send_after for non-blocking
          Logger.debug(
            "[RateLimit.Router] Rate limit hit for #{provider}, waiting #{delay_ms}ms before retry (attempt #{attempt + 1})"
          )

          # Use the larger of the calculated delay or the configured retry delay
          actual_delay = max(delay_ms, retry_delay_ms)
          Process.send_after(self(), {:execute_queued, provider}, actual_delay)

          # Return queued status - caller will receive result via message
          ref = make_ref()
          {{:queued, ref}, state}
        end
    end
  end

  defp do_get_queue_status(state) do
    queue_lengths =
      state.queues
      |> Enum.map(fn {provider, queue} -> {provider, length(queue)} end)
      |> Map.new()

    pending_count = Enum.reduce(queue_lengths, 0, fn {_provider, len}, acc -> acc + len end)

    providers_on_hold =
      Enum.filter(queue_lengths, fn {_provider, len} -> len > 0 end)
      |> Enum.map(fn {provider, _len} -> provider end)

    %{
      pending_requests: pending_count,
      providers_on_hold: providers_on_hold,
      queue_lengths: queue_lengths
    }
  end

  defp do_get_queue_length(provider, state) do
    case Map.get(state.queues, provider) do
      nil -> 0
      queue -> length(queue)
    end
  end

  defp do_cancel_request(ref, state) do
    # Search all queues for the request
    found =
      Enum.find_value(state.queues, nil, fn {provider, queue} ->
        if Enum.any?(queue, fn req -> req.ref == ref end) do
          provider
        end
      end)

    case found do
      nil ->
        {{:error, :not_found}, state}

      provider ->
        queue = Map.get(state.queues, provider, [])
        new_queue = Enum.reject(queue, fn req -> req.ref == ref end)
        state = put_in(state.queues[provider], new_queue)
        state = update_in(state.pending_count, &(&1 - 1))

        Logger.debug("[RateLimit.Router] Cancelled request #{inspect(ref)} from #{provider} queue")
        {:ok, state}
    end
  end

  defp do_process_queue(provider, state) do
    {result, state} = do_execute_queued(provider, state)
    {result, state}
  end

  defp do_retry_request(provider, ref, state) do
    queue = Map.get(state.queues, provider, [])

    case Enum.find(queue, fn req -> req.ref == ref end) do
      nil ->
        # Request was cancelled or already processed
        {:ok, state}

      request ->
        # Check rate limit again
        case Tracker.can_request?(provider, state.tracker_server) do
          :ok ->
            # Execute the request
            state = dequeue_request(provider, ref, state)
            Tracker.record_request(provider, estimate_tokens(request.payload), state.tracker_server)

            # Notify caller or execute callback
            if request.callback do
              spawn(fn -> request.callback.(request) end)
            end

            if request.from do
              GenServer.reply(request.from, {:executing, ref})
            end

            Logger.debug("[RateLimit.Router] Executing queued request #{inspect(ref)} for #{provider}")
            {:ok, state}

          {:wait, delay_ms} ->
            # Re-queue with incremented retry count
            if request.retries >= request.max_retries do
              # Max retries exceeded, remove from queue
              state = dequeue_request(provider, ref, state)

              if request.from do
                GenServer.reply(request.from, {:error, :rate_limit_exceeded})
              end

              Logger.warning("[RateLimit.Router] Request #{inspect(ref)} exceeded max retries for #{provider}")

              {:ok, state}
            else
              # Update retry count and re-queue
              updated_request = %{request | retries: request.retries + 1}
              state = dequeue_request(provider, ref, state)
              state = enqueue_request(provider, updated_request, delay_ms, state)

              Logger.debug(
                "[RateLimit.Router] Re-queueing request #{inspect(ref)} for #{provider} (retry #{updated_request.retries})"
              )

              {:ok, state}
            end
        end
    end
  end

  defp do_execute_queued(provider, state) do
    queue = Map.get(state.queues, provider, [])

    if length(queue) > 0 do
      # Try to process the first request in the queue
      case Tracker.can_request?(provider, state.tracker_server) do
        :ok ->
          [request | remaining] = queue
          state = put_in(state.queues[provider], remaining)
          state = update_in(state.pending_count, &(&1 - 1))

          Tracker.record_request(provider, estimate_tokens(request.payload), state.tracker_server)

          # Execute callback if provided
          if request.callback do
            spawn(fn -> request.callback.(request) end)
          end

          if request.from do
            GenServer.reply(request.from, {:executing, request.ref})
          end

          Logger.debug(
            "[RateLimit.Router] Processed queued request #{inspect(request.ref)} for #{provider}"
          )

          # Schedule next queue processing
          Process.send_after(self(), {:execute_queued, provider}, state.retry_interval_ms)

          {:ok, state}

        {:wait, delay_ms} ->
          # Set up retry timer for the queue
          Process.send_after(self(), {:execute_queued, provider}, delay_ms)
          {:ok, state}
      end
    else
      {:ok, state}
    end
  end

  defp enqueue_request(provider, request, delay_ms, state) do
    queue = Map.get(state.queues, provider, [])

    # Check max queue size
    if length(queue) >= state.max_queue_size do
      Logger.warning("[RateLimit.Router] Queue full for #{provider}, dropping request")
      state
    else
      new_queue = queue ++ [request]
      state = put_in(state.queues[provider], new_queue)
      state = update_in(state.pending_count, &(&1 + 1))

      # Set up retry timer
      Process.send_after(self(), {:retry_request, provider, request.ref}, delay_ms)

      # Register queue process in registry for lookup
      register_queue_process(provider, self())

      Logger.debug(
        "[RateLimit.Router] Enqueued request #{inspect(request.ref)} for #{provider} (queue length: #{length(new_queue)})"
      )

      state
    end
  end

  defp dequeue_request(provider, ref, state) do
    queue = Map.get(state.queues, provider, [])
    new_queue = Enum.reject(queue, fn req -> req.ref == ref end)
    state = put_in(state.queues[provider], new_queue)
    state = update_in(state.pending_count, &(&1 - 1))
    state
  end

  defp register_queue_process(provider, pid) do
    registry_key = {@registry_key_prefix, provider}

    # Register in Opal.Registry if available
    case Code.ensure_loaded(Opal.Registry) do
      {:module, Opal.Registry} ->
        Registry.register(Opal.Registry, registry_key, %{pid: pid, type: :rate_limit_queue})
        Logger.debug("[RateLimit.Router] Registered queue process for #{provider} in registry")

      _ ->
        Logger.debug("[RateLimit.Router] Opal.Registry not available, skipping registration")
    end
  end

  defp estimate_tokens(payload) do
    # Simple estimation based on message content length
    # In production, this could use a more sophisticated tokenizer
    messages = Map.get(payload, :messages, [])

    Enum.reduce(messages, 0, fn msg, acc ->
      content = Map.get(msg, :content, "")
      acc + (String.length(content) |> div(4))
    end)
    |> max(100) # Minimum estimate of 100 tokens per request
  end

  defp current_time_ms do
    System.system_time(:millisecond)
  end
end
