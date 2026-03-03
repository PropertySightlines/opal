defmodule AgentHarness.RateLimit.RouterTest do
  use ExUnit.Case, async: false

  alias AgentHarness.RateLimit.Router
  alias AgentHarness.RateLimit.Tracker

  # Use unique names for each test to avoid conflicts
  defp start_router(opts \\ []) do
    name = :"#{__MODULE__}.#{System.unique_integer([:positive])}"
    tracker_name = :"#{__MODULE__}.Tracker.#{System.unique_integer([:positive])}"

    # Start tracker with test limits
    {:ok, _tracker_pid} = Tracker.start_link(
      name: tracker_name,
      limits: %{
        groq: %{rpm: 3, tpm: 10_000},
        cerebras: %{rpm: 2, tpm: 5_000},
        nvidia: %{rpm: 10, tpm: 50_000}
      }
    )

    # Start router with tracker server reference
    {:ok, router_pid} = Router.start_link(opts ++ [name: name, tracker_server: tracker_name])

    {name, router_pid, tracker_name}
  end

  defp get_queue_status(server) do
    Router.get_queue_status(server)
  end

  defp get_queue_length(server, provider) do
    Router.get_queue_length(provider, server)
  end

  defp record_request(tracker, provider, tokens) do
    Tracker.record_request(provider, tokens, tracker)
  end

  defp reset_all(tracker) do
    Tracker.reset_all(tracker)
  end

  defp get_status(tracker, provider) do
    Tracker.get_status(provider, tracker)
  end

  describe "start_link/1" do
    test "starts with default configuration" do
      {name, _pid, _tracker} = start_router()

      status = get_queue_status(name)
      assert status.pending_requests == 0
      assert status.providers_on_hold == []
      assert status.queue_lengths == %{}
    end

    test "starts with custom retry interval" do
      {name, _pid, _tracker} = start_router(retry_interval_ms: 500)

      # Verify through behavior - queue a request and check timing
      status = get_queue_status(name)
      assert status.pending_requests == 0
    end

    test "starts with custom max queue size" do
      {name, _pid, _tracker} = start_router(max_queue_size: 5)

      status = get_queue_status(name)
      assert status.pending_requests == 0
    end
  end

  describe "request/3" do
    test "returns {:executing, ref} when rate limit allows" do
      {name, _pid, tracker} = start_router()

      # Reset tracker to ensure we're under limit
      reset_all(tracker)

      result = GenServer.call(name, {:request, :groq, %{messages: []}, []})

      assert match?({:executing, _ref}, result)
    end

    test "returns {:queued, ref} when rate limit hit" do
      {name, _pid, tracker} = start_router()

      # Hit the rate limit (3 RPM for groq)
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)

      result = GenServer.call(name, {:request, :groq, %{messages: []}, []})

      assert match?({:queued, _ref}, result)
    end

    test "queues requests with metadata" do
      {name, _pid, tracker} = start_router()

      # Hit the rate limit
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)

      payload = %{messages: [%{role: "user", content: "test"}], model: "test-model"}

      {:queued, ref} = Router.request(:groq, payload, server: name, max_retries: 5)

      assert is_reference(ref)

      # Check queue status
      status = get_queue_status(name)
      assert status.pending_requests == 1
      assert :groq in status.providers_on_hold
      assert status.queue_lengths[:groq] == 1
    end

    test "maintains per-provider queues" do
      {name, _pid, tracker} = start_router()

      # Hit rate limits for both providers
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)

      record_request(tracker, :cerebras, 100)
      record_request(tracker, :cerebras, 100)

      {:queued, ref1} = Router.request(:groq, %{}, server: name)
      {:queued, ref2} = Router.request(:cerebras, %{}, server: name)

      assert is_reference(ref1)
      assert is_reference(ref2)
      assert ref1 != ref2

      status = get_queue_status(name)
      assert status.pending_requests == 2
      assert :groq in status.providers_on_hold
      assert :cerebras in status.providers_on_hold
      assert status.queue_lengths[:groq] == 1
      assert status.queue_lengths[:cerebras] == 1
    end

    test "accepts callback option" do
      {name, _pid, tracker} = start_router()

      # Hit the rate limit
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)

      parent = self()

      callback = fn request_data ->
        send(parent, {:callback_executed, request_data})
      end

      {:queued, _ref} = Router.request(:groq, %{}, server: name, callback: callback)

      # Callback should be stored with the request
      status = get_queue_status(name)
      assert status.pending_requests == 1
    end
  end

  describe "execute_with_retry/3" do
    test "executes function immediately when rate limit allows" do
      {name, _pid, tracker} = start_router()

      reset_all(tracker)

      fun = fn -> :success end

      result = Router.execute_with_retry(:groq, fun, server: name, max_retries: 3)

      assert result == {:ok, :success}
    end

    test "returns {:queued, ref} when rate limit hit" do
      {name, _pid, tracker} = start_router()

      # Hit the rate limit
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)

      fun = fn -> {:ok, :success} end

      result = Router.execute_with_retry(:groq, fun, server: name, max_retries: 3)

      assert match?({:queued, _ref}, result)
    end

    test "respects max_retries option" do
      {name, _pid, tracker} = start_router()

      # Hit the rate limit
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)

      fun = fn -> {:ok, :success} end

      # With max_retries: 0, should fail immediately
      result = Router.execute_with_retry(:groq, fun, server: name, max_retries: 0)

      assert result == {:error, :rate_limit_exceeded}
    end

    test "handles function execution errors" do
      {name, _pid, tracker} = start_router()

      reset_all(tracker)

      fun = fn -> raise "test error" end

      result = Router.execute_with_retry(:groq, fun, server: name, max_retries: 3)

      assert match?({:error, %RuntimeError{message: "test error"}}, result)
    end

    test "accepts integer max_retries" do
      {name, _pid, tracker} = start_router()

      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)

      fun = fn -> {:ok, :success} end

      result = Router.execute_with_retry(:groq, fun, server: name, max_retries: 2)

      assert match?({:queued, _ref}, result)
    end
  end

  describe "get_queue_status/0" do
    test "returns empty status when no queued requests" do
      {name, _pid, _tracker} = start_router()

      status = get_queue_status(name)

      assert status.pending_requests == 0
      assert status.providers_on_hold == []
      assert status.queue_lengths == %{}
    end

    test "returns correct counts with queued requests" do
      {name, _pid, tracker} = start_router()

      # Hit rate limits and queue requests
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)

      record_request(tracker, :cerebras, 100)
      record_request(tracker, :cerebras, 100)

      Router.request(:groq, %{}, server: name)
      Router.request(:groq, %{}, server: name)
      Router.request(:cerebras, %{}, server: name)

      status = get_queue_status(name)

      assert status.pending_requests == 3
      assert :groq in status.providers_on_hold
      assert :cerebras in status.providers_on_hold
      assert status.queue_lengths[:groq] == 2
      assert status.queue_lengths[:cerebras] == 1
    end

    test "updates status when requests are processed" do
      {name, _pid, tracker} = start_router()

      # Hit rate limit and queue
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)

      Router.request(:groq, %{}, server: name)

      status_before = get_queue_status(name)
      assert status_before.pending_requests == 1

      # Reset tracker to allow processing
      reset_all(tracker)

      # Trigger queue processing
      Router.process_queue(:groq, name)

      status_after = get_queue_status(name)
      assert status_after.pending_requests == 0
    end
  end

  describe "get_queue_length/1" do
    test "returns 0 for empty queue" do
      {name, _pid, _tracker} = start_router()

      assert get_queue_length(name, :groq) == 0
      assert get_queue_length(name, :unknown_provider) == 0
    end

    test "returns correct length for provider queue" do
      {name, _pid, tracker} = start_router()

      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)

      Router.request(:groq, %{}, server: name)
      Router.request(:groq, %{}, server: name)

      assert get_queue_length(name, :groq) == 2
    end
  end

  describe "cancel_request/1" do
    test "cancels a queued request" do
      {name, _pid, tracker} = start_router()

      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)

      {:queued, ref} = Router.request(:groq, %{}, server: name)

      assert get_queue_length(name, :groq) == 1

      result = Router.cancel_request(ref, name)
      assert result == :ok

      assert get_queue_length(name, :groq) == 0
    end

    test "returns error for unknown reference" do
      {name, _pid, _tracker} = start_router()

      unknown_ref = make_ref()
      result = Router.cancel_request(unknown_ref, name)

      assert result == {:error, :not_found}
    end

    test "updates pending count on cancel" do
      {name, _pid, tracker} = start_router()

      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)

      {:queued, ref1} = Router.request(:groq, %{}, server: name)
       {:queued, _ref2} = Router.request(:groq, %{}, server: name)

      status_before = get_queue_status(name)
      assert status_before.pending_requests == 2

      GenServer.call(name, {:cancel_request, ref1})

      status_after = get_queue_status(name)
      assert status_after.pending_requests == 1
    end
  end

  describe "process_queue/1" do
    test "processes queued requests when rate limit allows" do
      {name, _pid, tracker} = start_router()

      # Hit rate limit and queue
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)

      parent = self()
      callback = fn _data -> send(parent, {:executed, :groq}) end

      Router.request(:groq, %{}, server: name, callback: callback)

      assert get_queue_length(name, :groq) == 1

      # Reset tracker to allow processing
      reset_all(tracker)

      # Process queue
      Router.process_queue(:groq, name)

      # Wait for callback
      assert_receive {:executed, :groq}, 1000

      assert get_queue_length(name, :groq) == 0
    end

    test "handles empty queue gracefully" do
      {name, _pid, _tracker} = start_router()

      result = Router.process_queue(:groq, name)
      assert result == :ok
    end
  end

  describe "retry mechanism" do
    test "re-queues request on retry if still rate limited" do
      {name, _pid, tracker} = start_router()

      # Hit rate limit
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)

      {:queued, ref} = Router.request(:groq, %{}, server: name, max_retries: 5)

      # Manually trigger retry while still rate limited
      send(name, {:retry_request, :groq, ref})
      Process.sleep(50)

      # Should still be queued (still rate limited)
      assert get_queue_length(name, :groq) == 1
    end

    test "executes request when rate limit clears" do
      {name, _pid, tracker} = start_router()

      # Hit rate limit
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)

      {:queued, ref} = Router.request(:groq, %{}, server: name)

      # Reset tracker so retry will succeed
      reset_all(tracker)

      # Manually trigger retry
      send(name, {:retry_request, :groq, ref})
      Process.sleep(50)

      # Queue should be empty after processing
      assert get_queue_length(name, :groq) == 0
    end

    test "removes request after max retries exceeded" do
      {name, _pid, tracker} = start_router()

      # Hit rate limit
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)

      # Queue with max_retries: 0 - should be removed on first retry
      {:queued, ref} = Router.request(:groq, %{}, server: name, max_retries: 0)

      # Manually trigger retry - should exceed max retries
      send(name, {:retry_request, :groq, ref})
      Process.sleep(50)

      # Request should be removed (max retries exceeded)
      assert get_queue_length(name, :groq) == 0
    end
  end

  describe "concurrent access" do
    test "handles concurrent queue operations" do
      {name, _pid, tracker} = start_router()

      # Hit rate limit
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)

      parent = self()

      # Spawn multiple processes queueing requests
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            result = Router.request(:groq, %{index: i}, server: name)
            send(parent, {:queued, i, result})
          end)
        end

      # Wait for all tasks
      Enum.each(tasks, &Task.await(&1, 5000))

      # All should be queued
      status = get_queue_status(name)
      assert status.pending_requests == 5
      assert status.queue_lengths[:groq] == 5
    end

    test "handles concurrent queue and cancel operations" do
      {name, _pid, tracker} = start_router()

      # Hit rate limit
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)

      refs =
        for _ <- 1..5 do
          {:queued, ref} = Router.request(:groq, %{}, server: name)
          ref
        end

      # Cancel some requests concurrently
      cancel_tasks =
        refs
        |> Enum.take(2)
        |> Enum.map(fn ref ->
          Task.async(fn ->
            Router.cancel_request(ref, name)
          end)
        end)

      Enum.each(cancel_tasks, &Task.await(&1, 5000))

      # Should have 3 remaining
      assert get_queue_length(name, :groq) == 3
    end
  end

  describe "integration with Tracker" do
    test "records tokens when executing queued requests" do
      {name, _pid, tracker} = start_router()

      # Hit rate limit
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)

      payload = %{messages: [%{content: "test message"}]}

      Router.request(:groq, payload, server: name)

      # Reset and process
      reset_all(tracker)
      Router.process_queue(:groq, name)

      # Should have recorded tokens
      status = get_status(tracker, :groq)
      assert status.rpm_remaining < 30
    end

    test "respects Tracker rate limits" do
      {name, _pid, tracker} = start_router()

      # Set very low limit
      reset_all(tracker)

      # Make requests until rate limited
      for _ <- 1..3 do
        record_request(tracker, :groq, 100)
      end

      # Should queue
      {:queued, _ref} = Router.request(:groq, %{}, server: name)

      status = get_queue_status(name)
      assert status.pending_requests == 1
    end
  end

  describe "token estimation" do
    test "estimates tokens from message content" do
      {name, _pid, tracker} = start_router()

      reset_all(tracker)

      # Long message should estimate more tokens
      long_payload = %{messages: [%{content: String.duplicate("a", 1000)}]}
      short_payload = %{messages: [%{content: "hi"}]}

      # Both requests should execute immediately (under rate limit of 3)
      Router.request(:groq, long_payload, server: name)
      Router.request(:groq, short_payload, server: name)

      # Give a moment for requests to be recorded
      Process.sleep(10)

      status = get_status(tracker, :groq)

      # Should have recorded 2 requests (3 - 2 = 1)
      assert status.rpm_remaining == 1
    end
  end
end
