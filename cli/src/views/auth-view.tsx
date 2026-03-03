import React, { useState, type FC } from "react";
import { Box, Text, useInput } from "ink";
import { openUrl, copyToClipboard } from "../lib/desktop.js";
import { colors } from "../lib/palette.js";
import { useOpalStore } from "../state/store.js";

// ── AuthView ─────────────────────────────────────────────────────

export const AuthView: FC = () => {
  const status = useOpalStore((s) => s.authStatus);
  const deviceCode = useOpalStore((s) => s.deviceCode);
  const verificationUri = useOpalStore((s) => s.verificationUri);
  const error = useOpalStore((s) => s.authError);
  const availableProviders = useOpalStore((s) => s.availableProviders);

  switch (status) {
    case "deviceCode":
    case "polling":
      return (
        <DeviceCodeView code={deviceCode} uri={verificationUri} polling={status === "polling"} />
      );

    case "error":
      return <AuthErrorView message={error} />;

    case "needsAuth":
      return <NeedsAuthView availableProviders={availableProviders} />;

    default:
      return null;
  }
};

// ── NeedsAuthView ────────────────────────────────────────────────

interface NeedsAuthViewProps {
  availableProviders: string[];
}

const NeedsAuthView: FC<NeedsAuthViewProps> = ({ availableProviders }) => {
  const session = useOpalStore((s) => s.session);
  const startDeviceFlow = useOpalStore((s) => s.startDeviceFlow);
  const selectApiKeyProvider = useOpalStore((s) => s.selectApiKeyProvider);
  const [selectedIndex, setSelectedIndex] = useState(0);

  useInput((_input, key) => {
    if (key.upArrow) {
      setSelectedIndex((prev) => Math.max(0, prev - 1));
    } else if (key.downArrow) {
      setSelectedIndex((prev) => Math.min(availableProviders.length - 1, prev + 1));
    } else if (key.return) {
      if (session) {
        const selected = availableProviders[selectedIndex];
        if (selected === "copilot") {
          startDeviceFlow(session);
        } else {
          selectApiKeyProvider(selected);
        }
      }
    }
  });

  const hasApiKeyProviders = availableProviders.some((p) => p !== "copilot");

  return (
    <Box flexDirection="column" padding={1} gap={1}>
      <Text bold color={colors.primary}>
        ✦ Welcome to Opal
      </Text>
      <Box flexDirection="column" marginLeft={2} gap={1}>
        {hasApiKeyProviders ? (
          <>
            <Text>API key providers detected. Select one to continue:</Text>
            {availableProviders.map((provider, index) => (
              <Text
                key={provider}
                color={index === selectedIndex ? colors.success : undefined}
              >
                {index === selectedIndex ? "❯ " : "  "}
                {provider === "copilot" 
                  ? "GitHub Copilot (OAuth)" 
                  : `${provider} (API key from environment)`}
              </Text>
            ))}
            <Text dimColor>
              Use{" "}
              <Text bold color={colors.primary}>↑↓</Text>
              {" "}to navigate,{" "}
              <Text bold color={colors.primary}>Enter</Text>
              {" "}to select
            </Text>
          </>
        ) : (
          <>
            <Text>GitHub Copilot sign-in is required to continue.</Text>
            <Text dimColor>
              Press{" "}
              <Text bold color={colors.primary}>
                Enter
              </Text>{" "}
              to open your browser and sign in with your GitHub account.
            </Text>
          </>
        )}
      </Box>
    </Box>
  );
};

// ── DeviceCodeView ───────────────────────────────────────────────

const DeviceCodeView: FC<{
  code: string | null;
  uri: string | null;
  polling: boolean;
}> = ({ code, uri, polling }) => {
  const [opened, setOpened] = useState(false);

  useInput((_input, key) => {
    if (key.return && !opened && code && uri) {
      copyToClipboard(code);
      openUrl(uri);
      setOpened(true);
    }
  });

  return (
    <Box flexDirection="column" padding={1} gap={1}>
      <Text bold color={colors.primary}>
        ✦ Welcome to Opal
      </Text>
      <Box flexDirection="column" marginLeft={2} gap={1}>
        <Text>
          Your one-time code:{" "}
          <Text bold color={colors.success}>
            {code}
          </Text>
          {opened && <Text dimColor> ✓ copied</Text>}
        </Text>
        {polling ? (
          <Text dimColor>Waiting for authorization — paste the code in your browser…</Text>
        ) : (
          <Text dimColor>
            Press{" "}
            <Text bold color={colors.primary}>
              Enter
            </Text>{" "}
            to copy the code to your clipboard and open the browser
          </Text>
        )}
      </Box>
    </Box>
  );
};

// ── AuthErrorView ────────────────────────────────────────────────

const AuthErrorView: FC<{ message: string | null }> = ({ message }) => {
  const session = useOpalStore((s) => s.session);
  const retryAuth = useOpalStore((s) => s.retryAuth);

  useInput((_input, key) => {
    if (key.return && session) retryAuth(session);
  });

  return (
    <Box flexDirection="column" padding={1} gap={1}>
      <Text bold color={colors.primary}>
        ✦ Welcome to Opal
      </Text>
      <Box flexDirection="column" marginLeft={2} gap={1}>
        <Text color={colors.error}>✖ Authentication failed</Text>
        {message && <Text dimColor>{message}</Text>}
        <Text dimColor>
          Press{" "}
          <Text bold color={colors.primary}>
            Enter
          </Text>{" "}
          to try again
        </Text>
      </Box>
    </Box>
  );
};
