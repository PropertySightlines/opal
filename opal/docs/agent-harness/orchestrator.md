# AgentHarness Orchestrator

## Overview

The `AgentHarness.Orchestrator` module provides intelligent task analysis and agent spawning strategies for complex multi-agent workflows. It automatically determines task complexity and selects the appropriate execution topology (parallel or sequential), manages provider distribution, and aggregates results from multiple agents.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Orchestrator                           │
├─────────────────────────────────────────────────────────────┤
│  analyze_task/1  →  Determines complexity & strategy        │
│  spawn_agents/2  →  Creates agent tasks based on topology  │
│  aggregate_results/1 → Combines results from all agents    │
│  run/2           →  Main entry point (orchestrates all)    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │    Topology Execution         │
              │  ┌─────────┐  ┌────────────┐  │
              │  │Parallel │  │Sequential  │  │
              │  └─────────┘  └────────────┘  │
              └───────────────────────────────┘
```

### Key Components

| Component | Responsibility |
|-----------|----------------|
| **Task Analyzer** | Examines task structure to determine complexity level |
| **Strategy Selector** | Chooses topology (parallel/sequential) based on analysis |
| **Agent Spawner** | Creates agent tasks with provider distribution |
| **Result Aggregator** | Combines results from multiple agent executions |
| **Provider Router** | Distributes work across available LLM providers |

## How Task Analysis Works

The orchestrator analyzes tasks through a multi-step process:

### 1. Subtask Detection

```elixir
# Task with explicit subtasks
task = %{
  description: "Research and analyze Elixir patterns",
  subtasks: [
    %{id: "research", description: "Gather information"},
    %{id: "analyze", description: "Analyze findings"},
    %{id: "report", description: "Create report"}
  ]
}

# Task without subtasks (creates single default task)
task = %{
  description: "Answer this question",
  agent: MyCustomAgent
}
```

### 2. Dependency Detection

The analyzer checks for task dependencies that would force sequential execution:

```elixir
# Explicit dependencies
task = %{
  description: "Multi-step pipeline",
  subtasks: [...],
  dependencies: [
    %{from: "step-2", to: "step-1"}  # step-2 depends on step-1
  ]
}

# Implicit dependencies (depends_on marker)
subtasks = [
  %{id: "step-1", description: "First step"},
  %{id: "step-2", description: "Second step", depends_on: ["step-1"]}
]
```

### 3. Complexity Determination

| Complexity | Subtask Count | Has Dependencies | Topology | Agent Count |
|------------|---------------|------------------|----------|-------------|
| `:simple` | 1 | Any | `:sequential` | 1 |
| `:moderate` | 2-3 | No | `:parallel` | subtask_count |
| `:moderate` | Any | Yes | `:sequential` | subtask_count |
| `:complex` | 4+ | No | `:parallel` | max(subtask_count, 3) |

### 4. Provider Discovery

Available providers are auto-discovered from environment variables:

```elixir
# Detected providers (from .env or system environment)
OPENROUTER_API_KEY=sk-or-...
NVIDIA_API_KEY=nvapi-...
GROQ_API_KEY=gsk_...
CEREBRAS_API_KEY=csk_...

# Logger output
[info] [Orchestrator] Available providers: [:openrouter, :nvidia, :groq, :cerebras]
```

### Analysis Example

```elixir
task = %{
  description: "Comprehensive code review",
  subtasks: [
    %{id: "security", description: "Check for vulnerabilities"},
    %{id: "performance", description: "Analyze performance"},
    %{id: "style", description: "Review code style"},
    %{id: "tests", description: "Evaluate test coverage"},
    %{id: "docs", description: "Check documentation"}
  ]
}

strategy = AgentHarness.Orchestrator.analyze_task(task)
# => %{
#      complexity: :complex,
#      topology: :parallel,
#      agent_count: 5,
#      providers: [:openrouter, :nvidia, :groq, :cerebras]
#    }
```

## Agent Spawning Strategies

### Parallel Spawning

Used for independent subtasks that can execute concurrently.

**When Used:**
- No dependencies between subtasks
- Complexity is `:moderate` or `:complex`
- Multiple providers available for load distribution

**Provider Distribution (Round-Robin):**

```elixir
# 5 agents, 4 providers
providers = [:groq, :nvidia, :openrouter, :cerebras]

# Distribution:
# Agent 1 → :groq
# Agent 2 → :nvidia
# Agent 3 → :openrouter
# Agent 4 → :cerebras
# Agent 5 → :groq  (wraps around)
```

**Code Example:**

```elixir
strategy = %{
  complexity: :complex,
  topology: :parallel,
  agent_count: 5,
  providers: [:groq, :nvidia, :openrouter]
}

