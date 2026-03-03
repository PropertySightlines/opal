# AgentHarness Rate Limit Router

## Overview

The Rate Limit Router ensures reliable API access across multiple providers (Groq, Cerebras, Nvidia, OpenRouter) by implementing a **"queue & sleep"** strategy. When rate limits are hit, requests are queued and automatically retried after the window resets—**never degrading to slower providers**.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AgentHarness.Router                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ Groq Queue  │  │ Nvidia Queue│  │ Cerebras Q  │         │
│  │ (3 pending) │  │ (0 pending) │  │ (1 pending) │         │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘         │
│         │                │                │                  │
│         └────────────────┴────────────────┘                  │
│                          │                                   │
│                  ┌───────▼────────┐                          │
│                  │ RateLimit      │                          │
│                  │ Tracker (ETS)  │                          │
│                  │ - RPM windows  │                          │
│                  │ - TPM windows  │                          │
│                  └────────────────┘                          │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. RateLimit.Tracker

GenServer that tracks rate limits using sliding windows.

**Features:**
- Sliding 60-second window for RPM (requests per minute)
- Sliding 60-second window for TPM (tokens per minute)
- Per-provider limits (configurable)
- Efficient cleanup via periodic timer

**API:**

```elixir
# Check if request can proceed
case AgentHarness.RateLimit.Tracker.can_request?(:groq) do
  :ok -> 
    # Proceed with request
    
  {:wait, delay_ms} -> 
    # Wait before retrying
    Process.sleep(delay_ms)
end

# Record a request after completion
AgentHarness.RateLimit.Tracker.record_request(:groq, tokens_used: 150)

# Get current status
status = AgentHarness.RateLimit.Tracker.get_status(:groq)
# => %{
#      rpm_remaining: 25,
#      tpm_remaining: 58500,
#      reset_in_ms: 45000
#    }
```

### 2. RateLimit.Router

GenServer that manages request queues and automatic retry.

**Features:**
- Per-provider request queues
- Non-blocking retry via `Process.send_after/3`
- Integration with Opal provider calls
- Request cancellation support

**API:**

```elixir
# Queue a request (returns immediately)
{:queued, ref} = AgentHarness.RateLimit.Router.request(:groq, %{prompt: "Hello"})

# Execute with automatic retry
{:ok, result} = AgentHarness.RateLimit.Router.execute_with_retry(
  :groq,
  fn -> Opal.Provider.OpenAICompatible.stream(model, messages, tools, opts) end,
  max_retries: 3
)

# Check queue status
status = AgentHarness.RateLimit.Router.get_queue_status()
# => %{
#      pending_requests: 5,
#      providers_on_hold: [:groq, :cerebras],
#      queue_lengths: %{groq: 3, cerebras: 2, nvidia: 0}
#    }

# Cancel a queued request
AgentHarness.RateLimit.Router.cancel_request(ref)
```

### 3. Opal Integration

Seamless integration with `Opal.Provider.OpenAICompatible`.

**Usage:**

```elixir
# Instead of calling provider directly:
Opal.Provider.OpenAICompatible.stream(model, messages, tools, opts)

# Use rate-limit-aware wrapper:
AgentHarness.RateLimit.OpalIntegration.stream_with_rate_limit(
  :groq,
  model,
  messages,
  tools,
  opts
)
```

## Configuration

### Provider Rate Limits

Configure in `config/agent_harness.exs` or via environment variables:

```elixir
config :agent_harness,
  rate_limits: %{
    groq: %{rpm: 30, tpm: 60_000},
    cerebras: %{rpm: 20, tpm: 60_000},
    nvidia: %{rpm: 100, tpm: 500_000},
    openrouter: %{rpm: 60, tpm: 100_000}
  }
```

**Environment Variables:**

