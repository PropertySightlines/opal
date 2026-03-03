defmodule AgentHarness.Agent.Examples do
  @moduledoc """
  Examples of Agent Communication Patterns.

  This module provides working examples of parent-child delegation,
  broadcast patterns, and hierarchical agent trees.

  ## Running Examples

  These examples assume the AgentHarness.Agent module is running
  within a proper supervision tree with access to Opal.Agent and
  DynamicSupervisor.

  ## Example Scenarios

    * `simple_delegation/0` - Basic parent-child task delegation
    * `broadcast_pattern/0` - One-to-many task distribution
    * `hierarchical_tree/0` - Multi-level agent hierarchy
    * `timeout_handling/0` - Timeout and retry patterns
    * `concurrent_delegations/0` - Parallel task delegation
  """

  require Logger

  # ── Example 1: Simple Delegation ────────────────────────────────────

  @doc """
  Demonstrates basic parent-child task delegation.

  ## Flow

      1. Parent spawns child agent
      2. Parent delegates task to child
      3. Child processes and reports result
      4. Parent receives and handles result

  ## Example Output

      {:ok, %{
        status: :success,
        output: "Analysis complete: found 15 patterns",
        metadata: %{duration_ms: 2500}
      }}
  """
  @spec simple_delegation() :: {:ok, map()} | {:error, term()}
  def simple_delegation do
    # This example shows the conceptual flow
    # In practice, you would run this within a supervision tree

    # Step 1: Start parent agent (typically via supervisor)
    # {:ok, parent_pid} = AgentHarness.Agent.start_link(
    #   session_id: "parent-123",
    #   agent_pid: parent_agent_pid,
    #   supervisor: dynamic_supervisor_pid
    # )

    # Step 2: Spawn child agent
    # {:ok, child_pid} = AgentHarness.Agent.spawn_child(parent_pid, %{
    #   system_prompt: "You are a research specialist",
    #   model: {:groq, "claude-haiku-3-5"}
    # })

    # Step 3: Delegate task
    # task = %{
    #   type: :research,
    #   input: %{
    #     query: "Find best practices for Elixir GenServer",
    #     sources: ["hexdocs", "github"]
    #   }
    # }
    #
    # {:ok, result} = AgentHarness.Agent.delegate(parent_pid, child_pid, task,
    #   timeout: 60_000
    # )

    # Step 4: Handle result
    # Logger.info("Research complete: #{inspect(result)}")

    # Conceptual return value
    {:ok, %{
      status: :success,
      output: "Found 15 GenServer best practices",
      metadata: %{duration_ms: 2500, tokens_used: 3200}
    }}
  end

  # ── Example 2: Broadcast Pattern ───────────────────────────────────

  @doc """
  Demonstrates one-to-many task distribution.

  ## Flow

      1. Parent spawns multiple children
      2. Parent broadcasts different tasks to each child
      3. Children process in parallel
      4. Parent collects and aggregates results

  ## Use Cases

    * Parallel research on different topics
    * Multi-region data collection
    * A/B testing with different prompts
    * Ensemble analysis

  ## Example Output

      {:ok, %{
        child1 => %{output: "Weather NYC: 72°F"},
        child2 => %{output: "Weather LA: 85°F"},
        child3 => %{output: "Weather Chicago: 68°F"}
      }}
  """
  @spec broadcast_pattern() :: {:ok, map()} | {:partial, map(), map()}
  def broadcast_pattern do
    # Step 1: Spawn multiple children
    # {:ok, child1} = AgentHarness.Agent.spawn_child(parent_pid, %{
    #   system_prompt: "You are a weather data specialist"
    # })
    # {:ok, child2} = AgentHarness.Agent.spawn_child(parent_pid, %{
    #   system_prompt: "You are a weather data specialist"
    # })
    # {:ok, child3} = AgentHarness.Agent.spawn_child(parent_pid, %{
    #   system_prompt: "You are a weather data specialist"
    # })

    # Step 2: Prepare tasks for broadcast
    # tasks = [
    #   {child1, %{type: :weather, city: "New York"}},
    #   {child2, %{type: :weather, city: "Los Angeles"}},
    #   {child3, %{type: :weather, city: "Chicago"}}
    # ]

    # Step 3: Broadcast and collect results
    # results = AgentHarness.Agent.broadcast(parent_pid, tasks,
    #   timeout: 30_000
    # )

    # Conceptual return value
    {:ok, %{
      "child1_pid" => %{output: "Weather NYC: 72°F, Sunny"},
      "child2_pid" => %{output: "Weather LA: 85°F, Clear"},
      "child3_pid" => %{output: "Weather Chicago: 68°F, Partly Cloudy"}
    }}
  end

  # ── Example 3: Hierarchical Tree ───────────────────────────────────

  @doc """
  Demonstrates multi-level agent hierarchy.

  ## Structure

                    Parent (Coordinator)
                   /        |        \
              Child1     Child2     Child3
              /   \       /   \       /   \
           G1a   G1b   G2a   G2b   G3a   G3b

  ## Flow

      1. Root coordinator receives high-level task
      2. Coordinator delegates to mid-level agents
      3. Mid-level agents delegate to leaf agents
      4. Results bubble up through the hierarchy

  ## Use Cases

    * Complex research projects
    * Multi-stage data processing
    * Hierarchical task decomposition
    * Organizational simulation

  ## Example Output

      {:ok, %{
        aggregated_results: [...],
        hierarchy_depth: 3,
        total_agents: 10
      }}
  """
  @spec hierarchical_tree() :: {:ok, map()}
  def hierarchical_tree do
    # Level 1: Root coordinator
    # {:ok, root_pid} = AgentHarness.Agent.start_link(...)

    # Level 2: Mid-level coordinators
    # {:ok, coordinator1} = AgentHarness.Agent.spawn_child(root_pid, %{
    #   system_prompt: "You coordinate research on technical topics"
    # })
    # {:ok, coordinator2} = AgentHarness.Agent.spawn_child(root_pid, %{
    #   system_prompt: "You coordinate research on business topics"
    # })

    # Level 3: Leaf researchers
    # {:ok, researcher1} = AgentHarness.Agent.spawn_child(coordinator1, %{
    #   system_prompt: "You research Elixir patterns"
    # })
    # {:ok, researcher2} = AgentHarness.Agent.spawn_child(coordinator1, %{
    #   system_prompt: "You research OTP patterns"
    # })

    # Delegate from root
    # root_task = %{
    #   type: :comprehensive_research,
    #   topics: ["Elixir", "OTP", "GenServer"],
    #   depth: :hierarchical
    # }
    #
    # # Root delegates to coordinators
    # AgentHarness.Agent.delegate(root_pid, coordinator1, %{
    #   type: :technical_research,
    #   topics: ["Elixir", "OTP"]
    # })
    #
    # # Coordinators delegate to researchers
    # AgentHarness.Agent.delegate(coordinator1, researcher1, %{
    #   type: :specific_research,
    #   topic: "Elixir patterns"
    # })

    # Conceptual return value
    {:ok, %{
      aggregated_results: [
        %{topic: "Elixir", findings: ["Pattern matching", "Pipes", "Macros"]},
        %{topic: "OTP", findings: ["GenServer", "Supervisor", "Registry"]},
        %{topic: "GenServer", findings: ["State management", "Async calls"]}
      ],
      hierarchy_depth: 3,
      total_agents: 10,
      total_duration_ms: 15000
    }}
  end

  # ── Example 4: Timeout Handling ────────────────────────────────────

  @doc """
  Demonstrates timeout and retry patterns.

  ## Timeout Strategies

    * **Simple timeout** - Single attempt with timeout
    * **Retry with backoff** - Multiple attempts with delay
    * **Progressive timeout** - Increasing timeout per retry

  ## Example Output

      # First attempt times out, retry succeeds
      {:ok, %{
        status: :success,
        output: "Result after retry",
        attempts: 2,
        total_duration_ms: 8000
      }}
  """
  @spec timeout_handling() :: {:ok, map()} | {:error, :timeout}
  def timeout_handling do
    # Strategy 1: Simple timeout
    # {:ok, result} = AgentHarness.Agent.delegate(parent_pid, child_pid, task,
    #   timeout: 30_000
    # )

    # Strategy 2: Retry with fixed delay
    # {:ok, result} = AgentHarness.Agent.delegate(parent_pid, child_pid, task,
    #   timeout: 10_000,
    #   retry_count: 3,
    #   retry_delay: 2_000
    # )

    # Strategy 3: Progressive timeout (manual implementation)
    # result = retry_with_progressive_timeout(parent_pid, child_pid, task,
    #   base_timeout: 5_000,
    #   multiplier: 2,
    #   max_attempts: 4
    # )

    # Conceptual return value - retry succeeded on second attempt
    {:ok, %{
      status: :success,
      output: "Analysis complete",
      attempts: 2,
      total_duration_ms: 8000,
      retry_details: [
        %{attempt: 1, timeout_ms: 5000, result: :timeout},
        %{attempt: 2, timeout_ms: 10000, result: :success}
      ]
    }}
  end

  # ── Example 5: Concurrent Delegations ──────────────────────────────

  @doc """
  Demonstrates parallel task delegation.

  ## Flow

      1. Parent has multiple independent tasks
      2. Parent delegates all tasks concurrently
      3. Parent uses Task.async to collect results
      4. Results are aggregated when all complete

  ## Use Cases

    * Independent sub-tasks
    * Map-reduce style processing
    * Parallel validation
    * Multi-source data fetching

  ## Example Output

      {:ok, [
        %{task_id: "t1", output: "Result 1"},
        %{task_id: "t2", output: "Result 2"},
        %{task_id: "t3", output: "Result 3"}
      ]}
  """
  @spec concurrent_delegations() :: {:ok, [map()]}
  def concurrent_delegations do
    # tasks = [
    #   %{id: "t1", type: :analyze, data: "dataset1"},
    #   %{id: "t2", type: :analyze, data: "dataset2"},
    #   %{id: "t3", type: :analyze, data: "dataset3"}
    # ]

    # # Spawn children for each task
    # children = Enum.map(tasks, fn _task ->
    #   {:ok, pid} = AgentHarness.Agent.spawn_child(parent_pid, %{})
    #   pid
    # end)

    # # Delegate concurrently using Task.async
    # tasks_with_refs =
    #   Enum.zip(tasks, children)
    #   |> Enum.map(fn {task, child_pid} ->
    #     Task.async(fn ->
    #       AgentHarness.Agent.delegate(parent_pid, child_pid, task,
    #         timeout: 30_000
    #       )
    #     end)
    #   end)

    # # Collect all results
    # results = Enum.map(tasks_with_refs, fn ref ->
    #   Task.await(ref, 35_000)
    # end)

    # Conceptual return value
    {:ok, [
      %{task_id: "t1", output: "Analysis of dataset1: 50 records", status: :success},
      %{task_id: "t2", output: "Analysis of dataset2: 75 records", status: :success},
      %{task_id: "t3", output: "Analysis of dataset3: 30 records", status: :success}
    ]}
  end

  # ── Example 6: Status Monitoring ───────────────────────────────────

  @doc """
  Demonstrates status update patterns.

  ## Flow

      1. Child sends periodic status updates
      2. Parent subscribes to status events
      3. Parent can report progress to user
      4. Final status indicates completion

  ## Example Output

      # Status updates received:
      # {:status, :running, %{progress: 0.0, message: "Starting..."}}
      # {:status, :running, %{progress: 0.5, message: "Processing..."}}
      # {:status, :running, %{progress: 0.8, message: "Finalizing..."}}
      # {:status, :completed, %{progress: 1.0, message: "Done"}}
  """
  @spec status_monitoring() :: :ok
  def status_monitoring do
    # In child agent:
    # AgentHarness.Agent.send_status(child_pid, :running, %{
    #   progress: 0.0,
    #   message: "Starting research..."
    # })
    #
    # # During processing
    # AgentHarness.Agent.send_status(child_pid, :running, %{
    #   progress: 0.5,
    #   message: "Analyzing data..."
    # })
    #
    # # On completion
    # AgentHarness.Agent.send_status(child_pid, :completed, %{
    #   progress: 1.0,
    #   message: "Research complete"
    # })

    # In parent (via Opal.Events subscription):
    # Opal.Events.subscribe(session_id)
    #
    # receive do
    #   {:opal_event, ^session_id, {:status, status, metadata}} ->
    #     IO.puts("Status: #{status} - #{metadata.message}")
    #     IO.puts("Progress: #{metadata.progress * 100}%")
    # end

    :ok
  end

  # ── Example 7: Error Handling ──────────────────────────────────────

  @doc """
  Demonstrates error handling patterns.

  ## Error Types

    * `:timeout` - Task exceeded timeout
    * `:child_down` - Child agent terminated
    * `:invalid_task` - Task data was malformed
    * `:execution_failed` - Task execution failed

  ## Handling Strategies

    * Retry on timeout
    * Spawn replacement on child_down
    * Log and skip on invalid_task
    * Escalate on execution_failed

  ## Example Output

      {:error, :timeout, %{
        task: %{type: :research},
        attempts: 3,
        total_duration_ms: 15000
      }}
  """
  @spec error_handling() :: {:ok, map()} | {:error, atom(), map()}
  def error_handling do
    # Pattern 1: Handle timeout
    # case AgentHarness.Agent.delegate(parent_pid, child_pid, task,
    #      timeout: 30_000,
    #      retry_count: 2
    #    ) do
    #   {:ok, result} ->
    #     {:ok, result}
    #
    #   {:error, :timeout} ->
    #     Logger.warning("Task timed out after retries")
    #     {:error, :timeout, %{task: task, attempts: 3}}
    # end

    # Pattern 2: Handle child_down
    # case AgentHarness.Agent.delegate(parent_pid, child_pid, task) do
    #   {:error, :child_down} ->
    #     # Spawn replacement and retry
    #     {:ok, new_child} = AgentHarness.Agent.spawn_child(parent_pid, %{})
    #     AgentHarness.Agent.delegate(parent_pid, new_child, task)
    # end

    # Pattern 3: Monitor child explicitly
    # ref = Process.monitor(child_pid)
    #
    # receive do
    #   {:result, result, _correlation_id} ->
    #     {:ok, result}
    #
    #   {:DOWN, ^ref, :process, _pid, reason} ->
    #     {:error, :child_down, %{reason: reason}}
    # after
    #   30_000 ->
    #     {:error, :timeout}
    # end

    # Conceptual return value
    {:ok, %{
      status: :success,
      output: "Handled all error cases",
      error_handling_strategies: [
        :retry_on_timeout,
        :respawn_on_child_down,
        :escalate_on_execution_failed
      ]
    }}
  end

  # ── Complete Example: Research Pipeline ────────────────────────────

  @doc """
  Complete example: Multi-stage research pipeline.

  This example combines all patterns into a realistic workflow:

      1. Coordinator receives high-level research request
      2. Spawns specialist agents for each sub-topic
      3. Broadcasts research tasks in parallel
      4. Collects and synthesizes results
      5. Reports final findings with progress updates

  ## Example Output

      {:ok, %{
        status: :completed,
        findings: [...],
        synthesis: "...",
        metadata: %{
          duration_ms: 45000,
          agents_used: 7,
          tokens_consumed: 25000
        }
      }}
  """
  @spec research_pipeline(String.t()) :: {:ok, map()}
  def research_pipeline(topic \\ "Elixir best practices") do
    # This is a conceptual example showing the full workflow

    # Step 1: Receive research request
    # research_request = %{
    #   topic: topic,
    #   depth: :comprehensive,
    #   subtopics: ["patterns", "testing", "deployment"]
    # }

    # Step 2: Spawn specialist agents
    # {:ok, patterns_agent} = AgentHarness.Agent.spawn_child(coordinator_pid, %{
    #   system_prompt: "You are an Elixir patterns expert"
    # })
    # {:ok, testing_agent} = AgentHarness.Agent.spawn_child(coordinator_pid, %{
    #   system_prompt: "You are a testing best practices expert"
    # })
    # {:ok, deployment_agent} = AgentHarness.Agent.spawn_child(coordinator_pid, %{
    #   system_prompt: "You are a deployment specialist"
    # })

    # Step 3: Send initial status
    # AgentHarness.Agent.send_status(coordinator_pid, :running, %{
    #   progress: 0.0,
    #   message: "Starting research on #{topic}"
    # })

    # Step 4: Broadcast research tasks
    # tasks = [
    #   {patterns_agent, %{type: :research, focus: "Elixir patterns"}},
    #   {testing_agent, %{type: :research, focus: "Testing strategies"}},
    #   {deployment_agent, %{type: :research, focus: "Deployment practices"}}
    # ]
    #
    # {:ok, results} = AgentHarness.Agent.broadcast(coordinator_pid, tasks,
    #   timeout: 60_000
    # )

    # Step 5: Update progress
    # AgentHarness.Agent.send_status(coordinator_pid, :running, %{
    #   progress: 0.8,
    #   message: "Synthesizing findings..."
    # })

    # Step 6: Synthesize results (could delegate to another agent)
    # {:ok, synthesis_agent} = AgentHarness.Agent.spawn_child(coordinator_pid, %{
    #   system_prompt: "You synthesize research findings"
    # })
    #
    # {:ok, synthesis} = AgentHarness.Agent.delegate(
    #   coordinator_pid,
    #   synthesis_agent,
    #   %{type: :synthesize, findings: results}
    # )

    # Step 7: Report completion
    # AgentHarness.Agent.send_status(coordinator_pid, :completed, %{
    #   progress: 1.0,
    #   message: "Research complete"
    # })

    # Conceptual return value
    {:ok, %{
      status: :completed,
      topic: topic,
      findings: [
        %{
          subtopic: "patterns",
          results: ["Pattern matching", "Function clauses", "Pipes"]
        },
        %{
          subtopic: "testing",
          results: ["ExUnit", "Property testing", "Mocking"]
        },
        %{
          subtopic: "deployment",
          results: ["Releases", "Docker", "Distillery"]
        }
      ],
      synthesis: "Elixir best practices emphasize functional programming, " <>
        "comprehensive testing, and robust deployment strategies.",
      metadata: %{
        duration_ms: 45000,
        agents_used: 4,
        tokens_consumed: 25000,
        hierarchy_depth: 2
      }
    }}
  end
end
