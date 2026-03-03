# AgentHarness Topologies

## Overview

Topologies define how agents are organized and execute tasks. AgentHarness Phase 2 supports **sequential** and **parallel** topologies, with an extensible architecture for future patterns (consensus, hierarchical, fan-out, collaborative, hybrid).

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                   Topology Manager                            │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  Topology.Registry                                   │    │
│  │  - :sequential → Sequential module                   │    │
│  │  - :parallel → Parallel module                       │    │
│  │  - Custom topologies...                              │    │
│  └──────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────┘
         │                    │
         ▼                    ▼
┌─────────────────┐  ┌─────────────────┐
│ Sequential      │  │ Parallel        │
│ ─────────────── │  │ ─────────────── │  │
│ Agent 1 →       │  │ Agent 1 ─┐      │
│ Agent 2 →       │  │ Agent 2 ─┼──►  │
│ Agent 3 →       │  │ Agent 3 ─┘      │
│ Result          │  │ Aggregate       │
└─────────────────┘  └─────────────────┘
```

## Built-in Topologies

### 1. Sequential Topology

Executes agents one after another, passing results between steps.

**Use Cases:**
- Multi-step tasks with dependencies
- Data processing pipelines
- Review → Revise → Finalize workflows

**API:**

```elixir
tasks = [
  %{type: :prompt, content: "Research Elixir best practices"},
  %{type: :prompt, content: "Write code examples"},
  %{type: :prompt, content: "Review and refine"}
]

{:ok, results} = AgentHarness.Topology.run(tasks, :sequential,
  timeout: 300_000,           # Total timeout
  task_timeout: 60_000,       # Per-task timeout
  on_error: :stop,            # :stop | :continue | :skip
  pass_results: true,         # Pass previous results to next task
  metadata: %{project: "docs"}
)
```

**Result Format:**

```elixir
{:ok, %{
  topology: :sequential,
  results: [
    %{task_id: 1, status: :success, output: "...", duration_ms: 1234},
    %{task_id: 2, status: :success, output: "...", duration_ms: 2345},
    %{task_id: 3, status: :success, output: "...", duration_ms: 3456}
  ],
  total_duration_ms: 7035,
  success_count: 3,
  error_count: 0
}}
```

**Error Handling Strategies:**

| Strategy | Behavior |
|----------|----------|
| `:stop` | Stop on first error, return partial results |
| `:continue` | Continue despite errors, collect all results |
| `:skip` | Skip failed task, continue with next |

### 2. Parallel Topology

Executes multiple agents concurrently, aggregating results.

**Use Cases:**
- Independent research tasks
- A/B testing prompts
- Multi-provider comparison
- Data collection from multiple sources

**API:**

```elixir
tasks = [
  %{type: :prompt, content: "Research topic A from angle 1"},
  %{type: :prompt, content: "Research topic A from angle 2"},
  %{type: :prompt, content: "Research topic A from angle 3"}
]

{:ok, results} = AgentHarness.Topology.run(tasks, :parallel,
  timeout: 60_000,            # Total timeout
  parallel_count: 3,          # Max concurrent agents
  on_error: :collect,         # :collect | :stop | :require_all
  require_all: false,         # Return partial if some fail
  metadata: %{research: "topic_a"}
)
```

**Result Format:**

```elixir
{:ok, %{
  topology: :parallel,
  results: [
    %{task_id: 1, status: :success, output: "...", duration_ms: 1234},
    %{task_id: 2, status: :success, output: "...", duration_ms: 1567},
    %{task_id: 3, status: :success, output: "...", duration_ms: 1890}
  ],
  total_duration_ms: 1890,    # Wall clock time (not sum)
  success_count: 3,
  error_count: 0,
  parallelism_factor: 2.5     # Sequential time / Parallel time
}}
```

**Concurrency Control:**

```elixir
# Limit concurrent agents to avoid rate limits
{:ok, results} = AgentHarness.Topology.run(tasks, :parallel,
  parallel_count: 2,  # Only 2 agents at a time
  timeout: 120_000
)
```

## Topology Registry

Register custom topologies:

```elixir
# Register a custom topology
AgentHarness.Topology.Registry.register(
  :custom_pipeline,
  MyApp.CustomPipelineTopology,
  description: "Custom multi-stage pipeline"
)

# Use registered topology
{:ok, results} = AgentHarness.Topology.run(tasks, :custom_pipeline)