```bash
# Groq
GROQ_RPM=30
GROQ_TPM=60000

# Cerebras
CEREBRAS_RPM=20
CEREBRAS_TPM=60000

# Nvidia
NVIDIA_RPM=100
NVIDIA_TPM=500000

# OpenRouter
OPENROUTER_RPM=60
OPENROUTER_TPM=100000
```

### Provider Model Info

```elixir
config :agent_harness,
  provider_models: %{
    groq: %{
      "llama-3.1-8b-instant" => %{context_window: 128_000, max_output: 8192},
      "llama-3.2-11b-vision-preview" => %{context_window: 128_000, max_output: 8192}
    },
    cerebras: %{
      "llama3.1-8b" => %{context_window: 8192, max_output: 8192},
      "gpt-oss-120b" => %{context_window: 65536, max_output: 32768}
    },
    nvidia: %{
      "meta/llama-3.1-8b-instruct" => %{context_window: 128_000, max_output: 4096}
    },
    openrouter: %{
      "meta-llama/llama-3-8b-instruct" => %{context_window: 8192, max_output: 2048}
    }
  }
```

## Usage Examples

### Basic Rate-Limited Request

```elixir
defmodule MyAgent do
  def run_prompt(provider, prompt) do
    config = get_provider_config(provider)
    model = get_model(provider)
    
    # Execute with automatic rate limit handling
    {:ok, result} = AgentHarness.RateLimit.Router.execute_with_retry(
      provider,
      fn ->
        Opal.Provider.OpenAICompatible.stream(
          model,
          [Opal.Message.user(prompt)],
          [],
          config: config
        )
      end,
      max_retries: 3,
      retry_delay: 5000
    )
    
    result
  end
end
```

### Queued Request (Non-Blocking)

```elixir
# Submit request (returns immediately with ref)
{:queued, ref} = AgentHarness.RateLimit.Router.request(
  :groq,
  %{prompt: "Analyze this code", tokens_estimate: 500}
)

# Continue other work...
do_other_work()

# Wait for completion (or use callback)
receive do
  {:request_complete, ^ref, result} ->
    IO.puts("Request completed: #{inspect(result)}")
    
  {:request_failed, ^ref, reason} ->
    IO.puts("Request failed: #{inspect(reason)}")
after
  60_000 ->
    IO.puts("Timeout waiting for request")
end
```

### Multi-Provider Sequential Execution

```elixir
def run_multi_provider(prompts) do
  providers = [:groq, :nvidia, :cerebras]
  
  results =
    Enum.zip(providers, prompts)
    |> Enum.map(fn {provider, prompt} ->
      Task.async(fn ->
        run_prompt(provider, prompt)
      end)
    end)
    |> Task.await_many(60_000)
    
  results
end
```

## Rate Limit Strategy

### Why "Queue & Sleep"?

1. **Preserves Speed Advantage**: Fast providers (Groq, Cerebras) stay fast after window reset
2. **Predictable Behavior**: No complex fallback logic
3. **Cost Control**: Free tier limits are respected, no accidental overages
4. **Simpler Debugging**: Single provider per request = easier tracing

### Token Management

**Estimating Tokens:**

```elixir
# Rough estimation (4 chars ≈ 1 token for English)
def estimate_tokens(text) when is_binary(text) do
  div(String.length(text), 4)
end

# Record with estimate
tokens = estimate_tokens(prompt) + estimate_tokens(expected_response)
AgentHarness.RateLimit.Tracker.record_request(:groq, tokens)
```

**Staying Under Limits:**

```elixir
# Break large tasks into chunks
def chunk_large_task(task, max_tokens: 40_000) do
  task
  |> String.split("\n")
  |> Enum.chunk_while(
    [],
    fn line, acc ->
      new_tokens = estimate_tokens(Enum.join(acc ++ [line], "\n"))
      if new_tokens <= max_tokens, do: {:cont, acc ++ [line]}, else: {:split, acc, [line]}
    end,
    fn
      [] -> {:cont, []}
      acc -> {:cont, acc}
    end
  )
end
```

