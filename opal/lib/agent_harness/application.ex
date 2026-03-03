defmodule AgentHarness.Application do
  @moduledoc """
  Agent Harness OTP Application.

  Provides application-level configuration and lifecycle management for
  Agent Harness Phase 2 components. The actual supervision tree is managed
  by `AgentHarness.Supervisor`, which is started as part of `Opal.Application`.

  ## Components

  The Agent Harness supervision tree includes:
    * `AgentHarness.Registry` - Registry for agent and component lookup
    * `AgentHarness.RateLimit.Tracker` - GenServer for RPM/TPM tracking
    * `AgentHarness.RateLimit.Router` - GenServer for request queuing
    * `AgentHarness.Topology.TaskSupervisor` - Task.Supervisor for parallel execution
    * `AgentHarness.DynamicSupervisor` - DynamicSupervisor for agent processes

  ## Configuration

  Configure rate limits in your config file:

      config :agent_harness,
        rate_limits: %{
          groq: %{rpm: 30, tpm: 60_000},
          cerebras: %{rpm: 20, tpm: 60_000},
          nvidia: %{rpm: 100, tpm: 500_000},
          openrouter: %{rpm: 60, tpm: 100_000}
        },
        default_topology: :sequential

  ## Integration with Opal

  This module is designed to coexist with `Opal.Application`.
  AgentHarness.Supervisor is started as a child of Opal.Supervisor,
  ensuring proper lifecycle management and graceful shutdown.

  The application shares Opal's Registry namespace for process lookup,
  ensuring seamless integration with the existing Opal ecosystem.

  ## Usage

  Agent Harness is automatically started when Opal starts.
  For manual control (e.g., in development):

      # Start the application (usually done by Opal.Application)
      iex> Application.start(:agent_harness)

      # Stop the application
      iex> Application.stop(:agent_harness)

      # Check health status
      iex> AgentHarness.Application.health_check()
      %{
        registry: :ok,
        rate_limit_tracker: :ok,
        rate_limit_router: :ok,
        task_supervisor: :ok,
        dynamic_supervisor: :ok
      }

  ## Start/Stop Commands

  Since Agent Harness is integrated into Opal:

      # Start Opal (which starts Agent Harness)
      iex> Application.start(:opal)

      # Stop Opal (which stops Agent Harness)
      iex> Application.stop(:opal)

      # Check Agent Harness status
      iex> AgentHarness.Application.get_summary()

  ## Health Checks

  Query component status:

      # Check if all components are running
      AgentHarness.Application.health_check()

      # Get detailed summary
      AgentHarness.Application.get_summary()

      # Check specific component
      Process.whereis(AgentHarness.RateLimit.Tracker)
  """

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("[AgentHarness.Application] Starting Agent Harness...")

    # Initialize rate limit configuration from application config
    initialize_rate_limit_config()

    # Setup Registry for agent and component lookup
    # Uses unique keys for component registration
    registry_children = [
      {Registry, keys: :unique, name: AgentHarness.Registry}
    ]

    # Core supervision tree with rate limiting and topology support
    children =
      registry_children ++
        [
          # Rate Limit Tracker - tracks RPM/TPM per provider
          AgentHarness.RateLimit.Tracker,

          # Rate Limit Router - queues requests when rate limits are hit
          AgentHarness.RateLimit.Router,

          # Task Supervisor for parallel topology execution
          {Task.Supervisor, name: AgentHarness.Topology.TaskSupervisor},

          # Dynamic Supervisor for agent processes
          {DynamicSupervisor, name: AgentHarness.DynamicSupervisor, strategy: :one_for_one}
        ]

    # Use :rest_for_one strategy for graceful shutdown
    # If Registry fails, all dependent components should terminate
    # If a rate limiter fails, components depending on it should restart
    opts = [strategy: :rest_for_one, name: AgentHarness.Supervisor]

    with {:ok, pid} <- Supervisor.start_link(children, opts) do
      Logger.info("[AgentHarness.Application] Agent Harness started successfully")
      {:ok, pid}
    end
  end

  @impl true
  def stop(_state) do
    Logger.info("[AgentHarness.Application] Stopping Agent Harness...")
    :ok
  end

  @doc """
  Returns the current rate limit configuration.

  ## Examples

      config = AgentHarness.Application.get_rate_limit_config()
      # => %{
      #      groq: %{rpm: 30, tpm: 60_000},
      #      cerebras: %{rpm: 20, tpm: 60_000}
      #    }
  """
  @spec get_rate_limit_config() :: map()
  def get_rate_limit_config do
    Application.get_env(:agent_harness, :rate_limits, %{})
  end

  @doc """
  Returns the default topology configuration.

  ## Examples

      topology = AgentHarness.Application.get_default_topology()
      # => :sequential
  """
  @spec get_default_topology() :: atom()
  def get_default_topology do
    Application.get_env(:agent_harness, :default_topology, :sequential)
  end

  @doc """
  Returns health status of all Agent Harness components.

  ## Examples

      status = AgentHarness.Application.health_check()
      # => %{
      #      registry: :ok,
      #      rate_limit_tracker: :ok,
      #      rate_limit_router: :ok,
      #      task_supervisor: :ok,
      #      dynamic_supervisor: :ok
      #    }
  """
  @spec health_check() :: %{atom() => :ok | :error}
  def health_check do
    %{
      registry: check_process(AgentHarness.Registry),
      rate_limit_tracker: check_process(AgentHarness.RateLimit.Tracker),
      rate_limit_router: check_process(AgentHarness.RateLimit.Router),
      task_supervisor: check_process(AgentHarness.Topology.TaskSupervisor),
      dynamic_supervisor: check_process(AgentHarness.DynamicSupervisor)
    }
  end

  @doc """
  Returns a summary of Agent Harness status including component PIDs and config.

  ## Examples

      summary = AgentHarness.Application.get_summary()
      # => %{
      #      components: %{...},
      #      rate_limits: %{...},
      #      default_topology: :sequential
      #    }
  """
  @spec get_summary() :: map()
  def get_summary do
    %{
      components: health_check(),
      rate_limits: get_rate_limit_config(),
      default_topology: get_default_topology()
    }
  end

  # Private Functions

  defp initialize_rate_limit_config do
    # Ensure rate limit config is loaded
    # This is primarily for documentation and validation
    rate_limits = get_rate_limit_config()

    if map_size(rate_limits) == 0 do
      Logger.warning("[AgentHarness.Application] No rate limits configured, using defaults")
    else
      Logger.debug(
        "[AgentHarness.Application] Rate limits configured for providers: #{inspect(Map.keys(rate_limits))}"
      )
    end

    :ok
  end

  defp check_process(name) do
    case Process.whereis(name) do
      nil -> :error
      pid when is_pid(pid) -> :ok
    end
  end
end
