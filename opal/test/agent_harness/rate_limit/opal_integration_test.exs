defmodule AgentHarness.RateLimit.OpalIntegrationTest do
  use ExUnit.Case, async: false

  alias AgentHarness.RateLimit.OpalIntegration
  alias AgentHarness.RateLimit.Router
  alias AgentHarness.RateLimit.Tracker

  defp start_services(_opts \\ []) do
    tracker_name = :"#{__MODULE__}.Tracker.#{System.unique_integer([:positive])}"
    router_name = :"#{__MODULE__}.Router.#{System.unique_integer([:positive])}"

    {:ok, _tracker_pid} = Tracker.start_link(
      name: tracker_name,
      limits: %{
        groq: %{rpm: 3, tpm: 10_000},
        cerebras: %{rpm: 2, tpm: 5_000}
      }
    )

    {:ok, _router_pid} = Router.start_link(name: router_name, tracker_server: tracker_name)

    {router_name, tracker_name}
  end

  defp create_test_model(model_id \\ "test-model") do
    %Opal.Provider.Model{
      id: model_id,
      provider: :groq,
      thinking_level: :off
    }
  end

  defp create_test_messages(content \\ "Hello") do
    [%Opal.Message{id: "msg-1", role: :user, content: content}]
  end

  defp record_request(tracker, provider, tokens) do
    Tracker.record_request(provider, tokens, tracker)
  end

  describe "stream_with_rate_limit/6" do
    test "executes stream when rate limit allows" do
      {router, tracker} = start_services()

      Tracker.reset_all(tracker)

      # Mock stream function - returns just the response (execute_with_retry wraps it)
      mock_stream = fn ->
        %Req.Response{status: 200, body: "test response"}
      end

      # Use Router directly since we can't call actual OpenAICompatible.stream
      result = Router.execute_with_retry(:groq, mock_stream, server: router, max_retries: 3)

      assert match?({:ok, %Req.Response{}}, result)
    end

    test "queues request when rate limit hit" do
      {router, tracker} = start_services()

      # Hit rate limit
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)

      mock_stream = fn ->
        {:ok, %Req.Response{status: 200}}
      end

      result = Router.execute_with_retry(:groq, mock_stream, server: router, max_retries: 3)

      assert match?({:queued, _ref}, result)
    end

    test "respects max_retries option" do
      {router, tracker} = start_services()

      # Hit rate limit
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)

      mock_stream = fn ->
        {:ok, %Req.Response{status: 200}}
      end

      result = Router.execute_with_retry(:groq, mock_stream, server: router, max_retries: 0)

      assert result == {:error, :rate_limit_exceeded}
    end
  end

  describe "request_with_queue/6" do
    test "returns {:executing, ref} when allowed" do
      {router, tracker} = start_services()

      Tracker.reset_all(tracker)

      model = create_test_model()
      messages = create_test_messages()

      result = Router.request(:groq, %{model: model, messages: messages}, server: router)

      assert match?({:executing, _ref}, result)
    end

    test "returns {:queued, ref} when rate limited" do
      {router, tracker} = start_services()

      # Hit rate limit
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)

      model = create_test_model()
      messages = create_test_messages()

      result = Router.request(:groq, %{model: model, messages: messages}, server: router)

      assert match?({:queued, _ref}, result)
    end
  end

  describe "execute_provider_call/3" do
    test "executes function with rate limit checking" do
      {router, tracker} = start_services()

      Tracker.reset_all(tracker)

      call_fn = fn -> :success end

      result = Router.execute_with_retry(:groq, call_fn, server: router, max_retries: 3)

      assert result == {:ok, :success}
    end

    test "handles function errors" do
      {router, tracker} = start_services()

      Tracker.reset_all(tracker)

      call_fn = fn -> raise "test error" end

      result = Router.execute_with_retry(:groq, call_fn, server: router, max_retries: 3)

      assert match?({:error, %RuntimeError{message: "test error"}}, result)
    end
  end

  describe "get_provider_config/1" do
    test "returns config for groq" do
      config = OpalIntegration.get_provider_config(:groq)

      assert config.endpoint == "https://api.groq.com/openai/v1/chat/completions"
      assert Map.has_key?(config, :api_key)
    end

    test "returns config for cerebras" do
      config = OpalIntegration.get_provider_config(:cerebras)

      assert config.endpoint == "https://api.cerebras.ai/v1/chat/completions"
      assert Map.has_key?(config, :api_key)
    end

    test "returns config for nvidia" do
      config = OpalIntegration.get_provider_config(:nvidia)

      assert config.endpoint == "https://integrate.api.nvidia.com/v1/chat/completions"
      assert Map.has_key?(config, :api_key)
    end

    test "returns config for openrouter" do
      config = OpalIntegration.get_provider_config(:openrouter)

      assert config.endpoint == "https://openrouter.ai/api/v1/chat/completions"
      assert Map.has_key?(config, :api_key)
    end

    test "returns config with nil api_key for unknown provider" do
      config = OpalIntegration.get_provider_config(:unknown)

      assert config == %{api_key: nil}
    end
  end

  describe "integration scenarios" do
    test "handles multiple providers with different rate limits" do
      {router, tracker} = start_services()

      # Hit groq limit
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)

      # Hit cerebras limit
      record_request(tracker, :cerebras, 100)
      record_request(tracker, :cerebras, 100)

      # Both should queue
      {:queued, groq_ref} = Router.request(:groq, %{}, server: router)
      {:queued, cerebras_ref} = Router.request(:cerebras, %{}, server: router)

      assert is_reference(groq_ref)
      assert is_reference(cerebras_ref)

      status = Router.get_queue_status(router)
      assert status.pending_requests == 2
      assert :groq in status.providers_on_hold
      assert :cerebras in status.providers_on_hold
    end

    test "processes queues independently per provider" do
      {router, tracker} = start_services()

      # Hit only groq limit
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)
      record_request(tracker, :groq, 100)

      # Groq should queue, cerebras should execute
      {:queued, _groq_ref} = Router.request(:groq, %{}, server: router)
      {:executing, _cerebras_ref} = Router.request(:cerebras, %{}, server: router)

      status = Router.get_queue_status(router)
      assert status.pending_requests == 1
      assert status.queue_lengths[:groq] == 1
      # cerebras queue is empty, so it might not be in the map
      assert Map.get(status.queue_lengths, :cerebras, 0) == 0
    end
  end
end
