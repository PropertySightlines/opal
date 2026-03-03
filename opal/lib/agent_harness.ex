defmodule AgentHarness do
  @moduledoc """
  Agent Harness Phase 2 - Rate Limiting, Topology Management, and Request Orchestration.

  This module provides infrastructure for managing LLM provider requests
  with rate limiting, queuing, intelligent routing, and multi-agent orchestration.

  ## Components

  ### Rate Limiting

    * `AgentHarness.RateLimit` - Rate limiting with sliding windows
    * `AgentHarness.RateLimit.Tracker` - GenServer for tracking RPM/TPM
    * `AgentHarness.RateLimit.Config` - Configuration management

  ### Topology Management

    * `AgentHarness.Topology` - Behaviour definition for execution topologies
    * `AgentHarness.Topology.Sequential` - Sequential agent execution
    * `AgentHarness.Topology.Parallel` - Concurrent agent execution
    * `AgentHarness.Topology.Registry` - Dynamic topology registration and switching

  ### Agent Communication

    * `AgentHarness.Agent` - OTP-native messaging for hierarchical agent trees
    * `AgentHarness.Agent.Protocol` - Message protocol documentation
    * `AgentHarness.Agent.Examples` - Usage examples and patterns

  ## Architecture

  ### Rate Limiting

  The rate limiter uses a "queue & sleep" strategy:
    1. Check if request is allowed via `Tracker.can_request?/1`
    2. If blocked, sleep for the recommended delay
    3. Record the request after completion via `Tracker.record_request/2`

  ### Topology Execution

  Topologies define how multiple agents are orchestrated:

    * **Sequential** - Agents execute one after another (for dependent tasks)
    * **Parallel** - Agents execute concurrently (for independent tasks)

  Future topologies (planned):
    * `:consensus` - Multiple agents vote on results
    * `:hierarchical` - Tree-like agent structure
    * `:fan_out` - One-to-many execution with aggregation
    * `:collaborative` - Agents share state and iterate
    * `:hybrid` - Combines multiple strategies

  ### Agent Communication

  The Agent Communication layer enables hierarchical agent trees:

    * **Parent → Child** - Task delegation via `AgentHarness.Agent.delegate/4`
    * **Child → Parent** - Result reporting via `AgentHarness.Agent.report/4`
    * **Broadcast** - One-to-many distribution via `AgentHarness.Agent.broadcast/3`
    * **Status Updates** - Progress tracking via `AgentHarness.Agent.send_status/3`

  Message Protocol:

      # Task delegation
      {:task, task_data, sender_pid, correlation_id}

      # Result reporting
      {:result, result_data, correlation_id}

      # Status updates
      {:status, status_atom, metadata}

      # Error handling
      {:error, reason, correlation_id}

  See `AgentHarness.Agent` for detailed documentation.

  ## Examples

  ### Rate-Limited Request

      # Start the tracker
      {:ok, _} = AgentHarness.RateLimit.Tracker.start_link()

      # Make a rate-limited request
      provider = :groq
      case AgentHarness.RateLimit.Tracker.can_request?(provider) do
        :ok ->
          response = call_llm_api(provider, messages)
          AgentHarness.RateLimit.Tracker.record_request(provider, response.usage.total_tokens)
          {:ok, response}

        {:wait, delay_ms} ->
          Process.sleep(delay_ms)
          # Retry logic here
      end

  ### Sequential Topology

      tasks = [
        %{id: "research", agent: ResearchAgent, input: %{topic: "Elixir"}},
        %{id: "analyze", agent: AnalysisAgent, input: %{focus: "patterns"}},
        %{id: "summarize", agent: SummaryAgent, input: %{format: "brief"}}
      ]

      {:ok, result} = AgentHarness.Topology.Sequential.run(tasks, timeout: 60_000)

  ### Parallel Topology

      tasks = [
        %{id: "weather_nyc", agent: WeatherAgent, input: %{city: "New York"}},
        %{id: "weather_la", agent: WeatherAgent, input: %{city: "Los Angeles"}},
        %{id: "weather_chi", agent: WeatherAgent, input: %{city: "Chicago"}}
      ]

      {:ok, result} = AgentHarness.Topology.Parallel.run(tasks,
        parallel_count: 3,
        timeout: 30_000
      )

  ### Dynamic Topology Switching

      # Register the registry (usually done in application supervisor)
      {:ok, _} = AgentHarness.Topology.Registry.start_link()

      # Run with different topologies
      AgentHarness.Topology.Registry.run(:sequential, tasks)
      AgentHarness.Topology.Registry.run(:parallel, tasks, parallel_count: 2)

      # Register custom topology
      AgentHarness.Topology.Registry.register(:custom, MyCustomTopology)
      AgentHarness.Topology.Registry.run(:custom, tasks)

  ## Task Format

  Tasks are maps with the following structure:

      %{
        id: "task-1",                    # Unique identifier
        agent: MyAgentModule,            # Agent module or function
        input: %{query: "data"},         # Input for the agent
        opts: [timeout: 5000]            # Per-task options
      }

  ## Result Format

  Results include metadata about execution:

      {:ok, %{
        results: [
          %{id: "task1", status: :success, output: ..., duration_ms: 1200},
          %{id: "task2", status: :error, error: :timeout, duration_ms: 5000}
        ],
        metadata: %{
          topology: :sequential,
          total_time_ms: 6200,
          success_count: 1,
          error_count: 1,
          task_count: 2
        }
      }}
  """

  @doc """
  Returns the version of Agent Harness.
  """
  @spec version() :: String.t()
  def version do
    "0.2.1"
  end
end
