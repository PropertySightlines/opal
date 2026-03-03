/**
 * Multi-agent command — parse and execute /multi and /sequential slash commands.
 *
 * Usage:
 *   /multi <prompt>              — Run multi-agent analysis with default agent count
 *   /multi <prompt> --agents N   — Run multi-agent analysis with N agents
 *   /sequential <prompt>         — Run sequential pipeline analysis
 *
 * @module
 */

import type { Session } from "../sdk/session.js";
import type { OrchestratorRunParams, OrchestratorRunResult } from "../sdk/protocol.js";

// ── Argument parsing ─────────────────────────────────────────────

export interface MultiCommandArgs {
  prompt: string;
  mode: "multi" | "sequential";
  agentCount?: number;
}

/**
 * Parse command arguments from the input string.
 * 
 * Examples:
 *   "analyze this code" → { prompt: "analyze this code", mode: "multi" }
 *   "analyze this --agents 5" → { prompt: "analyze this", mode: "multi", agentCount: 5 }
 *   "review prd --agents 3" → { prompt: "review prd", mode: "multi", agentCount: 3 }
 */
export function parseMultiCommand(input: string, mode: "multi" | "sequential"): MultiCommandArgs | null {
  const trimmed = input.trim();
  if (!trimmed) return null;

  // Parse --agents flag
  const agentsMatch = trimmed.match(/--agents\s+(\d+)/);
  let agentCount: number | undefined;
  let prompt = trimmed;

  if (agentsMatch) {
    agentCount = parseInt(agentsMatch[1], 10);
    // Remove the --agents flag from the prompt
    prompt = trimmed.replace(agentsMatch[0], "").trim();
  }

  if (!prompt) return null;

  return {
    prompt,
    mode,
    agentCount: mode === "multi" ? agentCount : undefined,
  };
}

// ── Command execution ────────────────────────────────────────────

/**
 * Execute a multi-agent command.
 * 
 * @param session - The active session
 * @param args - Parsed command arguments
 * @returns Result message or undefined for success
 */
export async function executeMultiCommand(
  session: Session,
  args: MultiCommandArgs,
): Promise<string | void> {
  const params: OrchestratorRunParams = {
    sessionId: session.id,
    text: args.prompt,
    mode: args.mode,
    ...(args.agentCount !== undefined ? { agentCount: args.agentCount } : {}),
  };

  try {
    const result = await session.request("orchestrator/run", params) as OrchestratorRunResult;
    
    const modeLabel = args.mode === "multi" ? "Multi-agent" : "Sequential";
    const agentInfo = args.agentCount ? `${args.agentCount} agents` : "default agents";
    
    return `${modeLabel} analysis started with ${agentInfo}. Session: ${result.orchestratorSessionId}`;
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    return `Multi-agent command failed: ${message}`;
  }
}

/**
 * Execute a multi-agent command and return the result.
 * 
 * This is a convenience wrapper that handles the session request directly.
 */
export async function runMultiAgent(
  session: Session,
  prompt: string,
  agentCount?: number,
): Promise<OrchestratorRunResult> {
  const params: OrchestratorRunParams = {
    sessionId: session.id,
    text: prompt,
    mode: "multi",
    ...(agentCount !== undefined ? { agentCount } : {}),
  };

  return session.request("orchestrator/run", params) as Promise<OrchestratorRunResult>;
}

/**
 * Execute a sequential pipeline command and return the result.
 */
export async function runSequential(
  session: Session,
  prompt: string,
): Promise<OrchestratorRunResult> {
  const params: OrchestratorRunParams = {
    sessionId: session.id,
    text: prompt,
    mode: "sequential",
  };

  return session.request("orchestrator/run", params) as Promise<OrchestratorRunResult>;
}
