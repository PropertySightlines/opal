defmodule AgentHarness.Agent do
  @moduledoc """
  Agent Communication Layer for Agent Harness Phase 2.

  Provides OTP-native messaging capabilities for hierarchical agent trees.
  Wraps Opal sessions with parent-child delegation and result reporting.

  ## Features

    * Parent → Child task delegation via `delegate/3`
    * Child → Parent result reporting via `report/3`
    * Child agent spawning under supervisor via `spawn_child/2`
    * Broadcast to multiple children via `broadcast/2`
    * Correlation IDs for request/response matching
    * Configurable timeouts with automatic notifications
    * Optional retry logic
    * Integration with `Opal.Events` for pub/sub

  ## Message Protocol

  All messages follow a standard protocol:

      # Task delegation (parent → child)
      {:task, task_data, sender_pid, correlation_id}

      # Result reporting (child → parent)
      {:result, result_data, correlation_id}

      # Status updates
      {:status, status_atom, metadata}

      # Error handling
      {:error, reason, correlation_id}

  ## Usage

  ### Parent Delegating to Child

      # Spawn a child agent
      {:ok, child_pid} = AgentHarness.Agent.spawn_child(parent_pid, %{
        system_prompt: "You are a research specialist"
      })

      # Delegate a task and wait for result
      {:ok, result} = AgentHarness.Agent.delegate(parent_pid, child_pid, %{
        type: :research,
        query: "Find information about Elixir GenServer patterns"
      }, timeout: 30_000)

  ### Child Reporting Results

      # In the child agent process
      AgentHarness.Agent.report(child_pid, parent_pid, %{
        findings: [...],
        summary: "Key patterns identified..."
      })

  ### Broadcasting to Multiple Children

      tasks = [
        {child1_pid, %{query: "weather NYC"}},
        {child2_pid, %{query: "weather LA"}},
        {child3_pid, %{query: "weather Chicago"}}
      ]

      results = AgentHarness.Agent.broadcast(parent_pid, tasks, timeout: 60_000)

  ## Architecture

  The Agent GenServer wraps an Opal.Agent session and adds:

    * Message queue for incoming tasks
    * Pending request tracking with correlation IDs
    * Timeout monitoring per delegation
    * Event forwarding to parent via `Opal.Events`

  ## State Management

  Each agent maintains:

    * `session_id` - Unique identifier for the Opal session
    * `parent_pid` - Reference to parent agent (if any)
    * `children` - Map of child PIDs under this agent
    * `pending` - Map of correlation_id → {from, timeout_ref, task}
    * `message_queue` - Queue of incoming messages to process

  ## Timeout Handling

  Timeouts are configurable per task:

      # Default timeout (30 seconds)
      AgentHarness.Agent.delegate(parent_pid, child_pid, task)

      # Custom timeout
      AgentHarness.Agent.delegate(parent_pid, child_pid, task, timeout: 60_000)

      # With retry
      AgentHarness.Agent.delegate(parent_pid, child_pid, task,
        timeout: 30_000,
        retry_count: 2,
        retry_delay: 5_000
      )

  ## Correlation IDs

  Each delegation generates a unique correlation ID for matching
  requests with responses:

      correlation_id = "task-" <> Opal.Id.session()

  This ensures that even with concurrent delegations, responses
  are matched to the correct request.

  ## Integration with Opal.Events

  All agent events are broadcast via `Opal.Events`:

      # Subscribe to agent events
      Opal.Events.subscribe(session_id)

      # Receive events
      receive do
        {:opal_event, ^session_id, {:task_received, task_data}} ->
          # Handle task received
        {:opal_event, ^session_id, {:task_completed, result}} ->
          # Handle task completed
      end

  ## See Also

    * `Opal.Agent` - Base agent implementation
    * `Opal.Events` - Event pub/sub system
    * `AgentHarness.Topology` - Execution topologies
  """

  use GenServer

  require Logger

  alias Opal.Agent
  alias Opal.Events

  # Default timeouts
  @default_timeout 30_000
  @default_retry_count 0
  @default_retry_delay 5_000

  # -- State --

  defstruct [
    :session_id,
    :agent_pid,
    :parent_pid,
    :supervisor,
    children: %{},
    pending: %{},
    message_queue: [],
    correlation_counter: 0
  ]

  @type t :: %__MODULE__{}

  @type task_data :: map()

  @type result_data :: map()

  @type correlation_id :: String.t()

  @type sender_pid :: pid()

  @type status_atom :: :running | :waiting | :completed | :failed

  @type metadata :: map()

  # ── Public API ─────────────────────────────────────────────────────

  @doc """
  Starts an agent communication wrapper.

  ## Options

    * `:session_id` - Session ID for the Opal agent (required)
    * `:agent_pid` - PID of the Opal.Agent process (required)
    * `:parent_pid` - Parent agent PID (optional, for child agents)
    * `:supervisor` - DynamicSupervisor for spawning children (optional)
    * `:name` - Registered name for the GenServer (optional)

  ## Examples

      {:ok, pid} = AgentHarness.Agent.start_link(
        session_id: "agent-123",
        agent_pid: agent_pid,
        parent_pid: parent_pid
      )

  ## Returns

    * `{:ok, pid}` - Agent started successfully
    * `{:error, reason}` - Failed to start
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Delegates a task from parent to child agent.

  Sends the task to the child and waits for the result.
  Uses correlation IDs to match request/response.

  ## Parameters

    * `parent_pid` - PID of the parent agent (sender)
    * `child_pid` - PID of the child agent (receiver)
    * `task` - Task data to delegate
    * `opts` - Options:
      * `:timeout` - Timeout in milliseconds (default: #{@default_timeout})
      * `:retry_count` - Number of retries on timeout (default: #{@default_retry_count})
      * `:retry_delay` - Delay between retries in ms (default: #{@default_retry_delay})

  ## Examples

      {:ok, result} = AgentHarness.Agent.delegate(parent_pid, child_pid, %{
        type: :analyze,
        data: "some data to analyze"
      })

      {:ok, result} = AgentHarness.Agent.delegate(parent_pid, child_pid, task,
        timeout: 60_000,
        retry_count: 2
      )

  ## Returns

    * `{:ok, result}` - Task completed successfully
    * `{:error, :timeout}` - Task timed out
    * `{:error, :child_down}` - Child agent terminated
    * `{:error, reason}` - Other error
  """
  @spec delegate(GenServer.server(), pid(), task_data(), keyword()) ::
          {:ok, result_data()} | {:error, term()}
  def delegate(parent_pid, child_pid, task, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    retry_count = Keyword.get(opts, :retry_count, @default_retry_count)
    retry_delay = Keyword.get(opts, :retry_delay, @default_retry_delay)

    GenServer.call(parent_pid, {:delegate, child_pid, task, timeout, retry_count, retry_delay},
      timeout + 5_000
    )
  end

  @doc """
  Reports a result from child to parent agent.

  Sends the result back to the parent, completing the delegation cycle.

  ## Parameters

    * `child_pid` - PID of the child agent (sender)
    * `parent_pid` - PID of the parent agent (receiver)
    * `result` - Result data to report
    * `correlation_id` - Optional correlation ID (auto-generated if not provided)

  ## Examples

      :ok = AgentHarness.Agent.report(child_pid, parent_pid, %{
        status: :success,
        output: "analysis complete"
      })

      :ok = AgentHarness.Agent.report(child_pid, parent_pid, result, correlation_id)

  ## Returns

    * `:ok` - Result reported successfully
    * `{:error, reason}` - Failed to report
  """
  @spec report(GenServer.server(), pid(), result_data(), correlation_id() | nil) ::
          :ok | {:error, term()}
  def report(child_pid, parent_pid, result, correlation_id \\ nil) do
    GenServer.cast(child_pid, {:report, parent_pid, result, correlation_id})
  end

  @doc """
  Spawns a child agent under the supervisor.

  Creates a new child agent with the specified options.

  ## Parameters

    * `parent_pid` - PID of the parent agent
    * `opts` - Options for the child agent:
      * `:system_prompt` - System prompt for the child
      * `:model` - Model specification
      * `:tools` - List of tools for the child
      * `:working_dir` - Working directory
      * `:name` - Registered name for the child agent wrapper

  ## Examples

      {:ok, child_pid} = AgentHarness.Agent.spawn_child(parent_pid, %{
        system_prompt: "You are a code review specialist",
        model: {:groq, "claude-haiku-3-5"}
      })

  ## Returns

    * `{:ok, child_pid}` - Child spawned successfully
    * `{:error, reason}` - Failed to spawn
  """
  @spec spawn_child(GenServer.server(), map()) :: {:ok, pid()} | {:error, term()}
  def spawn_child(parent_pid, opts \\ %{}) do
    GenServer.call(parent_pid, {:spawn_child, opts})
  end

  @doc """
  Broadcasts tasks to multiple child agents.

  Sends different tasks to multiple children and collects results.

  ## Parameters

    * `parent_pid` - PID of the parent agent
    * `tasks` - List of `{child_pid, task_data}` tuples
    * `opts` - Options:
      * `:timeout` - Timeout for all tasks (default: #{@default_timeout})
      * `:collect_mode` - `:all` (wait for all) or `:first_n` (collect N results)

  ## Examples

      tasks = [
        {child1, %{query: "research topic A"}},
        {child2, %{query: "research topic B"}},
        {child3, %{query: "research topic C"}}
      ]

      results = AgentHarness.Agent.broadcast(parent_pid, tasks, timeout: 60_000)

  ## Returns

    * `{:ok, results}` - Map of `{child_pid, result}` for successful completions
    * `{:partial, results, errors}` - Some tasks completed, some failed
    * `{:error, reason}` - Broadcast failed
  """
  @spec broadcast(GenServer.server(), [{pid(), task_data()}], keyword()) ::
          {:ok, map()} | {:partial, map(), map()} | {:error, term()}
  def broadcast(parent_pid, tasks, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    GenServer.call(parent_pid, {:broadcast, tasks, timeout}, timeout + 5_000)
  end

  @doc """
  Sends a status update.

  Broadcasts status information to interested parties.

  ## Parameters

    * `agent_pid` - PID of the agent
    * `status` - Status atom (e.g., `:running`, `:waiting`, `:completed`)
    * `metadata` - Additional metadata (optional)

  ## Examples

      :ok = AgentHarness.Agent.send_status(agent_pid, :running, %{progress: 0.5})

  ## Returns

    * `:ok` - Status sent successfully
  """
  @spec send_status(GenServer.server(), status_atom(), metadata()) :: :ok
  def send_status(agent_pid, status, metadata \\ %{}) do
    GenServer.cast(agent_pid, {:status, status, metadata})
  end

  @doc """
  Returns the current state of the agent.

  ## Parameters

    * `agent_pid` - PID of the agent

  ## Returns

    * `%AgentHarness.Agent{}` - Current agent state
  """
  @spec get_state(GenServer.server()) :: t()
  def get_state(agent_pid) do
    GenServer.call(agent_pid, :get_state)
  end

  @doc """
  Returns the session ID of the agent.

  ## Parameters

    * `agent_pid` - PID of the agent

  ## Returns

    * `String.t()` - Session ID
  """
  @spec get_session_id(GenServer.server()) :: String.t()
  def get_session_id(agent_pid) do
    GenServer.call(agent_pid, :get_session_id)
  end

  @doc """
  Returns the list of child agents.

  ## Parameters

    * `agent_pid` - PID of the agent

  ## Returns

    * `[pid()]` - List of child PIDs
  """
  @spec get_children(GenServer.server()) :: [pid()]
  def get_children(agent_pid) do
    GenServer.call(agent_pid, :get_children)
  end

  # ── GenServer Callbacks ────────────────────────────────────────────

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    agent_pid = Keyword.fetch!(opts, :agent_pid)
    parent_pid = Keyword.get(opts, :parent_pid)
    supervisor = Keyword.get(opts, :supervisor)

    # Register for session events
    Events.subscribe(session_id)

    state = %__MODULE__{
      session_id: session_id,
      agent_pid: agent_pid,
      parent_pid: parent_pid,
      supervisor: supervisor
    }

    Logger.debug(
      "[AgentHarness.Agent] Initialized session=#{session_id} " <>
        "parent=#{inspect(parent_pid)} children=[]"
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:delegate, child_pid, task, timeout, retry_count, retry_delay}, from, state) do
    correlation_id = generate_correlation_id(state)

    # Send task to child
    send_task(child_pid, task, state.session_id, correlation_id)

    # Set up timeout monitoring
    timeout_ref = Process.send_after(self(), {:timeout, correlation_id, retry_count, retry_delay}, timeout)

    # Track pending request
    new_state = %{
      state
      | pending: Map.put(state.pending, correlation_id, {from, timeout_ref, child_pid, task})
    }

    Logger.debug(
      "[AgentHarness.Agent] Delegated task session=#{state.session_id} " <>
        "correlation_id=#{correlation_id} child=#{inspect(child_pid)} timeout=#{timeout}"
    )

    {:noreply, new_state}
  end

  def handle_call({:spawn_child, opts}, _from, state) do
    case do_spawn_child(state, opts) do
      {:ok, child_pid} ->
        new_state = %{
          state
          | children: Map.put(state.children, child_pid, %{started_at: System.system_time()})
        }

        Logger.debug(
          "[AgentHarness.Agent] Spawned child session=#{state.session_id} " <>
            "child=#{inspect(child_pid)} total_children=#{map_size(state.children)}"
        )

        {:reply, {:ok, child_pid}, new_state}

      {:error, reason} ->
        Logger.error("[AgentHarness.Agent] Failed to spawn child: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:broadcast, tasks, timeout}, from, state) do
    broadcast_id = "broadcast-" <> Opal.Id.session()

    # Send tasks to all children
    correlation_ids =
      Enum.map(tasks, fn {child_pid, task} ->
        correlation_id = generate_correlation_id(state)
        send_task(child_pid, task, state.session_id, correlation_id)
        {child_pid, correlation_id}
      end)

    # Set up timeout monitoring for broadcast
    timeout_ref =
      Process.send_after(self(), {:broadcast_timeout, broadcast_id}, timeout)

    # Track pending broadcast
    broadcast_state = %{
      timeout_ref: timeout_ref,
      tasks: Map.new(correlation_ids),
      results: %{},
      errors: %{},
      from: from
    }

    new_state = %{
      state
      | pending: Map.put(state.pending, broadcast_id, broadcast_state)
    }

    Logger.debug(
      "[AgentHarness.Agent] Broadcast started session=#{state.session_id} " <>
        "broadcast_id=#{broadcast_id} count=#{length(tasks)}"
    )

    {:noreply, new_state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:get_session_id, _from, state) do
    {:reply, state.session_id, state}
  end

  def handle_call(:get_children, _from, state) do
    {:reply, Map.keys(state.children), state}
  end

  @impl true
  def handle_cast({:report, parent_pid, result, correlation_id}, state) do
    # If correlation_id is nil, this is a standalone report (not in response to delegation)
    if correlation_id do
      send(parent_pid, {:result, result, correlation_id})
    else
      # Generate a new correlation ID for standalone reports
      new_correlation_id = generate_correlation_id(state)
      send(parent_pid, {:result, result, new_correlation_id})
    end

    Logger.debug(
      "[AgentHarness.Agent] Result reported session=#{state.session_id} " <>
        "parent=#{inspect(parent_pid)} correlation_id=#{inspect(correlation_id)}"
    )

    {:noreply, state}
  end

  def handle_cast({:status, status, metadata}, state) do
    Events.broadcast(state.session_id, {:status, status, metadata})

    Logger.debug(
      "[AgentHarness.Agent] Status update session=#{state.session_id} " <>
        "status=#{status} metadata=#{inspect(metadata)}"
    )

    {:noreply, state}
  end

  @impl true
  def handle_info({:result, result_data, correlation_id}, state) do
    case Map.get(state.pending, correlation_id) do
      {from, timeout_ref, _child_pid, _task} ->
        # Cancel timeout
        Process.cancel_timer(timeout_ref)

        # Reply to original caller
        GenServer.reply(from, {:ok, result_data})

        # Remove from pending
        new_state = %{state | pending: Map.delete(state.pending, correlation_id)}

        Logger.debug(
          "[AgentHarness.Agent] Result received session=#{state.session_id} " <>
            "correlation_id=#{correlation_id}"
        )

        {:noreply, new_state}

      broadcast_state when is_map(broadcast_state) and is_map_key(broadcast_state, :tasks) ->
        # This is part of a broadcast
        handle_broadcast_result(correlation_id, result_data, broadcast_state, state)

      nil ->
        Logger.warning(
          "[AgentHarness.Agent] Result received for unknown correlation_id=#{correlation_id}"
        )

        {:noreply, state}
    end
  end

  def handle_info({:error, reason, correlation_id}, state) do
    case Map.get(state.pending, correlation_id) do
      {from, timeout_ref, _child_pid, _task} ->
        # Cancel timeout
        Process.cancel_timer(timeout_ref)

        # Reply to original caller
        GenServer.reply(from, {:error, reason})

        # Remove from pending
        new_state = %{state | pending: Map.delete(state.pending, correlation_id)}

        Logger.debug(
          "[AgentHarness.Agent] Error received session=#{state.session_id} " <>
            "correlation_id=#{correlation_id} reason=#{inspect(reason)}"
        )

        {:noreply, new_state}

      nil ->
        Logger.warning(
          "[AgentHarness.Agent] Error received for unknown correlation_id=#{correlation_id}"
        )

        {:noreply, state}
    end
  end

  def handle_info({:timeout, correlation_id, retry_count, retry_delay}, state) do
    case Map.get(state.pending, correlation_id) do
      {from, _timeout_ref, child_pid, task} ->
        if retry_count > 0 do
          # Retry the delegation
          Logger.info(
            "[AgentHarness.Agent] Timeout, retrying session=#{state.session_id} " <>
              "correlation_id=#{correlation_id} retries_left=#{retry_count}"
          )

          # Send task again
          new_correlation_id = generate_correlation_id(state)
          send_task(child_pid, task, state.session_id, new_correlation_id)

          # Set up new timeout with decremented retry count
          new_timeout_ref =
            Process.send_after(self(), {:timeout, new_correlation_id, retry_count - 1, retry_delay}, retry_delay)

          # Update pending with new correlation ID
          new_pending =
            state.pending
            |> Map.delete(correlation_id)
            |> Map.put(new_correlation_id, {from, new_timeout_ref, child_pid, task})

          {:noreply, %{state | pending: new_pending}}
        else
          # No more retries, return timeout error
          Logger.warning(
            "[AgentHarness.Agent] Timeout exhausted session=#{state.session_id} " <>
              "correlation_id=#{correlation_id}"
          )

          GenServer.reply(from, {:error, :timeout})
          new_state = %{state | pending: Map.delete(state.pending, correlation_id)}

          {:noreply, new_state}
        end

      nil ->
        Logger.warning(
          "[AgentHarness.Agent] Timeout for unknown correlation_id=#{correlation_id}"
        )

        {:noreply, state}
    end
  end

  def handle_info({:broadcast_timeout, broadcast_id}, state) do
    case Map.get(state.pending, broadcast_id) do
      %{from: from, tasks: tasks, results: results, errors: errors} ->
        # Determine which tasks timed out
        timed_out =
          Map.keys(tasks)
          |> Enum.filter(fn correlation_id ->
            not Map.has_key?(results, correlation_id) and not Map.has_key?(errors, correlation_id)
          end)

        # Record timeouts as errors
        new_errors =
          Enum.reduce(timed_out, errors, fn correlation_id, acc ->
            {child_pid, _} = Enum.find(tasks, fn {_, cid} -> cid == correlation_id end)
            Map.put(acc, child_pid, :timeout)
          end)

        # Reply with partial results
        reply =
          if map_size(new_errors) == 0 do
            {:ok, results}
          else
            {:partial, results, new_errors}
          end

        GenServer.reply(from, reply)

        Logger.info(
          "[AgentHarness.Agent] Broadcast timeout session=#{state.session_id} " <>
            "broadcast_id=#{broadcast_id} completed=#{map_size(results)} timed_out=#{map_size(new_errors)}"
        )

        {:noreply, %{state | pending: Map.delete(state.pending, broadcast_id)}}

      nil ->
        Logger.warning(
          "[AgentHarness.Agent] Broadcast timeout for unknown broadcast_id=#{broadcast_id}"
        )

        {:noreply, state}
    end
  end

  def handle_info({:DOWN, _ref, :process, child_pid, _reason}, state) do
    # Child agent terminated
    new_children = Map.delete(state.children, child_pid)

    # Check if any pending tasks were waiting on this child
    new_pending =
      Enum.reduce(state.pending, state.pending, fn
        {correlation_id, {from, timeout_ref, ^child_pid, _task}}, acc ->
          Process.cancel_timer(timeout_ref)
          GenServer.reply(from, {:error, :child_down})
          Map.delete(acc, correlation_id)

        {correlation_id, %{tasks: tasks} = broadcast_state}, acc when is_map_key(tasks, correlation_id) ->
          # Handle broadcast with dead child
          new_errors = Map.put(broadcast_state.errors, child_pid, :child_down)
          new_broadcast = %{broadcast_state | errors: new_errors}
          Map.put(acc, correlation_id, new_broadcast)

        _, acc ->
          acc
      end)

    Logger.info(
      "[AgentHarness.Agent] Child terminated session=#{state.session_id} " <>
        "child=#{inspect(child_pid)} remaining_children=#{map_size(new_children)}"
    )

    {:noreply, %{state | children: new_children, pending: new_pending}}
  end

  def handle_info({:opal_event, _session_id, _event}, state) do
    # Forward Opal events as needed
    # For now, we just log them
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Clean up: unsubscribe from events
    Events.unsubscribe(state.session_id)

    # Cancel all pending timeouts
    Enum.each(state.pending, fn
      {_correlation_id, {_from, timeout_ref, _child_pid, _task}} ->
        Process.cancel_timer(timeout_ref)

      {_broadcast_id, %{timeout_ref: timeout_ref}} ->
        Process.cancel_timer(timeout_ref)
    end)

    Logger.debug("[AgentHarness.Agent] Terminated session=#{state.session_id}")
    :ok
  end

  # ── Internal Functions ─────────────────────────────────────────────

  defp generate_correlation_id(state) do
    counter = state.correlation_counter + 1
    correlation_id = "task-#{state.session_id}-#{counter}-#{System.system_time(:microsecond)}"
    %{state | correlation_counter: counter}
    correlation_id
  end

  defp send_task(child_pid, task, session_id, correlation_id) do
    # Broadcast task start event
    Events.broadcast(session_id, {:task_delegated, %{correlation_id: correlation_id, task: task}})

    # Send task message to child
    send(child_pid, {:task, task, self(), correlation_id})

    Logger.debug(
      "[AgentHarness.Agent] Task sent session=#{session_id} " <>
        "correlation_id=#{correlation_id} child=#{inspect(child_pid)}"
    )
  end

  defp do_spawn_child(state, opts) do
    supervisor = state.supervisor

    if is_nil(supervisor) do
      {:error, :no_supervisor}
    else
      session_id = "sub-" <> Opal.Id.session()

      # Build agent options
      agent_opts = [
        session_id: session_id,
        system_prompt: Map.get(opts, :system_prompt, ""),
        model: resolve_model(opts),
        tools: Map.get(opts, :tools, []),
        working_dir: Map.get(opts, :working_dir, state.session_id),
        config: Opal.Config.new(),
        tool_supervisor: nil
      ]

      case DynamicSupervisor.start_child(supervisor, {Agent, agent_opts}) do
        {:ok, agent_pid} ->
          # Start the agent communication wrapper for the child
          child_opts = [
            session_id: session_id,
            agent_pid: agent_pid,
            parent_pid: self(),
            supervisor: supervisor,
            name: Map.get(opts, :name)
          ]

          case start_link(child_opts) do
            {:ok, child_wrapper_pid} ->
              {:ok, child_wrapper_pid}

            {:error, reason} ->
              DynamicSupervisor.terminate_child(supervisor, agent_pid)
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp resolve_model(opts) do
    case Map.get(opts, :model) do
      nil ->
        # Default model - use a reasonable default
        %Opal.Provider.Model{provider: :groq, id: "claude-haiku-3-5"}

      model when is_tuple(model) ->
        Opal.Provider.Model.coerce(model)

      model when is_binary(model) ->
        Opal.Provider.Model.coerce(model)

      %Opal.Provider.Model{} = model ->
        model
    end
  end

  defp handle_broadcast_result(correlation_id, result_data, broadcast_state, state) do
    # Find which child this result belongs to
    child_pid =
      Enum.find_value(broadcast_state.tasks, fn {pid, cid} ->
        if cid == correlation_id, do: pid
      end)

    if child_pid do
      # Cancel the timeout for this specific task
      new_tasks = Map.delete(broadcast_state.tasks, correlation_id)
      new_results = Map.put(broadcast_state.results, child_pid, result_data)

      # Check if all tasks are complete
      if map_size(new_tasks) == 0 do
        # All tasks complete, reply to original caller
        Process.cancel_timer(broadcast_state.timeout_ref)
        GenServer.reply(broadcast_state.from, {:ok, new_results})

        Logger.debug(
          "[AgentHarness.Agent] Broadcast complete session=#{state.session_id} " <>
            "results=#{map_size(new_results)}"
        )

        {:noreply, %{state | pending: Map.delete(state.pending, broadcast_state)}}
      else
        # Still waiting for more results
        new_broadcast = %{broadcast_state | tasks: new_tasks, results: new_results}
        new_pending = Map.put(state.pending, broadcast_state, new_broadcast)

        {:noreply, %{state | pending: new_pending}}
      end
    else
      Logger.warning(
        "[AgentHarness.Agent] Broadcast result for unknown child correlation_id=#{correlation_id}"
      )

      {:noreply, state}
    end
  end
end