tasks = AgentHarness.Orchestrator.spawn_agents(task, strategy)
# => [
#      %{
#        id: "security",
#        agent: SecurityAgent,
#        input: %{subtask_id: "security", ...},
#        opts: [provider: :groq, timeout: 60_000]
#      },
#      %{
#        id: "performance",
#        agent: PerformanceAgent,
#        input: %{subtask_id: "performance", ...},
#        opts: [provider: :nvidia, timeout: 60_000]
#      },
#      ...
#    ]
```

### Sequential Spawning

Used for dependent subtasks that must execute in order.

**When Used:**
- Dependencies exist between subtasks
- Complexity is `:simple`
- Topology explicitly forced to `:sequential`

**Execution Flow:**

```
Agent 1 (step-1) → Agent 2 (step-2) → Agent 3 (step-3)
     completes         starts            starts
```

**Code Example:**

```elixir
task = %{
  description: "Research pipeline",
  subtasks: [
    %{id: "gather", description: "Gather data"},
    %{id: "analyze", description: "Analyze data", depends_on: ["gather"]},
    %{id: "report", description: "Write report", depends_on: ["analyze"]}
  ]
}

strategy = AgentHarness.Orchestrator.analyze_task(task)
# topology will be :sequential due to dependencies

tasks = AgentHarness.Orchestrator.spawn_agents(task, strategy)
# => [
#      %{id: "step-1", ...},  # gather
#      %{id: "step-2", ...},  # analyze
#      %{id: "step-3", ...}   # report
#    ]
```

## Result Aggregation

The orchestrator aggregates results differently based on topology type.

### Parallel Aggregation

Collects independent results from all agents:

```elixir
parallel_result = {:ok, %{
  results: [
    %{id: "task-1", status: :success, output: "Result A", duration_ms: 1200},
    %{id: "task-2", status: :success, output: "Result B", duration_ms: 950},
    %{id: "task-3", status: :error, error: :timeout, duration_ms: 5000}
  ],
  metadata: %{topology: :parallel, success_count: 2, error_count: 1}
}}

{:ok, aggregated} = AgentHarness.Orchestrator.aggregate_results(parallel_result)
# => {:ok, %{
#      outputs: ["Result A", "Result B"],
#      error_details: [%{id: "task-3", error: :timeout}],
#      success_count: 2,
#      error_count: 1,
#      total_count: 3,
#      topology: :parallel,
#      metadata: %{...}
#    }}
```

### Sequential Aggregation

Chains results, preserving execution order and final output:

```elixir
sequential_result = {:ok, %{
  results: [
    %{id: "step-1", status: :success, output: "Research data", duration_ms: 1200},
    %{id: "step-2", status: :success, output: "Analysis", duration_ms: 800},
    %{id: "step-3", status: :success, output: "Final report", duration_ms: 500}
  ],
  metadata: %{topology: :sequential, success_count: 3}
}}

{:ok, aggregated} = AgentHarness.Orchestrator.aggregate_results(sequential_result)
# => {:ok, %{
#      final_output: "Final report",
#      chain: [
#        %{id: "step-1", status: :success, output: "Research data", ...},
#        %{id: "step-2", status: :success, output: "Analysis", ...},
#        %{id: "step-3", status: :success, output: "Final report", ...}
#      ],
#      success_count: 3,
#      error_count: 0,
#      total_count: 3,
#      topology: :sequential,
#      metadata: %{...}
#    }}
```

### Error Handling

Partial failures are handled gracefully:

```elixir
# With on_error: :collect (default)
{:ok, result} = AgentHarness.Orchestrator.run(task, on_error: :collect)
# Successful results preserved, errors included in response

# With on_error: :stop
{:error, {:tasks_failed, response}} = AgentHarness.Orchestrator.run(task, on_error: :stop)
# Stops on first failure

# With require_all: true (parallel only)
{:error, {:partial_failure, response}} = AgentHarness.Orchestrator.run(task, require_all: true)
# Fails if any task fails
```

## Configuration Options

### run/2 Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:agent_count` | `pos_integer()` | Auto | Override agent count |
| `:topology` | `:parallel \| :sequential \| :auto` | `:auto` | Force topology |
| `:timeout` | `timeout()` | 60_000 | Total timeout (ms) |
| `:providers` | `[atom()]` | Auto | Explicit provider list |
| `:on_error` | `:collect \| :stop \| :skip` | `:collect` | Error strategy |
| `:parallel_count` | `pos_integer() \| :infinity` | `:infinity` | Max concurrent agents |

### Configuration Examples

