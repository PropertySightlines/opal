#!/usr/bin/env bash
# Launches the Opal CLI with environment loading and mise tool management.
#
# Usage:
#   ./scripts/dev-cli.sh                    # Launch CLI normally
#   ./scripts/dev-cli.sh --debug            # Launch with debug features enabled
#   ./scripts/dev-cli.sh --multi            # Launch with multi-agent mode enabled
#   ./scripts/dev-cli.sh --debug --multi    # Both flags
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
DEBUG_FLAG=""
MULTI_FLAG=""
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      DEBUG_FLAG="--debug"
      shift
      ;;
    --multi)
      MULTI_FLAG="true"
      shift
      ;;
    *)
      EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

# Build environment variables
ENV_VARS=""
if [ -n "$MULTI_FLAG" ]; then
  ENV_VARS="OPAL_MULTI_AGENT=true"
fi

# Run mise exec for elixir and node, then launch CLI
if [ -n "$ENV_VARS" ]; then
  exec mise exec elixir node -- bash -c "$ENV_VARS node $PROJECT_ROOT/cli/dist/bin.js ${DEBUG_FLAG} ${EXTRA_ARGS[*]}"
else
  exec mise exec elixir node -- node "$PROJECT_ROOT/cli/dist/bin.js" ${DEBUG_FLAG} ${EXTRA_ARGS[*]}
fi
