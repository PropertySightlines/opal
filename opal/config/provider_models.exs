%{
  "openrouter" => %{
    model: "stepfun/step-3.5-flash:free",
    endpoint: "https://openrouter.ai/api/v1/chat/completions",
    system_prompt: "You are a creative brainstorming assistant. Generate diverse ideas."
  },
  "groq" => %{
    model: "moonshotai/kimi-k2-instruct-0905",
    endpoint: "https://api.groq.com/openai/v1/chat/completions",
    system_prompt: "You are a critical analyst. Identify flaws and potential issues."
  },
  "nvidia" => %{
    model: "qwen/qwen3.5-397b-a17b",
    endpoint: "https://integrate.api.nvidia.com/v1/chat/completions",
    system_prompt: "You are the lead orchestrator. Provide comprehensive, authoritative analysis."
  },
  "cerebras" => %{
    model: "gpt-oss-120b",
    endpoint: "https://api.cerebras.ai/v1/chat/completions",
    system_prompt: "You are a detail-oriented reviewer. Check for completeness and accuracy."
  }
}
