defmodule AgentHarness.RateLimit.ConfigTest do
  use ExUnit.Case, async: true

  alias AgentHarness.RateLimit.Config

  describe "load/0" do
    test "returns default limits when no config is set" do
      # Save current config
      original_config = Application.get_env(:agent_harness, :rate_limits)

      try do
        # Clear config
        Application.delete_env(:agent_harness, :rate_limits)

        limits = Config.load()

        assert limits.groq.rpm == 30
        assert limits.groq.tpm == 60_000
        assert limits.cerebras.rpm == 20
        assert limits.cerebras.tpm == 60_000
        assert limits.nvidia.rpm == 100
        assert limits.nvidia.tpm == 500_000
        assert limits.openrouter.rpm == 60
        assert limits.openrouter.tpm == 100_000
      after
        # Restore original config
        if original_config, do: Application.put_env(:agent_harness, :rate_limits, original_config)
      end
    end

    test "merges application config with defaults" do
      original_config = Application.get_env(:agent_harness, :rate_limits)

      try do
        # Set custom config
        Application.put_env(:agent_harness, :rate_limits, %{
          groq: %{rpm: 50, tpm: 80_000}
        })

        limits = Config.load()

        # Custom config takes precedence
        assert limits.groq.rpm == 50
        assert limits.groq.tpm == 80_000

        # Other providers keep defaults
        assert limits.cerebras.rpm == 20
        assert limits.nvidia.rpm == 100
      after
        # Restore original config
        if original_config, do: Application.put_env(:agent_harness, :rate_limits, original_config)
      end
    end
  end

  describe "get_provider_limit/1" do
    test "returns limit for known provider" do
      # Save and restore config to avoid interference from other tests
      original_config = Application.get_env(:agent_harness, :rate_limits)

      try do
        # Reset to defaults
        Application.delete_env(:agent_harness, :rate_limits)
        limit = Config.get_provider_limit(:groq)
        assert limit.rpm == 30
        assert limit.tpm == 60_000
      after
        if original_config, do: Application.put_env(:agent_harness, :rate_limits, original_config)
      end
    end

    test "returns zero limits for unknown provider" do
      limit = Config.get_provider_limit(:unknown_provider)
      assert limit.rpm == 0
      assert limit.tpm == 0
    end

    test "respects application config" do
      original_config = Application.get_env(:agent_harness, :rate_limits)

      try do
        Application.put_env(:agent_harness, :rate_limits, %{
          groq: %{rpm: 100, tpm: 200_000}
        })

        limit = Config.get_provider_limit(:groq)
        assert limit.rpm == 100
        assert limit.tpm == 200_000
      after
        if original_config, do: Application.put_env(:agent_harness, :rate_limits, original_config)
      end
    end
  end

  describe "parse_provider/1" do
    test "parses lowercase provider name" do
      assert Config.parse_provider("groq") == :groq
      assert Config.parse_provider("cerebras") == :cerebras
      assert Config.parse_provider("nvidia") == :nvidia
      assert Config.parse_provider("openrouter") == :openrouter
    end

    test "parses uppercase provider name" do
      assert Config.parse_provider("GROQ") == :groq
      assert Config.parse_provider("CEREBRAS") == :cerebras
    end

    test "parses mixed case provider name" do
      assert Config.parse_provider("GrOq") == :groq
      assert Config.parse_provider("NvIdIa") == :nvidia
    end
  end

  describe "providers/0" do
    test "returns list of default providers" do
      providers = Config.providers()
      assert providers == [:groq, :cerebras, :nvidia, :openrouter]
    end
  end

  describe "environment variable loading" do
    test "reads RPM from environment variable" do
      original = System.get_env("GROQ_RPM")

      try do
        System.put_env("GROQ_RPM", "999")
        Application.delete_env(:agent_harness, :rate_limits)

        limit = Config.get_provider_limit(:groq)
        assert limit.rpm == 999
        # TPM should still be default
        assert limit.tpm == 60_000
      after
        if original, do: System.put_env("GROQ_RPM", original), else: System.delete_env("GROQ_RPM")
      end
    end

    test "reads TPM from environment variable" do
      original = System.get_env("GROQ_TPM")

      try do
        System.put_env("GROQ_TPM", "999999")
        Application.delete_env(:agent_harness, :rate_limits)

        limit = Config.get_provider_limit(:groq)
        # RPM should still be default
        assert limit.rpm == 30
        assert limit.tpm == 999_999
      after
        if original, do: System.put_env("GROQ_TPM", original), else: System.delete_env("GROQ_TPM")
      end
    end

    test "reads both RPM and TPM from environment variables" do
      original_rpm = System.get_env("CEREBRAS_RPM")
      original_tpm = System.get_env("CEREBRAS_TPM")

      try do
        System.put_env("CEREBRAS_RPM", "50")
        System.put_env("CEREBRAS_TPM", "150000")
        Application.delete_env(:agent_harness, :rate_limits)

        limit = Config.get_provider_limit(:cerebras)
        assert limit.rpm == 50
        assert limit.tpm == 150_000
      after
        if original_rpm, do: System.put_env("CEREBRAS_RPM", original_rpm), else: System.delete_env("CEREBRAS_RPM")
        if original_tpm, do: System.put_env("CEREBRAS_TPM", original_tpm), else: System.delete_env("CEREBRAS_TPM")
      end
    end

    test "application config takes precedence over environment variables" do
      original_rpm = System.get_env("GROQ_RPM")
      original_config = Application.get_env(:agent_harness, :rate_limits)

      try do
        System.put_env("GROQ_RPM", "999")
        Application.put_env(:agent_harness, :rate_limits, %{
          groq: %{rpm: 111, tpm: 222}
        })

        limit = Config.get_provider_limit(:groq)
        # Application config should win
        assert limit.rpm == 111
        assert limit.tpm == 222
      after
        if original_rpm, do: System.put_env("GROQ_RPM", original_rpm), else: System.delete_env("GROQ_RPM")
        if original_config, do: Application.put_env(:agent_harness, :rate_limits, original_config)
      end
    end

    test "ignores invalid environment variable values" do
      original = System.get_env("GROQ_RPM")

      try do
        System.put_env("GROQ_RPM", "invalid")
        Application.delete_env(:agent_harness, :rate_limits)

        limit = Config.get_provider_limit(:groq)
        # Should fall back to default
        assert limit.rpm == 30
      after
        if original, do: System.put_env("GROQ_RPM", original), else: System.delete_env("GROQ_RPM")
      end
    end
  end
end
