#!/bin/bash
# Legacy entry point: the user-facing build now always installs the main app.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/install-applications.command" "$@"
