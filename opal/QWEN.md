# Opal - Project Context

## Project Overview

**Opal** is an OTP-native coding agent SDK built with Elixir. It provides a small, idiomatic agent harness for building AI-powered coding assistants. The project serves two purposes:

1. **CLI Agent**: A command-line coding agent for development tasks
2. **Elixir Library**: Embeddable SDK for adding agent capabilities to Elixir applications

### Key Features

- **Built-in Tools**: File editing, shell execution, grep search, sub-agent spawning, task management, user interaction
- **OTP-Native Architecture**: Leverages Erlang supervision trees, process isolation, and message passing
- **Streaming Events**: Real-time pub/sub event system for agent introspection
- **JSON-RPC Transport**: RPC interface for building custom UIs
- **MCP Support**: Model Context Protocol integration via `anubis_mcp`
- **GitHub Copilot Provider**: Primary supported LLM provider (designed for extensibility)

### Core Principles

- **OTP First**: Uses Erlang primitives over custom implementations
- **Minimal but Useful**: Small core with essential functionality
- **Cross-Platform**: Works on Windows, macOS, and Linux
- **Research-Driven**: Aligned with current agentic AI research

## Building and Running

### Prerequisites

- **Erlang/OTP 27.2** (managed via mise)
- **Elixir 1.19.5-otp-27** (managed via mise)

### Setup

```bash
# Install dependencies
mise run deps

# Or manually with Mix
mix deps.get
```

### Development Commands

```bash
# Run in development mode (TUI)
mise run dev

# Run with debug features enabled
mise run dev -- --debug

# Run tests
mise run test
# Or: mix test

# Lint and format
mise run lint && mise run format
# Or: mix format && mix lint (if configured)

# Generate documentation
mix docs

# Run dialyzer for type checking
mix dialyzer

# Start IEx console
iex -S mix

# Inspect a running agent (live introspection)
mise run inspect
```

### Configuration

Configuration is managed via `config/` directory:

- `config/config.exs` - Base configuration
- `config/dev.exs` - Development settings (debug logging)
- `config/test.exs` - Test configuration
- `config/prod.exs` - Production settings
- `config/runtime.exs` - Runtime environment variables

Environment variables:
- `OPAL_DATA_DIR` - Custom data directory
- `OPAL_SHELL` - Shell preference (`:sh`, `:bash`, etc.)
- `OPAL_COPILOT_DOMAIN` - Copilot domain (default: `github.com`)

## Project Structure

```
opal/
├── lib/
│   ├── opal/              # Core library modules
│   │   ├── agent/         # Agent process & state management
│   │   ├── auth/          # Authentication (Copilot)
│   │   ├── context/       # Context window management
│   │   ├── mcp/           # Model Context Protocol integration
│   │   ├── provider/      # LLM providers (Copilot, OpenAI)
│   │   ├── rpc/           # JSON-RPC server & protocol
│   │   ├── session/       # Session lifecycle & compaction
│   │   ├── shell/         # Shell execution
│   │   ├── tool/          # Built-in tools
│   │   └── util/          # Utilities (path, hash, gitignore)
│   ├── mix/               # Mix tasks
│   └── opal.ex            # Public API
├── test/
│   ├── opal/              # Unit & integration tests
│   └── support/           # Test helpers
├── config/                # Configuration files
└── priv/                  # Runtime assets
```

## Development Conventions

### Code Style

- **Formatting**: Use `mix format` (configured in `.formatter.exs`)
- **Documentation**: Module docs required for public APIs
- **Typespecs**: Encouraged for public functions
- **Pattern Matching**: Prefer pattern matching over conditionals

### Testing Practices

- **Async Tests**: Use `async: true` where possible (default in `test_helper.exs`)
- **Test Providers**: Mock LLM providers for isolated testing
- **Coverage**: Some modules excluded from coverage (I/O-bound, integration-only)
- **Test Files**: Mirror lib structure in `test/opal/`

### Module Organization

Modules are organized by domain:

- **Public API**: `Opal`, `Opal.Agent`, `Opal.Config`, `Opal.Events`, `Opal.Session`
- **RPC Server**: `Opal.RPC.*`
- **Providers**: `Opal.Provider.*`, `Opal.Auth.*`
- **Tools**: `Opal.Tool.*`, `Opal.Skill`
- **MCP**: `Opal.MCP.*`
- **Internals**: `Opal.Context`, `Opal.Message`, `Opal.SessionServer`

### Tool Definition

Tools implement the `Opal.Tool` behaviour:

```elixir
defmodule MyTool do
  use Opal.Tool,
    name: "my_tool",
    description: "Does something useful"

  @impl true
  def parameters do
    %{
      "type" => "object",
      "properties" => %{
        "input" => %{"type" => "string", "description" => "Input value"}
      },
      "required" => ["input"]
    }
  end

  @impl true
  def execute(%{"input" => input}, _context) do
    {:ok, "Result: #{input}"}
  end
end
```

### Skills

Skills are loadable instruction modules stored in `.qwen/skills/` or similar directories, discovered via the `use_skill` tool.

## Key Dependencies

| Dependency | Purpose |
|------------|---------|
| `req` | HTTP client for LLM API calls |
| `llm_db` | LLM database/interaction layer |
| `jason` | JSON encoding/decoding |
| `nimble_options` | Option validation |
| `glob_ex` | Glob pattern matching |
| `yaml_elixir` | YAML parsing |
| `anubis_mcp` | Model Context Protocol |
| `ex_doc` | Documentation generation (dev) |
| `dialyxir` | Dialyzer integration (dev) |

## Architecture Notes

### Session Lifecycle

1. `Opal.start_session/1` creates a `SessionServer` under `Opal.SessionSupervisor`
2. Agent runs as a GenServer with message queue for prompts
3. Tools execute as separate processes under supervision tree
4. Events published via `Opal.Events` pub/sub
5. Session can be compacted to manage context window

### Event System

Events are published to subscribers via `Opal.Events`:

- `:thinking_delta` - Model reasoning updates
- `:message_delta` - Response text deltas
- `:tool_execution_start` / `:tool_execution_end` - Tool lifecycle
- `:agent_end` - Session completion

Subscribe with `Opal.Events.subscribe(session_id)`.

### RPC Interface

JSON-RPC 2.0 over stdio enables external control:

```json
{"jsonrpc": "2.0", "method": "prompt", "params": {"text": "..."}}
```

See `lib/opal/rpc/` for protocol details.

## Important Notes

- **Logger**: Must use stderr (stdout reserved for JSON-RPC)
- **Data Directory**: Defaults to `~/.opal` (Unix) or `%APPDATA%/opal` (Windows)
- **Sessions**: Persisted in data directory for inspection/resumption
- **Disclaimer**: Hobby project; no sandbox or guardrails built-in
