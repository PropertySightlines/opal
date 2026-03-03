#!/usr/bin/env bash
# Demo script for the Opal orchestrator.
# Runs a demonstration of multi-agent orchestration with the AgentHarness.Orchestrator.
#
# Usage:
#   ./scripts/demo-orchestrator.sh              # Run orchestrator demo
#   ./scripts/demo-orchestrator.sh --verbose    # Run with verbose logging
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load .env file if it exists
if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/.env"
  set +a
fi

# Check mise is available
if ! command -v mise &> /dev/null; then
  echo "Error: mise is not installed or not in PATH."
  echo "Install mise: https://mise.jdx.dev/"
  exit 1
fi

# Parse arguments
VERBOSE_FLAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verbose)
      VERBOSE_FLAG="--verbose"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

echo "Running orchestrator demo..."
echo ""

# Run mise exec for elixir and node, then run the orchestrator demo
exec mise exec elixir node -- bash -c "cd $PROJECT_ROOT/opal && mix run -e 'AgentHarness.OrchestratorDemo.run()'"
