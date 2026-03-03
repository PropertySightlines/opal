defmodule AgentHarness.Topology.Registry do
  @moduledoc """
  Registry for Agent Harness topologies.

  Provides dynamic registration and lookup of topology implementations,
  allowing runtime switching between different execution strategies.

  ## Features

    * Register topologies by atom name
    * Dynamic topology switching at runtime
    * Built-in topologies auto-registered on first use
    * Thread-safe registration and lookup

  ## Usage

      # Register a custom topology
      AgentHarness.Topology.Registry.register(:custom, MyCustomTopology)

      # Run tasks using a registered topology by name
      AgentHarness.Topology.Registry.run(:sequential, tasks, timeout: 30_000)

      # List all registered topologies
      AgentHarness.Topology.Registry.list()
      # => [:sequential, :parallel, :custom]

      # Unregister a topology
      AgentHarness.Topology.Registry.unregister(:custom)

  ## Built-in Topologies

  The following topologies are available by default:

    * `:sequential` - `AgentHarness.Topology.Sequential`
    * `:parallel` - `AgentHarness.Topology.Parallel`

  ## Dynamic Topology Switching

  Topologies can be switched at runtime based on task requirements:

      topology =
        if tasks_require_ordering do
          :sequential
        else
          :parallel
        end

      AgentHarness.Topology.Registry.run(topology, tasks)

  ## Custom Topologies

  Create a custom topology by implementing the `AgentHarness.Topology` behaviour:

      defmodule MyCustomTopology do
        @behaviour AgentHarness.Topology

        @impl true
        def run(tasks, opts) do
          # Custom execution logic
          {:ok, %{results: results, metadata: metadata}}
        end

        @impl true
        def name, do: :custom
      end

      # Register and use
      AgentHarness.Topology.Registry.register(:custom, MyCustomTopology)
      AgentHarness.Topology.Registry.run(:custom, tasks)

  ## Options

  Options are passed through to the underlying topology implementation.
  See specific topology documentation for available options.
  """

  use GenServer

  require Logger

  # Built-in topologies
  @builtin_topologies %{
    sequential: AgentHarness.Topology.Sequential,
    parallel: AgentHarness.Topology.Parallel
  }

  # -- State --

  defstruct [
    topologies: @builtin_topologies
  ]

  @type t :: %__MODULE__{}

  @type topology_name :: atom()

  @type topology_module :: module()

  # ── Public API ─────────────────────────────────────────────────────

  @doc """
  Starts the topology registry GenServer.

  ## Options

    * `:name` - Registered name for the GenServer (default: `__MODULE__`)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Registers a topology module under the given name.

  ## Parameters

    * `name` - Atom name to register the topology under
    * `module` - Module implementing `AgentHarness.Topology` behaviour
    * `server` - Registry server name (default: `__MODULE__`)

  ## Examples

      AgentHarness.Topology.Registry.register(:consensus, ConsensusTopology)
      AgentHarness.Topology.Registry.register(:hierarchical, HierarchicalTopology)

  ## Returns

    * `:ok` - Topology registered successfully
    * `{:error, :already_registered}` - Name is already in use
  """
  @spec register(topology_name(), topology_module(), GenServer.server()) ::
          :ok | {:error, :already_registered}
  def register(name, module, server \\ __MODULE__) do
    GenServer.call(server, {:register, name, module})
  end

  @doc """
  Unregisters a topology by name.

  ## Parameters

    * `name` - Atom name of the topology to unregister
    * `server` - Registry server name (default: `__MODULE__`)

  ## Examples

      AgentHarness.Topology.Registry.unregister(:custom)

  ## Returns

    * `:ok` - Topology unregistered successfully
    * `{:error, :not_found}` - Topology name not found
    * `{:error, :builtin}` - Cannot unregister built-in topologies
  """
  @spec unregister(topology_name(), GenServer.server()) ::
          :ok | {:error, :not_found} | {:error, :builtin}
  def unregister(name, server \\ __MODULE__) do
    GenServer.call(server, {:unregister, name})
  end

  @doc """
  Looks up a topology module by name.

  ## Parameters

    * `name` - Atom name of the topology
    * `server` - Registry server name (default: `__MODULE__`)

  ## Examples

      {:ok, module} = AgentHarness.Topology.Registry.lookup(:sequential)
      # => {:ok, AgentHarness.Topology.Sequential}

      :error = AgentHarness.Topology.Registry.lookup(:nonexistent)

  ## Returns

    * `{:ok, module}` - Topology found
    * `:error` - Topology not found
  """
  @spec lookup(topology_name(), GenServer.server()) :: {:ok, topology_module()} | :error
  def lookup(name, server \\ __MODULE__) do
    GenServer.call(server, {:lookup, name})
  end

  @doc """
  Runs tasks using the registered topology.

  ## Parameters

    * `name` - Atom name of the topology to use
    * `tasks` - List of task maps to execute
    * `opts` - Options passed to the topology's `run/2` callback
    * `server` - Registry server name (default: `__MODULE__`)

  ## Examples

      tasks = [
        %{id: "task1", agent: MyAgent, input: %{data: "value"}}
      ]

      AgentHarness.Topology.Registry.run(:sequential, tasks, timeout: 30_000)

  ## Returns

    * `{:ok, result}` - Execution completed successfully
    * `{:error, reason}` - Execution failed

  ## See Also

    * `AgentHarness.Topology.Sequential` for sequential execution options
    * `AgentHarness.Topology.Parallel` for parallel execution options
  """
  @spec run(topology_name(), list(map()), keyword(), GenServer.server()) ::
          {:ok, map()} | {:error, term()}
  def run(name, tasks, opts \\ [], server \\ __MODULE__) do
    case lookup(name, server) do
      {:ok, module} ->
        Logger.debug("[Topology.Registry] Running topology: #{name} with #{length(tasks)} tasks")
        module.run(tasks, opts)

      :error ->
        Logger.error("[Topology.Registry] Topology not found: #{name}")
        {:error, {:unknown_topology, name}}
    end
  end

  @doc """
  Lists all registered topology names.

  ## Parameters

    * `server` - Registry server name (default: `__MODULE__`)

  ## Examples

      AgentHarness.Topology.Registry.list()
      # => [:parallel, :sequential, :custom]

  ## Returns

    * `list(atom())` - List of registered topology names
  """
  @spec list(GenServer.server()) :: [topology_name()]
  def list(server \\ __MODULE__) do
    GenServer.call(server, :list)
  end

  @doc """
  Returns information about a registered topology.

  ## Parameters

    * `name` - Atom name of the topology
    * `server` - Registry server name (default: `__MODULE__`)

  ## Examples

      {:ok, info} = AgentHarness.Topology.Registry.info(:sequential)
      # => %{name: :sequential, module: AgentHarness.Topology.Sequential, builtin: true}

  ## Returns

    * `{:ok, info}` - Topology information map
    * `:error` - Topology not found
  """
  @spec info(topology_name(), GenServer.server()) :: {:ok, map()} | :error
  def info(name, server \\ __MODULE__) do
    case lookup(name, server) do
      {:ok, module} ->
        is_builtin = Map.has_key?(@builtin_topologies, name)

        info = %{
          name: name,
          module: module,
          builtin: is_builtin
        }

        # Try to get topology name from module if available
        info =
          if function_exported?(module, :name, 0) do
            Map.put(info, :topology_name, module.name())
          else
            info
          end

        {:ok, info}

      :error ->
        :error
    end
  end

  @doc """
  Checks if a topology is registered.

  ## Parameters

    * `name` - Atom name of the topology
    * `server` - Registry server name (default: `__MODULE__`)

  ## Examples

      true = AgentHarness.Topology.Registry.registered?(:sequential)
      false = AgentHarness.Topology.Registry.registered?(:nonexistent)

  ## Returns

    * `true` - Topology is registered
    * `false` - Topology is not registered
  """
  @spec registered?(topology_name(), GenServer.server()) :: boolean()
  def registered?(name, server \\ __MODULE__) do
    GenServer.call(server, {:registered?, name})
  end

  # ── GenServer Callbacks ────────────────────────────────────────────

  @impl true
  def init(_opts) do
    Logger.info("[Topology.Registry] Initialized with built-in topologies: #{inspect(Map.keys(@builtin_topologies))}")
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:register, name, module}, _from, state) do
    if Map.has_key?(state.topologies, name) do
      Logger.warning("[Topology.Registry] Topology already registered: #{name}")
      {:reply, {:error, :already_registered}, state}
    else
      Logger.debug("[Topology.Registry] Registered topology: #{name}")
      new_state = %{state | topologies: Map.put(state.topologies, name, module)}
      {:reply, :ok, new_state}
    end
  end

  def handle_call({:unregister, name}, _from, state) do
    cond do
      Map.has_key?(@builtin_topologies, name) ->
        Logger.warning("[Topology.Registry] Cannot unregister built-in topology: #{name}")
        {:reply, {:error, :builtin}, state}

      Map.has_key?(state.topologies, name) ->
        Logger.debug("[Topology.Registry] Unregistered topology: #{name}")
        new_state = %{state | topologies: Map.delete(state.topologies, name)}
        {:reply, :ok, new_state}

      true ->
        Logger.warning("[Topology.Registry] Topology not found: #{name}")
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:lookup, name}, _from, state) do
    result =
      case Map.get(state.topologies, name) do
        nil -> :error
        module -> {:ok, module}
      end

    {:reply, result, state}
  end

  def handle_call(:list, _from, state) do
    {:reply, Map.keys(state.topologies), state}
  end

  def handle_call({:registered?, name}, _from, state) do
    {:reply, Map.has_key?(state.topologies, name), state}
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.debug("[Topology.Registry] Terminating")
    :ok
  end
end