```elixir
# Basic usage (auto-detection)
{:ok, result} = AgentHarness.Orchestrator.run(task)

# Custom agent count
{:ok, result} = AgentHarness.Orchestrator.run(task, agent_count: 5)

# Force parallel execution
{:ok, result} = AgentHarness.Orchestrator.run(task, topology: :parallel)

# Force sequential execution
{:ok, result} = AgentHarness.Orchestrator.run(task, topology: :sequential)

# Custom timeout and error handling
{:ok, result} = AgentHarness.Orchestrator.run(task,
  timeout: 120_000,
  on_error: :stop
)

# Limit parallel concurrency
{:ok, result} = AgentHarness.Orchestrator.run(task,
  topology: :parallel,
  parallel_count: 2
)

# Explicit providers
{:ok, result} = AgentHarness.Orchestrator.run(task,
  providers: [:groq, :nvidia]
)

# Combined options
{:ok, result} = AgentHarness.Orchestrator.run(task,
  agent_count: 5,
  topology: :parallel,
  timeout: 120_000,
  providers: [:groq, :nvidia, :openrouter],
  on_error: :collect,
  parallel_count: 3
)
```

## Usage Examples

### Example 1: Basic Multi-Agent Research

```elixir
defmodule ResearchOrchestrator do
  def research_topic(topic) do
    task = %{
      description: "Research #{topic} comprehensively",
      subtasks: [
        %{
          id: "historical",
          description: "Gather historical context",
          agent: ResearchAgent
        },
        %{
          id: "current",
          description: "Analyze current state",
          agent: AnalysisAgent
        },
        %{
          id: "future",
          description: "Predict future trends",
          agent: ForecastAgent
        }
      ]
    }

    {:ok, result} = AgentHarness.Orchestrator.run(task,
      timeout: 90_000,
      parallel_count: 3
    )

    # Access individual outputs
    result.outputs
  end
end
```

### Example 2: Sequential Pipeline

```elixir
defmodule CodeReviewPipeline do
  def review_code(code) do
    task = %{
      description: "Complete code review",
      subtasks: [
        %{
          id: "security",
          description: "Check for security vulnerabilities",
          agent: SecurityAgent,
          input: %{code: code}
        },
        %{
          id: "performance",
          description: "Analyze performance implications",
          agent: PerformanceAgent,
          depends_on: ["security"]
        },
        %{
          id: "summary",
          description: "Generate review summary",
          agent: SummaryAgent,
          depends_on: ["security", "performance"]
        }
      ]
    }

    {:ok, result} = AgentHarness.Orchestrator.run(task,
      topology: :sequential,
      timeout: 120_000
    )

    # Get final output
    result.final_output
  end
end
```

### Example 3: Hybrid Approach (Manual)

```elixir
defmodule HybridResearch do
  def research_and_synthesize(topic) do
    # Phase 1: Parallel research
    research_task = %{
      description: "Parallel research on #{topic}",
      subtasks: [
        %{id: "technical", description: "Technical aspects"},
        %{id: "business", description: "Business implications"},
        %{id: "community", description: "Community sentiment"}
      ]
    }

    {:ok, research_result} = AgentHarness.Orchestrator.run(research_task,
      topology: :parallel,
      parallel_count: 3
    )

    # Phase 2: Sequential synthesis
    synthesis_task = %{
      description: "Synthesize research findings",
      subtasks: [
        %{
          id: "synthesize",
          description: "Combine findings: #{inspect(research_result.outputs)}",
          agent: SynthesisAgent
        }
      ]
    }

    {:ok, synthesis_result} = AgentHarness.Orchestrator.run(synthesis_task,
      topology: :sequential
    )

    synthesis_result.final_output
  end
end
```

### Example 4: Custom Agent with Provider Selection

```elixir
defmodule CustomAgentExample do
  def run_with_custom_agents do
    task = %{
      description: "Multi-provider comparison",
      subtasks: [
        %{
          id: "groq_response",
          description: "Generate response using Groq",
          agent: fn input, _opts ->
            call_groq(input.prompt)
          end
        },
        %{
          id: "nvidia_response",
          description: "Generate response using NVIDIA",
          agent: fn input, _opts ->
            call_nvidia(input.prompt)
          end
        }
      ],
      input: %{prompt: "Explain Elixir processes"}
    }

    {:ok, result} = AgentHarness.Orchestrator.run(task,
      topology: :parallel,
      providers: [:groq, :nvidia]
    )

    compare_responses(result.outputs)
  end

  defp call_groq(prompt) do
    # Implementation
  end

  defp call_nvidia(prompt) do
    # Implementation
  end
end
```

