defmodule AgentHarness.Orchestrator do
  @moduledoc """
  Orchestrator for Multi-Agent Workflows.

  Provides intelligent task analysis and agent spawning strategies for complex
  multi-agent workflows. Automatically determines task complexity and selects
  appropriate execution topology (parallel or sequential).

  ## Features

    * Task complexity analysis with automatic strategy selection
    * Parallel agent spawning for independent subtasks
    * Sequential agent spawning for dependent tasks
    * Result aggregation from multiple agents
    * Provider load balancing across available LLM providers
    * Configurable agent count with sensible defaults

  ## Task Complexity Levels

  The orchestrator analyzes tasks and assigns complexity levels:

    * `:simple` - Single agent execution (sequential topology)
    * `:moderate` - 2-3 agents (parallel topology)
    * `:complex` - 3+ agents (parallel topology with all providers)

  ## Usage

  ### Basic Usage

      task = %{
        description: "Research and summarize Elixir concurrency patterns",
        subtasks: [
          %{id: "research", description: "Research concurrency patterns"},
          %{id: "analyze", description: "Analyze performance implications"},
          %{id: "summarize", description: "Create summary document"}
        ]
      }

      {:ok, result} = AgentHarness.Orchestrator.run(task)

  ### Custom Agent Count

      {:ok, result} = AgentHarness.Orchestrator.run(task, agent_count: 5)

  ### Forced Topology

      {:ok, result} = AgentHarness.Orchestrator.run(task, topology: :sequential)

  ## Provider Configuration

  The orchestrator automatically discovers available providers from environment
  variables. For parallel tasks, it distributes work across all available providers
  to maximize throughput.

  Detected providers are logged at startup:

      [info] [Orchestrator] Available providers: [:openrouter, :nvidia, :groq, :cerebras]

  ## Options

    * `:agent_count` - Override default agent count (default: based on complexity)
    * `:topology` - Force specific topology: `:parallel`, `:sequential`, or `:auto` (default: `:auto`)
    * `:timeout` - Total timeout for execution (default: 60_000ms)
    * `:providers` - Explicit list of providers to use (default: all available)
    * `:on_error` - Error handling strategy (passed to topology)

  ## Architecture

      ┌─────────────────────────────────────────────────────────────┐
      │                      Orchestrator                           │
      ├─────────────────────────────────────────────────────────────┤
      │  analyze_task/1  →  Determines complexity & strategy        │
      │  spawn_agents/2  →  Creates agent tasks based on topology  │
      │  aggregate_results/1 → Combines results from all agents    │
      │  run/2           →  Main entry point (orchestrates all)    │
      └─────────────────────────────────────────────────────────────┘

  See `AgentHarness.Topology.Parallel` and `AgentHarness.Topology.Sequential`
  for topology implementation details.
  """

  require Logger

  alias AgentHarness.Topology.Parallel
  alias AgentHarness.Topology.Sequential

  # Default configuration
  @default_agent_count 3
  @default_timeout 60_000
  @default_topology :auto

  # Complexity thresholds
  @simple_threshold 1
  @moderate_threshold 3

  # Available providers (discovered from environment)
  @provider_env_vars [
    openrouter: "OPENROUTER_API_KEY",
    nvidia: "NVIDIA_API_KEY",
    groq: "GROQ_API_KEY",
    cerebras: "CEREBRAS_API_KEY"
  ]

  @type task :: map()
  @type complexity :: :simple | :moderate | :complex
  @type topology :: :parallel | :sequential | :auto
  @type strategy :: %{
          complexity: complexity(),
          topology: topology(),
          agent_count: pos_integer(),
          providers: [atom()]
        }

  @doc """
  Analyzes task complexity and determines execution strategy.

  Examines the task structure to determine:
    - Number of subtasks
    - Task dependencies
    - Required parallelism

  ## Parameters

    * `task` - Task map to analyze. Should contain:
      * `:description` - Task description
      * `:subtasks` - List of subtask maps (optional)
      * `:dependencies` - List of dependency specifications (optional)

  ## Returns

  A strategy map containing:
    * `:complexity` - Task complexity level (`:simple`, `:moderate`, `:complex`)
    * `:topology` - Recommended topology (`:parallel` or `:sequential`)
    * `:agent_count` - Recommended number of agents
    * `:providers` - List of available providers for parallel execution

  ## Examples

      task = %{
        description: "Research and analyze data",
        subtasks: [
          %{id: "research", description: "Gather information"},
          %{id: "analyze", description: "Analyze findings"},
          %{id: "report", description: "Create report"}
        ]
      }

      strategy = AgentHarness.Orchestrator.analyze_task(task)
      # => %{
      #      complexity: :moderate,
      #      topology: :parallel,
      #      agent_count: 3,
      #      providers: [:openrouter, :nvidia, :groq, :cerebras]
      #    }

  ## Complexity Rules

    * **Simple** (1 subtask): Single agent, sequential topology
    * **Moderate** (2-3 subtasks): Multiple agents, parallel topology
    * **Complex** (4+ subtasks): Multiple agents with all providers, parallel topology

  Dependencies between subtasks force sequential topology regardless of count.
  """
  @spec analyze_task(task()) :: strategy()
  def analyze_task(task) when is_map(task) do
    subtasks = get_subtasks(task)
    subtask_count = length(subtasks)
    has_dependencies = has_dependencies?(task, subtasks)
    providers = get_available_providers()

    # Determine complexity based on subtask count and dependencies
    complexity = determine_complexity(subtask_count, has_dependencies)

    # Determine topology
    topology =
      cond do
        has_dependencies ->
          :sequential

        complexity == :simple ->
          :sequential

        true ->
          :parallel
      end

    # Determine agent count
    agent_count =
      cond do
        complexity == :simple ->
          1

        complexity == :moderate ->
          min(subtask_count, @default_agent_count)

        complexity == :complex ->
          max(subtask_count, @default_agent_count)
      end

    strategy = %{
      complexity: complexity,
      topology: topology,
      agent_count: agent_count,
      providers: providers
    }

    Logger.info(
      "[Orchestrator] Task analyzed: complexity=#{complexity}, " <>
        "topology=#{topology}, agents=#{agent_count}, providers=#{length(providers)}"
    )

    strategy
  end

  @doc """
  Spawns agents based on the determined strategy.

  Creates task specifications for each agent according to the topology
  and distributes work across available providers for parallel execution.

  ## Parameters

    * `task` - Original task map
    * `strategy` - Strategy map from `analyze_task/1`

  ## Options

    * `:agent_count` - Override the strategy's agent count
    * `:providers` - Override the strategy's providers list

  ## Returns

  A list of task specifications ready for topology execution. Each task contains:
    * `:id` - Unique task identifier
    * `:agent` - Agent module or function to execute
    * `:input` - Input data for the agent
    * `:opts` - Execution options including provider assignment

  ## Examples

      strategy = %{
        complexity: :moderate,
        topology: :parallel,
        agent_count: 3,
        providers: [:groq, :nvidia]
      }

      tasks = AgentHarness.Orchestrator.spawn_agents(task, strategy)
      # => [
      #      %{id: "task-1", agent: WorkerAgent, input: %{...}, opts: [provider: :groq]},
      #      %{id: "task-2", agent: WorkerAgent, input: %{...}, opts: [provider: :nvidia]},
      #      %{id: "task-3", agent: WorkerAgent, input: %{...}, opts: [provider: :groq]}
      #    ]

  ## Provider Distribution

  For parallel tasks, agents are distributed across providers in round-robin
  fashion to balance load:

      providers: [:groq, :nvidia, :openrouter]
      agents: [1, 2, 3, 4, 5]
      # Distribution:
      # Agent 1 → :groq
      # Agent 2 → :nvidia
      # Agent 3 → :openrouter
      # Agent 4 → :groq
      # Agent 5 → :nvidia
  """
  @spec spawn_agents(task(), strategy(), keyword()) :: [map()]
  def spawn_agents(task, strategy, opts \\ []) do
    agent_count = Keyword.get(opts, :agent_count, strategy.agent_count)
    providers = Keyword.get(opts, :providers, strategy.providers)
    subtasks = get_subtasks(task)

    Logger.info(
      "[Orchestrator] Spawning #{agent_count} agents with topology=#{strategy.topology}, " <>
        "providers=#{inspect(providers)}"
    )

    tasks =
      case strategy.topology do
        :parallel ->
          spawn_parallel_agents(subtasks, agent_count, providers, task)

        :sequential ->
          spawn_sequential_agents(subtasks, agent_count, providers, task)
      end

    Logger.debug("[Orchestrator] Spawned #{length(tasks)} agent tasks")
    tasks
  end

  @doc """
  Aggregates results from multiple agent executions.

  Combines results based on topology type:
    - **Parallel**: Merges independent results, handles partial failures
    - **Sequential**: Chains results, passes output between dependent tasks

  ## Parameters

    * `result` - Result tuple from topology execution:
      * `{:ok, result_map}` - Successful execution
      * `{:error, reason}` - Failed execution

  ## Returns

  Aggregated result in standardized format:
    * `{:ok, aggregated_data}` - Successfully aggregated
    * `{:error, reason}` - Aggregation failed

  ## Examples

      # Parallel results
      parallel_result = {:ok, %{
        results: [
          %{id: "task-1", status: :success, output: "Result A"},
          %{id: "task-2", status: :success, output: "Result B"}
        ],
        metadata: %{topology: :parallel, success_count: 2}
      }}

      {:ok, aggregated} = AgentHarness.Orchestrator.aggregate_results(parallel_result)
      # => {:ok, %{
      #      outputs: ["Result A", "Result B"],
      #      success_count: 2,
      #      error_count: 0,
      #      metadata: %{...}
      #    }}

      # Sequential results with chaining
      sequential_result = {:ok, %{
        results: [
          %{id: "step-1", status: :success, output: "Research data"},
          %{id: "step-2", status: :success, output: "Analysis of research data"}
        ],
        metadata: %{topology: :sequential, success_count: 2}
      }}

      {:ok, aggregated} = AgentHarness.Orchestrator.aggregate_results(sequential_result)
      # => {:ok, %{
      #      final_output: "Analysis of research data",
      #      chain: [...],
      #      success_count: 2,
      #      metadata: %{...}
      #    }}

  ## Error Handling

  Partial failures are handled gracefully:
    - Successful results are preserved
    - Error details are included in aggregation
    - Metadata includes failure counts
  """
  @spec aggregate_results({:ok, map()} | {:error, term()}) :: {:ok, map()} | {:error, term()}
  def aggregate_results({:error, reason}), do: {:error, reason}

  def aggregate_results({:ok, result}) when is_map(result) do
    results = Map.get(result, :results, [])
    metadata = Map.get(result, :metadata, %{})
    topology = Map.get(metadata, :topology)

    aggregated =
      case topology do
        :parallel ->
          aggregate_parallel_results(results, metadata)

        :sequential ->
          aggregate_sequential_results(results, metadata)

        _ ->
          aggregate_generic_results(results, metadata)
      end

    Logger.info(
      "[Orchestrator] Results aggregated: topology=#{topology}, " <>
        "success=#{Map.get(aggregated, :success_count, 0)}, " <>
        "errors=#{Map.get(aggregated, :error_count, 0)}"
    )

    {:ok, aggregated}
  end

  @doc """
  Main entry point: analyzes, spawns, and aggregates in a single call.

  Orchestrates the complete multi-agent workflow:
    1. Analyzes task complexity
    2. Spawns agents based on strategy
    3. Executes using appropriate topology
    4. Aggregates results

  ## Parameters

    * `task` - Task map to execute
    * `opts` - Execution options

  ## Options

    * `:agent_count` - Override default agent count
    * `:topology` - Force topology: `:parallel`, `:sequential`, or `:auto` (default: `:auto`)
    * `:timeout` - Total timeout in milliseconds (default: #{@default_timeout})
    * `:providers` - Explicit provider list (default: auto-discovered)
    * `:on_error` - Error handling: `:collect`, `:stop`, `:skip` (default: `:collect`)
    * `:parallel_count` - Max concurrent agents for parallel topology (default: `:infinity`)

  ## Returns

    * `{:ok, aggregated_result}` - Successful execution with aggregated results
    * `{:error, reason}` - Execution failed

  ## Examples

      # Basic usage with auto-detection
      task = %{
        description: "Research Elixir patterns",
        subtasks: [
          %{id: "research", description: "Find patterns", agent: ResearchAgent},
          %{id: "analyze", description: "Analyze patterns", agent: AnalysisAgent},
          %{id: "summarize", description: "Summarize findings", agent: SummaryAgent}
        ]
      }

      {:ok, result} = AgentHarness.Orchestrator.run(task)

      # Custom configuration
      {:ok, result} = AgentHarness.Orchestrator.run(task,
        agent_count: 5,
        topology: :parallel,
        timeout: 120_000,
        parallel_count: 3
      )

      # Force sequential execution
      {:ok, result} = AgentHarness.Orchestrator.run(task, topology: :sequential)

  ## Execution Flow

      ┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
      │ analyze_task │ ──→ │ spawn_agents │ ──→ │   topology   │ ──→ │  aggregate   │
      │    /1        │     │    /2        │     │    .run      │     │  _results/1  │
      └──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
  """
  @spec run(task(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(task, opts \\ []) do
    topology_override = Keyword.get(opts, :topology, @default_topology)
    agent_count_override = Keyword.get(opts, :agent_count)
    providers_override = Keyword.get(opts, :providers)

    Logger.info("[Orchestrator] Starting task execution")

    # Step 1: Analyze task
    strategy = analyze_task(task)

    # Apply overrides
    strategy = apply_overrides(strategy, topology_override, agent_count_override, providers_override)

    # Step 2: Spawn agents
    agent_tasks = spawn_agents(task, strategy,
      agent_count: strategy.agent_count,
      providers: strategy.providers
    )

    # Step 3: Execute topology
    topology_result =
      case strategy.topology do
        :parallel ->
          run_parallel(agent_tasks, opts)

        :sequential ->
          run_sequential(agent_tasks, opts)
      end

    # Step 4: Aggregate results
    aggregate_results(topology_result)
  end

  # ── Private Functions ─────────────────────────────────────────────

  # Get subtasks from task map
  defp get_subtasks(task) do
    subtasks = Map.get(task, :subtasks, Map.get(task, "subtasks", []))

    # If no explicit subtasks but there's a description, create a single task
    if Enum.empty?(subtasks) do
      default_agent = Map.get(task, :agent, &default_agent_handler/2)

      [
        %{
          id: "main",
          description: Map.get(task, :description, Map.get(task, "description", "")),
          agent: default_agent,
          input: Map.get(task, :input, %{})
        }
      ]
    else
      subtasks
    end
  end

  # Check if task has dependencies
  defp has_dependencies?(task, _subtasks) do
    # Check for explicit dependencies
    dependencies = Map.get(task, :dependencies, Map.get(task, "dependencies", []))

    if Enum.empty?(dependencies) do
      # Check if subtasks have dependency markers
      subtasks = get_subtasks(task)

      Enum.any?(subtasks, fn subtask ->
        Map.has_key?(subtask, :depends_on) or Map.has_key?(subtask, "depends_on")
      end)
    else
      true
    end
  end

  # Determine complexity level
  defp determine_complexity(subtask_count, has_dependencies)

  defp determine_complexity(count, _deps) when count <= @simple_threshold, do: :simple
  defp determine_complexity(count, _deps) when count < @moderate_threshold, do: :moderate
  defp determine_complexity(_count, true), do: :moderate
  defp determine_complexity(_count, _deps), do: :complex

  # Get available providers from environment
  defp get_available_providers do
    providers =
      Enum.filter(@provider_env_vars, fn {_name, env_var} ->
        System.get_env(env_var) not in [nil, ""]
      end)
      |> Enum.map(fn {name, _env_var} -> name end)

    if Enum.empty?(providers) do
      Logger.warning("[Orchestrator] No providers configured in environment")
      [:default]
    else
      Logger.info("[Orchestrator] Available providers: #{inspect(providers)}")
      providers
    end
  end

  # Spawn agents for parallel execution
  defp spawn_parallel_agents(subtasks, agent_count, providers, task) do
    default_agent = Map.get(task, :agent, &default_agent_handler/2)

    Enum.with_index(subtasks, 1)
    |> Enum.map(fn {subtask, index} ->
      provider = get_provider_for_index(index, providers)
      agent = Map.get(subtask, :agent, default_agent)

      %{
        id: Map.get(subtask, :id, "task-#{index}"),
        agent: agent,
        input: prepare_agent_input(subtask, task, index),
        opts: [provider: provider, timeout: @default_timeout]
      }
    end)
    |> maybe_limit_count(agent_count)
  end

  # Spawn agents for sequential execution
  defp spawn_sequential_agents(subtasks, _agent_count, providers, task) do
    default_agent = Map.get(task, :agent, &default_agent_handler/2)

    Enum.with_index(subtasks, 1)
    |> Enum.map(fn {subtask, index} ->
      provider = get_provider_for_index(index, providers)
      agent = Map.get(subtask, :agent, default_agent)

      %{
        id: Map.get(subtask, :id, "step-#{index}"),
        agent: agent,
        input: prepare_agent_input(subtask, task, index),
        opts: [provider: provider, timeout: @default_timeout]
      }
    end)
  end

  # Get provider for index (round-robin distribution)
  defp get_provider_for_index(index, [_ | _] = providers) do
    Enum.at(providers, rem(index - 1, length(providers)))
  end

  defp get_provider_for_index(_index, _providers), do: :default

  # Prepare input for agent
  defp prepare_agent_input(subtask, task, index) do
    subtask_input = Map.get(subtask, :input, %{})

    base_input =
      task
      |> Map.get(:input, %{})
      |> Map.merge(%{
        subtask_id: Map.get(subtask, :id, "task-#{index}"),
        subtask_description: Map.get(subtask, :description, ""),
        subtask_index: index
      })

    Map.merge(base_input, subtask_input)
  end

  # Limit task count if needed
  defp maybe_limit_count(tasks, agent_count) when length(tasks) > agent_count do
    Enum.take(tasks, agent_count)
  end

  defp maybe_limit_count(tasks, _agent_count), do: tasks

  # Apply user overrides to strategy
  defp apply_overrides(strategy, topology_override, agent_count_override, providers_override) do
    strategy
    |> apply_topology_override(topology_override)
    |> apply_agent_count_override(agent_count_override)
    |> apply_providers_override(providers_override)
  end

  defp apply_topology_override(strategy, :auto), do: strategy

  defp apply_topology_override(strategy, topology) when topology in [:parallel, :sequential] do
    %{strategy | topology: topology}
  end

  defp apply_topology_override(strategy, _), do: strategy

  defp apply_agent_count_override(strategy, nil), do: strategy

  defp apply_agent_count_override(strategy, count) when is_integer(count) and count > 0 do
    %{strategy | agent_count: count}
  end

  defp apply_agent_count_override(strategy, _), do: strategy

  defp apply_providers_override(strategy, nil), do: strategy

  defp apply_providers_override(strategy, providers) when is_list(providers) do
    %{strategy | providers: providers}
  end

  defp apply_providers_override(strategy, _), do: strategy

  # Run parallel topology
  defp run_parallel(agent_tasks, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    on_error = Keyword.get(opts, :on_error, :collect)
    parallel_count = Keyword.get(opts, :parallel_count, :infinity)

    Logger.debug("[Orchestrator] Running parallel topology with #{length(agent_tasks)} tasks")

    Parallel.run(agent_tasks,
      timeout: timeout,
      on_error: on_error,
      parallel_count: parallel_count
    )
  end

  # Run sequential topology
  defp run_sequential(agent_tasks, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    on_error = Keyword.get(opts, :on_error, :continue)

    Logger.debug("[Orchestrator] Running sequential topology with #{length(agent_tasks)} tasks")

    Sequential.run(agent_tasks,
      timeout: timeout,
      on_error: on_error
    )
  end

  # Aggregate parallel results
  defp aggregate_parallel_results(results, metadata) do
    success_count = Map.get(metadata, :success_count, 0)
    error_count = Map.get(metadata, :error_count, 0)

    outputs =
      results
      |> Enum.filter(&(&1.status == :success))
      |> Enum.map(&Map.get(&1, :output))

    errors =
      results
      |> Enum.filter(&(&1.status == :error))
      |> Enum.map(&%{id: &1.id, error: Map.get(&1, :error)})

    %{
      outputs: outputs,
      error_details: errors,
      success_count: success_count,
      error_count: error_count,
      total_count: length(results),
      topology: :parallel,
      metadata: metadata
    }
  end

  # Aggregate sequential results
  defp aggregate_sequential_results(results, metadata) do
    success_count = Map.get(metadata, :success_count, 0)
    error_count = Map.get(metadata, :error_count, 0)

    # Build result chain
    chain =
      Enum.map(results, fn result ->
        %{
          id: Map.get(result, :id),
          status: Map.get(result, :status),
          output: Map.get(result, :output),
          error: Map.get(result, :error),
          duration_ms: Map.get(result, :duration_ms, 0)
        }
      end)

    # Get final output from last successful result
    final_output =
      results
      |> Enum.reverse()
      |> Enum.find(&(&1.status == :success))
      |> then(fn
        nil -> nil
        result -> Map.get(result, :output)
      end)

    %{
      final_output: final_output,
      chain: chain,
      success_count: success_count,
      error_count: error_count,
      total_count: length(results),
      topology: :sequential,
      metadata: metadata
    }
  end

  # Generic aggregation fallback
  defp aggregate_generic_results(results, metadata) do
    success_count = Map.get(metadata, :success_count, 0)
    error_count = Map.get(metadata, :error_count, 0)

    %{
      results: results,
      success_count: success_count,
      error_count: error_count,
      total_count: length(results),
      topology: :unknown,
      metadata: metadata
    }
  end

  # Default agent handler for tasks without explicit agents
  defp default_agent_handler(input, _opts) do
    # This is a placeholder that returns the input as-is
    # In production, this would call an actual LLM agent
    Logger.debug("[Orchestrator] Default handler processing: #{inspect(input)}")

    {:ok,
     %{
       processed: true,
       input: input,
       message: "Default handler - implement custom agent for actual processing"
     }}
  end
end
