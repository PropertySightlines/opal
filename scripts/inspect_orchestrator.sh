#!/usr/bin/env bash
#
# inspect_orchestrator.sh — Connect to a running Opal instance and inspect orchestrator state.
#
# Usage:
#   ./scripts/inspect_orchestrator.sh
#   ./scripts/inspect_orchestrator.sh --session <session_id>
#
# This script:
#   1. Reads the node file (~/.opal/node) to get the running node name and cookie
#   2. Connects via iex --remsh to the running node
#   3. Queries orchestrator state and displays it
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NODE_FILE="$HOME/.opal/node"

# Parse arguments
SESSION_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session|-s)
      SESSION_ID="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 [--session <session_id>]"
      echo ""
      echo "Connect to a running Opal instance and inspect orchestrator state."
      echo ""
      echo "Options:"
      echo "  --session, -s  Session ID to inspect (default: show all active sessions)"
      echo "  --help, -h     Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Check if node file exists
if [[ ! -f "$NODE_FILE" ]]; then
  echo "✗ No running Opal instance found"
  echo ""
  echo "Start Opal first with:"
  echo "  mise run dev"
  echo ""
  echo "Or start manually:"
  echo "  cd $PROJECT_ROOT/opal"
  echo "  mise exec -- iex --sname opal -S mix"
  exit 1
fi

# Read node name and cookie
NODE_NAME="$(sed -n '1p' "$NODE_FILE")"
COOKIE="$(sed -n '2p' "$NODE_FILE")"

if [[ -z "$NODE_NAME" || -z "$COOKIE" ]]; then
  echo "✗ Invalid node file format"
  echo "File: $NODE_FILE"
  exit 1
fi

echo "Connecting to Opal node: $NODE_NAME"
echo ""

# Build the command to run
if [[ -n "$SESSION_ID" ]]; then
  CMD="AgentHarness.OrchestratorInspector.status(\"$SESSION_ID\")"
else
  CMD="""
  IO.puts("Active Orchestrator Sessions:")
  IO.puts(String.duplicate("=", 50))
  AgentHarness.OrchestratorInspector.list_sessions()
  |> Enum.each(fn {sid, status} ->
    IO.puts("Session: #{sid}")
    IO.puts("  Status: #{status.status}")
    IO.puts("  Progress: #{status.completed}/#{status.total}")
    IO.puts("")
  end)
  """
fi

# Connect to the running node
exec iex --sname inspect_$$ --remsh "$NODE_NAME" --cookie "$COOKIE" \
  -e "$CMD"
