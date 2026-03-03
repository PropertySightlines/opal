/**
 * MultiAgentView — Display multi-agent execution progress and results.
 *
 * Shows:
 * - Overall orchestration status
 * - Individual agent status cards
 * - Progress indicators for each agent
 * - Aggregated results when complete
 *
 * @module
 */

import React, { type FC, useEffect, useState } from "react";
import { Box, Text } from "ink";
import { colors } from "../lib/palette.js";
import { useOpalStore } from "../state/store.js";
import { useActiveAgent } from "../state/selectors.js";

// ── Types ────────────────────────────────────────────────────────

export interface AgentStatus {
  id: string;
  name: string;
  status: "pending" | "running" | "completed" | "error";
  progress?: number;
  message?: string;
  result?: string;
}

export interface MultiAgentState {
  orchestratorSessionId: string;
  mode: "multi" | "sequential";
  totalAgents: number;
  agents: AgentStatus[];
  isRunning: boolean;
  isComplete: boolean;
  aggregatedResult?: string;
}

// ── Status indicator ─────────────────────────────────────────────

interface StatusIndicatorProps {
  status: AgentStatus["status"];
}

const StatusIndicator: FC<StatusIndicatorProps> = ({ status }) => {
  const [dots, setDots] = useState(0);

  useEffect(() => {
    if (status !== "running" && status !== "pending") return;
    const timer = setInterval(() => {
      setDots((d) => (d + 1) % 4);
    }, 300);
    return () => clearInterval(timer);
  }, [status]);

  switch (status) {
    case "pending":
      return <Text color="gray">{"○"} {".".repeat(dots)}{" "}</Text>;
    case "running":
      return <Text color="yellow">{"◐"} {".".repeat(dots)}{" "}</Text>;
    case "completed":
      return <Text color="green">{"✔"} </Text>;
    case "error":
      return <Text color="red">{"✖"} </Text>;
  }
};

// ── Agent card ───────────────────────────────────────────────────

interface AgentCardProps {
  agent: AgentStatus;
  index: number;
}

const AgentCard: FC<AgentCardProps> = ({ agent, index }) => {
  const statusColor =
    agent.status === "completed"
      ? "green"
      : agent.status === "error"
        ? colors.error
        : agent.status === "running"
          ? "yellow"
          : "gray";

  return (
    <Box
      flexDirection="column"
      borderStyle="round"
      borderColor={statusColor}
      paddingX={1}
      marginTop={1}
    >
      <Box>
        <StatusIndicator status={agent.status} />
        <Text bold color={statusColor}>
          Agent {index + 1}: {agent.name}
        </Text>
      </Box>
      {agent.message && (
        <Box marginTop={1}>
          <Text dimColor>{agent.message}</Text>
        </Box>
      )}
      {agent.progress !== undefined && agent.status === "running" && (
        <Box marginTop={1}>
          <ProgressBar progress={agent.progress} />
        </Box>
      )}
      {agent.result && agent.status === "completed" && (
        <Box marginTop={1} flexDirection="column">
          <Text dimColor>Result:</Text>
          <Text>{agent.result}</Text>
        </Box>
      )}
    </Box>
  );
};

// ── Progress bar ─────────────────────────────────────────────────

interface ProgressBarProps {
  progress: number;
  width?: number;
}

const ProgressBar: FC<ProgressBarProps> = ({ progress, width = 20 }) => {
  const filled = Math.round((progress / 100) * width);
  const empty = width - filled;

  return (
    <Text>
      <Text color="green">{"█".repeat(filled)}</Text>
      <Text color="gray">{"░".repeat(empty)}</Text>
      <Text dimColor> {progress}%</Text>
    </Text>
  );
};

// ── Orchestrator header ──────────────────────────────────────────

interface OrchestratorHeaderProps {
  mode: "multi" | "sequential";
  totalAgents: number;
  isRunning: boolean;
  isComplete: boolean;
}

