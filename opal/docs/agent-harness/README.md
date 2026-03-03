# AgentHarness — Phase 2 Documentation

## Overview

AgentHarness is a modular agent topology platform built on top of Opal's OpenAI-compatible provider. It provides:

1. **Rate Limit Router** — Queue & retry strategy for multi-provider API access
2. **Topology Manager** — Sequential and parallel agent execution patterns
3. **Agent Communication** — OTP-native message passing between agents
4. **Supervision Tree** — Integrated with Opal's application lifecycle

## Quick Start

### 1. Start AgentHarness

```elixir
# AgentHarness starts automatically with Opal
Application.start(:opal)
# AgentHarness.Supervisor is started as a child
```

### 2. Check Health

```elixir
AgentHarness.Application.health_check()
# => %{
#      registry: :ok,
#      rate_limit_tracker: :ok,
#      rate_limit_router: :ok,
#      task_supervisor: :ok,
#      dynamic_supervisor: :ok
#    }
```

### 3. Run a Rate-Limited Request

```elixir
# Configure provider
config = %{
  endpoint: "https://api.groq.com/openai/v1/chat/completions",
  api_key: System.get_env("GROQ_API_KEY")
}

# Execute with automatic rate limiting
{:ok, result} = AgentHarness.RateLimit.Router.execute_with_retry(
  :groq,
  fn ->
    Opal.Provider.OpenAICompatible.stream(
      %Opal.Provider.Model{id: "llama-3.1-8b-instant"},
      [Opal.Message.user("Hello!")],
      [],
      config: config
    )
  end
)
```

### 4. Run Sequential Topology

```elixir
tasks = [
  %{type: :prompt, content: "Research Elixir OTP"},
  %{type: :prompt, content: "Write code examples"},
  %{type: :prompt, content: "Review for correctness"}
]

{:ok, results} = AgentHarness.Topology.run(tasks, :sequential,
  task_timeout: 60_000,
  pass_results: true
)
```

### 5. Run Parallel Topology

```elixir
tasks = [
  %{type: :prompt, content: "Research topic A"},
  %{type: :prompt, content: "Research topic B"},
  %{type: :prompt, content: "Research topic C"}
]

{:ok, results} = AgentHarness.Topology.run(tasks, :parallel,
  parallel_count: 3,
  timeout: 90_000
)
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     AgentHarness                                 │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Rate Limit Layer                                           │ │
│  │  ┌──────────────┐  ┌──────────────┐                        │ │
│  │  │ Tracker      │  │ Router       │                        │ │
│  │  │ (ETS windows)│  │ (Queues)     │                        │ │
│  │  └──────────────┘  └──────────────┘                        │ │
│  └────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Topology Layer                                             │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │ │
│  │  │ Sequential   │  │ Parallel     │  │ Registry     │     │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘     │ │
│  └────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Agent Communication                                        │ │
│  │  ┌──────────────┐  ┌──────────────┐                        │ │
│  │  │ Agent        │  │ Protocol     │                        │ │
│  │  │ (GenServer)  │  │ (Messages)   │                        │ │
│  │  └──────────────┘  └──────────────┘                        │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │  Opal.Provider  │
                    │  OpenAICompatible│
                    └─────────────────┘
```

## Components

### Rate Limit Layer

**Modules:**
- `AgentHarness.RateLimit.Tracker` — Sliding window RPM/TPM tracking
- `AgentHarness.RateLimit.Router` — Request queuing and retry
- `AgentHarness.RateLimit.Config` — Configuration loader
- `AgentHarness.RateLimit.OpalIntegration` — Opal provider integration

**Strategy:** Queue & Sleep (not degrade to slower providers)

**Configuration:**
```elixir
config :agent_harness,
  rate_limits: %{
    groq: %{rpm: 30, tpm: 60_000},
    cerebras: %{rpm: 20, tpm: 60_000},
    nvidia: %{rpm: 100, tpm: 500_000},
    openrouter: %{rpm: 60, tpm: 100_000}
  }
```

📖 **Full Docs:** [docs/agent-harness/rate-limit-router.md](docs/agent-harness/rate-limit-router.md)

### Topology Layer

**Modules:**
- `AgentHarness.Topology` — Behaviour definition
- `AgentHarness.Topology.Sequential` — Sequential execution
- `AgentHarness.Topology.Parallel` — Parallel execution
- `AgentHarness.Topology.Registry` — Topology registration

**Built-in Topologies:**
- `:sequential` — Agent 1 → Agent 2 → Agent 3
- `:parallel` — Agent 1, Agent 2, Agent 3 (concurrent)

📖 **Full Docs:** [docs/agent-harness/topologies.md](docs/agent-harness/topologies.md)

### Orchestrator (Multi-Agent Workflows)