# List all registered topologies
topologies = AgentHarness.Topology.Registry.list()
# => [:sequential, :parallel, :custom_pipeline]

# Check if registered
AgentHarness.Topology.Registry.registered?(:parallel)
# => true
```

## Usage Examples

### Example 1: Code Review Pipeline (Sequential)

```elixir
defmodule CodeReviewPipeline do
  def run(code) do
    tasks = [
      %{
        type: :prompt,
        content: "Review this code for bugs: #{code}",
        system_prompt: "You are a senior engineer focused on correctness"
      },
      %{
        type: :prompt,
        content: "Suggest performance improvements",
        system_prompt: "You are a performance expert"
      },
      %{
        type: :prompt,
        content: "Check security vulnerabilities",
        system_prompt: "You are a security researcher"
      },
      %{
        type: :prompt,
        content: "Generate final report",
        system_prompt: "Synthesize all feedback into actionable items"
      }
    ]

    {:ok, results} = AgentHarness.Topology.run(tasks, :sequential,
      pass_results: true,
      task_timeout: 60_000
    )

    # Extract final report
    final_report = List.last(results).output
  end
end
```

### Example 2: Multi-Angle Research (Parallel)

```elixir
defmodule ResearchAgent do
  def research_topic(topic) do
    tasks = [
      %{type: :prompt, content: "Historical context of #{topic}"},
      %{type: :prompt, content: "Current state of #{topic}"},
      %{type: :prompt, content: "Future trends in #{topic}"},
      %{type: :prompt, content: "Controversies around #{topic}"},
      %{type: :prompt, content: "Key figures in #{topic}"}
    ]

    {:ok, results} = AgentHarness.Topology.run(tasks, :parallel,
      parallel_count: 3,  # Respect rate limits
      timeout: 90_000,
      require_all: false  # Return partial if some fail
    )

    # Aggregate results
    aggregate_findings(results)
  end

  defp aggregate_findings(results) do
    results
    |> Enum.filter(&(&1.status == :success))
    |> Enum.map(& &1.output)
    |> Enum.join("\n\n---\n\n")
  end
end
```

### Example 3: Hybrid (Sequential + Parallel)

```elixir
defmodule HybridPipeline do
  def run_research_and_review(topic) do
    # Phase 1: Parallel research
    research_tasks = [
      %{type: :prompt, content: "Research #{topic} - technical aspects"},
      %{type: :prompt, content: "Research #{topic} - business aspects"},
      %{type: :prompt, content: "Research #{topic} - community sentiment"}
    ]

    {:ok, research_results} = AgentHarness.Topology.run(
      research_tasks, :parallel, parallel_count: 3
    )

    # Phase 2: Sequential synthesis
    synthesis_tasks = [
      %{
        type: :prompt,
        content: "Synthesize: #{inspect(research_results)}",
        system_prompt: "Combine all research into coherent analysis"
      }
    ]

    {:ok, synthesis_results} = AgentHarness.Topology.run(
      synthesis_tasks, :sequential
    )

    synthesis_results
  end
end
```

### Example 4: Provider Comparison (Parallel)

```elixir
defmodule ProviderComparison do
  def compare_providers(prompt) do
    # Same prompt to different providers
    tasks = [
      %{provider: :groq, prompt: prompt},
      %{provider: :cerebras, prompt: prompt},
      %{provider: :nvidia, prompt: prompt}
    ]

    {:ok, results} = AgentHarness.Topology.run(tasks, :parallel,
      parallel_count: 3
    )

    # Compare responses
    compare_responses(results)
  end

  defp compare_responses(results) do
    Enum.map(results, fn r ->
      %{
        provider: r.metadata.provider,
        quality: score_response(r.output),
        latency: r.duration_ms,
        tokens: r.token_count
      }
    end)
  end
end
```

## Creating Custom Topologies

Implement the `AgentHarness.Topology` behaviour:

```elixir
defmodule MyApp.ConsensusTopology do
  @behaviour AgentHarness.Topology

  @impl true
  def name, do: :consensus

  @impl true
  def run(tasks, opts) do
    # 1. Send same task to multiple providers
    provider_tasks = for provider <- opts[:providers] do
      %{provider: provider, task: hd(tasks)}
    end

    # 2. Run in parallel
    {:ok, parallel_results} = AgentHarness.Topology.Parallel.run(
      provider_tasks,
      parallel_count: length(provider_tasks)
    )

    # 3. Aggregate via voting
    consensus = vote_on_results(parallel_results)

    {:ok, %{
      topology: :consensus,
      results: parallel_results,
      consensus: consensus,
      vote_distribution: calculate_distribution(parallel_results)
    }}
  end

  defp vote_on_results(results) do
    # Implement voting logic
    # e.g., majority vote, weighted vote, etc.
  end
