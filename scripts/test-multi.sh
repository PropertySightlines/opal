#!/usr/bin/env bash
# Runs multi-agent specific tests for Opal.
#
# Usage:
#   ./scripts/test-multi.sh              # Run multi-agent tests
#   ./scripts/test-multi.sh --watch      # Run in watch mode
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
WATCH_MODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --watch)
      WATCH_MODE="--watch"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

echo "Running multi-agent tests..."

# Run mise exec for elixir and node, then run tests
exec mise exec elixir node -- bash -c "cd $PROJECT_ROOT/opal && mix test --only multi_agent $WATCH_MODE"
