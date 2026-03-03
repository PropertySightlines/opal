defmodule AgentHarness.Topology do
  @moduledoc """
  Topology behaviour for Agent Harness Phase 2.

  Defines the contract for execution topologies that determine how agents
  are orchestrated and coordinated during task execution.

  ## Topology Types

  Built-in topologies:

    * `AgentHarness.Topology.Sequential` - Agents execute one after another
    * `AgentHarness.Topology.Parallel` - Agents execute concurrently

  Future topologies (planned):

    * `:consensus` - Multiple agents vote on results
    * `:hierarchical` - Tree-like agent structure with parent-child relationships
    * `:fan_out` - One agent fans out to many, then aggregates
    * `:collaborative` - Agents share state and iterate together
    * `:hybrid` - Combines multiple topology strategies

  ## Usage

  Topologies are executed through the registry:

      # Register a topology
      AgentHarness.Topology.Registry.register(:sequential, AgentHarness.Topology.Sequential)

      # Run tasks using a registered topology
      AgentHarness.Topology.Registry.run(:sequential, tasks, timeout: 30_000)

      # Or run directly with a module
      AgentHarness.Topology.Sequential.run(tasks, timeout: 30_000)

  ## Task Format

  Tasks are maps with the following structure:

      %{
        id: "task-1",
        agent: MyAgentModule,
        input: %{query: "What is the weather?"},
        opts: [timeout: 5000]
      }

  ## Result Format

  Results include metadata about execution:

      {:ok, %{
        results: [...],
        metadata: %{
          topology: :sequential,
          total_time_ms: 1500,
          success_count: 3,
          error_count: 0
        }
      }}

  ## Callback

  See `c:run/2` for the behaviour callback specification.
  """

  @doc """
  Executes a list of tasks according to the topology's execution strategy.

  ## Parameters

    * `task` - A list of task maps to execute. Each task should contain:
      * `:id` - Unique identifier for the task
      * `:agent` - The agent module or function to execute
      * `:input` - Input data for the agent
      * `:opts` - Optional execution options for this specific task

    * `opts` - Keyword list of options for topology execution:
      * `:timeout` - Maximum time in milliseconds for entire execution (default: 30_000)
      * `:on_error` - Error handling strategy: `:stop`, `:continue`, or `:skip` (default: `:continue`)
      * `:metadata` - Additional metadata to include in results

  ## Returns

    * `{:ok, result}` - Execution completed successfully with aggregated results
    * `{:error, reason}` - Execution failed with error reason

  ## Example

      tasks = [
        %{id: "step1", agent: WeatherAgent, input: %{city: "NYC"}},
        %{id: "step2", agent: NewsAgent, input: %{topic: "weather"}},
        %{id: "step3", agent: SummaryAgent, input: %{format: "brief"}}
      ]

      AgentHarness.Topology.Sequential.run(tasks, timeout: 60_000)
  """
  @callback run(task :: map(), opts :: keyword()) :: {:ok, result :: map()} | {:error, term()}

  @doc """
  Returns the topology name as an atom.

  Used for identification and logging purposes.
  """
  @callback name() :: atom()

  @optional_callbacks [name: 0]
end
