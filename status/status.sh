#!/bin/bash
# tmux status bar — OS dispatcher
# Detects platform and runs the appropriate status script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$(uname -s)" in
    Darwin)
        exec "$SCRIPT_DIR/status-darwin.sh"
        ;;
    Linux)
        # WSL detection — if /proc/version mentions Microsoft, it's WSL
        # WSL uses the Linux script (same procfs/sysfs interface)
        exec "$SCRIPT_DIR/status-linux.sh"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        exec "$SCRIPT_DIR/status-windows.sh"
        ;;
    *)
        echo "CPU:? MEM:? NET:?"
        ;;
esac