end

# Register and use
AgentHarness.Topology.Registry.register(
  :consensus,
  MyApp.ConsensusTopology,
  description: "Multi-provider consensus voting"
)
```

## Performance Considerations

### Sequential vs Parallel

| Factor | Sequential | Parallel |
|--------|------------|----------|
| Latency | Sum of all tasks | Max of all tasks |
| Rate Limit Impact | Lower (spread over time) | Higher (burst) |
| Cost | Same | Same |
| Use Case | Dependent tasks | Independent tasks |

### Rate Limit Awareness

Always consider rate limits when using parallel topology:

```elixir
# Bad: May hit rate limits
AgentHarness.Topology.run(tasks, :parallel, parallel_count: 10)

# Good: Respect rate limits
AgentHarness.Topology.run(tasks, :parallel,
  parallel_count: 3,  # Within RPM budget
  timeout: 120_000    # Allow time for rate limit waits
)
```

### Token Budgeting

```elixir
# Estimate total tokens
total_estimate = Enum.reduce(tasks, 0, fn task, acc ->
  acc + estimate_tokens(task.content)
end)

# Check if within budget
if total_estimate > get_tpm_budget() do
  # Split into batches
  tasks
  |> Enum.chunk_every(3)
  |> Enum.map(fn batch ->
    AgentHarness.Topology.run(batch, :parallel)
  end)
else
  AgentHarness.Topology.run(tasks, :parallel)
end
```

## Monitoring

### Topology Execution Status

```elixir
# Get execution info
info = AgentHarness.Topology.Registry.info(:sequential)
IO.puts("Sequential topology: #{info.description}")
```

### Task Progress

```elixir
# Subscribe to progress events (via Opal.Events)
Opal.Events.subscribe(session_id)

receive do
  {:topology_progress, %{completed: 2, total: 5}} ->
    IO.puts("40% complete")
    
  {:topology_complete, %{results: results}} ->
    IO.puts("Done: #{length(results)} results")
end
```

## Future Topologies (Phase 3+)

| Topology | Description | Status |
|----------|-------------|--------|
| `:consensus` | Multi-provider voting | Planned |
| `:hierarchical` | Parent → child → grandchild trees | Planned |
| `:fan_out` | Parallel queries → aggregate | Planned |
| `:collaborative` | Peer-to-peer negotiation | Planned |
| `:hybrid` | Dynamic topology selection | Planned |

## Testing

### Unit Tests

```bash
mix agent_harness.test
```

### Live Tests

```bash
mix agent_harness.test.live
```

### Manual Testing

```elixir
iex -S mix

# Test sequential
tasks = [
  %{type: :prompt, content: "Say hello"},
  %{type: :prompt, content: "Say goodbye"}
]
AgentHarness.Topology.run(tasks, :sequential)

# Test parallel
tasks = [
  %{type: :prompt, content: "Research A"},
  %{type: :prompt, content: "Research B"},
  %{type: :prompt, content: "Research C"}
]
AgentHarness.Topology.run(tasks, :parallel, parallel_count: 2)
```

## Troubleshooting

### Sequential: Tasks Not Passing Results

**Symptom:** Later tasks don't have context from earlier tasks

**Solution:**
```elixir
# Enable pass_results option
AgentHarness.Topology.run(tasks, :sequential, pass_results: true)
```

### Parallel: Timeout Too Short

**Symptom:** Some tasks timeout before completion

**Solution:**
```elixir
# Increase timeout or reduce parallel_count
AgentHarness.Topology.run(tasks, :parallel,
  timeout: 120_000,      # Increase from default
  parallel_count: 2      # Reduce concurrency
)
```

### Parallel: Rate Limit Errors

**Symptom:** 429 errors from providers

**Solution:**
```elixir
# Reduce parallel_count or use rate-limited router
AgentHarness.Topology.run(tasks, :parallel,
  parallel_count: 2,  # Within RPM budget
  use_router: true    # Enable rate limit queuing
)
```

## References

- [Rate Limit Router](rate-limit-router.md)
- [Agent Communication](agent-communication.md)
- [Opal Documentation](../README.md)
