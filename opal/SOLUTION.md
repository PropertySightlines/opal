# OpenAI-Compatible Provider - Solution Summary

## Problem Statement

Opal only supported GitHub Copilot as a provider. Users needed to integrate with:
- OpenRouter (free tier models)
- Nvidia NIM
- Groq  
- Cerebras

The error was: `function :openrouter.stream/4 is undefined (module :openrouter is not available)`

## Root Cause Analysis

1. **Provider Resolution**: Opal resolves providers by module reference, not by atom name
2. **Missing Config Path**: No mechanism to pass provider-specific config (API keys, endpoints)
3. **Incorrect Callback Signature**: Original `openai_compatible.ex` had wrong `stream/4` signature
4. **Missing JSON Decode**: `parse_stream_event/1` wasn't decoding JSON before parsing

## Solution Implemented

### 1. Fixed Provider Module (`lib/opal/provider/openai_compatible.ex`)

**Key changes:**
- Correct `stream/4` callback signature matching `Opal.Provider` behaviour
- Proper SSE streaming with `into: :self`
- JSON decoding in `parse_stream_event/1` before parsing
- Support for `provider_config` from `Opal.Config`

```elixir
@impl true
def stream(model, messages, tools, opts \\ []) do
  config =
    case Keyword.get(opts, :config) do
      %Opal.Config{provider_config: provider_config} -> provider_config
      %{} = cfg -> cfg
      _ -> %{}
    end

  endpoint = Map.get(config, :endpoint, "https://api.openai.com/v1/chat/completions")
  api_key = Map.fetch!(config, :api_key)
  # ...
end
```

### 2. Added Provider Config Support (`lib/opal/config.ex`)

Added `provider_config` field to `Opal.Config` struct:

```elixir
defstruct [
  # ...
  provider_config: %{},  # Provider-specific config (api_key, endpoint, etc.)
  # ...
]
```

### 3. Updated Agent to Pass Config (`lib/opal/agent/agent.ex`)

Modified `run_turn/1` to pass config to provider:

```elixir
case state.provider.stream(state.model, messages, tools,
       tool_context: %{working_dir: state.working_dir},
       config: state.config  # <-- Added
     ) do
  # ...
end
```

### 4. Created Test Infrastructure

**Unit Tests** (`lib/mix/tasks/opal.test.provider.ex`):
- Module loads correctly
- All callbacks implemented with correct signatures
- Message conversion works
- Tool conversion works

**Live Tests** (`lib/mix/tasks/opal.test.provider.live.ex`):
- Tests real API calls to OpenRouter, Groq, Nvidia, Cerebras
- Loads API keys from `.env`
- Reports pass/fail for each provider

### 5. Documentation

Created comprehensive docs:
- `docs/openai-compatible-provider.md` - User guide
- `SOLUTION.md` - This file, technical summary

## Usage

### Basic Example

```elixir
{:ok, agent} = Opal.start_session(%{
  provider: Opal.Provider.OpenAICompatible,
  model: "llama-3.1-8b-instant",
  provider_config: %{
    endpoint: "https://api.groq.com/openai/v1/chat/completions",
    api_key: System.get_env("GROQ_API_KEY")
  }
})

{:ok, response} = Opal.prompt_sync(agent, "Hello!", 60_000)
```

### With Multiple Providers

```elixir
# Fast provider for simple tasks
{:ok, fast_agent} = Opal.start_session(%{
  provider: Opal.Provider.OpenAICompatible,
  model: "llama-3.1-8b-instant",
  provider_config: %{
    endpoint: "https://api.groq.com/openai/v1/chat/completions",
    api_key: System.get_env("GROQ_API_KEY")
  }
})

# Quality provider for complex tasks
{:ok, smart_agent} = Opal.start_session(%{
  provider: Opal.Provider.OpenAICompatible,
  model: "meta/llama-3.1-70b-instruct",
  provider_config: %{
    endpoint: "https://integrate.api.nvidia.com/v1/chat/completions",
    api_key: System.get_env("NVIDIA_API_KEY")
  }
})
```

## Testing

### Run Unit Tests
```bash
mix opal.test.provider
```

