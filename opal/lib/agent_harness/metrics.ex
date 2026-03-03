defmodule AgentHarness.Metrics do
  @moduledoc """
  Memory and system metrics for Agent Harness.

  Provides lightweight monitoring capabilities using built-in Erlang functions.
  No external dependencies required.

  ## Features

    * Memory usage tracking (current, total, allocated)
    * Process count monitoring
    * System information (ERTS version, scheduler info)
    * Agent Harness agent statistics

  ## Usage

      # Get current memory usage in MB
      memory_mb = AgentHarness.Metrics.get_memory_usage()

      # Get number of active processes
      count = AgentHarness.Metrics.get_process_count()

      # Get detailed system info
      info = AgentHarness.Metrics.get_system_info()

      # Get stats for all AgentHarness agents
      stats = AgentHarness.Metrics.get_agent_stats()

  ## Memory Metrics

  Memory is reported in megabytes (MB) for readability:

      %{
        total: 256.5,      # Total memory allocated
        processes: 45.2,   # Memory used by Erlang processes
        system: 211.3,     # Memory used by system
        atom: 1.2,         # Memory used for atoms
        binary: 15.8,      # Memory used for binaries
        code: 35.4,        # Memory used for code
        ets: 8.5           # Memory used by ETS tables
      }

  ## See Also

    * `AgentHarness.Application.get_metrics/0` - Aggregated metrics
    * `:erlang.memory/0` - Erlang memory information
    * `:erlang.process_info/2` - Process information
  """

  require Logger

  @bytes_per_mb 1_048_576

  @type memory_info :: %{
          total: float(),
          processes: float(),
          system: float(),
          atom: float(),
          binary: float(),
          code: float(),
          ets: float()
        }

  @type system_info :: %{
          erts_version: String.t(),
          elixir_version: String.t(),
          schedulers: pos_integer(),
          schedulers_online: pos_integer(),
          wordsize: pos_integer(),
          system_architecture: String.t(),
          total_memory: float(),
          total_memory_allocated: float(),
          process_count: non_neg_integer(),
          process_limit: non_neg_integer()
        }

  @type agent_stats :: %{
          total_agents: non_neg_integer(),
          agents: list(map()),
          total_children: non_neg_integer()
        }

  # ── Public API ─────────────────────────────────────────────────────

  @doc """
  Returns current memory usage in MB.

  ## Examples

      iex> AgentHarness.Metrics.get_memory_usage()
      %{
        total: 256.5,
        processes: 45.2,
        system: 211.3,
        atom: 1.2,
        binary: 15.8,
        code: 35.4,
        ets: 8.5
      }

  ## Returns

    * Map with memory breakdown in megabytes
  """
  @spec get_memory_usage() :: memory_info()
  def get_memory_usage do
    memory = :erlang.memory()

    %{
      total: bytes_to_mb(memory[:total]),
      processes: bytes_to_mb(memory[:processes]),
      system: bytes_to_mb(memory[:system]),
      atom: bytes_to_mb(memory[:atom]),
      binary: bytes_to_mb(memory[:binary]),
      code: bytes_to_mb(memory[:code]),
      ets: bytes_to_mb(memory[:ets])
    }
  end

  @doc """
  Returns the number of active processes.

  ## Examples

      iex> AgentHarness.Metrics.get_process_count()
      142

  ## Returns

    * Non-negative integer representing active process count
  """
  @spec get_process_count() :: non_neg_integer()
  def get_process_count do
    :erlang.system_info(:process_count)
  end

  @doc """
  Returns system information including ERTS version, memory, and scheduler info.

  ## Examples

      iex> AgentHarness.Metrics.get_system_info()
      %{
        erts_version: "14.2.1",
        elixir_version: "1.15.7",
        schedulers: 8,
        schedulers_online: 8,
        wordsize: 8,
        system_architecture: "x86_64-apple-darwin22.1.0",
        total_memory: 256.5,
        total_memory_allocated: 280.3,
        process_count: 142,
        process_limit: 1_048_576
      }

  ## Returns

    * Map with system information
  """
  @spec get_system_info() :: system_info()
  def get_system_info do
    memory = :erlang.memory()
    process_count = :erlang.system_info(:process_count)
    process_limit = :erlang.system_info(:process_limit)

    %{
      erts_version: :erlang.system_info(:version) |> to_string(),
      elixir_version: System.version(),
      schedulers: :erlang.system_info(:schedulers),
      schedulers_online: :erlang.system_info(:schedulers_online),
      wordsize: :erlang.system_info(:wordsize),
      system_architecture: :erlang.system_info(:system_architecture) |> to_string(),
      total_memory: bytes_to_mb(memory[:total]),
      total_memory_allocated: bytes_to_mb(memory[:total_memory_allocated]),
      process_count: process_count,
      process_limit: process_limit
    }
  end

  @doc """
  Returns statistics for all AgentHarness agents.

  Queries the AgentHarness.DynamicSupervisor to find all running agents
  and collects their statistics.

  ## Examples

      iex> AgentHarness.Metrics.get_agent_stats()
      %{
        total_agents: 5,
        agents: [
          %{
            pid: #PID<0.123.0>,
            session_id: "agent-abc123",
            children: 2,
            pending_tasks: 1,
            memory_kb: 1024
          },
          ...
        ],
        total_children: 8
      }

  ## Returns

    * Map with agent statistics
  """
  @spec get_agent_stats() :: agent_stats()
  def get_agent_stats do
    agents = collect_agent_stats()
    total_children = Enum.reduce(agents, 0, fn agent, acc -> acc + Map.get(agent, :children, 0) end)

    %{
      total_agents: length(agents),
      agents: agents,
      total_children: total_children
    }
  end

  @doc """
  Returns memory info for a specific process.

  ## Parameters

    * `pid` - Process identifier

  ## Examples

      iex> AgentHarness.Metrics.get_process_memory(pid)
      %{memory_kb: 1024, message_queue_len: 0, heap_size: 500}

  ## Returns

    * Map with process memory information or nil if process doesn't exist
  """
  @spec get_process_memory(pid()) :: map() | nil
  def get_process_memory(pid) do
    case :erlang.process_info(pid, [:memory, :message_queue_len, :heap_size, :stack_size]) do
      :undefined ->
        nil

      info when is_list(info) ->
        info_map = Map.new(info)

        %{
          memory_kb: div(Map.get(info_map, :memory, 0), 1024),
          message_queue_len: Map.get(info_map, :message_queue_len, 0),
          heap_size: Map.get(info_map, :heap_size, 0),
          stack_size: Map.get(info_map, :stack_size, 0)
        }
    end
  end

  @doc """
  Returns ETS table statistics.

  ## Examples

      iex> AgentHarness.Metrics.get_ets_stats()
      [
        %{
          name: :agent_harness_requests,
          size: 150,
          memory_kb: 512,
          objects: 150
        },
        ...
      ]

  ## Returns

    * List of ETS table statistics
  """
  @spec get_ets_stats() :: list(map())
  def get_ets_stats do
    :ets.all()
    |> Enum.map(fn table ->
      info = :ets.info(table)

      %{
        name: info[:name],
        size: info[:size],
        memory_kb: div(info[:memory], 1024),
        objects: info[:size],
        type: info[:type]
      }
    end)
    |> Enum.filter(fn stats -> stats.name != nil end)
  end

  # ── Internal Functions ─────────────────────────────────────────────

  defp bytes_to_mb(bytes) when is_integer(bytes) do
    Float.round(bytes / @bytes_per_mb, 2)
  end

  defp bytes_to_mb(bytes) when is_float(bytes) do
    Float.round(bytes / @bytes_per_mb, 2)
  end

  defp collect_agent_stats do
    # Get all children from the DynamicSupervisor
    case Supervisor.which_children(AgentHarness.DynamicSupervisor) do
      children when is_list(children) ->
        children
        |> Enum.filter(fn
          {_id, pid, :worker, _modules} when is_pid(pid) ->
            # Check if this is an AgentHarness.Agent process
            try do
              case :erlang.process_info(pid, :registered_name) do
                {:registered_name, name} ->
                  # Check if it's an agent wrapper
                  String.contains?(inspect(name), "AgentHarness.Agent")

                _ ->
                  # Try to get state via GenServer.call
                  case is_agent_process?(pid) do
                    true -> true
                    false -> false
                  end
              end
            rescue
              _ -> false
            end

          _ ->
            false
        end)
        |> Enum.map(fn {_id, pid, :worker, _modules} ->
          get_agent_info(pid)
        end)
        |> Enum.filter(fn info -> info != nil end)

      _ ->
        []
    end
  end

  defp is_agent_process?(pid) do
    try do
      # Try to call get_session_id to verify it's an agent
      GenServer.call(pid, :get_session_id, 100)
      true
    rescue
      _ -> false
    end
  end

  defp get_agent_info(pid) do
    try do
      state = GenServer.call(pid, :get_state, 100)

      %{
        pid: pid,
        session_id: state.session_id,
        children: map_size(state.children),
        pending_tasks: map_size(state.pending),
        memory_kb: div(:erlang.process_info(pid, :memory) |> elem(1), 1024)
      }
    rescue
      _ -> nil
    end
  end
end
