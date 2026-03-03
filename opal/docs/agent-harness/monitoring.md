# Agent Harness Monitoring

This document describes the memory monitoring and metrics capabilities built into Agent Harness.

## Overview

Agent Harness provides lightweight, built-in monitoring capabilities using Erlang's native functions. No external dependencies are required.

## Features

- **Memory Usage Tracking**: Monitor total, process, and system memory
- **Process Count**: Track active Erlang processes
- **System Information**: ERTS version, schedulers, architecture
- **Agent Statistics**: Track all running agents and their children
- **Rate Limit Memory**: Monitor memory usage per provider queue
- **Health Checks**: Component status monitoring

## API Reference

### AgentHarness.Metrics

The `AgentHarness.Metrics` module provides core monitoring functions.

#### `get_memory_usage/0`

Returns current memory usage breakdown in megabytes.

```elixir
iex> AgentHarness.Metrics.get_memory_usage()
%{
  total: 256.5,
  processes: 45.2,
  system: 211.3,
  atom: 1.2,
  binary: 15.8,
  code: 35.4,
  ets: 8.5
}
```

**Fields:**
- `total`: Total memory allocated by the BEAM
- `processes`: Memory used by Erlang processes (heaps + stacks)
- `system`: Memory used by the system (NIFs, drivers, etc.)
- `atom`: Memory used for atom storage
- `binary`: Memory used for binary data
- `code`: Memory used for loaded code
- `ets`: Memory used by ETS tables

#### `get_process_count/0`

Returns the number of active Erlang processes.

```elixir
iex> AgentHarness.Metrics.get_process_count()
142
```

#### `get_system_info/0`

Returns detailed system information.

```elixir
iex> AgentHarness.Metrics.get_system_info()
%{
  erts_version: "14.2.1",
  elixir_version: "1.15.7",
  schedulers: 8,
  schedulers_online: 8,
  wordsize: 8,
  system_architecture: "x86_64-apple-darwin22.1.0",
  total_memory: 256.5,
  total_memory_allocated: 280.3,
  process_count: 142,
  process_limit: 1_048_576
}
```

#### `get_agent_stats/0`

Returns statistics for all AgentHarness agents.

```elixir
iex> AgentHarness.Metrics.get_agent_stats()
%{
  total_agents: 5,
  agents: [
    %{
      pid: #PID<0.123.0>,
      session_id: "agent-abc123",
      children: 2,
      pending_tasks: 1,
      memory_kb: 1024
    },
    ...
  ],
  total_children: 8
}
```

#### `get_process_memory/1`

Returns memory info for a specific process.

```elixir
iex> AgentHarness.Metrics.get_process_memory(pid)
%{
  memory_kb: 1024,
  message_queue_len: 0,
  heap_size: 500,
  stack_size: 100
}
```

#### `get_ets_stats/0`

Returns ETS table statistics.

```elixir
iex> AgentHarness.Metrics.get_ets_stats()
[
  %{
    name: :agent_harness_requests,
    size: 150,
    memory_kb: 512,
    objects: 150,
    type: :set
  },
  ...
]
```

### AgentHarness.RateLimit.Tracker

The rate limit tracker includes memory monitoring for provider queues.

#### `get_memory_status/0`

Returns memory status for all provider queues.

```elixir
iex> AgentHarness.RateLimit.Tracker.get_memory_status()
%{
  providers: %{
    groq: %{
      entries: 15,
      total_tokens: 22500,
      estimated_memory_kb: 12,
      window_ms: 60000
    },
    cerebras: %{
      entries: 8,
      total_tokens: 12000,
      estimated_memory_kb: 6,
      window_ms: 60000
    }
  },
  total_entries: 23,
  total_estimated_memory_kb: 18,
  ets_table_info: %{
    size: 23,
    memory_kb: 64,
    name: AgentHarness.RateLimit.Tracker.Requests
  }
}
```

### AgentHarness.Application

The application module provides aggregated metrics and health checks.

#### `get_metrics/0`

Aggregates all metrics into a single response.