**Module:**
- `AgentHarness.Orchestrator` — Intelligent task analysis and agent orchestration

**Features:**
- Automatic task complexity analysis
- Dynamic topology selection (parallel vs sequential)
- Agent spawning with provider load balancing
- Result aggregation from multiple agents
- Configurable execution strategies

**Quick Example:**
```elixir
task = %{
  description: "Research Elixir patterns",
  subtasks: [
    %{id: "research", description: "Find patterns"},
    %{id: "analyze", description: "Analyze findings"},
    %{id: "summarize", description: "Create summary"}
  ]
}

# Auto-detects complexity and runs with appropriate topology
{:ok, result} = AgentHarness.Orchestrator.run(task)

# Or force specific topology
{:ok, result} = AgentHarness.Orchestrator.run(task, topology: :parallel)
```

**CLI Commands:**
- `/multi` — Run parallel multi-agent task
- `/sequential` — Run sequential multi-agent task
- `/analyze` — Analyze task without executing

📖 **Full Docs:** [docs/agent-harness/orchestrator.md](docs/agent-harness/orchestrator.md)

### Agent Communication Layer

**Modules:**
- `AgentHarness.Agent` — Agent GenServer
- `AgentHarness.Agent.Protocol` — Message protocol
- `AgentHarness.Agent.Examples` — Usage examples

**Message Types:**
```elixir
{:task, task_data, sender_pid, correlation_id}
{:result, result_data, correlation_id}
{:status, status_atom, metadata}
{:error, reason, correlation_id}
```

📖 **Full Docs:** [docs/agent-harness/agent-communication.md](docs/agent-harness/agent-communication.md)

### Supervision Tree

**Modules:**
- `AgentHarness.Application` — Application lifecycle
- `AgentHarness.Supervisor` — Main supervisor

**Structure:**
```
AgentHarness.Supervisor (:rest_for_one)
├── AgentHarness.Registry
├── AgentHarness.RateLimit.Tracker
├── AgentHarness.RateLimit.Router
├── AgentHarness.Topology.TaskSupervisor
└── AgentHarness.DynamicSupervisor
```

## Testing

### Run Unit Tests

```bash
mix agent_harness.test
```

Expected output:
```
============================================================
AgentHarness Phase 2 - Unit Tests
============================================================

Running 80+ tests across:
- RateLimit.Tracker (22 tests)
- RateLimit.Config (14 tests)
- RateLimit.Router (31 tests)
- OpalIntegration (14 tests)
- Topology components
- Agent communication

All AgentHarness Unit Tests Passed!
============================================================
```

### Run Live Integration Tests

```bash
mix agent_harness.test.live
```

Expected output:
```
============================================================
AgentHarness Phase 2 - Live Integration Tests
============================================================

Loaded environment from: /path/to/.env

1. Rate Limit Tracker (Live) ... ✓ PASS
2. Sequential Topology (Live) ... ✓ PASS
3. Parallel Topology (Live) ... ✓ PASS
4. Agent Communication (Live) ... ✓ PASS

============================================================
All Live Integration Tests Passed!
============================================================
```

## Usage Patterns

### Pattern 1: Single Provider with Rate Limiting

```elixir
defmodule SimpleAgent do
  def run(prompt) do
    config = %{
      endpoint: "https://api.groq.com/openai/v1/chat/completions",
      api_key: System.get_env("GROQ_API_KEY")
    }

    AgentHarness.RateLimit.Router.execute_with_retry(
      :groq,
      fn ->
        Opal.Provider.OpenAICompatible.stream(
          %Opal.Provider.Model{id: "llama-3.1-8b-instant"},
          [Opal.Message.user(prompt)],
          [],
          config: config
        )
      end,
      max_retries: 3
    )
  end
end
```

### Pattern 2: Multi-Provider Sequential Pipeline

```elixir
defmodule ResearchPipeline do
  def research(topic) do
    tasks = [
      %{
        provider: :groq,
        prompt: "Gather facts about #{topic}"
      },
      %{
        provider: :nvidia,
        prompt: "Analyze implications of the facts"
      },
      %{
        provider: :cerebras,
        prompt: "Generate recommendations"
      }
    ]

    AgentHarness.Topology.run(tasks, :sequential,
      task_timeout: 60_000,
      pass_results: true,
      use_router: true  # Enable rate limiting
    )
  end
end
```

### Pattern 3: Parallel Research with Aggregation

