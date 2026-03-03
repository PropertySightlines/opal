defmodule AgentHarness.Topology.Sequential do
  @moduledoc """
  Sequential topology for Agent Harness.

  Executes agents one after another in order. Each agent must complete
  before the next one starts.

  ## Use Cases

    * Multi-step tasks with dependencies (e.g., research → analyze → summarize)
    * Tasks where output of one agent is input to the next
    * Workflows requiring strict ordering
    * Debugging and step-by-step execution

  ## Execution Flow

      Agent 1 → Agent 2 → Agent 3 → Results
      (completes)  (starts)   (starts)

  ## Example

      tasks = [
        %{
          id: "research",
          agent: ResearchAgent,
          input: %{topic: "Elixir concurrency"}
        },
        %{
          id: "analyze",
          agent: AnalysisAgent,
          input: %{focus: "performance patterns"}
        },
        %{
          id: "summarize",
          agent: SummaryAgent,
          input: %{format: "bullet points"}
        }
      ]

      {:ok, result} = AgentHarness.Topology.Sequential.run(tasks, timeout: 60_000)

      # Result structure:
      # %{
      #   results: [
      #     %{id: "research", status: :success, output: ..., duration_ms: 1200},
      #     %{id: "analyze", status: :success, output: ..., duration_ms: 800},
      #     %{id: "summarize", status: :success, output: ..., duration_ms: 500}
      #   ],
      #   metadata: %{
      #     topology: :sequential,
      #     total_time_ms: 2500,
      #     success_count: 3,
      #     error_count: 0
      #   }
      # }

  ## Error Handling

  By default, errors are collected and execution continues. Use `:on_error`
  to change behavior:

      # Stop on first error
      Sequential.run(tasks, on_error: :stop)

      # Skip failed tasks and continue
      Sequential.run(tasks, on_error: :skip)

      # Continue and collect errors (default)
      Sequential.run(tasks, on_error: :continue)

  ## Options

    * `:timeout` - Total timeout for all tasks (default: 30_000ms)
    * `:task_timeout` - Per-task timeout (default: inherits from `:timeout`)
    * `:on_error` - Error strategy: `:stop`, `:continue`, `:skip` (default: `:continue`)
    * `:pass_results` - If `true`, pass previous results to next task's input (default: `false`)
    * `:metadata` - Custom metadata to include in response

  See `AgentHarness.Topology` for the behaviour specification.
  """

  @behaviour AgentHarness.Topology

  require Logger

  @default_timeout 30_000
  @default_on_error :continue

  @doc """
  Returns the topology name.
  """
  @impl true
  def name, do: :sequential

  @doc """
  Executes tasks sequentially, one after another.

  See `AgentHarness.Topology` for callback details.
  """
  @impl true
  def run(tasks, opts \\ []) when is_list(tasks) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    on_error = Keyword.get(opts, :on_error, @default_on_error)
    _pass_results = Keyword.get(opts, :pass_results, false)
    custom_metadata = Keyword.get(opts, :metadata, %{})

    start_time = System.monotonic_time(:millisecond)

    results =
      Enum.reduce_while(tasks, [], fn task, acc ->
        case execute_task(task, timeout, opts) do
          {:ok, result} ->
            {:cont, [result | acc]}

          {:error, reason} ->
            error_result = create_error_result(task, reason)

            case on_error do
              :stop ->
                Logger.error("[Sequential] Stopping on error: #{inspect(reason)}")
                {:halt, {:error, {:stopped, error_result, Enum.reverse(acc)}}}

              :skip ->
                Logger.warning("[Sequential] Skipping failed task: #{task.id}")
                {:cont, acc}

              :continue ->
                Logger.warning("[Sequential] Task failed but continuing: #{task.id}")
                {:cont, [error_result | acc]}
            end
        end
      end)

    end_time = System.monotonic_time(:millisecond)
    total_time_ms = end_time - start_time

    case results do
      {:error, _} = error ->
        error

      results_list when is_list(results_list) ->
        final_results = Enum.reverse(results_list)
        {:ok, build_response(final_results, total_time_ms, custom_metadata)}
    end
  end

  # Execute a single task with timeout
  defp execute_task(task, total_timeout, opts) do
    task_timeout = Keyword.get(opts, :task_timeout, total_timeout)
    task_id = get_task_id(task)

    Logger.debug("[Sequential] Starting task: #{task_id}")

    start_time = System.monotonic_time(:millisecond)

    result =
      try do
        Task.async(fn ->
          execute_agent(task)
        end)
        |> Task.await(task_timeout)
      catch
        :exit, {:timeout, _} ->
          Logger.error("[Sequential] Task timeout: #{task_id}")
          {:error, :timeout}

        :exit, reason ->
          Logger.error("[Sequential] Task exit: #{task_id} - #{inspect(reason)}")
          {:error, reason}

        kind, reason ->
          Logger.error("[Sequential] Task error: #{task_id} - #{inspect({kind, reason})}")
          {:error, {kind, reason}}
      end

    end_time = System.monotonic_time(:millisecond)
    duration_ms = end_time - start_time

    case result do
      {:ok, output} ->
        Logger.debug("[Sequential] Task completed: #{task_id} (#{duration_ms}ms)")

        {:ok,
         %{
           id: task_id,
           status: :success,
           output: output,
           duration_ms: duration_ms,
           started_at: start_time,
           completed_at: end_time
         }}

      {:error, reason} ->
        Logger.warning("[Sequential] Task failed: #{task_id} - #{inspect(reason)}")

        {:error,
         %{
           id: task_id,
           status: :error,
           error: reason,
           duration_ms: duration_ms,
           started_at: start_time,
           completed_at: end_time
         }}

      other ->
        # Assume successful if not a tuple
        Logger.debug("[Sequential] Task completed: #{task_id} (#{duration_ms}ms)")

        {:ok,
         %{
           id: task_id,
           status: :success,
           output: other,
           duration_ms: duration_ms,
           started_at: start_time,
           completed_at: end_time
         }}
    end
  end

  # Execute the agent for a task
  defp execute_agent(task) do
    agent = Map.get(task, :agent)
    input = Map.get(task, :input, %{})
    task_opts = Map.get(task, :opts, [])

    cond do
      is_function(agent, 1) ->
        agent.(input)

      is_function(agent, 2) ->
        agent.(input, task_opts)

      is_atom(agent) and function_exported?(agent, :run, 2) ->
        agent.run(input, task_opts)

      is_atom(agent) and function_exported?(agent, :run, 1) ->
        agent.run(input)

      is_map(agent) and is_function(Map.get(agent, :execute), 1) ->
        agent.execute.(input)

      true ->
        Logger.warning("[Sequential] Unknown agent type: #{inspect(agent)}")
        {:error, {:unknown_agent, agent}}
    end
  end

  # Build the response with metadata
  defp build_response(results, total_time_ms, custom_metadata) do
    success_count = Enum.count(results, &(&1.status == :success))
    error_count = Enum.count(results, &(&1.status == :error))

    %{
      results: results,
      metadata: Map.merge(
        %{
          topology: :sequential,
          total_time_ms: total_time_ms,
          success_count: success_count,
          error_count: error_count,
          task_count: length(results)
        },
        custom_metadata
      )
    }
  end

  # Create an error result for a task
  defp create_error_result(task, reason) do
    now = System.monotonic_time(:millisecond)

    %{
      id: get_task_id(task),
      status: :error,
      error: reason,
      duration_ms: 0,
      started_at: now,
      completed_at: now
    }
  end

  # Get task ID with fallback
  defp get_task_id(task) when is_map(task) do
    Map.get(task, :id, Map.get(task, "id", "unknown"))
  end

  defp get_task_id(_), do: "unknown"
end
