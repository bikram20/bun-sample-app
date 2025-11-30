# Bun Sample App

A sample Bun application demonstrating deployment on DigitalOcean App Platform using the dev template.

## Overview

This is a minimal Bun application that:
- Uses Bun for both package management and runtime
- Provides a simple HTTP server with health check endpoint
- Supports hot reload for rapid development
- Automatically handles dependency changes via `dev_startup.sh`

## Features

- **Health endpoint**: `/health` - Returns service status
- **Root endpoint**: `/` - Returns a greeting with a UUID
- **Info endpoint**: `/info` - Returns service information
- **Echo endpoint**: `/echo` - Echoes request details

## Project Structure

```
bun-sample-app/
├── index.ts          # Main server file
├── package.json      # Dependencies and scripts
├── dev_startup.sh    # Development startup script with hot reload
├── appspec.yaml      # DigitalOcean App Platform configuration
└── README.md         # This file
```

## Local Development

1. Install Bun (if not already installed):
   ```bash
   curl -fsSL https://bun.sh/install | bash
   ```

2. Install dependencies:
   ```bash
   bun install
   ```

3. Run the development server:
   ```bash
   bun run dev
   # or
   bun run --hot index.ts
   ```

4. The server will start on `http://localhost:8080`

## Deployment to DigitalOcean App Platform

This app is configured to work with the [appdev-template](https://github.com/bikram20/appdev-template) container.

### Prerequisites

- A DigitalOcean account
- `doctl` CLI installed and authenticated
- This repository pushed to GitHub

### Deployment Steps

1. **Push this repository to GitHub** (if not already done)

2. **Update `appspec.yaml`** with your repository URL:
   ```yaml
   - key: GITHUB_REPO_URL
     value: https://github.com/YOUR_USERNAME/bun-sample-app
   ```

3. **Deploy using doctl**:
   ```bash
   doctl apps create --spec appspec.yaml
   ```

   Or use the App Platform UI:
   - Create App → GitHub → Select `bikram20/appdev-template` repo
   - Configure environment variables:
     - `GITHUB_REPO_URL`: Your bun-sample-app repo URL
     - `INSTALL_NODE`: `true` (Bun requires Node.js base)
     - `RUN_COMMAND`: `bash dev_startup.sh`
     - `ENABLE_DEV_HEALTH`: `false` (app has its own health endpoint)

4. **Verify deployment**:
   - Check health: `https://your-app-url/health`
   - Check logs: `doctl apps logs <app-id> --type run`

## How `dev_startup.sh` Works

The `dev_startup.sh` script provides automatic hot-reload functionality:

1. **Initial Setup**: Installs dependencies using `bun install`

2. **Dependency Monitoring**: Background watcher monitors `package.json` and `bun.lockb` for changes
   - When dependencies change, it runs `bun install` and restarts the server

3. **Code Hot Reload**: Uses Bun's `--hot` flag for automatic code reloading
   - When source files change, Bun automatically restarts the server

4. **Continuous Operation**: The script runs in a loop, ensuring the server stays running

## Key Behaviors

- **Git sync is continuous** - Your app is NOT auto-restarted. The `--hot` flag handles code changes automatically.
- **Dependency changes trigger restart** - When `package.json` or `bun.lockb` changes, dependencies are reinstalled and the server restarts.
- **Health check endpoint** - The app provides `/health` endpoint for App Platform health checks.

## Troubleshooting

- **Server not starting**: Check that `index.ts` exists and `bun install` completed successfully
- **Dependencies not updating**: Ensure `bun.lockb` is committed to your repository
- **Hot reload not working**: Verify Bun's `--hot` flag is being used (check `dev_startup.sh`)

## Example API Calls

```bash
# Health check
curl https://your-app-url/health

# Root endpoint
curl https://your-app-url/

# Info endpoint
curl https://your-app-url/info

# Echo endpoint
curl https://your-app-url/echo?test=123
```

## Notes

- Bun requires Node.js to be installed in the container (hence `INSTALL_NODE=true`)
- The app listens on port 8080 (configurable via `PORT` environment variable)
- Bun's `--hot` flag provides fast hot reload for TypeScript/JavaScript files

