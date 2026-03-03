import Config

# Agent Harness Rate Limit Configuration
#
# Configure rate limits for LLM providers.
# These limits are used by AgentHarness.RateLimit.Tracker
# to enforce RPM (requests per minute) and TPM (tokens per minute) limits.
#
# Configuration priority:
#   1. Explicit options passed to Tracker.start_link/1
#   2. This application config
#   3. Environment variables (e.g., GROQ_RPM, GROQ_TPM)
#   4. Default values
#
# Environment variables can override these settings:
#   GROQ_RPM=30
#   GROQ_TPM=60000
#   CEREBRAS_RPM=20
#   CEREBRAS_TPM=60000
#   NVIDIA_RPM=100
#   NVIDIA_TPM=500000
#   OPENROUTER_RPM=60
#   OPENROUTER_TPM=100000

config :agent_harness, :rate_limits, %{
  # Groq - Fast inference provider
  # Limits: 30 RPM, 60K TPM (free tier)
  groq: %{
    rpm: 30,
    tpm: 60_000
  },

  # Cerebras - Ultra-fast inference provider
  # Limits: 20 RPM, 60K TPM
  cerebras: %{
    rpm: 20,
    tpm: 60_000
  },

  # NVIDIA - NIM inference provider
  # Limits: 100 RPM, 500K TPM
  nvidia: %{
    rpm: 100,
    tpm: 500_000
  },

  # OpenRouter - Multi-provider gateway
  # Limits: 60 RPM, 100K TPM
  openrouter: %{
    rpm: 60,
    tpm: 100_000
  }
}

# Sliding window duration (default: 60 seconds)
# config :agent_harness, :rate_limit_window_ms, 60_000