const OrchestratorHeader: FC<OrchestratorHeaderProps> = ({
  mode,
  totalAgents,
  isRunning,
  isComplete,
}) => {
  const title = mode === "multi" ? "Multi-Agent Analysis" : "Sequential Pipeline";
  const status = isComplete
    ? "Complete"
    : isRunning
      ? "Running"
      : "Pending";
  const statusColor = isComplete ? "green" : isRunning ? "yellow" : "gray";

  return (
    <Box flexDirection="column" marginBottom={1}>
      <Box>
        <Text bold color={colors.primary}>
          {"⬡"} {title}
        </Text>
        <Text dimColor> — </Text>
        <Text color={statusColor}>{status}</Text>
      </Box>
      <Box>
        <Text dimColor>
          Total agents: {totalAgents}
        </Text>
      </Box>
    </Box>
  );
};

// ── Aggregated results ───────────────────────────────────────────

interface AggregatedResultsProps {
  results: string[];
  mode: "multi" | "sequential";
}

const AggregatedResults: FC<AggregatedResultsProps> = ({ results, mode }) => {
  if (results.length === 0) return null;

  return (
    <Box flexDirection="column" marginTop={2} borderStyle="single" borderColor="green" paddingX={1}>
      <Box>
        <Text bold color="green">
          {"★"} Aggregated Results
        </Text>
      </Box>
      <Box marginTop={1} flexDirection="column">
        {results.map((result, i) => (
          <Box key={i} marginTop={1}>
            <Text dimColor>Agent {i + 1}: </Text>
            <Text>{result}</Text>
          </Box>
        ))}
      </Box>
      {mode === "multi" && (
        <Box marginTop={1}>
          <Text dimColor italic>
            Results shown above are from parallel agent execution.
          </Text>
        </Box>
      )}
      {mode === "sequential" && (
        <Box marginTop={1}>
          <Text dimColor italic>
            Results shown above are from sequential pipeline execution.
          </Text>
        </Box>
      )}
    </Box>
  );
};

// ── Main view ────────────────────────────────────────────────────

export interface MultiAgentViewProps {
  /** Initial state from command execution */
  initialState?: Partial<MultiAgentState>;
  /** Callback when execution completes */
  onComplete?: () => void;
}

/**
 * Multi-agent execution view.
 *
 * Displays real-time progress of multi-agent or sequential pipeline execution.
 * Shows individual agent status cards and aggregated results when complete.
 */
export const MultiAgentView: FC<MultiAgentViewProps> = ({ initialState, onComplete }) => {
  const { entries, isRunning, statusMessage } = useActiveAgent();
  const session = useOpalStore((s) => s.session);

  // Local state for tracking agent progress
  const [agentState, setAgentState] = useState<MultiAgentState | null>(
    initialState
      ? ({
          orchestratorSessionId: initialState.orchestratorSessionId ?? "",
          mode: initialState.mode ?? "multi",
          totalAgents: initialState.totalAgents ?? 3,
          agents: initialState.agents ?? [],
          isRunning: initialState.isRunning ?? true,
          isComplete: initialState.isComplete ?? false,
          aggregatedResult: initialState.aggregatedResult,
        } as MultiAgentState)
      : null,
  );

  // Update agent state based on timeline entries
  useEffect(() => {
    if (!agentState) return;

    // Process entries to extract agent status updates
    const completedAgents = entries
      .filter((e) => e.kind === "message")
      .map((e) => "content" in e ? (e as any).content : "");

    setAgentState((prev) => {
      if (!prev) return null;

      const updatedAgents = prev.agents.map((agent, i) => {
        if (completedAgents[i]) {
          return { ...agent, status: "completed" as const, result: completedAgents[i] };
        }
        if (prev.isRunning && i < completedAgents.length) {
          return { ...agent, status: "running" as const, progress: 50 + (i * 10) };
        }
        return agent;
      });

      const allComplete = updatedAgents.every((a) => a.status === "completed");
      
      if (allComplete && !prev.isComplete) {
        // Execution complete
        setTimeout(() => onComplete?.(), 500);
      }

      return {
        ...prev,
        agents: updatedAgents,
        isComplete: allComplete,
        isRunning: !allComplete && prev.isRunning,
      };
    });
  }, [entries, agentState, onComplete]);

  // Initialize agent state if not set
  useEffect(() => {
    if (!agentState && session) {
      const defaultAgents: AgentStatus[] = Array.from({ length: 3 }, (_, i) => ({
        id: `agent-${i}`,
        name: `Agent ${i + 1}`,
        status: "pending" as const,
      }));

      setAgentState({
        orchestratorSessionId: session.id,
        mode: "multi",
        totalAgents: 3,
        agents: defaultAgents,
        isRunning: true,
        isComplete: false,
      });
    }
  }, [agentState, session]);

  if (!agentState) {
    return (
      <Box flexDirection="column" padding={1}>
        <Text dimColor>Initializing multi-agent execution...</Text>
      </Box>
    );
  }

  return (
    <Box flexDirection="column" padding={1}>
      <OrchestratorHeader
        mode={agentState.mode}
        totalAgents={agentState.totalAgents}
        isRunning={agentState.isRunning}
        isComplete={agentState.isComplete}
      />

      <Box flexDirection="column">
        {agentState.agents.map((agent, i) => (
          <AgentCard key={agent.id} agent={agent} index={i} />
        ))}
      </Box>

      {agentState.isComplete && agentState.aggregatedResult && (
        <AggregatedResults
          results={[agentState.aggregatedResult]}
          mode={agentState.mode}
        />
      )}

      {agentState.isRunning && statusMessage && (
        <Box marginTop={2}>
          <Text dimColor color="yellow">
            {"◐"} {statusMessage}
          </Text>
        </Box>
      )}
    </Box>
  );
};

