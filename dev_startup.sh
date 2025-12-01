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
WORKSPACE="${WORKSPACE_PATH:-/workspaces/app}"
echo "Changing to workspace: $WORKSPACE"
cd "$WORKSPACE" || {
  echo "ERROR: Failed to change to workspace directory: $WORKSPACE"
  exit 1
}

echo "Current directory: $(pwd)"
echo "Contents: $(ls -la)"

# Install Bun if not already installed
if ! command -v bun &> /dev/null; then
  echo "Installing Bun..."
  curl -fsSL https://bun.sh/install | bash || {
    echo "ERROR: Bun installation failed"
    exit 1
  }
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
  echo "PATH: $PATH"
  echo "BUN_INSTALL: $BUN_INSTALL"
  ls -la "$BUN_INSTALL/bin/" || echo "Bun bin directory does not exist"
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

# Wait for package.json to exist (git sync might still be in progress)
echo "Waiting for package.json to be available..."
for i in {1..30}; do
  if [ -f "package.json" ]; then
    echo "package.json found!"
    break
  fi
  echo "Waiting... ($i/30)"
  sleep 2
done

if [ ! -f "package.json" ]; then
  echo "ERROR: package.json not found after waiting. Listing directory contents:"
  ls -la
  exit 1
fi

echo "Installing dependencies (bun install)..."
bun install || {
  echo "WARNING: bun install failed, but continuing..."
  # Create empty hash file so script can continue
  touch "$HASH_FILE"
}
hash_files | sha256sum | awk '{print $1}' > "$HASH_FILE" || echo "0" > "$HASH_FILE"

# Background watcher function that monitors dependency files
watch_dependencies() {
  # Set workspace directory (use absolute path)
  local WATCH_DIR="${WORKSPACE_PATH:-/workspaces/app}"
  local HASH_FILE_PATH="$WATCH_DIR/.deps_hash"
  local WATCH_FILES=("package.json" "bun.lockb")
  
  # Define hash function inside watcher
  hash_files() {
    cd "$WATCH_DIR" || return 1
    for f in "${WATCH_FILES[@]}"; do
      [ -f "$f" ] && sha256sum "$f" 2>/dev/null
    done
  }
  
  # Ensure Bun is in PATH for this function
  export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
  export PATH="$BUN_INSTALL/bin:$PATH"
  
  echo "[WATCHER] Started monitoring package.json and bun.lockb in $WATCH_DIR"
  echo "[WATCHER] Hash file path: $HASH_FILE_PATH"
  
  # Get initial hash for reference
  cd "$WATCH_DIR" || exit 1
  initial_hash=$(hash_files | sha256sum | awk '{print $1}')
  echo "[WATCHER] Initial hash: $initial_hash"
  
  while true; do
    sleep 10  # Check every 10 seconds
    cd "$WATCH_DIR" || continue
    
    current=$(hash_files | sha256sum | awk '{print $1}')
    previous=$(cat "$HASH_FILE_PATH" 2>/dev/null || echo "")
    
    # Debug: log every check (first few times to verify it's working)
    if [ -z "$previous" ] || [ "$current" != "$previous" ]; then
      echo "[WATCHER] Check: current=$current, previous=${previous:-'(empty)'}"
    fi
    
    # Debug: log hash comparison (only when different to reduce noise)
    if [ "$current" != "$previous" ]; then
      if [ -n "$current" ]; then
        echo "[WATCHER] Dependencies changed detected!"
        echo "[WATCHER] Previous hash: ${previous:-'(empty)'}"
        echo "[WATCHER] Current hash: $current"
        echo "[WATCHER] Re-installing dependencies..."
        bun install
        echo "$current" > "$HASH_FILE_PATH"
        # Kill Bun to trigger restart by outer loop
        echo "[WATCHER] Killing Bun process to trigger restart..."
        pkill -f "bun.*index.ts" 2>/dev/null || true
        sleep 1
      else
        echo "[WATCHER] WARNING: Current hash is empty, skipping install"
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

