defmodule Mix.Tasks.Opal.Test.Provider do
  @moduledoc """
  Test the OpenAI-compatible provider.

  Usage: mix opal.test.provider
  """

  use Mix.Task

  @shortdoc "Test OpenAI-compatible provider"

  def run(_args) do
    # Ensure compiled
    Mix.Task.run("compile")

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("OpenAI-Compatible Provider Test Suite")
    IO.puts(String.duplicate("=", 60) <> "\n")

    test_module_loads()
    test_callback_signatures()
    test_message_conversion()
    test_tool_conversion()

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("All Unit Tests Passed!")
    IO.puts(String.duplicate("=", 60) <> "\n")
  end

  defp test_module_loads do
    IO.write("1. Module loads... ")

    try do
      Code.ensure_loaded!(Opal.Provider.OpenAICompatible)
      IO.puts("✓ PASS")
    rescue
      e ->
        IO.puts("✗ FAIL: #{inspect(e)}")
        exit(:test_failed)
    end
  end

  defp test_callback_signatures do
    IO.write("2. Callback signatures... ")

    try do
      unless function_exported?(Opal.Provider.OpenAICompatible, :stream, 4) do
        raise "stream/4 not exported"
      end

      unless function_exported?(Opal.Provider.OpenAICompatible, :parse_stream_event, 1) do
        raise "parse_stream_event/1 not exported"
      end

      unless function_exported?(Opal.Provider.OpenAICompatible, :convert_messages, 2) do
        raise "convert_messages/2 not exported"
      end

      unless function_exported?(Opal.Provider.OpenAICompatible, :convert_tools, 1) do
        raise "convert_tools/1 not exported"
      end

      IO.puts("✓ PASS")
    rescue
      e ->
        IO.puts("✗ FAIL: #{inspect(e)}")
        exit(:test_failed)
    end
  end

  defp test_message_conversion do
    IO.write("3. Message conversion... ")

    try do
      model = Opal.Provider.Model.new("test-model", thinking_level: :off)

      messages = [
        Opal.Message.system("You are a helpful assistant"),
        Opal.Message.user("Hello, world!"),
        Opal.Message.assistant("Hi there!")
      ]

      result = Opal.Provider.OpenAICompatible.convert_messages(model, messages)

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
        exit(:test_failed)
    end
  end

  defp test_tool_conversion do
    IO.write("4. Tool conversion... ")

    try do
      tools = [Opal.Tool.ReadFile]
      result = Opal.Provider.OpenAICompatible.convert_tools(tools)

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
        exit(:test_failed)
    end
  end
end