// ── Hook for multi-agent state ───────────────────────────────────

/**
 * Hook to manage multi-agent execution state.
 *
 * @example
 * ```tsx
 * const { startMulti, agents, isComplete } = useMultiAgent();
 *
 * const handleMulti = async (prompt: string) => {
 *   await startMulti(prompt, { agentCount: 5 });
 * };
 * ```
 */
export function useMultiAgent() {
  const session = useOpalStore((s) => s.session);
  const [agents, setAgents] = useState<AgentStatus[]>([]);
  const [isRunning, setIsRunning] = useState(false);
  const [isComplete, setIsComplete] = useState(false);
  const [mode, setMode] = useState<"multi" | "sequential">("multi");

  const startMulti = async (prompt: string, options?: { agentCount?: number }) => {
    if (!session) return;

    setIsRunning(true);
    setIsComplete(false);
    setMode("multi");

    const agentCount = options?.agentCount ?? 3;
    const initialAgents: AgentStatus[] = Array.from({ length: agentCount }, (_, i) => ({
      id: `agent-${i}`,
      name: `Agent ${i + 1}`,
      status: "pending" as const,
    }));
    setAgents(initialAgents);

    try {
      const result = await session.request("orchestrator/run", {
        sessionId: session.id,
        text: prompt,
        mode: "multi",
        agentCount,
      }) as { orchestratorSessionId: string; agentCount: number };

      // Update agents to running state
      setAgents((prev) =>
        prev.map((agent) => ({ ...agent, status: "running" as const })),
      );
    } catch (err: unknown) {
      setIsRunning(false);
      throw err;
    }
  };

  const startSequential = async (prompt: string) => {
    if (!session) return;

    setIsRunning(true);
    setIsComplete(false);
    setMode("sequential");

    const initialAgents: AgentStatus[] = [
      { id: "analyst", name: "Analyst", status: "pending" as const },
      { id: "reviewer", name: "Reviewer", status: "pending" as const },
      { id: "synthesizer", name: "Synthesizer", status: "pending" as const },
    ];
    setAgents(initialAgents);

    try {
      await session.request("orchestrator/run", {
        sessionId: session.id,
        text: prompt,
        mode: "sequential",
      });
    } catch (err: unknown) {
      setIsRunning(false);
      throw err;
    }
  };

  const updateAgentStatus = (agentId: string, status: AgentStatus["status"], message?: string) => {
    setAgents((prev) =>
      prev.map((agent) =>
        agent.id === agentId ? { ...agent, status, message } : agent,
      ),
    );
  };

  const complete = () => {
    setIsRunning(false);
    setIsComplete(true);
  };

  return {
    agents,
    isRunning,
    isComplete,
    mode,
    startMulti,
    startSequential,
    updateAgentStatus,
    complete,
  };
}
