defmodule AgentHarness.RateLimit.TrackerTest do
  use ExUnit.Case, async: true

  alias AgentHarness.RateLimit.Tracker

  # Use unique server names for each test to avoid conflicts
  defp start_tracker(opts \\ []) do
    name = :"#{__MODULE__}.#{System.unique_integer([:positive])}"
    {:ok, pid} = Tracker.start_link(opts ++ [name: name])
    {name, pid}
  end

  defp can_request?(server, provider) do
    Tracker.can_request?(provider, server)
  end

  defp record_request(server, provider, tokens) do
    Tracker.record_request(provider, tokens, server)
  end

  defp get_status(server, provider) do
    Tracker.get_status(provider, server)
  end

  describe "start_link/1" do
    test "starts with default limits" do
      {name, _pid} = start_tracker()

      assert Tracker.get_limits(name) == %{
               groq: %{rpm: 30, tpm: 60_000},
               cerebras: %{rpm: 20, tpm: 60_000},
               nvidia: %{rpm: 100, tpm: 500_000},
               openrouter: %{rpm: 60, tpm: 100_000}
             }
    end

    test "starts with custom limits" do
      custom_limits = %{
        groq: %{rpm: 10, tpm: 20_000},
        test_provider: %{rpm: 5, tpm: 10_000}
      }

      {name, _pid} = start_tracker(limits: custom_limits)
      limits = Tracker.get_limits(name)

      assert limits.groq.rpm == 10
      assert limits.groq.tpm == 20_000
      assert limits.test_provider.rpm == 5
      assert limits.test_provider.tpm == 10_000
    end

    test "starts with custom window" do
      {name, _pid} = start_tracker(window_ms: 30_000)
      # Window is internal state, verify through behavior
      # Record a request and check status
      record_request(name, :groq, 100)
      status = get_status(name, :groq)
      assert status.rpm_remaining == 29
    end
  end

  describe "can_request?/2" do
    test "returns :ok when under RPM limit" do
      {name, _pid} = start_tracker(limits: %{groq: %{rpm: 10, tpm: 100_000}})

      # Make 5 requests (under limit of 10)
      for _ <- 1..5 do
        assert can_request?(name, :groq) == :ok
        record_request(name, :groq, 100)
      end

      # Should still be allowed
      assert can_request?(name, :groq) == :ok
    end

    test "returns {:wait, delay} when at RPM limit" do
      {name, _pid} = start_tracker(limits: %{groq: %{rpm: 3, tpm: 100_000}})

      # Hit the RPM limit
      for _ <- 1..3 do
        record_request(name, :groq, 100)
      end

      # Should be blocked
      assert {:wait, delay} = can_request?(name, :groq)
      assert is_integer(delay)
      assert delay >= 0
    end

    test "returns :ok when under TPM limit" do
      {name, _pid} = start_tracker(limits: %{groq: %{rpm: 100, tpm: 10_000}})

      # Use 5000 tokens (under limit of 10000)
      record_request(name, :groq, 5000)
      assert can_request?(name, :groq) == :ok
    end

    test "returns {:wait, delay} when at TPM limit" do
      {name, _pid} = start_tracker(limits: %{groq: %{rpm: 100, tpm: 1000}})

      # Hit the TPM limit
      record_request(name, :groq, 500)
      record_request(name, :groq, 500)

      # Should be blocked
      assert {:wait, delay} = can_request?(name, :groq)
      assert is_integer(delay)
      assert delay >= 0
    end

    test "handles unknown provider with zero limits" do
      {name, _pid} = start_tracker()

      # Unknown provider has zero limits - requests are allowed but not tracked
      # (no limits enforced for unconfigured providers)
      assert can_request?(name, :unknown_provider) == :ok
    end
  end

  describe "record_request/3" do
    test "records request with integer tokens" do
      {name, _pid} = start_tracker()

      assert record_request(name, :groq, 1500) == :ok

      status = get_status(name, :groq)
      assert status.rpm_remaining == 29
      assert status.tpm_remaining == 58_500
    end

    test "records request with keyword options" do
      {name, _pid} = start_tracker()

      assert record_request(name, :groq, tokens_used: 2000) == :ok

      status = get_status(name, :groq)
      assert status.rpm_remaining == 29
      assert status.tpm_remaining == 58_000
    end

    test "records request with map options" do
      {name, _pid} = start_tracker()

      assert record_request(name, :groq, %{tokens_used: 2500}) == :ok

      status = get_status(name, :groq)
      assert status.rpm_remaining == 29
      assert status.tpm_remaining == 57_500
    end

    test "records multiple requests" do
      {name, _pid} = start_tracker(limits: %{groq: %{rpm: 100, tpm: 100_000}})

      for i <- 1..10 do
        record_request(name, :groq, 100 * i)
      end

      status = get_status(name, :groq)
      assert status.rpm_remaining == 90

      # Total tokens: 100 + 200 + 300 + ... + 1000 = 5500
      assert status.tpm_remaining == 100_000 - 5500
    end
  end

  describe "get_status/2" do
    test "returns correct remaining counts" do
      {name, _pid} = start_tracker(limits: %{groq: %{rpm: 50, tpm: 50_000}})

      record_request(name, :groq, 1000)
      record_request(name, :groq, 2000)
      record_request(name, :groq, 3000)

      status = get_status(name, :groq)
      assert status.rpm_remaining == 47
      assert status.tpm_remaining == 44_000
      assert is_integer(status.reset_in_ms)
      assert status.reset_in_ms >= 0
    end

    test "returns full limits when no requests made" do
      {name, _pid} = start_tracker()

      status = get_status(name, :groq)
      assert status.rpm_remaining == 30
      assert status.tpm_remaining == 60_000
    end

    test "reset_in_ms reflects oldest entry" do
      {name, _pid} = start_tracker(limits: %{groq: %{rpm: 10, tpm: 100_000}})

      record_request(name, :groq, 100)
      Process.sleep(10)
      record_request(name, :groq, 200)

      status = get_status(name, :groq)
      # reset_in_ms should be close to 60000 (window) minus ~10ms
      assert status.reset_in_ms > 59_000
      assert status.reset_in_ms <= 60_000
    end
  end

  describe "reset_provider/2" do
    test "resets counters for specific provider" do
      {name, _pid} = start_tracker()

      # Make some requests
      record_request(name, :groq, 5000)
      record_request(name, :cerebras, 3000)

      # Reset groq
      assert Tracker.reset_provider(:groq, name) == :ok

      # Groq should be reset
      groq_status = get_status(name, :groq)
      assert groq_status.rpm_remaining == 30
      assert groq_status.tpm_remaining == 60_000

      # Cerebras should still have usage
      cerebras_status = get_status(name, :cerebras)
      assert cerebras_status.rpm_remaining == 19
      assert cerebras_status.tpm_remaining == 57_000
    end
  end

  describe "reset_all/1" do
    test "resets all provider counters" do
      {name, _pid} = start_tracker()

      # Make requests to multiple providers
      record_request(name, :groq, 5000)
      record_request(name, :cerebras, 3000)
      record_request(name, :nvidia, 10_000)

      # Reset all
      assert Tracker.reset_all(name) == :ok

      # All should be reset
      assert get_status(name, :groq).rpm_remaining == 30
      assert get_status(name, :cerebras).rpm_remaining == 20
      assert get_status(name, :nvidia).rpm_remaining == 100
    end
  end

  describe "sliding window behavior" do
    test "entries expire after window passes" do
      # Use a short window for testing
      {name, _pid} = start_tracker(window_ms: 100, limits: %{groq: %{rpm: 5, tpm: 10_000}})

      # Make requests
      record_request(name, :groq, 1000)
      record_request(name, :groq, 1000)
      record_request(name, :groq, 1000)

      status_before = get_status(name, :groq)
      assert status_before.rpm_remaining == 2

      # Wait for window to expire
      Process.sleep(150)

      # Trigger cleanup by making a request
      record_request(name, :groq, 500)

      status_after = get_status(name, :groq)
      # Old entries should be expired, only the new one counts
      assert status_after.rpm_remaining == 4
      assert status_after.tpm_remaining == 9500
    end

    test "can_request respects sliding window" do
      {name, _pid} = start_tracker(window_ms: 100, limits: %{groq: %{rpm: 2, tpm: 10_000}})

      # Hit the limit
      record_request(name, :groq, 100)
      record_request(name, :groq, 100)

      # Should be blocked
      assert {:wait, _} = can_request?(name, :groq)

      # Wait for window to expire
      Process.sleep(150)

      # Should be allowed again
      assert can_request?(name, :groq) == :ok
    end
  end

  describe "concurrent access" do
    test "handles concurrent requests safely" do
      {name, _pid} = start_tracker(limits: %{groq: %{rpm: 1000, tpm: 1_000_000}})

      # Spawn multiple processes making requests
      parent = self()

      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            record_request(name, :groq, 100)
            send(parent, {:done, i})
          end)
        end

      # Wait for all tasks
      Enum.each(tasks, &Task.await(&1, 5000))

      # Verify all requests were recorded
      status = get_status(name, :groq)
      assert status.rpm_remaining == 990
      assert status.tpm_remaining == 999_000
    end
  end

  describe "delay calculation" do
    test "delay decreases as time passes" do
      {name, _pid} = start_tracker(window_ms: 1000, limits: %{groq: %{rpm: 2, tpm: 10_000}})

      # Hit the limit
      record_request(name, :groq, 100)
      record_request(name, :groq, 100)

      {:wait, delay1} = can_request?(name, :groq)

      # Wait a bit
      Process.sleep(200)

      {:wait, delay2} = can_request?(name, :groq)

      # Delay should have decreased
      assert delay2 < delay1
    end

    test "delay is zero when under limits" do
      {name, _pid} = start_tracker()

      assert can_request?(name, :groq) == :ok
    end
  end
end