```elixir
defmodule ParallelResearch do
  def research_multiple_topics(topics) do
    tasks = Enum.map(topics, fn topic ->
      %{prompt: "Research #{topic} thoroughly"}
    end)

    {:ok, results} = AgentHarness.Topology.run(tasks, :parallel,
      parallel_count: 3,  # Respect rate limits
      timeout: 120_000,
      require_all: false  # Return partial if some fail
    )

    # Aggregate results
    aggregate(results)
  end

  defp aggregate(results) do
    results
    |> Enum.filter(&(&1.status == :success))
    |> Enum.map(& &1.output)
    |> Enum.join("\n\n---\n\n")
  end
end
```

### Pattern 4: Parent-Child Delegation

```elixir
defmodule HierarchicalAgent do
  def run(parent_session_id, task) do
    # Start parent agent
    {:ok, parent_pid} = AgentHarness.Agent.start_link(
      session_id: parent_session_id,
      agent_pid: parent_agent_pid
    )

    # Spawn children
    child_tasks = [
      %{type: :research, query: "Background check"},
      %{type: :analysis, query: "SWOT analysis"},
      %{type: :recommendation, query: "Action items"}
    ]

    children = Enum.map(child_tasks, fn task ->
      {:ok, pid} = AgentHarness.Agent.spawn_child(parent_pid, task)
      pid
    end)

    # Delegate to children
    results = Enum.zip(child_tasks, children)
    |> Enum.map(fn {task, child_pid} ->
      AgentHarness.Agent.delegate(parent_pid, child_pid, task,
        timeout: 60_000
      )
    end)

    # Aggregate child results
    synthesize_results(results)
  end
end
```

## Configuration Reference

### Full Config Example

```elixir
# config/agent_harness.exs
config :agent_harness,
  # Rate limits per provider
  rate_limits: %{
    groq: %{rpm: 30, tpm: 60_000},
    cerebras: %{rpm: 20, tpm: 60_000},
    nvidia: %{rpm: 100, tpm: 500_000},
    openrouter: %{rpm: 60, tpm: 100_000}
  },

  # Provider model info
  provider_models: %{
    groq: %{
      "llama-3.1-8b-instant" => %{context_window: 128_000, max_output: 8192}
    },
    cerebras: %{
      "llama3.1-8b" => %{context_window: 8192, max_output: 8192}
    }
  },

  # Default topology
  default_topology: :sequential,

  # Queue settings
  max_queue_size: 100,
  default_retry_count: 3,
  retry_delay_ms: 5000,

  # Cleanup settings
  cleanup_interval_ms: 10_000
```

### Environment Variables

```bash
# Rate limits (override config)
GROQ_RPM=30
GROQ_TPM=60000
CEREBRAS_RPM=20
CEREBRAS_TPM=60000
NVIDIA_RPM=100
NVIDIA_TPM=500000
OPENROUTER_RPM=60
OPENROUTER_TPM=100000

# API keys
GROQ_API_KEY=gsk_...
CEREBRAS_API_KEY=csk_...
NVIDIA_API_KEY=nvapi-...
OPENROUTER_API_KEY=sk-or-...
```

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Requests stuck in queue | Rate limit not resetting | Check `Tracker.get_status/1`, manually trigger `Router.process_queue/1` |
| Parallel timeout | Too many concurrent requests | Reduce `parallel_count` or increase `timeout` |
| Agent not responding | Child process crashed | Check `Agent.start_link` options, ensure supervisor is running |
| Rate limit hit too fast | Token estimates wrong | Adjust estimation factor, reduce request size |

### Debug Commands

```elixir
# Check rate limit status
AgentHarness.RateLimit.Tracker.get_status(:groq)

# Check queue status
AgentHarness.RateLimit.Router.get_queue_status()

# Manually process queue
AgentHarness.RateLimit.Router.process_queue(:groq)

# List registered topologies
AgentHarness.Topology.Registry.list()

# Check application health
AgentHarness.Application.health_check()

# Get detailed summary
AgentHarness.Application.get_summary()
```

## Future Phases

| Phase | Feature | Status |
|-------|---------|--------|
| Phase 2 | Rate Limit Router + Topologies | ✅ Complete |
| Phase 3 | Consensus Topology | Planned |
| Phase 4 | Hierarchical Agents | Planned |
| Phase 5 | Fan-Out/Fan-Back | Planned |
| Phase 6 | Collaborative Agents | Planned |
| Phase 7 | Hybrid Topologies | Planned |
| Phase 8 | LiveView Dashboard | Planned |

## References

- [Rate Limit Router Docs](docs/agent-harness/rate-limit-router.md)
- [Topology Docs](docs/agent-harness/topologies.md)
- [Orchestrator Docs](docs/agent-harness/orchestrator.md)
- [Agent Communication Docs](docs/agent-harness/agent-communication.md)
- [Monitoring Docs](docs/agent-harness/monitoring.md)
- [Opal Documentation](README.md)
- [OpenAI-Compatible Provider](docs/openai-compatible-provider.md)
