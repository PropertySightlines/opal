# OpenAI-Compatible Provider for Opal

## Overview

The `Opal.Provider.OpenAICompatible` module enables Opal to work with any OpenAI-compatible API endpoint, including:

- **OpenRouter** (https://openrouter.ai) - Access to 100+ models with unified billing
- **Groq** (https://groq.com) - Ultra-fast LLM inference
- **Nvidia NIM** (https://nvidia.com) - Enterprise-grade model hosting
- **Cerebras** (https://cerebras.ai) - High-performance AI cloud
- Any OpenAI-compatible endpoint

## Quick Start

### 1. Get an API Key

Choose your provider and obtain an API key:

| Provider | Sign Up | Free Tier |
|----------|---------|-----------|
| OpenRouter | https://openrouter.ai | Yes, select models |
| Groq | https://console.groq.com | Yes, rate limited |
| Nvidia | https://build.nvidia.com | Yes, $500 credit |
| Cerebras | https://cloud.cerebras.ai | Contact for access |

### 2. Store Your API Key

Add to your `.env` file (already in project root):

```bash
OPENROUTER_API_KEY=sk-or-v1-...
GROQ_API_KEY=gsk_...
NVIDIA_API_KEY=nvapi-...
CEREBRAS_API_KEY=csk-...
```

### 3. Start a Session

```elixir
# Using OpenRouter
{:ok, agent} = Opal.start_session(%{
  provider: Opal.Provider.OpenAICompatible,
  model: "meta-llama/llama-3-8b-instruct",
  provider_config: %{
    endpoint: "https://openrouter.ai/api/v1/chat/completions",
    api_key: System.get_env("OPENROUTER_API_KEY")
  }
})

# Using Groq
{:ok, agent} = Opal.start_session(%{
  provider: Opal.Provider.OpenAICompatible,
  model: "llama-3.1-8b-instant",
  provider_config: %{
    endpoint: "https://api.groq.com/openai/v1/chat/completions",
    api_key: System.get_env("GROQ_API_KEY")
  }
})

# Using Nvidia
{:ok, agent} = Opal.start_session(%{
  provider: Opal.Provider.OpenAICompatible,
  model: "meta/llama-3.1-8b-instruct",
  provider_config: %{
    endpoint: "https://integrate.api.nvidia.com/v1/chat/completions",
    api_key: System.get_env("NVIDIA_API_KEY")
  }
})

# Using Cerebras
{:ok, agent} = Opal.start_session(%{
  provider: Opal.Provider.OpenAICompatible,
  model: "llama3.1-8b",
  provider_config: %{
    endpoint: "https://api.cerebras.ai/v1/chat/completions",
    api_key: System.get_env("CEREBRAS_API_KEY")
  }
})
```

### 4. Send a Prompt

```elixir
# Async prompt (returns immediately)
Opal.prompt(agent, "Write a Python function to add two numbers")

# Sync prompt (blocks until response)
{:ok, response} = Opal.prompt_sync(agent, "Explain Elixir's OTP", 60_000)

# Stream events
Opal.stream(agent, "Hello")
|> Enum.each(fn
  {:message_delta, %{delta: text}} -> IO.write(text)
  {:agent_end, _} -> IO.puts("\nDone!")
  _ -> :ok
end)
```

## Configuration Options

### provider_config Map

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `:endpoint` | String | Yes | Full API endpoint URL |
| `:api_key` | String | Yes | Bearer token for authentication |
| `:model` | String | No | Override model ID (uses session model by default) |
| `:headers` | Map | No | Additional HTTP headers |

### Model IDs by Provider

Different providers use different model ID formats:

**OpenRouter:**
- `meta-llama/llama-3-8b-instruct` (free tier)
- `meta-llama/llama-3.1-70b-instruct`
- `anthropic/claude-3-haiku`
- `google/gemini-flash-1.5`

**Groq:**
- `llama-3.1-8b-instant`
- `llama-3.2-11b-vision-preview`
- `mixtral-8x7b-32768`

**Nvidia:**
- `meta/llama-3.1-8b-instruct`
- `meta/llama-3.1-70b-instruct`
- `mistralai/mistral-large`

**Cerebras:**
- `llama3.1-8b`
- `llama3.1-70b`

## Testing

### Run Unit Tests

```bash
mix opal.test.provider
```

### Run Live API Tests

```bash
mix opal.test.provider.live
```

This tests all configured providers with real API calls.

## Architecture

### How It Works

1. **Session Start**: `Opal.start_session/1` creates an agent with the specified provider module
2. **Config Storage**: `provider_config` is stored in `Opal.Config.provider_config`
3. **Prompt Handling**: When prompted, the agent calls `provider.stream/4`
4. **SSE Streaming**: The provider makes an HTTP POST with `into: :self` for SSE
5. **Event Parsing**: SSE chunks are parsed via `parse_stream_event/1`
6. **Response Assembly**: Text deltas are accumulated and emitted via `Opal.Events`

### Key Files

| File | Purpose |
|------|---------|
| `lib/opal/provider/openai_compatible.ex` | Main provider implementation |
| `lib/opal/agent/agent.ex` | Agent loop calling provider |
| `lib/opal/agent/stream.ex` | SSE parsing and event dispatch |
| `lib/opal/provider/provider.ex` | Provider behaviour definition |
| `lib/opal/config.ex` | Configuration with `provider_config` field |

## Troubleshooting

### "Module not available" Error

**Problem:** `function :openrouter.stream/4 is undefined`

**Solution:** Use the full module name:
```elixir
# Wrong
provider: :openrouter

# Correct
provider: Opal.Provider.OpenAICompatible
```

### "api_key not found" Error

**Problem:** `KeyError: key :api_key not found in: %{}`

**Solution:** Pass `provider_config` with `api_key`:
```elixir
Opal.start_session(%{
  provider: Opal.Provider.OpenAICompatible,
  provider_config: %{api_key: "your-key"}
})
```

### "Invalid model ID" Error

**Problem:** Provider returns 400 with "invalid model" message

**Solution:** Check the model ID format for your provider (see table above). Don't include provider prefix unless required.

### Empty Responses

**Problem:** Agent returns but response is empty

**Solution:** Check debug logs:
```bash
mix opal.test.provider.live 2>&1 | grep "Parsed SSE"
```

If you see `Parsed SSE events: []`, the JSON structure doesn't match expected format.

### Rate Limiting

**Problem:** 429 Too Many Requests

**Solution:** Implement retry logic or switch to a different provider. Free tiers have strict limits.

```elixir
# Example: Retry with backoff
{:error, :rate_limited} = Opal.prompt_sync(agent, "...")
Process.sleep(5000)  # Wait 5 seconds
Opal.prompt_sync(agent, "...")
```

## Multi-Provider Routing (Future)

The architecture supports routing requests to different providers based on task type:

```elixir
# Fast provider for simple tasks
fast_config = %{provider: OpenAICompatible, model: "groq/llama-3.1-8b"}

# Quality provider for complex reasoning
quality_config = %{provider: OpenAICompatible, model: "openrouter/claude-3-opus"}

# Route based on task complexity
provider = if complex_task?, do: quality_config, else: fast_config
```

## Security Notes

⚠️ **Never commit API keys to version control**

- `.env` is in `.gitignore` by default
- Use environment variables in production
- Rotate keys periodically

## References

- [Opal Architecture](ARCHITECTURE.md)
- [Opal.Provider behaviour](lib/opal/provider/provider.ex)
- [OpenRouter API](https://openrouter.ai/docs)
- [Groq API](https://console.groq.com/docs)
- [Nvidia NIM API](https://docs.nvidia.com/nim)