## Monitoring

### Check Rate Limit Status

```elixir
# Get status for all providers
for provider <- [:groq, :cerebras, :nvidia, :openrouter] do
  status = AgentHarness.RateLimit.Tracker.get_status(provider)
  IO.puts("#{provider}: #{status.rpm_remaining} RPM, #{status.tpm_remaining} TPM")
end
```

### Queue Monitoring

```elixir
# Get queue status
status = AgentHarness.RateLimit.Router.get_queue_status()

IO.puts("Pending requests: #{status.pending_requests}")
IO.puts("Providers on hold: #{inspect(status.providers_on_hold)}")

for {provider, length} <- status.queue_lengths do
  IO.puts("  #{provider}: #{length} queued")
end
```

## Troubleshooting

### Requests Stuck in Queue

**Symptom:** Requests remain queued indefinitely

**Check:**
```elixir
# Is the provider actually rate-limited?
status = AgentHarness.RateLimit.Tracker.get_status(:groq)
IO.inspect(status)

# Is the queue processor running?
AgentHarness.RateLimit.Router.process_queue(:groq)
```

### Unexpected Rate Limit Hits

**Symptom:** Rate limits hit faster than expected

**Check:**
```elixir
# Are token estimates accurate?
# Compare estimated vs actual tokens
estimated = 500
actual = get_actual_tokens_from_response(response)
IO.puts("Estimate: #{estimated}, Actual: #{actual}")

# Adjust estimation factor if needed
```

### Queue Growing Unbounded

**Symptom:** Queue length keeps increasing

**Solution:**
```elixir
# Set max queue size in config
config :agent_harness,
  max_queue_size: 100  # Reject requests beyond this

# Or monitor and alert
queue_status = AgentHarness.RateLimit.Router.get_queue_status()
if queue_status.pending_requests > 50 do
  Logger.warning("Queue backlog growing: #{inspect(queue_status)}")
end
```

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
# Start IEx
iex -S mix

# Test rate limit tracker
iex> AgentHarness.RateLimit.Tracker.can_request?(:groq)
:ok

iex> AgentHarness.RateLimit.Tracker.record_request(:groq, 1000)
:ok

iex> AgentHarness.RateLimit.Tracker.get_status(:groq)
%{rpm_remaining: 29, tpm_remaining: 59000, reset_in_ms: 58432}

# Test router
iex> {:queued, ref} = AgentHarness.RateLimit.Router.request(:groq, %{test: true})
iex> AgentHarness.RateLimit.Router.get_queue_status()
```

## Performance Considerations

### ETS for Sliding Windows

The Tracker uses ETS tables for O(1) insert/lookup:

```elixir
# Request timestamps stored as:
# {provider, timestamp} -> true

# Token records stored as:
# {provider, timestamp, tokens} -> tokens
```

### Periodic Cleanup

Every 10 seconds, old entries are purged:

```elixir
# Cleanup interval (configurable)
config :agent_harness, cleanup_interval_ms: 10_000
```

### Concurrency

- Tracker: Single GenServer (serialized access)
- Router: Single GenServer with per-provider queues
- Queued requests: Processed sequentially per provider

For high concurrency, consider:
- Partitioning by provider (multiple Router instances)
- Using `:parallel` topology for independent requests

## Future Enhancements

- [ ] Priority queues (premium requests jump queue)
- [ ] Token budget tracking (daily/weekly limits)
- [ ] Adaptive rate limits (learn from actual API responses)
- [ ] Distributed rate limiting (multi-node support)
- [ ] Metrics export (Prometheus, StatsD)

## References

- [Groq Rate Limits](https://console.groq.com/docs/rate-limits)
- [Cerebras API Docs](https://docs.cerebras.ai)
- [Nvidia NIM Docs](https://docs.nvidia.com/nim)
- [OpenRouter Docs](https://openrouter.ai/docs)