Expected output:
```
============================================================
OpenAI-Compatible Provider Test Suite
============================================================

1. Module loads... ✓ PASS
2. Callback signatures... ✓ PASS
3. Message conversion... ✓ PASS
4. Tool conversion... ✓ PASS

============================================================
All Unit Tests Passed!
============================================================
```

### Run Live Tests
```bash
mix opal.test.provider.live
```

Expected output (with valid API keys):
```
============================================================
OpenAI-Compatible Provider - Live API Tests
============================================================

Testing Groq (llama-3.1-8b-instant)... ✓ PASS
   Response: Hello, I'm your AI coding assistant...

Testing Nvidia NIM (meta/llama-3.1-8b-instruct)... ✓ PASS
   Response: Hello, I'm Opal, your AI coding assistant...

Testing Cerebras (llama3.1-8b)... ✓ PASS
   Response: Hello, I'm your expert coding assistant...

============================================================
Live Tests Complete
============================================================
```

## Files Changed/Created

### Modified Files
| File | Changes |
|------|---------|
| `lib/opal/config.ex` | Added `provider_config` field |
| `lib/opal/agent/agent.ex` | Pass config to provider.stream/4 |

### New Files
| File | Purpose |
|------|---------|
| `lib/opal/provider/openai_compatible.ex` | OpenAI-compatible provider |
| `lib/mix/tasks/opal.test.provider.ex` | Unit tests |
| `lib/mix/tasks/opal.test.provider.live.ex` | Live API tests |
| `docs/openai-compatible-provider.md` | User documentation |
| `SOLUTION.md` | This file |

## Architecture Decisions

### 1. Config via Opal.Config.provider_config

**Why:** Clean separation of concerns, follows existing patterns

**Alternatives considered:**
- Separate config module: Too much boilerplate
- Environment variables only: Inflexible for multi-provider
- Keyword list in session opts: Already used, but needs struct storage

### 2. Module-Based Provider Resolution

**Why:** BEAM makes this natural and efficient

**Alternatives considered:**
- Atom-based registry: Would need extra lookup table
- String-based routing: Error-prone, no compile-time checks

### 3. SSE Streaming via Req

**Why:** Matches Copilot implementation, reuses existing infrastructure

**Alternatives considered:**
- HTTPoison: Less Elixir-idiomatic
- Mint: Too low-level for this use case

## Known Limitations

1. **No Built-in Rate Limiting**: Users must implement retry logic
2. **No Multi-Provider Failover**: Single provider per session
3. **No Token Counting**: Depends on provider to return usage stats
4. **No Response Caching**: Every call hits the API

## Future Enhancements

### Short Term
- [ ] Add retry logic with exponential backoff
- [ ] Support for vision models (image inputs)
- [ ] Better error messages for common issues

### Medium Term
- [ ] Multi-provider failover (auto-retry with different provider)
- [ ] Response caching layer
- [ ] Token usage tracking and budgeting

### Long Term
- [ ] Consensus voting (call 3 providers, aggregate responses)
- [ ] Hierarchical agent routing (parent decides which provider to use)
- [ ] LiveView dashboard for monitoring multiple providers

## Troubleshooting Guide

### Common Issues

| Error | Cause | Solution |
|-------|-------|----------|
| `module :openrouter is not available` | Using atom instead of module | Use `Opal.Provider.OpenAICompatible` |
| `key :api_key not found` | Missing provider_config | Pass `provider_config: %{api_key: "..."}` |
| `invalid model ID` | Wrong model format | Check provider's model ID format |
| Empty responses | SSE parsing issue | Check debug logs for `Parsed SSE events` |
| 429 Rate Limited | Too many requests | Implement retry or switch provider |

### Debug Commands

```bash
# Check if module compiles
mix compile

# Run unit tests
mix opal.test.provider

# Run live tests with debug output
mix opal.test.provider.live 2>&1 | grep "Parsed SSE"

# Check .env loading
mix opal.test.provider.live 2>&1 | grep "Loaded environment"
```

## References

- [Opal Provider Behaviour](lib/opal/provider/provider.ex)
- [Copilot Provider Implementation](lib/opal/provider/copilot.ex)
- [OpenRouter API Docs](https://openrouter.ai/docs)
- [Groq API Docs](https://console.groq.com/docs)
- [Nvidia NIM Docs](https://docs.nvidia.com/nim)
- [Cerebras API Docs](https://docs.cerebras.ai)
