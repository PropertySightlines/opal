defmodule AgentHarness.RateLimit do
  @moduledoc """
  Rate limiting utilities for Agent Harness Phase 2.

  This module provides rate limiting functionality for LLM providers,
  tracking both requests per minute (RPM) and tokens per minute (TPM)
  using sliding window algorithms.

  ## Components

    * `AgentHarness.RateLimit.Tracker` - GenServer for tracking rate limits
    * `AgentHarness.RateLimit.Config` - Configuration loader for provider limits

  ## Quick Start

      # Start the tracker (usually done in your application supervisor)
      {:ok, _} = AgentHarness.RateLimit.Tracker.start_link()

      # Check if a request can be made
      case AgentHarness.RateLimit.Tracker.can_request?(:groq) do
        :ok ->
          # Make the request
          response = make_api_call()
          AgentHarness.RateLimit.Tracker.record_request(:groq, tokens_used: response.tokens)

        {:wait, delay_ms} ->
          # Wait and retry
          Process.sleep(delay_ms)
          # Then retry
      end

      # Get current status
      status = AgentHarness.RateLimit.Tracker.get_status(:groq)
      # => %{rpm_remaining: 25, tpm_remaining: 55000, reset_in_ms: 45000}

  ## Configuration

  Provider limits can be configured via:

      # 1. Application config
      config :agent_harness, :rate_limits, %{
        groq: %{rpm: 30, tpm: 60_000},
        cerebras: %{rpm: 20, tpm: 60_000}
      }

      # 2. Environment variables
      GROQ_RPM=30
      GROQ_TPM=60000

  See `AgentHarness.RateLimit.Config` for details.
  """

  @doc """
  Returns the default provider limits.
  """
  @spec default_limits() :: map()
  def default_limits do
    %{
      groq: %{rpm: 30, tpm: 60_000},
      cerebras: %{rpm: 20, tpm: 60_000},
      nvidia: %{rpm: 100, tpm: 500_000},
      openrouter: %{rpm: 60, tpm: 100_000}
    }
  end

  @doc """
  Returns the list of supported providers.
  """
  @spec providers() :: [atom()]
  def providers do
    [:groq, :cerebras, :nvidia, :openrouter]
  end
end
