defmodule AgentHarness.RateLimit.Tracker do
  @moduledoc """
  Rate limit tracker for Agent Harness Phase 2.

  Tracks RPM (requests per minute) and TPM (tokens per minute) per provider
  using sliding 60-second windows. Uses `:ets` for efficient time-based cleanup
  and non-blocking operations.

  ## Features

    * Sliding window algorithm for accurate rate limiting
    * Per-provider RPM and TPM tracking
    * Configurable limits per provider
    * Debug logging for observability

  ## Usage

      # Check if a request can be made
      case AgentHarness.RateLimit.Tracker.can_request?(:groq) do
        :ok -> :proceed
        {:wait, delay_ms} -> :sleep_and_retry
      end

      # Record a request after making it
      AgentHarness.RateLimit.Tracker.record_request(:groq, tokens_used: 1500)

      # Get current status
      status = AgentHarness.RateLimit.Tracker.get_status(:groq)
      # => %{rpm_remaining: 25, tpm_remaining: 55000, reset_in_ms: 45000}

  ## Provider Configuration

  Limits are configured via application config:

      config :agent_harness, :rate_limits, %{
        groq: %{rpm: 30, tpm: 60_000},
        cerebras: %{rpm: 20, tpm: 60_000},
        nvidia: %{rpm: 100, tpm: 500_000},
        openrouter: %{rpm: 60, tpm: 100_000}
      }

  Or via environment variables in `.env`:

      GROQ_RPM=30
      GROQ_TPM=60000
      CEREBRAS_RPM=20
      CEREBRAS_TPM=60000
  """

  use GenServer
  require Logger

  # -- Configuration --

  @default_window_ms 60_000
  @cleanup_interval_ms 10_000

  @default_limits %{
    groq: %{rpm: 30, tpm: 60_000},
    cerebras: %{rpm: 20, tpm: 60_000},
    nvidia: %{rpm: 100, tpm: 500_000},
    openrouter: %{rpm: 60, tpm: 100_000}
  }

  # -- State --

  defstruct [
    :ets_table,
    :table_name,
    :cleanup_timer,
    limits: %{},
    window_ms: @default_window_ms
  ]

  @type t :: %__MODULE__{}

  @type provider :: atom()

  @type status :: %{
          rpm_remaining: non_neg_integer(),
          tpm_remaining: non_neg_integer(),
          reset_in_ms: non_neg_integer()
        }

  # ── Public API ─────────────────────────────────────────────────────

  @doc """
  Starts the rate limit tracker GenServer.

  ## Options

    * `:name` - Registered name for the GenServer (default: `__MODULE__`)
    * `:limits` - Provider rate limits map (default: from config or @default_limits)
    * `:window_ms` - Sliding window duration in milliseconds (default: 60_000)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Checks if a request can be made for the given provider.

  Returns `:ok` if within limits, or `{:wait, delay_ms}` with the recommended
  delay before retrying.

  ## Examples

      iex> AgentHarness.RateLimit.Tracker.can_request?(:groq)
      :ok

      iex> AgentHarness.RateLimit.Tracker.can_request?(:groq)
      {:wait, 5000}
  """
  @spec can_request?(provider()) :: :ok | {:wait, non_neg_integer()}
  def can_request?(provider, server \\ __MODULE__) do
    GenServer.call(server, {:can_request, provider})
  end

  @doc """
  Records a request for the given provider with the specified token count.

  ## Examples

      iex> AgentHarness.RateLimit.Tracker.record_request(:groq, tokens_used: 1500)
      :ok

      iex> AgentHarness.RateLimit.Tracker.record_request(:groq, 1500)
      :ok
  """
  @spec record_request(provider(), non_neg_integer() | keyword() | map()) :: :ok
  def record_request(provider, tokens_used, server \\ __MODULE__)

  def record_request(provider, tokens_used, server) when is_integer(tokens_used) do
    GenServer.call(server, {:record_request, provider, tokens_used})
  end

  def record_request(provider, opts, server) when is_list(opts) do
    tokens = Keyword.get(opts, :tokens_used, 0)
    record_request(provider, tokens, server)
  end

  def record_request(provider, map, server) when is_map(map) do
    tokens = Map.get(map, :tokens_used, Map.get(map, "tokens_used", 0))
    record_request(provider, tokens, server)
  end

  @doc """
  Gets the current rate limit status for a provider.

  Returns a map with:
    * `:rpm_remaining` - Remaining requests in the current window
    * `:tpm_remaining` - Remaining tokens in the current window
    * `:reset_in_ms` - Time until the oldest entry expires

  ## Examples

      iex> AgentHarness.RateLimit.Tracker.get_status(:groq)
      %{rpm_remaining: 25, tpm_remaining: 55000, reset_in_ms: 45000}
  """
  @spec get_status(provider()) :: status()
  def get_status(provider, server \\ __MODULE__) do
    GenServer.call(server, {:get_status, provider})
  end

  @doc """
  Resets the rate limit counters for a specific provider.

  Useful for testing or manual intervention.
  """
  @spec reset_provider(provider()) :: :ok
  def reset_provider(provider, server \\ __MODULE__) do
    GenServer.call(server, {:reset_provider, provider})
  end

  @doc """
  Resets all rate limit counters.

  Useful for testing or manual intervention.
  """
  @spec reset_all() :: :ok
  def reset_all(server \\ __MODULE__) do
    GenServer.call(server, :reset_all)
  end

  @doc """
  Returns the configured limits for all providers.
  """
  @spec get_limits() :: map()
  def get_limits(server \\ __MODULE__) do
    GenServer.call(server, :get_limits)
  end

  @doc """
  Returns memory status for all provider queues.

  Tracks memory usage per provider based on the number of entries
  in the sliding window and estimated memory footprint.

  ## Examples

      iex> AgentHarness.RateLimit.Tracker.get_memory_status()
      %{
        providers: %{
          groq: %{entries: 15, estimated_memory_kb: 12, window_ms: 60000},
          cerebras: %{entries: 8, estimated_memory_kb: 6, window_ms: 60000}
        },
        total_entries: 23,
        total_estimated_memory_kb: 18,
        ets_table_info: %{size: 23, memory_kb: 64}
      }

  ## Returns

    * Map with memory status per provider
  """
  @spec get_memory_status() :: map()
  def get_memory_status(server \\ __MODULE__) do
    GenServer.call(server, :get_memory_status)
  end

  # ── GenServer Callbacks ────────────────────────────────────────────

  @impl true
  def init(opts) do
    Logger.debug("[RateLimit.Tracker] Initializing with opts: #{inspect(opts)}")

    # Create ETS table for storing request timestamps and token counts
    # Format: {provider, timestamp, tokens_used}
    # Use unique table name per instance to support multiple trackers (e.g., in tests)
    table_name = Keyword.get(opts, :name, __MODULE__.Requests)
    ets_table =
      case :ets.whereis(table_name) do
        :undefined ->
          :ets.new(table_name, [
            :set,
            :public,
            :named_table,
            read_concurrency: true,
            write_concurrency: false
          ])
        existing_table ->
          # Table already exists, clear it for fresh start
          :ets.delete_all_objects(existing_table)
          existing_table
      end

    # Load provider limits from config or use defaults
    limits = load_limits(opts)
    window_ms = Keyword.get(opts, :window_ms, @default_window_ms)

    # Set up periodic cleanup timer
    cleanup_timer = :timer.send_interval(@cleanup_interval_ms, :cleanup)

    state = %__MODULE__{
      ets_table: ets_table,
      cleanup_timer: cleanup_timer,
      limits: limits,
      window_ms: window_ms,
      table_name: table_name
    }

    Logger.info(
      "[RateLimit.Tracker] Started with providers: #{inspect(Map.keys(limits))}, window: #{window_ms}ms"
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:can_request, provider}, _from, state) do
    {result, state} = do_can_request(provider, state)
    {:reply, result, state}
  end

  def handle_call({:record_request, provider, tokens}, _from, state) do
    {result, state} = do_record_request(provider, tokens, state)
    {:reply, result, state}
  end

  def handle_call({:get_status, provider}, _from, state) do
    status = do_get_status(provider, state)
    {:reply, status, state}
  end

  def handle_call({:reset_provider, provider}, _from, state) do
    do_reset_provider(provider, state)
    Logger.debug("[RateLimit.Tracker] Reset provider: #{provider}")
    {:reply, :ok, state}
  end

  def handle_call(:reset_all, _from, state) do
    :ets.delete_all_objects(state.ets_table)
    Logger.info("[RateLimit.Tracker] Reset all providers")
    {:reply, :ok, state}
  end

  def handle_call(:get_limits, _from, state) do
    {:reply, state.limits, state}
  end

  def handle_call(:get_memory_status, _from, state) do
    status = do_get_memory_status(state)
    {:reply, status, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    state = do_cleanup(state)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ── Internal Implementation ────────────────────────────────────────

  defp load_limits(opts) do
    configured_limits =
      Keyword.get(opts, :limits) ||
        Application.get_env(:agent_harness, :rate_limits) ||
        @default_limits

    # Merge with defaults to ensure all providers have limits
    Map.merge(@default_limits, configured_limits)
  end

  defp do_can_request(provider, state) do
    now_ms = current_time_ms()
    window_start = now_ms - state.window_ms
    limit = get_provider_limit(provider, state)

    # Clean up old entries first
    cleanup_old_entries(provider, window_start, state.ets_table)

    # Get current counts
    {request_count, token_count} = get_current_counts(provider, window_start, state.ets_table)

    rpm_limit = Map.get(limit, :rpm, 0)
    tpm_limit = Map.get(limit, :tpm, 0)

    cond do
      rpm_limit > 0 and request_count >= rpm_limit ->
        delay = calculate_delay(provider, :rpm, window_start, state)
        Logger.debug(
          "[RateLimit.Tracker] RPM limit hit for #{provider}: #{request_count}/#{rpm_limit}, wait #{delay}ms"
        )

        {{:wait, delay}, state}

      tpm_limit > 0 and token_count >= tpm_limit ->
        delay = calculate_delay(provider, :tpm, window_start, state)
        Logger.debug(
          "[RateLimit.Tracker] TPM limit hit for #{provider}: #{token_count}/#{tpm_limit}, wait #{delay}ms"
        )

        {{:wait, delay}, state}

      true ->
        Logger.debug(
          "[RateLimit.Tracker] Request allowed for #{provider}: #{request_count}/#{rpm_limit} RPM, #{token_count}/#{tpm_limit} TPM"
        )

        {:ok, state}
    end
  end

  defp do_record_request(provider, tokens, state) do
    now_ms = current_time_ms()
    key = {provider, now_ms, System.unique_integer([:positive])}

    # Store request with timestamp and token count
    :ets.insert(state.ets_table, {key, tokens})

    Logger.debug(
      "[RateLimit.Tracker] Recorded request for #{provider}: #{tokens} tokens at #{now_ms}"
    )

    {:ok, state}
  end

  defp do_get_status(provider, state) do
    now_ms = current_time_ms()
    window_start = now_ms - state.window_ms
    limit = get_provider_limit(provider, state)

    # Clean up old entries first
    cleanup_old_entries(provider, window_start, state.ets_table)

    # Get current counts
    {request_count, token_count, oldest_timestamp} =
      get_current_counts_with_oldest(provider, window_start, state.ets_table)

    rpm_limit = Map.get(limit, :rpm, 0)
    tpm_limit = Map.get(limit, :tpm, 0)

    rpm_remaining = max(0, rpm_limit - request_count)
    tpm_remaining = max(0, tpm_limit - token_count)

    reset_in_ms =
      if oldest_timestamp != nil do
        max(0, oldest_timestamp + state.window_ms - now_ms)
      else
        0
      end

    %{
      rpm_remaining: rpm_remaining,
      tpm_remaining: tpm_remaining,
      reset_in_ms: reset_in_ms
    }
  end

  defp do_reset_provider(provider, state) do
    # Remove all entries for this provider
    :ets.match_delete(state.ets_table, {{provider, :_, :_}, :_})
    :ok
  end

  defp do_cleanup(state) do
    now_ms = current_time_ms()
    window_start = now_ms - state.window_ms

    # Get all providers
    providers = Map.keys(state.limits)

    # Clean up each provider
    Enum.each(providers, fn provider ->
      cleanup_old_entries(provider, window_start, state.ets_table)
    end)

    Logger.debug("[RateLimit.Tracker] Cleanup completed at #{now_ms}")
    state
  end

  defp cleanup_old_entries(provider, window_start, ets_table) do
    # Use select_delete to efficiently remove old entries in one operation
    # Pattern: {{provider, timestamp, unique_id}, tokens}
    # Delete where timestamp < window_start
    :ets.select_delete(ets_table, [
      {{{provider, :"$1", :_}, :_}, [{:<, :"$1", window_start}], [true]}
    ])

    :ok
  end

  defp get_current_counts(provider, window_start, ets_table) do
    pattern = {{provider, :"$1", :_}, :"$2"}
    matches = :ets.match(ets_table, pattern)

    Enum.reduce(matches, {0, 0}, fn [timestamp, tokens], {req_count, tok_count} ->
      if timestamp >= window_start do
        {req_count + 1, tok_count + tokens}
      else
        {req_count, tok_count}
      end
    end)
  end

  defp get_current_counts_with_oldest(provider, window_start, ets_table) do
    pattern = {{provider, :"$1", :_}, :"$2"}
    matches = :ets.match(ets_table, pattern)

    Enum.reduce(matches, {0, 0, nil}, fn [timestamp, tokens], {req_count, tok_count, oldest} ->
      if timestamp >= window_start do
        new_oldest =
          cond do
            oldest == nil -> timestamp
            timestamp < oldest -> timestamp
            true -> oldest
          end

        {req_count + 1, tok_count + tokens, new_oldest}
      else
        {req_count, tok_count, oldest}
      end
    end)
  end

  defp calculate_delay(provider, _limit_type, window_start, state) do
    # Find the oldest entry that's causing the limit to be exceeded
    pattern = {{provider, :"$1", :_}, :_}
    matches = :ets.match(state.ets_table, pattern)

    # Filter to entries within window and sort by timestamp
    # matches is [[timestamp1], [timestamp2], ...]
    entries_in_window =
      Enum.filter(matches, fn [timestamp] -> timestamp >= window_start end)
      |> Enum.map(fn [timestamp] -> timestamp end)
      |> Enum.sort()

    now_ms = current_time_ms()

    case entries_in_window do
      [] ->
        0

      timestamps ->
        # Find when the oldest entry will expire
        oldest = List.first(timestamps)
        delay = oldest + state.window_ms - now_ms
        max(0, delay)
    end
  end

  defp get_provider_limit(provider, state) do
    Map.get(state.limits, provider, %{rpm: 0, tpm: 0})
  end

  defp do_get_memory_status(state) do
    now_ms = current_time_ms()
    window_start = now_ms - state.window_ms

    # Get ETS table info
    ets_info = :ets.info(state.ets_table)
    ets_size = ets_info[:size] || 0
    ets_memory_kb = div(ets_info[:memory] || 0, 1024)

    # Get memory status per provider
    provider_stats =
      Enum.map(state.limits, fn {provider, _limit} ->
        {entry_count, total_tokens} = get_current_counts(provider, window_start, state.ets_table)
        # Estimate memory per entry: ~800 bytes per {key, value} tuple
        estimated_memory_kb = div(entry_count * 800, 1024)

        {provider,
         %{
           entries: entry_count,
           total_tokens: total_tokens,
           estimated_memory_kb: max(1, estimated_memory_kb),
           window_ms: state.window_ms
         }}
      end)
      |> Map.new()

    total_entries = Enum.reduce(provider_stats, 0, fn {_p, stats}, acc -> acc + stats.entries end)
    total_memory_kb = Enum.reduce(provider_stats, 0, fn {_p, stats}, acc -> acc + stats.estimated_memory_kb end)

    %{
      providers: provider_stats,
      total_entries: total_entries,
      total_estimated_memory_kb: total_memory_kb,
      ets_table_info: %{
        size: ets_size,
        memory_kb: ets_memory_kb,
        name: state.table_name
      }
    }
  end

  defp current_time_ms do
    System.system_time(:millisecond)
  end

  @impl true
  def terminate(_reason, state) do
    # Clean up ETS table on termination
    catch_error(:ets.delete(state.table_name))
    :ok
  end

  defp catch_error(fun) do
    try do
      fun.()
    rescue
      _ -> :ok
    end
  end
end
