defmodule AgentHarness.OrchestratorInspector do
  @moduledoc """
  Inspector for orchestrator state - used by inspect_orchestrator.sh script.

  Provides functions to query and display orchestrator execution state
  from a running Opal instance.
  """

  @ets_table :orchestrator_state

  @doc """
  Lists all active orchestrator sessions with their status.
  """
  def list_sessions do
    case :ets.info(@ets_table) do
      :undefined ->
        IO.puts("No orchestrator state table found")
        []

      _ ->
        @ets_table
        |> :ets.match({:"$1", :"$2"})
        |> Enum.map(fn [session_id, state] ->
          {session_id, extract_status(state)}
        end)
    end
  end

  @doc """
  Gets detailed status for a specific session.
  """
  def status(session_id) do
    case :ets.lookup(@ets_table, session_id) do
      [{^session_id, state}] ->
        display_status(session_id, state)

      [] ->
        IO.puts("Session not found: #{session_id}")
        nil
    end
  end

  defp extract_status(state) do
    %{
      status: Map.get(state, :status, :unknown),
      completed: Map.get(state, :completed_count, 0),
      total: Map.get(state, :total_agents, 0),
      strategy: Map.get(state, :strategy, :unknown)
    }
  end

  defp display_status(session_id, state) do
    IO.puts("Orchestrator Session: #{session_id}")
    IO.puts(String.duplicate("=", 50))
    IO.puts("Status: #{Map.get(state, :status, :unknown)}")
    IO.puts("Strategy: #{Map.get(state, :topology, :unknown)}")
    IO.puts("Progress: #{Map.get(state, :completed_count, 0)}/#{Map.get(state, :total_agents, 0)}")
    IO.puts("Timeout: #{Map.get(state, :timeout, 0)}ms")
    IO.puts("")

    case Map.get(state, :agents, []) do
      [] ->
        IO.puts("No agents spawned yet")

      agents ->
        IO.puts("Agents:")
        Enum.each(agents, fn agent ->
          IO.puts("  - #{agent.id}: #{agent.status} (#{agent.provider})")
        end)
    end

    case Map.get(state, :result) do
      nil -> :ok
      result ->
        IO.puts("")
        IO.puts("Result:")
        IO.inspect(result, limit: :infinity)
    end

    :ok
  end
end