```elixir
iex> AgentHarness.Application.get_metrics()
%{
  memory: %{total: 256.5, processes: 45.2, system: 211.3, ...},
  process_count: 142,
  system_info: %{erts_version: "14.2.1", schedulers: 8, ...},
  agent_stats: %{total_agents: 5, agents: [...], total_children: 8},
  rate_limit_memory: %{total_entries: 23, total_estimated_memory_kb: 18, ...},
  health: %{registry: :ok, rate_limit_tracker: :ok, ...}
}
```

#### `health_check/0`

Returns health status of all components with memory info.

```elixir
iex> AgentHarness.Application.health_check()
%{
  registry: :ok,
  rate_limit_tracker: :ok,
  rate_limit_router: :ok,
  task_supervisor: :ok,
  dynamic_supervisor: :ok,
  memory: %{
    total_mb: 256.5,
    processes_mb: 45.2,
    system_mb: 211.3
  }
}
```

## Mix Task

Use the included mix task to display metrics from the command line:

```bash
mix agent_harness.metrics
```

### Example Output

```
============================================================
Agent Harness - Metrics
============================================================

MEMORY USAGE
----------------------------------------
  Total:       256.5 MB
  Processes:   45.2 MB
  System:      211.3 MB
  Atom:        1.2 MB
  Binary:      15.8 MB
  Code:        35.4 MB
  ETS:         8.5 MB

PROCESS COUNT
----------------------------------------
  Active:      142
  Limit:       1.0M
  Usage:       0.01%

SYSTEM INFO
----------------------------------------
  ERTS:        14.2.1
  Elixir:      1.15.7
  Schedulers:  8/8
  Wordsize:    8 bytes
  Architecture: x86_64-apple-darwin22.1.0

AGENT STATISTICS
----------------------------------------
  Total Agents:    5
  Total Children:  8

  Active Agents:
    - agent-abc123
      PID: #PID<0.123.0>
      Children: 2
      Pending Tasks: 1
      Memory: 1024 KB

RATE LIMIT TRACKER
----------------------------------------
  Total Entries:       23
  Estimated Memory:    18 KB
  ETS Table Memory:    64 KB

  Per-Provider:
    groq:
      Entries: 15
      Tokens:  22.5K
      Memory:  12 KB
    cerebras:
      Entries: 8
      Tokens:  12.0K
      Memory:  6 KB

HEALTH CHECK
----------------------------------------
  ✓ Registry: OK
  ✓ Rate Limit Tracker: OK
  ✓ Rate Limit Router: OK
  ✓ Task Supervisor: OK
  ✓ Dynamic Supervisor: OK

============================================================
```

## Implementation Details

### Memory Calculation

Memory values are converted from bytes to megabytes using:
```elixir
mb = bytes / 1_048_576
```

### Rate Limit Memory Estimation

Memory for rate limit entries is estimated at ~800 bytes per entry, accounting for:
- Tuple overhead
- Timestamp storage
- Token count storage
- ETS internal overhead

### Process Memory

Process memory includes:
- Heap size
- Stack size
- Message queue
- Internal process structures

## Best Practices

### Monitoring Frequency

For production monitoring:
- Poll metrics every 30-60 seconds
- Set up alerts for memory thresholds
- Track trends over time

### Memory Thresholds

Recommended alert thresholds:
- **Warning**: 70% of available memory
- **Critical**: 85% of available memory
- **Process count**: 50% of process limit

### Agent Monitoring

Monitor agent statistics to:
- Detect agent leaks (agents not being cleaned up)
- Identify agents with high memory usage
- Track pending task backlogs

## Troubleshooting

### High Memory Usage

1. Check `get_ets_stats/0` for large ETS tables
2. Review agent stats for memory-heavy agents
3. Check rate limit tracker for excessive entries

### High Process Count

1. Review agent stats for orphaned agents
2. Check for process leaks in custom code
3. Monitor agent child counts

### Rate Limit Memory Growth

1. Check if cleanup interval is appropriate
2. Review window size configuration
3. Monitor entries per provider

## See Also

- `AgentHarness.Metrics` - Core metrics module
- `AgentHarness.Application` - Application-level metrics aggregation
- `AgentHarness.RateLimit.Tracker` - Rate limit tracking with memory monitoring
- `:erlang.memory/0` - Erlang memory information
- `:erlang.process_info/2` - Process information
