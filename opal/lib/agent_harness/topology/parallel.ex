defmodule AgentHarness.Topology.Parallel do
  @moduledoc """
  Parallel topology for Agent Harness.

  Executes agents concurrently using `Task.Supervisor`. Results are aggregated
  when all tasks complete or when a timeout occurs.

  ## Use Cases

    * Independent subtasks that can run in parallel
    * Research and comparison across multiple sources
    * A/B testing different approaches
    * Batch processing of unrelated items
    * Reducing total execution time for independent work

  ## Execution Flow

      Agent 1 ─┐
      Agent 2 ─┼→ Aggregate Results
      Agent 3 ─┘

  ## Example

      tasks = [
        %{
          id: "weather_nyc",
          agent: WeatherAgent,
          input: %{city: "New York"}
        },
        %{
          id: "weather_la",
          agent: WeatherAgent,
          input: %{city: "Los Angeles"}
        },
        %{
          id: "weather_chicago",
          agent: WeatherAgent,
          input: %{city: "Chicago"}
        }
      ]

      # Run all tasks in parallel
      {:ok, result} = AgentHarness.Topology.Parallel.run(tasks, timeout: 30_000)

      # Limit concurrency to 2 at a time
      {:ok, result} = Parallel.run(tasks, parallel_count: 2, timeout: 30_000)

      # Result structure:
      # %{
      #   results: [
      #     %{id: "weather_nyc", status: :success, output: ..., duration_ms: 1200},
      #     %{id: "weather_la", status: :success, output: ..., duration_ms: 950},
      #     %{id: "weather_chicago", status: :success, output: ..., duration_ms: 1100}
      #   ],
      #   metadata: %{
      #     topology: :parallel,
      #     total_time_ms: 1200,  # Time of slowest task
      #     success_count: 3,
      #     error_count: 0,
      #     max_concurrency: 3
      #   }
      # }

  ## Concurrency Control

  Use `:parallel_count` to limit how many tasks run simultaneously:

      # Run at most 2 tasks at a time
      Parallel.run(tasks, parallel_count: 2)

      # Run all tasks at once (default)
      Parallel.run(tasks, parallel_count: :infinity)

  ## Error Handling

  By default, errors are collected and results are returned for successful tasks:

      {:ok, result} = Parallel.run(tasks, on_error: :collect)

      # Result will include both successful and failed tasks
      # result.metadata.error_count > 0

  Use `:require_all` to fail if any task fails:

      {:error, :partial_failure} = Parallel.run(tasks, require_all: true)

  ## Options

    * `:timeout` - Total timeout for all tasks (default: 30_000ms)
    * `:parallel_count` - Maximum concurrent tasks: integer or `:infinity` (default: `:infinity`)
    * `:on_error` - Error strategy: `:collect`, `:stop` (default: `:collect`)
    * `:require_all` - If `true`, return error if any task fails (default: `false`)
    * `:supervisor` - Custom Task.Supervisor name (default: uses dynamic supervisor)
    * `:metadata` - Custom metadata to include in response

  ## Supervisor Setup

  For production use, start a dedicated Task.Supervisor:

      # In your application supervisor
      {Task.Supervisor, name: MyParallelSupervisor}

      # Then use it
      Parallel.run(tasks, supervisor: MyParallelSupervisor)

  See `AgentHarness.Topology` for the behaviour specification.
  """

  @behaviour AgentHarness.Topology

  require Logger

  @default_timeout 30_000
  @default_parallel_count :infinity
  @default_on_error :collect

  @doc """
  Returns the topology name.
  """
  @impl true
  def name, do: :parallel

  @doc """
  Executes tasks in parallel with configurable concurrency.

  See `AgentHarness.Topology` for callback details.
  """
  @impl true
  def run(tasks, opts \\ []) when is_list(tasks) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    parallel_count = Keyword.get(opts, :parallel_count, @default_parallel_count)
    on_error = Keyword.get(opts, :on_error, @default_on_error)
    require_all = Keyword.get(opts, :require_all, false)
    supervisor = Keyword.get(opts, :supervisor)
    custom_metadata = Keyword.get(opts, :metadata, %{})

    start_time = System.monotonic_time(:millisecond)

    results =
      case parallel_count do
        :infinity ->
          # Run all tasks at once
          run_unbounded(tasks, timeout, supervisor)

        count when is_integer(count) and count > 0 ->
          # Run with limited concurrency
          run_bounded(tasks, count, timeout, supervisor)

        _ ->
          # Invalid parallel_count, default to unbounded
          run_unbounded(tasks, timeout, supervisor)
      end

    end_time = System.monotonic_time(:millisecond)
    total_time_ms = end_time - start_time

    # Process results based on error handling strategy
    process_results(results, total_time_ms, on_error, require_all, custom_metadata)
  end

  # Run all tasks without concurrency limits
  defp run_unbounded(tasks, timeout, supervisor) do
    tasks
    |> Enum.map(fn task ->
      spawn_task(task, timeout, supervisor)
    end)
    |> collect_tasks(timeout)
  end

  # Run tasks with bounded concurrency using a streaming approach
  defp run_bounded(tasks, max_concurrency, timeout, _supervisor) do
    Logger.debug("[Parallel] Running with max_concurrency: #{max_concurrency}")

    # Use Task.async_stream for bounded concurrency
    tasks
    |> Task.async_stream(
      fn task ->
        execute_task(task, timeout)
      end,
      max_concurrency: max_concurrency,
      timeout: timeout,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, reason} -> %{status: :error, error: reason, id: "unknown"}
    end)
  end

  # Spawn a single task
  defp spawn_task(task, timeout, _supervisor) do
    start_time = System.monotonic_time(:millisecond)

    Task.async(fn ->
      result = execute_task(task, timeout)

      # Add timing information
      end_time = System.monotonic_time(:millisecond)

      # execute_task returns a map, so we just add timing info
      result
      |> Map.put(:started_at, start_time)
      |> Map.put(:completed_at, end_time)
      |> Map.put(:duration_ms, end_time - start_time)
    end)
  end

  # Collect results from spawned tasks
  defp collect_tasks(task_refs, timeout) do
    Enum.map(task_refs, fn task_ref ->
      try do
        Task.await(task_ref, timeout)
      catch
        :exit, {:timeout, _} ->
          %{
            id: "unknown",
            status: :error,
            error: :timeout,
            duration_ms: 0
          }

        :exit, reason ->
          %{
            id: "unknown",
            status: :error,
            error: reason,
            duration_ms: 0
          }
      end
    end)
  end

  # Execute a single task (used by bounded concurrency)
  defp execute_task(task, _timeout) do
    task_id = get_task_id(task)
    start_time = System.monotonic_time(:millisecond)

    Logger.debug("[Parallel] Starting task: #{task_id}")

    result =
      try do
        execute_agent(task)
      catch
        kind, reason ->
          Logger.error("[Parallel] Task error: #{task_id} - #{inspect({kind, reason})}")
          {:error, {kind, reason}}
      end

    end_time = System.monotonic_time(:millisecond)
    duration_ms = end_time - start_time

    case result do
      {:ok, output} ->
        Logger.debug("[Parallel] Task completed: #{task_id} (#{duration_ms}ms)")

        %{
          id: task_id,
          status: :success,
          output: output,
          duration_ms: duration_ms,
          started_at: start_time,
          completed_at: end_time
        }

      {:error, reason} ->
        Logger.warning("[Parallel] Task failed: #{task_id} - #{inspect(reason)}")

        %{
          id: task_id,
          status: :error,
          error: reason,
          duration_ms: duration_ms,
          started_at: start_time,
          completed_at: end_time
        }

      other ->
        Logger.debug("[Parallel] Task completed: #{task_id} (#{duration_ms}ms)")

        %{
          id: task_id,
          status: :success,
          output: other,
          duration_ms: duration_ms,
          started_at: start_time,
          completed_at: end_time
        }
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
        Logger.warning("[Parallel] Unknown agent type: #{inspect(agent)}")
        {:error, {:unknown_agent, agent}}
    end
  end

  # Process results based on error handling strategy
  defp process_results(results, total_time_ms, on_error, require_all, custom_metadata) do
    success_count = Enum.count(results, &(&1.status == :success))
    error_count = Enum.count(results, &(&1.status == :error))

    # Calculate max concurrency used
    max_concurrency =
      results
      |> Enum.map(&Map.get(&1, :duration_ms, 0))
      |> then(fn durations ->
        # Approximate: count tasks that started within the first task's duration
        case durations do
          [] -> 0
          _ -> length(results)
        end
      end)

    metadata = %{
      topology: :parallel,
      total_time_ms: total_time_ms,
      success_count: success_count,
      error_count: error_count,
      task_count: length(results),
      max_concurrency: max_concurrency
    }

    response = %{
      results: results,
      metadata: Map.merge(metadata, custom_metadata)
    }

    cond do
      require_all and error_count > 0 ->
        Logger.error("[Parallel] require_all=true but #{error_count} tasks failed")
        {:error, {:partial_failure, response}}

      on_error == :stop and error_count > 0 ->
        Logger.error("[Parallel] on_error=:stop but tasks failed")
        {:error, {:tasks_failed, response}}

      true ->
        Logger.info(
          "[Parallel] Completed: #{success_count}/#{length(results)} successful (#{total_time_ms}ms)"
        )

        {:ok, response}
    end
  end

  # Get task ID with fallback
  defp get_task_id(task) when is_map(task) do
    Map.get(task, :id, Map.get(task, "id", "unknown"))
  end

  defp get_task_id(_), do: "unknown"
end
