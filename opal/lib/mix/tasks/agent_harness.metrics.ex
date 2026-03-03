defmodule Mix.Tasks.AgentHarness.Metrics do
  @moduledoc """
  Display Agent Harness metrics including memory usage, process count, and agent statistics.

  Usage: mix agent_harness.metrics

  ## Examples

      # Display current metrics
      mix agent_harness.metrics

  ## Output

  The task displays:
    * Memory usage (total, processes, system, atom, binary, code, ets)
    * Process count and limit
    * System information (ERTS version, schedulers, architecture)
    * Agent statistics (total agents, children, per-agent details)
    * Rate limit tracker memory status
    * Health check status for all components

  ## See Also

    * `AgentHarness.Metrics` - Metrics collection module
    * `AgentHarness.Application.get_metrics/0` - Aggregated metrics API
  """

  use Mix.Task

  @shortdoc "Display Agent Harness metrics"

  def run(_args) do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("Agent Harness - Metrics")
    IO.puts(String.duplicate("=", 60) <> "\n")

    # Ensure compiled
    Mix.Task.run("compile")

    # Start the opal application (agent_harness is part of opal)
    case Application.ensure_all_started(:opal) do
      {:ok, _apps} ->
        display_metrics()

      {:error, reason} ->
        IO.puts("Error starting opal: #{inspect(reason)}")
        exit({:startup_failed, reason})
    end

    IO.puts("\n" <> String.duplicate("=", 60) <> "\n")
  end

  defp display_metrics do
    # Memory Usage
    IO.puts("MEMORY USAGE")
    IO.puts(String.duplicate("-", 40))
    memory = AgentHarness.Metrics.get_memory_usage()
    IO.puts("  Total:       #{format_mb(memory.total)}")
    IO.puts("  Processes:   #{format_mb(memory.processes)}")
    IO.puts("  System:      #{format_mb(memory.system)}")
    IO.puts("  Atom:        #{format_mb(memory.atom)}")
    IO.puts("  Binary:      #{format_mb(memory.binary)}")
    IO.puts("  Code:        #{format_mb(memory.code)}")
    IO.puts("  ETS:         #{format_mb(memory.ets)}")

    # Process Count
    IO.puts("\nPROCESS COUNT")
    IO.puts(String.duplicate("-", 40))
    process_count = AgentHarness.Metrics.get_process_count()
    system_info = AgentHarness.Metrics.get_system_info()
    IO.puts("  Active:      #{process_count}")
    IO.puts("  Limit:       #{format_number(system_info.process_limit)}")
    IO.puts("  Usage:       #{Float.round(process_count / system_info.process_limit * 100, 2)}%")

    # System Info
    IO.puts("\nSYSTEM INFO")
    IO.puts(String.duplicate("-", 40))
    IO.puts("  ERTS:        #{system_info.erts_version}")
    IO.puts("  Elixir:      #{system_info.elixir_version}")
    IO.puts("  Schedulers:  #{system_info.schedulers_online}/#{system_info.schedulers}")
    IO.puts("  Wordsize:    #{system_info.wordsize} bytes")
    IO.puts("  Architecture: #{system_info.system_architecture}")

    # Agent Stats
    IO.puts("\nAGENT STATISTICS")
    IO.puts(String.duplicate("-", 40))
    agent_stats = AgentHarness.Metrics.get_agent_stats()
    IO.puts("  Total Agents:    #{agent_stats.total_agents}")
    IO.puts("  Total Children:  #{agent_stats.total_children}")

    if agent_stats.total_agents > 0 do
      IO.puts("\n  Active Agents:")
      Enum.each(agent_stats.agents, fn agent ->
        IO.puts("    - #{agent.session_id}")
        IO.puts("      PID: #{inspect(agent.pid)}")
        IO.puts("      Children: #{agent.children}")
        IO.puts("      Pending Tasks: #{agent.pending_tasks}")
        IO.puts("      Memory: #{agent.memory_kb} KB")
      end)
    end

    # Rate Limit Memory
    IO.puts("\nRATE LIMIT TRACKER")
    IO.puts(String.duplicate("-", 40))
    rate_limit_memory = AgentHarness.RateLimit.Tracker.get_memory_status()
    IO.puts("  Total Entries:       #{rate_limit_memory.total_entries}")
    IO.puts("  Estimated Memory:    #{rate_limit_memory.total_estimated_memory_kb} KB")
    IO.puts("  ETS Table Memory:    #{rate_limit_memory.ets_table_info.memory_kb} KB")

    if map_size(rate_limit_memory.providers) > 0 do
      IO.puts("\n  Per-Provider:")
      Enum.each(rate_limit_memory.providers, fn {provider, stats} ->
        IO.puts("    #{provider}:")
        IO.puts("      Entries: #{stats.entries}")
        IO.puts("      Tokens:  #{format_number(stats.total_tokens)}")
        IO.puts("      Memory:  #{stats.estimated_memory_kb} KB")
      end)
    end

    # Health Check
    IO.puts("\nHEALTH CHECK")
    IO.puts(String.duplicate("-", 40))
    health = AgentHarness.Application.health_check()
    Enum.each(health, fn {component, status} ->
      status_icon = if status == :ok, do: "✓", else: "✗"
      IO.puts("  #{status_icon} #{format_component(component)}: #{format_status(status)}")
    end)
  end

  defp format_mb(value) when is_float(value) do
    "#{value} MB"
  end

  defp format_mb(value) when is_integer(value) do
    "#{value} MB"
  end

  defp format_number(value) when value >= 1_000_000 do
    "#{Float.round(value / 1_000_000, 1)}M"
  end

  defp format_number(value) when value >= 1_000 do
    "#{Float.round(value / 1_000, 1)}K"
  end

  defp format_number(value) do
    "#{value}"
  end

  defp format_component(component) do
    component
    |> to_string()
    |> String.replace("_", " ")
    |> Macro.camelize()
  end

  defp format_status(:ok), do: "OK"
  defp format_status(:error), do: "ERROR"
  defp format_status(status), do: inspect(status)
end
