import React, { type FC } from "react";
import { Box, Text } from "ink";
import { colors } from "../lib/palette.js";
import { useOpalStore } from "../state/store.js";

export const AuthView: FC = () => {
  const status = useOpalStore((s) => s.authStatus);
  const error = useOpalStore((s) => s.authError);
  const availableProviders = useOpalStore((s) => s.availableProviders);

  if (status === "error") {
    return (
      <Box flexDirection="column" padding={1} gap={1}>
        <Text bold color={colors.error}>
          ✖ Authentication Error
        </Text>
        <Box flexDirection="column" marginLeft={2} gap={1}>
          {error && <Text dimColor>{error}</Text>}
          <Text dimColor>
            Set API keys in .env file:
          </Text>
          <Box flexDirection="column" marginLeft={2}>
            <Text dimColor>OPENROUTER_API_KEY=sk-or-...</Text>
            <Text dimColor>GROQ_API_KEY=gsk_...</Text>
            <Text dimColor>NVIDIA_API_KEY=nvapi-...</Text>
            <Text dimColor>CEREBRAS_API_KEY=csk-...</Text>
          </Box>
        </Box>
      </Box>
    );
  }

  // Auto-authenticated - show brief status
  return (
    <Box flexDirection="column" padding={1} gap={1}>
      <Text bold color={colors.success}>
        ✓ Authenticated
      </Text>
      <Box flexDirection="column" marginLeft={2} gap={1}>
        <Text dimColor>
          Using providers: {availableProviders.join(", ")}
        </Text>
        <Text dimColor>Starting session...</Text>
      </Box>
    </Box>
  );
};
