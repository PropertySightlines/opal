defmodule Mix.Tasks.Opal.Test.Provider.Live do
  @moduledoc """
  Live test the OpenAI-compatible provider with real API calls.

  Usage: mix opal.test.provider.live

  Requires API keys to be set in environment or .env file.
  """

  use Mix.Task

  @shortdoc "Live test OpenAI-compatible provider"

  def run(_args) do
    # Ensure compiled and application started (disable RPC for tests)
    Mix.Task.run("compile")
    Application.put_env(:opal, :start_rpc, false)
    Application.ensure_all_started(:opal)

    # Load .env file
    load_env_file()

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("OpenAI-Compatible Provider - Live API Tests")
    IO.puts(String.duplicate("=", 60) <> "\n")

    # Test OpenRouter
    openrouter_key = System.get_env("OPENROUTER_API_KEY")
    if openrouter_key && openrouter_key != "" do
      test_openrouter(openrouter_key)
    else
      IO.puts("⊘ OpenRouter: Skipped (no API key)\n")
    end

    # Test Groq
    groq_key = System.get_env("GROQ_API_KEY")
    if groq_key && groq_key != "" do
      test_groq(groq_key)
    else
      IO.puts("⊘ Groq: Skipped (no API key)\n")
    end

    # Test Nvidia
    nvidia_key = System.get_env("NVIDIA_API_KEY")
    if nvidia_key && nvidia_key != "" do
      test_nvidia(nvidia_key)
    else
      IO.puts("⊘ Nvidia: Skipped (no API key)\n")
    end

    # Test Cerebras
    cerebras_key = System.get_env("CEREBRAS_API_KEY")
    if cerebras_key && cerebras_key != "" do
      test_cerebras(cerebras_key)
    else
      IO.puts("⊘ Cerebras: Skipped (no API key)\n")
    end

    IO.puts(String.duplicate("=", 60))
    IO.puts("Live Tests Complete")
    IO.puts(String.duplicate("=", 60) <> "\n")
  end

  defp load_env_file do
    env_path = Path.expand(".env", File.cwd!())

    if File.exists?(env_path) do
      env_path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.each(fn line ->
        case String.split(line, "=", parts: 2) do
          [key, value] ->
            key = String.trim(key)
            # Trim quotes AND any trailing whitespace/CR
            value = value |> String.trim() |> String.trim(~s("')) |> String.trim()
            System.put_env(key, value)
          _ ->
            :ok
        end
      end)

      IO.puts("Loaded environment from: #{env_path}\n")
    end
  end

  defp test_openrouter(api_key) do
    IO.write("Testing OpenRouter (llama-3-8b-instruct:free)... ")

    try do
      {:ok, agent} = Opal.start_session(%{
        provider: Opal.Provider.OpenAICompatible,
        model: "openrouter/meta-llama/llama-3-8b-instruct:free",
        provider_config: %{
          endpoint: "https://openrouter.ai/api/v1/chat/completions",
          api_key: api_key
        },
        default_tools: []
      })

      {:ok, response} = Opal.prompt_sync(agent, "Write a Python function to add two numbers. Only the function, no explanation.", 60_000)

      Opal.stop_session(agent)

      if String.contains?(response, "def") and String.contains?(response, "return") do
        IO.puts("✓ PASS")
        IO.puts("   Response:\n")
        response
        |> String.split("\n")
        |> Enum.take(8)
        |> Enum.each(fn line -> IO.puts("   " <> line) end)
        IO.puts("")
      else
        IO.puts("? Response received")
        IO.puts("   Preview: #{String.slice(response, 0, 150)}...\n")
      end
    rescue
      e ->
        IO.puts("✗ FAIL")
        IO.puts("   Error: #{Exception.message(e)}\n")
    end
  end

  defp test_groq(api_key) do
    IO.write("Testing Groq (llama-3.1-8b-instant)... ")

    try do
      {:ok, agent} = Opal.start_session(%{
        provider: Opal.Provider.OpenAICompatible,
        model: "llama-3.1-8b-instant",
        provider_config: %{
          endpoint: "https://api.groq.com/openai/v1/chat/completions",
          api_key: api_key
        },
        default_tools: []
      })

      {:ok, response} = Opal.prompt_sync(agent, "Say hello in exactly one sentence.", 60_000)

      Opal.stop_session(agent)

      if String.length(response) > 0 do
        IO.puts("✓ PASS")
        IO.puts("   Response: #{String.slice(response, 0, 100)}...\n")
      else
        IO.puts("✗ FAIL (empty response)\n")
      end
    rescue
      e ->
        IO.puts("✗ FAIL")
        IO.puts("   Error: #{Exception.message(e)}\n")
    end
  end

  defp test_nvidia(api_key) do
    IO.write("Testing Nvidia NIM (meta/llama-3.1-8b-instruct)... ")

    try do
      {:ok, agent} = Opal.start_session(%{
        provider: Opal.Provider.OpenAICompatible,
        model: "meta/llama-3.1-8b-instruct",
        provider_config: %{
          endpoint: "https://integrate.api.nvidia.com/v1/chat/completions",
          api_key: api_key
        },
        default_tools: []
      })

      {:ok, response} = Opal.prompt_sync(agent, "Say hello in one sentence.", 60_000)

      Opal.stop_session(agent)

      if String.length(response) > 0 do
        IO.puts("✓ PASS")
        IO.puts("   Response: #{String.slice(response, 0, 100)}...\n")
      else
        IO.puts("✗ FAIL (empty response)\n")
      end
    rescue
      e ->
        IO.puts("✗ FAIL")
        IO.puts("   Error: #{Exception.message(e)}\n")
    end
  end

  defp test_cerebras(api_key) do
    IO.write("Testing Cerebras (llama3.1-8b)... ")

    try do
      {:ok, agent} = Opal.start_session(%{
        provider: Opal.Provider.OpenAICompatible,
        model: "llama3.1-8b",
        provider_config: %{
          endpoint: "https://api.cerebras.ai/v1/chat/completions",
          api_key: api_key
        },
        default_tools: []
      })

      {:ok, response} = Opal.prompt_sync(agent, "Say hello in one sentence.", 60_000)

      Opal.stop_session(agent)

      if String.length(response) > 0 do
        IO.puts("✓ PASS")
        IO.puts("   Response: #{String.slice(response, 0, 100)}...\n")
      else
        IO.puts("✗ FAIL (empty response)\n")
      end
    rescue
      e ->
        IO.puts("✗ FAIL")
        IO.puts("   Error: #{Exception.message(e)}\n")
    end
  end
end
