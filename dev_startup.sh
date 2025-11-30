#!/usr/bin/env bash
#
# Bun Application Development Startup Script
# ==========================================
#
# WHAT IT DOES:
# This script provides automatic hot-reload functionality for Bun applications in a
# development environment. It continuously monitors dependency files (package.json and
# bun.lockb) for changes and automatically reinstalls dependencies when they are modified.
# The script uses Bun's built-in --hot flag for code hot-reload, which automatically
# restarts the server when source files change.
#
# The script operates with a dual-process architecture:
#   1. Background watcher: Monitors package.json and bun.lockb every 10 seconds
#      for changes. When dependencies change, it runs 'bun install' to update
#      dependencies and kills the Bun process to trigger a restart.
#   2. Main loop: Runs Bun with --hot flag for code hot-reload, and automatically
#      restarts it when the watcher kills it (indicating dependency changes) or if
#      it crashes.
#
# WHY IT'S NEEDED:
# In a containerized development environment (like DigitalOcean App Platform), this
# script enables automatic dependency management when package.json is updated via
# git sync. When new dependencies are added and pushed to GitHub, the git sync
# service pulls the changes, and this script detects the modification, installs
# dependencies using Bun, and restarts the server automatically. This ensures the
# application always has the correct dependencies installed and the server is
# running the latest code, without requiring manual 'bun install' commands or
# server restarts. The --hot flag on Bun also provides automatic code reloading
# for source file changes.
#
# HOW IT'S USED:
# This script is executed by the container's RUN_COMMAND as specified in the
# appspec.yaml file. It:
#   - Runs 'bun install' initially to install all dependencies
#   - Creates a hash file (.deps_hash) to track dependency file state
#   - Starts a background process that monitors package.json and bun.lockb
#   - Enters a main loop that runs Bun on port 8080 with --hot enabled
#   - When the watcher detects dependency changes, it kills Bun, triggering
#     the main loop to restart it with the updated dependencies
#
# The script runs continuously, with the background watcher and main loop
# coordinating to ensure dependencies are always up-to-date and the server
# restarts when needed.
#
set -euo pipefail

# Change to workspace directory (where the app repo is cloned)
cd "${WORKSPACE_PATH:-/workspaces/app}"

# Install Bun if not already installed
if ! command -v bun &> /dev/null; then
  echo "Installing Bun..."
  curl -fsSL https://bun.sh/install | bash
  # Bun installer adds to ~/.bun/bin, ensure it's in PATH
  export BUN_INSTALL="$HOME/.bun"
  export PATH="$BUN_INSTALL/bin:$PATH"
  # Source Bun's environment if available
  [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun" || true
fi

# Ensure Bun is in PATH (in case it was already installed)
export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
export PATH="$BUN_INSTALL/bin:$PATH"

# Verify Bun is available
if ! command -v bun &> /dev/null; then
  echo "ERROR: Bun installation failed or not in PATH"
  exit 1
fi

echo "Bun version: $(bun --version)"

# Files to watch for dependency changes
WATCH_FILES=("package.json" "bun.lockb")
HASH_FILE=".deps_hash"

hash_files() {
  for f in "${WATCH_FILES[@]}"; do
    [ -f "$f" ] && sha256sum "$f"
  done
}

echo "Installing dependencies (bun install)..."
bun install
hash_files | sha256sum | awk '{print $1}' > "$HASH_FILE"

# Background watcher function that monitors dependency files
watch_dependencies() {
  # Ensure Bun is in PATH for this function
  export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
  export PATH="$BUN_INSTALL/bin:$PATH"
  while true; do
    sleep 10  # Check every 10 seconds
    current=$(hash_files | sha256sum | awk '{print $1}')
    previous=$(cat "$HASH_FILE" 2>/dev/null || true)
    if [ "$current" != "$previous" ]; then
      echo "[WATCHER] Dependencies changed. Re-installing..."
      bun install
      echo "$current" > "$HASH_FILE"
      # Kill Bun to trigger restart by outer loop
      if [ -n "${BUN_PID:-}" ]; then
        echo "[WATCHER] Killing Bun (PID: $BUN_PID) to restart..."
        kill "$BUN_PID" 2>/dev/null || true
      fi
    fi
  done
}

# Start background watcher
watch_dependencies &
WATCHER_PID=$!

# Cleanup function for graceful shutdown
cleanup() {
  echo "Shutting down..."
  [ -n "${WATCHER_PID:-}" ] && kill "$WATCHER_PID" 2>/dev/null || true
  [ -n "${BUN_PID:-}" ] && kill "$BUN_PID" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

# Main loop: Bun runs with --hot, watcher kills it when deps change, loop restarts it
while true; do
  echo "Starting Bun server with hot reload..."
  bun --hot index.ts &
  BUN_PID=$!
  echo "Bun started (PID: $BUN_PID)"

  # Wait for Bun to exit (either from crash or watcher kill)
  wait "$BUN_PID" 2>/dev/null || true

  echo "Bun exited. Restarting in 2 seconds..."
  sleep 2
done

