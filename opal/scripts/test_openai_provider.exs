defmodule OpenAICompatibleTest do
  @moduledoc """
  Test script for OpenAI-compatible provider.
  
  Run with: mix run scripts/test_openai_provider.exs
  """

  alias Opal.Provider.OpenAICompatible
  alias Opal.Provider.Model
  alias Opal.Message

  def run do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("OpenAI-Compatible Provider Test Suite")
    IO.puts(String.duplicate("=", 60) <> "\n")

    # Test 1: Module compiles and loads
    test_module_loads()

    # Test 2: Callback signatures
    test_callback_signatures()

    # Test 3: Message conversion
    test_message_conversion()

    # Test 4: Tool conversion
    test_tool_conversion()

    # Test 5: Live API test (if API key available)
    test_live_api()

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("Test Suite Complete")
    IO.puts(String.duplicate("=", 60) <> "\n")
  end

  defp test_module_loads do
    IO.write("1. Module loads... ")

    try do
      Code.ensure_loaded!(OpenAICompatible)
      IO.puts("✓ PASS")
    rescue
      e ->
        IO.puts("✗ FAIL: #{inspect(e)}")
    end
  end

  defp test_callback_signatures do
    IO.write("2. Callback signatures... ")

    try do
      # Check stream/4 exists
      unless function_exported?(OpenAICompatible, :stream, 4) do
        raise "stream/4 not exported"
      end

      # Check parse_stream_event/1 exists
      unless function_exported?(OpenAICompatible, :parse_stream_event, 1) do
        raise "parse_stream_event/1 not exported"
      end

      # Check convert_messages/2 exists
      unless function_exported?(OpenAICompatible, :convert_messages, 2) do
        raise "convert_messages/2 not exported"
      end

      # Check convert_tools/1 exists
      unless function_exported?(OpenAICompatible, :convert_tools, 1) do
        raise "convert_tools/1 not exported"
      end

      IO.puts("✓ PASS")
    rescue
      e ->
        IO.puts("✗ FAIL: #{inspect(e)}")
    end
  end

  defp test_message_conversion do
    IO.write("3. Message conversion... ")

    try do
      model = Model.new("test-model", thinking_level: :off)

      messages = [
        Message.system("You are a helpful assistant"),
        Message.user("Hello, world!"),
        Message.assistant("Hi there!")
      ]

      result = OpenAICompatible.convert_messages(model, messages)

      # Verify structure
      unless is_list(result) and length(result) == 3 do
        raise "Expected 3 messages, got #{length(result)}"
      end

      [system_msg, user_msg, assistant_msg] = result

      unless system_msg.role == "system" do
        raise "System message role incorrect"
      end

      unless user_msg.role == "user" do
        raise "User message role incorrect"
      end

      unless assistant_msg.role == "assistant" do
        raise "Assistant message role incorrect"
      end

      IO.puts("✓ PASS")
    rescue
      e ->
        IO.puts("✗ FAIL: #{inspect(e)}")
    end
  end

  defp test_tool_conversion do
    IO.write("4. Tool conversion... ")

    try do
      # Use a built-in tool for testing
      tools = [Opal.Tool.ReadFile]
      result = OpenAICompatible.convert_tools(tools)

      unless is_list(result) and length(result) == 1 do
        raise "Expected 1 tool, got #{length(result)}"
      end

      [tool] = result

      unless tool.type == "function" do
        raise "Tool type should be 'function'"
      end

      unless is_map(tool.function) do
        raise "Tool should have 'function' key"
      end

      unless is_binary(tool.function.name) do
        raise "Tool function name should be a string"
      end

      unless is_binary(tool.function.description) do
        raise "Tool function description should be a string"
      end

      unless is_map(tool.function.parameters) do
        raise "Tool function parameters should be a map"
      end

      IO.puts("✓ PASS")
    rescue
      e ->
        IO.puts("✗ FAIL: #{inspect(e)}")
    end
  end

  defp test_live_api do
    IO.puts("\n5. Live API Test")
    
    # Load API keys from .env file
    load_env_file()
    
    api_key = System.get_env("OPENROUTER_API_KEY")
    
    if is_nil(api_key) or api_key == "" do
      IO.puts("   OPENROUTER_API_KEY not set - skipping live tests")
      IO.puts("   (Keys should be in .env file)")
    else
      test_openrouter_live(api_key)
    end
  end

  defp test_openrouter_live(api_key) do
    IO.write("   Testing OpenRouter free tier... ")

    try do
      config = %{
        endpoint: "https://openrouter.ai/api/v1/chat/completions",
        api_key: api_key
      }

      model = Model.new("openrouter/meta-llama/llama-3-8b-instruct:free")

      # Start session with OpenAI-compatible provider
      {:ok, agent} = Opal.start_session(%{
        provider: OpenAICompatible,
        model: model,
        config: config,
        default_tools: [] # No tools for simple test
      })

      # Send prompt and collect response
      {:ok, response} = Opal.prompt_sync(agent, "Write a Python function to add two numbers", 60_000)

      Opal.stop_session(agent)

      if String.contains?(response, "def") and String.contains?(response, "return") do
        IO.puts("✓ PASS")
        IO.puts("\n   Response preview:")
        lines = String.split(response, "\n")
        Enum.take(lines, 5) |> Enum.each(fn line -> IO.puts("   " <> line) end)
      else
        IO.puts("? Response received (may not be Python code)")
        IO.puts("   Got: #{String.slice(response, 0, 200)}...")
      end
    rescue
      e ->
        IO.puts("✗ FAIL")
        IO.puts("   #{Exception.message(e)}")
    end
  end

  defp load_env_file do
    # Try multiple locations
    env_paths = [
      Path.expand("../.env", __DIR__),
      Path.expand("../../.env", __DIR__),
      ".env"
    ]
    
    env_path = Enum.find(env_paths, &File.exists?/1)
    
    if env_path do
      env_path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.each(fn line ->
        case String.split(line, "=", parts: 2) do
          [key, value] ->
            key = String.trim(key)
            value = String.trim(value, ~s("'))
            System.put_env(key, value)
          _ ->
            :ok
        end
      end)
      
      IO.puts("   Loaded environment from: #{env_path}")
    else
      IO.puts("   .env file not found")
    end
  end
end

# Run the tests
OpenAICompatibleTest.run()
