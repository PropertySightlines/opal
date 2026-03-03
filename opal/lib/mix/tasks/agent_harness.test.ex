defmodule Mix.Tasks.AgentHarness.Test do
  @moduledoc """
  Run AgentHarness unit tests.

  Usage: mix agent_harness.test
  """

  use Mix.Task

  @shortdoc "Run AgentHarness unit tests"

  def run(_args) do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("AgentHarness Phase 2 - Unit Tests")
    IO.puts(String.duplicate("=", 60) <> "\n")

    # Ensure compiled
    Mix.Task.run("compile")

    # Run tests
    result =
      System.cmd(
        "mix",
        ["test", "test/agent_harness", "--color"],
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    IO.puts("\n" <> String.duplicate("=", 60))

    case result do
      {_, 0} ->
        IO.puts("All AgentHarness Unit Tests Passed!")
        IO.puts(String.duplicate("=", 60) <> "\n")

      {_output, exit_code} ->
        IO.puts("Some tests failed (exit code: #{exit_code})")
        IO.puts(String.duplicate("=", 60) <> "\n")
        exit({:test_failed, exit_code})
    end
  end
end
