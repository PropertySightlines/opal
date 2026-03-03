# Opal - Usage Guide

## Directory Structure

```
~/elixirOpal/opal/          ← Project root (work from here!)
├── .mise.toml              ← Mise task definitions
├── cli/                    ← TypeScript CLI (Node.js)
│   ├── src/                ← CLI source code
│   ├── dist/               ← Built CLI (after pnpm build)
│   └── package.json
├── opal/                   ← Elixir backend
│   ├── lib/                ← Elixir source code
│   ├── config/             ← Elixir config files
│   ├── mix.exs             ← Mix project definition
│   └── priv/               ← Runtime assets
└── scripts/                ← Launcher scripts
```

## Quick Start

### 1. Install Dependencies

```bash
cd ~/elixirOpal/opal
mise run deps
```

This installs:
- Elixir 1.19 + Erlang 27 (via mise)
- Node.js 22+ (via mise)
- Elixir dependencies (mix deps.get)
- Node dependencies (pnpm install)

### 2. Configure API Keys

Edit `.env` file in project root:

```bash
# .env
OPENROUTER_API_KEY=sk-or-v1-...
GROQ_API_KEY=gsk_...
NVIDIA_API_KEY=nvapi-...
CEREBRAS_API_KEY=csk-...
```

### 3. Configure Provider Models (Optional)

Edit `opal/config/provider_models.exs` to customize models:

```elixir
%{
  "openrouter" => %{
    model: "meta-llama/llama-3-8b-instruct",
    endpoint: "https://openrouter.ai/api/v1/chat/completions"
  },
  "groq" => %{
    model: "llama-3.1-8b-instant",
    endpoint: "https://api.groq.com/openai/v1/chat/completions"
  },
  # ...
}
```

### 4. Build CLI

```bash
cd cli
pnpm build
cd ..
```

### 5. Launch

```bash
# Standard dev mode
mise run dev

# Multi-agent mode
mise run dev:multi

# With launcher script
./scripts/dev-cli.sh
./scripts/dev-cli.sh --debug
./scripts/dev-cli.sh --multi
```

## Available Commands

### Mise Tasks

| Command | Description |
|---------|-------------|
| `mise run deps` | Install all dependencies |
| `mise run dev` | Launch CLI in dev mode |
| `mise run dev:multi` | Launch with multi-agent features |
| `mise run test` | Run all tests |
| `mise run test:multi` | Run multi-agent tests |
| `mise run lint` | Lint code |
| `mise run format` | Format code |
| `mise run orchestrator` | Run orchestrator demo |
| `mise run inspect` | Connect to running instance |
| `mise run inspect:orchestrator` | Inspect orchestrator state |

### CLI Slash Commands

Once CLI is running:

```
/multi <prompt>              # Multi-agent analysis
/multi <prompt> --agents N   # Specify agent count
/sequential <prompt>         # Sequential pipeline
```

## Testing

```bash
# Run all tests
mise run test

# Run multi-agent specific tests
mise run test:multi

# Run orchestrator demo
mise run orchestrator

# Run with launcher script
./scripts/demo-orchestrator.sh
./scripts/test-multi.sh
```

## Debugging

```bash
# Launch with debug features
mise run dev -- --debug
./scripts/dev-cli.sh --debug

# Connect to running instance
mise run inspect
./scripts/inspect_orchestrator.sh

# Inspect specific session
./scripts/inspect_orchestrator.sh --session <session_id>
```

## Common Issues

### No API Keys Configured

```
✗ Authentication Error
No API keys configured. Set OPENROUTER_API_KEY, etc. in .env
```

**Solution:** Create/edit `.env` file with your API keys.

### Mise Not Found

```
mise: command not found
```

**Solution:** Install mise:
```bash
curl https://mise.run | sh
```

### Build Errors

```
pnpm: command not found
```

**Solution:** Enable corepack:
```bash
corepack enable
```

## Project Layout

- **`cli/`** - TypeScript React Ink TUI
- **`opal/`** - Elixir backend (OTP application)
- **`scripts/`** - Bash launcher scripts
- **`docs/`** - Documentation
- **`.mise.toml`** - Task orchestration

## Next Steps

1. Read `README.md` for project overview
2. Read `docs/agent-harness/orchestrator.md` for multi-agent docs
3. Try `/multi` command in CLI for multi-agent workflows
