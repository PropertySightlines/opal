defmodule AgentHarness.Agent.Protocol do
  @moduledoc """
  Message Protocol Documentation for Agent Harness Communication Layer.

  This module documents the OTP-native message protocol used for
  inter-agent communication in Agent Harness Phase 2.

  ## Overview

  The protocol uses standard Erlang message passing (`send/receive`)
  with no serialization overhead. Messages are tuples with a well-defined
  structure for request/response matching via correlation IDs.

  ## Message Types

  ### 1. Task Delegation (Parent → Child)

  ```elixir
  {:task, task_data, sender_pid, correlation_id}
  ```

  **Fields:**
    * `task_data` - Map containing the task to execute
      * `type` - Atom identifying the task type (e.g., `:research`, `:analyze`)
      * `input` - Input data for the task
      * `opts` - Optional task-specific configuration
    * `sender_pid` - PID of the parent agent
    * `correlation_id` - Unique string for request/response matching

  **Example:**
  ```elixir
  send(child_pid, {:task, %{
    type: :research,
    input: %{query: "Find Elixir best practices"},
    opts: %{depth: :comprehensive}
  }, parent_pid, "task-agent123-1-1234567890"})
  ```

  ### 2. Result Reporting (Child → Parent)

  ```elixir
  {:result, result_data, correlation_id}
  ```

  **Fields:**
    * `result_data` - Map containing the task result
      * `status` - Atom (`:success`, `:partial`, `:failed`)
      * `output` - The actual result data
      * `metadata` - Optional metadata (duration, tokens used, etc.)
    * `correlation_id` - Matching correlation ID from the task

  **Example:**
  ```elixir
  send(parent_pid, {:result, %{
    status: :success,
    output: "Key findings: ...",
    metadata: %{duration_ms: 1500, tokens: 2500}
  }, "task-agent123-1-1234567890"})
  ```

  ### 3. Status Updates (Any → Any)

  ```elixir
  {:status, status_atom, metadata}
  ```

  **Fields:**
    * `status_atom` - Current status state
      * `:running` - Task is in progress
      * `:waiting` - Waiting for external input
      * `:completed` - Task finished successfully
      * `:failed` - Task encountered an error
      * `:idle` - Agent is idle
    * `metadata` - Optional status metadata
      * `progress` - Float 0.0-1.0 indicating completion
      * `message` - Human-readable status message
      * `timestamp` - Unix timestamp of status update

  **Example:**
  ```elixir
  send(parent_pid, {:status, :running, %{
    progress: 0.5,
    message: "Analyzing data...",
    timestamp: System.system_time(:second)
  }})
  ```

  ### 4. Error Reporting (Any → Any)

  ```elixir
  {:error, reason, correlation_id}
  ```

  **Fields:**
    * `reason` - Error reason (atom or string)
      * `:timeout` - Operation timed out
      * `:invalid_task` - Task data was invalid
      * `:execution_failed` - Task execution failed
      * `:child_down` - Child agent terminated
      * `{:error, term}` - Detailed error tuple
    * `correlation_id` - Related correlation ID (if applicable)

  **Example:**
  ```elixir
  send(parent_pid, {:error, :timeout, "task-agent123-1-1234567890"})
  ```

  ## Correlation ID Format

  Correlation IDs follow this format:

  ```
  task-<session_id>-<counter>-<timestamp>
  ```

  Example: `task-agent123-5-1709481234567890`

  **Components:**
    * `session_id` - The parent agent's session identifier
    * `counter` - Monotonically increasing counter per session
    * `timestamp` - Microsecond timestamp for uniqueness

  ## Request/Response Flow

  ### Basic Delegation Flow

  ```
  Parent                          Child
    |                               |
    |--- {:task, ...} ------------->|
    |                               |
    |  (sets timeout monitor)       | (processes task)
    |                               |
    |<-- {:result, ...} ------------|
    |                               |
    | (cancels timeout, replies)    |
  ```

  ### Timeout Flow

  ```
  Parent                          Child
    |                               |
    |--- {:task, ...} ------------->|
    |                               |
    |  (timeout fires)              | (still processing)
    |                               |
    | (retry or error reply)        |
    |                               |
    |<-- {:result, ...} ------------| (late result, ignored)
  ```

  ### Broadcast Flow

  ```
  Parent                    Multiple Children
    |                       /    |    \
    |--- {:task, ...} ---->|     |     |
    |--- {:task, ...} ------------>|     |
    |--- {:task, ...} ----------------->|
    |                       |     |     |
    |<-- {:result, ...} ----|     |     |
    |<-- {:result, ...} <---------|     |
    |<-- {:result, ...} <--------------|
    |                       |     |     |
    | (aggregates results)  |     |     |
  ```

  ## Integration with Opal.Events

  All agent events are also broadcast via `Opal.Events` for pub/sub:

  ```elixir
  # Subscribe to agent events
  Opal.Events.subscribe(session_id)

  # Receive events
  receive do
    {:opal_event, ^session_id, {:task_delegated, metadata}} ->
      # Task was delegated to a child

    {:opal_event, ^session_id, {:task_completed, metadata}} ->
      # Task completed

    {:opal_event, ^session_id, {:status, status_atom, metadata}} ->
      # Status update
  end
  ```

  ## Error Handling Patterns

  ### Timeout with Retry

  ```elixir
  # Parent sets up retry logic
  {:ok, result} = AgentHarness.Agent.delegate(parent_pid, child_pid, task,
    timeout: 30_000,
    retry_count: 2,
    retry_delay: 5_000
  )
  ```

  ### Child Down Detection

  ```elixir
  # Parent monitors child
  ref = Process.monitor(child_pid)

  receive do
    {:result, result, _correlation_id} ->
      # Normal result

    {:DOWN, ^ref, :process, _pid, reason} ->
      # Child terminated unexpectedly
      {:error, {:child_down, reason}}
  end
  ```

  ## Best Practices

  1. **Always use correlation IDs** - Ensures request/response matching
  2. **Set appropriate timeouts** - Prevent indefinite blocking
  3. **Monitor child processes** - Use `Process.monitor/1` for detection
  4. **Handle late responses** - Ignore results after timeout
  5. **Use status updates** - Provide visibility into long-running tasks
  6. **Clean up on terminate** - Cancel timers and unsubscribe from events

  ## See Also

    * `AgentHarness.Agent` - Main agent communication module
    * `Opal.Events` - Event pub/sub system
    * `Opal.Agent` - Base agent implementation
  """

  # This module is documentation-only
  # The actual implementation is in AgentHarness.Agent

  @doc """
  Returns the protocol version.
  """
  @spec version() :: String.t()
  def version, do: "1.0.0"

  @doc """
  Returns the list of supported message types.
  """
  @spec message_types() :: [atom()]
  def message_types, do: [:task, :result, :status, :error]

  @doc """
  Returns the list of valid status atoms.
  """
  @spec valid_statuses() :: [atom()]
  def valid_statuses, do: [:running, :waiting, :completed, :failed, :idle]
end
