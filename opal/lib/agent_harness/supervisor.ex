defmodule AgentHarness.Supervisor do
  @moduledoc """
  Agent Harness Supervisor.

  Supervises the Agent Harness components with a `:rest_for_one` strategy
  to ensure graceful shutdown and proper restart semantics.

  ## Supervision Tree

      AgentHarness.Supervisor
      ├── AgentHarness.Registry (Registry)
      ├── AgentHarness.RateLimit.Tracker (GenServer)
      ├── AgentHarness.RateLimit.Router (GenServer)
      ├── AgentHarness.Topology.TaskSupervisor (Task.Supervisor)
      └── AgentHarness.DynamicSupervisor (DynamicSupervisor)

  ## Strategy

  Uses `:rest_for_one` strategy:
    * If Registry fails, all components are restarted (they depend on it)
    * If RateLimit.Tracker fails, Router and dependents restart
    * If RateLimit.Router fails, only Router restarts
    * If TaskSupervisor fails, only TaskSupervisor restarts
    * If DynamicSupervisor fails, only DynamicSupervisor restarts

  ## Graceful Shutdown

  Components are shut down in reverse order with a 5-second timeout:
    1. DynamicSupervisor (terminates all agent processes)
    2. TaskSupervisor (terminates running tasks)
    3. RateLimit.Router (drains pending requests)
    4. RateLimit.Tracker (finalizes rate limit state)
    5. Registry (unregisters all processes)

  ## Integration with Opal

  This supervisor is designed to coexist with `Opal.Supervisor`.
  It does not modify Opal's supervision tree but extends it via composition.

  The Registry can optionally share entries with `Opal.Registry` for
  cross-component discovery.

  ## Usage

  The supervisor is started automatically by `AgentHarness.Application`.
  For manual control:

      # Start the supervisor
      {:ok, pid} = AgentHarness.Supervisor.start_link()

      # Count supervised children
      Supervisor.count_children(AgentHarness.Supervisor)

      # Terminate the supervisor (and all children)
      Supervisor.stop(AgentHarness.Supervisor)

  ## Child Specifications

  Each child is configured with appropriate restart and shutdown settings:

      # Registry - permanent, never restarts (application handles this)
      {Registry, keys: :unique, name: AgentHarness.Registry}

      # RateLimit.Tracker - permanent, restarts on failure
      AgentHarness.RateLimit.Tracker

      # RateLimit.Router - permanent, restarts on failure
      AgentHarness.RateLimit.Router

      # TaskSupervisor - permanent, restarts on failure
      {Task.Supervisor, name: AgentHarness.Topology.TaskSupervisor}

      # DynamicSupervisor - permanent, restarts on failure
      {DynamicSupervisor, name: AgentHarness.DynamicSupervisor, strategy: :one_for_one}

  ## Monitoring

  Monitor the supervisor for failures:

      Process.monitor(AgentHarness.Supervisor)

  Receive `:DOWN` message if supervisor terminates.

  ## See Also

    * `AgentHarness.Application` - Application module
    * `AgentHarness.RateLimit.Tracker` - Rate limit tracking
    * `AgentHarness.RateLimit.Router` - Request routing
    * `AgentHarness.Topology.TaskSupervisor` - Task execution
    * `AgentHarness.DynamicSupervisor` - Agent process management
  """

  use Supervisor

  require Logger

  @doc """
  Starts the Agent Harness supervisor.

  ## Options

    * `:name` - Registered name for the supervisor (default: `__MODULE__`)
    * `:strategy` - Supervision strategy (default: `:rest_for_one`)

  ## Examples

      {:ok, pid} = AgentHarness.Supervisor.start_link()
      {:ok, pid} = AgentHarness.Supervisor.start_link(name: MySupervisor)
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(_opts) do
    Logger.debug("[AgentHarness.Supervisor] Initializing supervision tree")

    # Define child specifications with appropriate restart and shutdown settings
    children = [
      # Registry for agent and component lookup
      # Unique keys ensure single registration per key
      # Shutdown :infinity to allow clean unregistration
      {Registry, keys: :unique, name: AgentHarness.Registry, shutdown: :infinity},

      # Rate Limit Tracker - monitors RPM/TPM per provider
      # Uses ETS for efficient time-based operations
      # Graceful shutdown allows final state persistence
      {AgentHarness.RateLimit.Tracker, shutdown: 5_000},

      # Rate Limit Router - queues requests when limits are hit
      # Integrates with Tracker for rate limit enforcement
      # Graceful shutdown allows pending request completion
      {AgentHarness.RateLimit.Router, shutdown: 5_000},

      # Task Supervisor for parallel topology execution
      # Used by AgentHarness.Topology.Parallel for concurrent tasks
      # Simple one_for_one strategy for task isolation
      {Task.Supervisor,
       name: AgentHarness.Topology.TaskSupervisor,
       start_child: {Task.Supervisor, :start_link, [[shutdown: 5_000]]}},

      # Dynamic Supervisor for agent processes
      # Spawns agent processes on demand
      # one_for_one strategy ensures agent failures don't cascade
      {DynamicSupervisor,
       name: AgentHarness.DynamicSupervisor, strategy: :one_for_one, shutdown: 5_000}
    ]

    # Use :rest_for_one for proper dependency ordering
    # Registry is started first and must be available for other components
    # If Registry fails, all dependent components should restart
    opts = [strategy: :rest_for_one]

    Logger.info(
      "[AgentHarness.Supervisor] Starting with #{length(children)} children using :rest_for_one strategy"
    )

    Supervisor.init(children, opts)
  end

  @doc """
  Returns the list of all supervised children.

  ## Examples

      children = AgentHarness.Supervisor.which_children()
      # => [
      #      {AgentHarness.DynamicSupervisor, pid, :supervisor, [...]},
      #      {AgentHarness.Topology.TaskSupervisor, pid, :supervisor, [...]},
      #      ...
      #    ]
  """
  @spec which_children() :: Supervisor.children()
  def which_children do
    Supervisor.which_children(__MODULE__)
  end

  @doc """
  Returns a count of supervised children.

  ## Examples

      count = AgentHarness.Supervisor.count_children()
      # => %{active: 5, supervisors: 2, workers: 3, specs: 5}
  """
  @spec count_children() :: Supervisor.count_children()
  def count_children do
    Supervisor.count_children(__MODULE__)
  end

  @doc """
  Terminates a child by name or PID.

  ## Examples

      # Terminate by registered name
      :ok = AgentHarness.Supervisor.terminate_child(AgentHarness.RateLimit.Router)

      # Terminate by PID
      :ok = AgentHarness.Supervisor.terminate_child(pid)
  """
  @spec terminate_child(GenServer.server() | pid()) :: :ok | {:error, :not_found}
  def terminate_child(child_spec) do
    case Supervisor.terminate_child(__MODULE__, child_spec) do
      :ok -> :ok
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @doc """
  Restarts a child after termination.

  ## Examples

      # Terminate and restart the router
      :ok = AgentHarness.Supervisor.terminate_child(AgentHarness.RateLimit.Router)
      {:ok, pid} = AgentHarness.Supervisor.restart_child(AgentHarness.RateLimit.Router)
  """
  @spec restart_child(atom()) :: {:ok, pid()} | {:error, term()}
  def restart_child(child_name) do
    Supervisor.restart_child(__MODULE__, child_name)
  end

  @doc """
  Returns the supervisor PID.

  ## Examples

      pid = AgentHarness.Supervisor.whereis()
  """
  @spec whereis() :: pid() | nil
  def whereis do
    Process.whereis(__MODULE__)
  end

  @doc """
  Checks if the supervisor is alive.

  ## Examples

      true = AgentHarness.Supervisor.alive?()
  """
  @spec alive?() :: boolean()
  def alive? do
    case whereis() do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end

  @doc """
  Stops the supervisor gracefully.

  ## Options

    * `:reason` - Stop reason (default: `:normal`)
    * `:timeout` - Shutdown timeout in ms (default: `:infinity`)

  ## Examples

      :ok = AgentHarness.Supervisor.stop()
      :ok = AgentHarness.Supervisor.stop(:shutdown)
  """
  @spec stop(:normal | :shutdown | term(), timeout()) :: :ok
  def stop(reason \\ :normal, timeout \\ :infinity) do
    Supervisor.stop(__MODULE__, reason, timeout)
  end
end
