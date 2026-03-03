# Opal - Testing Guide

## Quick Answers

### Q: Which build command do I use?
**A:** Use `mise run build` (not `~/.local/bin/mise run build`)

The `~/.local/bin/` path means mise isn't in your PATH. Fix it:
```bash
# Add mise to PATH (add to ~/.bashrc or ~/.zshrc)
export PATH="$HOME/.local/bin:$PATH"

# Then reload shell
source ~/.bashrc  # or source ~/.zshrc

# Now you can use mise directly
mise run build
```

### Q: Do I need to build the CLI?
**A:** Yes, but only once (or when you change TypeScript code).

```bash
cd cli && pnpm build && cd ..
```

### Q: Which model is used for single provider?
**A:** The first available provider in your `.env` file. Order matters!

### Q: Which model is used for orchestrator?
**A:** Nvidia (`qwen/qwen3.5-397b-a17b`) - configured as the "lead orchestrator"

### Q: When does orchestrator spawn agents?
**A:** Only when you use `/multi` or `/sequential` commands. Normal prompts use single agent.

---

## Step-by-Step Testing

### Step 1: Verify Setup

```bash
# Go to project root
cd ~/elixirOpal/opal

# Check mise is available
which mise
# If not found, add to PATH:
export PATH="$HOME/.local/bin:$PATH"

# Verify API keys are set
cat .env
# Should show OPENROUTER_API_KEY, GROQ_API_KEY, etc.
```

### Step 2: Build (One-Time)

```bash
# Full build (Elixir + TypeScript)
mise run build

# Or just build CLI
cd cli && pnpm build && cd ..
```

### Step 3: Launch CLI

```bash
# Standard launch (TTY error may appear but is harmless)
mise run dev

# Or with workaround (no TTY error)
mise run dev -- --no-halt
```

### Step 4: Test Single Provider

When CLI launches, it auto-detects providers from `.env`. The **first provider** in this list is used by default:

1. openrouter
2. groq  
3. nvidia
4. cerebras

**To test a specific provider:**

Edit `.env` and comment out providers you don't want:
```bash
# Comment out all except nvidia
# OPENROUTER_API_KEY=...
# GROQ_API_KEY=...
NVIDIA_API_KEY=nvapi-...
# CEREBRAS_API_KEY=...
```

Then restart CLI. It will use only Nvidia.

**Send a test prompt:**
```
What is 2+2?
```

### Step 5: Test Multi-Agent

**Multi-agent uses ALL available providers**, with Nvidia as the orchestrator.

**Commands:**
```
/multi Analyze this code for security issues
/multi Research Elixir OTP patterns --agents 5
/sequential "Research topic" "Analyze findings" "Write summary"
```

**What happens:**
1. `/multi` spawns parallel agents (one per provider)
2. Each agent has a role based on system prompt:
   - **Nvidia**: Lead orchestrator (authoritative analysis)
   - **Groq**: Critical analyst (identify flaws)
   - **OpenRouter**: Creative brainstorming (diverse ideas)
   - **Cerebras**: Detail reviewer (check completeness)
3. Results are aggregated and displayed

**Sequential mode:**
```
/sequential "Step 1 prompt" "Step 2 prompt" "Step 3 prompt"
```
Runs agents one after another, passing results between steps.

---

## Provider Configuration

### Current Models (from `opal/config/provider_models.exs`)

| Provider | Model | Role |
|----------|-------|------|
| openrouter | stepfun/step-3.5-flash:free | Creative brainstorming |
| groq | moonshotai/kimi-k2-instruct-0905 | Critical analyst |
| **nvidia** | **qwen/qwen3.5-397b-a17b** | **Lead orchestrator** |
| cerebras | gpt-oss-120b | Detail reviewer |

### Change Models

Edit `opal/config/provider_models.exs`:
```elixir
%{
  "nvidia" => %{
    model: "your-model-here",
    endpoint: "https://integrate.api.nvidia.com/v1/chat/completions",
    system_prompt: "Your role description"
  }
}
```

Then rebuild:
```bash
mise run build
```

---

## Troubleshooting

### TTY Error (Harmless)
```
[error] driver_select(...) stealing control of fd=0
```
**This is normal with waveterm.** The CLI still works. Ignore it or use `--no-halt`.

### No Providers Detected
```
✗ Authentication Error
No API keys configured
```
**Fix:** Ensure `.env` has at least one API key:
```bash
OPENROUTER_API_KEY=sk-or-v1-...
```

### Build Fails
```
pnpm: command not found
```
**Fix:** Enable corepack:
```bash
corepack enable
```

### mise Not Found
```
mise: command not found
```
**Fix:** Add to PATH:
```bash
export PATH="$HOME/.local/bin:$PATH"
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
```

---

## Quick Test Commands

```bash
# 1. Go to project
cd ~/elixirOpal/opal

# 2. Build (if needed)
cd cli && pnpm build && cd ..

# 3. Launch
mise run dev

# 4. In CLI, test single provider
What is the capital of France?

# 5. Test multi-agent
/multi What are the pros and cons of microservices?

# 6. Test sequential
/sequential "List 3 ideas" "Expand on idea 2" "Critique the expansion"
```

---

## Summary

| Task | Command |
|------|---------|
| Build | `mise run build` or `cd cli && pnpm build` |
| Launch | `mise run dev` |
| Single provider test | Just type a prompt |
| Multi-agent test | `/multi <prompt>` |
| Sequential test | `/sequential "step1" "step2"` |
| Change provider | Edit `.env` (comment/uncomment) |
| Change model | Edit `opal/config/provider_models.exs` |

**Orchestrator (Nvidia) is only used for `/multi` and `/sequential`.** Normal prompts use the first available provider.