### Example 5: Task Analysis Only (No Execution)

```elixir
# Analyze task without executing
task = %{
  description: "Large research project",
  subtasks: [
    %{id: "task1", description: "Research A"},
    %{id: "task2", description: "Research B"},
    %{id: "task3", description: "Research C"},
    %{id: "task4", description: "Research D"}
  ]
}

strategy = AgentHarness.Orchestrator.analyze_task(task)
# => %{
#      complexity: :complex,
#      topology: :parallel,
#      agent_count: 4,
#      providers: [:groq, :nvidia, :openrouter, :cerebras]
#    }

# Use strategy info for planning
IO.puts("Will use #{strategy.agent_count} agents with #{strategy.topology} topology")
```

## CLI Slash Commands

The orchestrator is accessible via JSON-RPC methods. These can be invoked through the Opal CLI or any RPC client.

### /multi - Run Parallel Multi-Agent Task

Executes a task using parallel topology (auto-detected or forced).

**RPC Method:** `orchestrator/run`

**Request:**

```json
{
  "jsonrpc": "2.0",
  "method": "orchestrator/run",
  "params": {
    "task": {
      "description": "Research Elixir concurrency patterns",
      "subtasks": [
        {"id": "research", "description": "Gather information"},
        {"id": "analyze", "description": "Analyze findings"},
        {"id": "summarize", "description": "Create summary"}
      ]
    },
    "options": {
      "topology": "parallel",
      "timeout": 90000,
      "parallel_count": 3
    }
  },
  "id": 1
}
```

**Response:**

```json
{
  "jsonrpc": "2.0",
  "result": {
    "session_id": "orch-abc123",
    "strategy": {
      "complexity": "moderate",
      "topology": "parallel",
      "agent_count": 3,
      "providers": ["groq", "nvidia", "openrouter"]
    },
    "result": {
      "outputs": [...],
      "success_count": 3,
      "error_count": 0,
      "topology": "parallel"
    }
  },
  "id": 1
}
```

### /sequential - Run Sequential Multi-Agent Task

Executes a task using sequential topology.

**RPC Method:** `orchestrator/run`

**Request:**

```json
{
  "jsonrpc": "2.0",
  "method": "orchestrator/run",
  "params": {
    "task": {
      "description": "Code review pipeline",
      "subtasks": [
        {"id": "security", "description": "Security review"},
        {"id": "performance", "description": "Performance analysis", "depends_on": ["security"]},
        {"id": "summary", "description": "Generate summary", "depends_on": ["performance"]}
      ]
    },
    "options": {
      "topology": "sequential",
      "timeout": 120000
    }
  },
  "id": 1
}
```

### /analyze - Analyze Task (No Execution)

Analyzes a task and returns the recommended strategy without executing.

**RPC Method:** `orchestrator/analyze`

**Request:**

```json
{
  "jsonrpc": "2.0",
  "method": "orchestrator/analyze",
  "params": {
    "task": {
      "description": "Research project",
      "subtasks": [
        {"id": "task1", "description": "Task 1"},
        {"id": "task2", "description": "Task 2"},
        {"id": "task3", "description": "Task 3"}
      ]
    }
  },
  "id": 1
}
```

**Response:**

```json
{
  "jsonrpc": "2.0",
  "result": {
    "strategy": {
      "complexity": "moderate",
      "topology": "parallel",
      "agent_count": 3,
      "providers": ["groq", "nvidia", "openrouter"]
    },
    "task_summary": {
      "subtask_count": 3,
      "has_dependencies": false,
      "description": "Research project"
    }
  },
  "id": 1
}
```

### /status - Check Orchestrator Status

Get the status of a running or completed orchestrator task.

**RPC Method:** `orchestrator/status`

**Request:**

```json
{
  "jsonrpc": "2.0",
  "method": "orchestrator/status",
  "params": {
    "session_id": "orch-abc123"
  },
  "id": 1
}
```

**Response:**

```json
{
  "jsonrpc": "2.0",
  "result": {
    "status": "running",
    "progress": {
      "completed_agents": 2,
      "total_agents": 5,
      "current_agent": "task-3"
    }
  },
  "id": 1
}
```

## Provider Configuration

### Auto-Discovery

Providers are automatically discovered from environment variables:

```bash
# .env file or system environment
OPENROUTER_API_KEY=sk-or-...
NVIDIA_API_KEY=nvapi-...
GROQ_API_KEY=gsk_...
CEREBRAS_API_KEY=csk_...
```

```elixir
# Detected at runtime
[info] [Orchestrator] Available providers: [:openrouter, :nvidia, :groq, :cerebras]
```

### Explicit Provider Configuration

Override auto-discovery with explicit provider list:

```elixir
# Use only specific providers
{:ok, result} = AgentHarness.Orchestrator.run(task,
  providers: [:groq, :nvidia]
)

# Use single provider for all agents
{:ok, result} = AgentHarness.Orchestrator.run(task,
  providers: [:groq]
)
```

### Provider Rate Limits

Configure rate limits in `config/agent_harness.exs`:

```elixir
config :agent_harness, :rate_limits, %{
  groq: %{rpm: 30, tpm: 60_000},
  cerebras: %{rpm: 20, tpm: 60_000},
  nvidia: %{rpm: 100, tpm: 500_000},
  openrouter: %{rpm: 60, tpm: 100_000}
}
```

### Provider Distribution Strategy

For parallel tasks, agents are distributed round-robin across providers:

```elixir
# 5 agents, 3 providers
providers = [:groq, :nvidia, :openrouter]

# Distribution:
# Agent 1 → groq
# Agent 2 → nvidia
# Agent 3 → openrouter
# Agent 4 → groq      (wraps around)
# Agent 5 → nvidia
```

This ensures:
- Load balancing across providers
- No single provider is overwhelmed
- Maximum utilization of available rate limits

## Troubleshooting

### No Providers Configured

**Symptom:**
```
[warning] [Orchestrator] No providers configured in environment
```

**Cause:** No API key environment variables are set.

**Solution:**
```bash
# Set at least one provider API key
export GROQ_API_KEY=gsk_...
# Or add to .env file
```

### Task Timeout

**Symptom:**
```
{:error, :timeout}
```

**Cause:** Task execution exceeded the timeout limit.

**Solution:**
```elixir
# Increase timeout
{:ok, result} = AgentHarness.Orchestrator.run(task, timeout: 120_000)

# Or reduce parallel_count to avoid rate limit waits
{:ok, result} = AgentHarness.Orchestrator.run(task,
  topology: :parallel,
  parallel_count: 2,
  timeout: 120_000
)
```

### Rate Limit Errors

**Symptom:**
```
{:error, {:rate_limit_exceeded, :groq}}
```

**Cause:** Too many concurrent requests hitting provider rate limits.

**Solution:**
```elixir
# Reduce parallel concurrency
{:ok, result} = AgentHarness.Orchestrator.run(task,
  parallel_count: 2  # Within RPM budget
)

# Or use explicit providers with higher limits
{:ok, result} = AgentHarness.Orchestrator.run(task,
  providers: [:nvidia]  # 100 RPM vs 30 RPM
)
```

### Partial Failures

**Symptom:**
```elixir
{:ok, %{
  outputs: [...],
  error_details: [%{id: "task-2", error: :timeout}],
  success_count: 2,
  error_count: 1
}}
```

**Cause:** Some agents failed while others succeeded.

**Solution:**
```elixir
# Check error_details for specific failures
{:ok, result} = AgentHarness.Orchestrator.run(task)
result.error_details  # Inspect failures

# Or fail fast on any error
{:ok, result} = AgentHarness.Orchestrator.run(task,
  on_error: :stop,
  require_all: true
)
```

### Unexpected Topology Selection

**Symptom:** Task runs sequential when you expected parallel (or vice versa).

**Cause:** Auto-detection based on task structure.

**Solution:**
```elixir
# Force specific topology
{:ok, result} = AgentHarness.Orchestrator.run(task,
  topology: :parallel  # or :sequential
)

# Or analyze first to understand
strategy = AgentHarness.Orchestrator.analyze_task(task)
IO.inspect(strategy.topology)
```

### Memory Issues

**Symptom:** High memory usage during parallel execution.

**Cause:** Too many concurrent agents.

**Solution:**
```elixir
# Limit concurrent agents
{:ok, result} = AgentHarness.Orchestrator.run(task,
  parallel_count: 2
)

# Monitor memory
AgentHarness.Metrics.get_memory_usage()
```

### Debug Commands

```elixir
# Check available providers
# (Set environment variables and restart)

# Analyze task without running
strategy = AgentHarness.Orchestrator.analyze_task(task)
IO.inspect(strategy)

# Check rate limit status
AgentHarness.RateLimit.Tracker.get_status(:groq)

# Check application health
AgentHarness.Application.health_check()

# Get detailed metrics
AgentHarness.Application.get_metrics()
```

## See Also

- [Topologies Documentation](topologies.md) - Detailed topology implementations
- [Rate Limit Router](rate-limit-router.md) - Provider rate limiting
- [Monitoring](monitoring.md) - Metrics and health checks
- [Agent Communication](agent-communication.md) - Inter-agent messaging
