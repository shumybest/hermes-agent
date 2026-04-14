#!/bin/bash
# Docker entrypoint: bootstrap config files into the managed Hermes home, then run hermes.
set -e

# Respect an injected HERMES_HOME (for example THEVIBER's shared-PVC state mount)
# and fall back to the image default only when the runtime did not provide one.
DEFAULT_HERMES_HOME="/opt/data"
HERMES_HOME="${HERMES_HOME:-$DEFAULT_HERMES_HOME}"
export HERMES_HOME
INSTALL_DIR="/opt/hermes"

# Create essential directory structure.  Cache and platform directories
# (cache/images, cache/audio, platforms/whatsapp, etc.) are created on
# demand by the application — don't pre-create them here so new installs
# get the consolidated layout from get_hermes_dir().
mkdir -p "$HERMES_HOME"/{cron,sessions,logs,hooks,memories,skills}

# .env
if [ ! -f "$HERMES_HOME/.env" ]; then
    cp "$INSTALL_DIR/.env.example" "$HERMES_HOME/.env"
fi

# config.yaml
if [ ! -f "$HERMES_HOME/config.yaml" ]; then
    cp "$INSTALL_DIR/cli-config.yaml.example" "$HERMES_HOME/config.yaml"
fi

# SOUL.md
if [ ! -f "$HERMES_HOME/SOUL.md" ]; then
    cp "$INSTALL_DIR/docker/SOUL.md" "$HERMES_HOME/SOUL.md"
fi

# Provide stable, non-hidden aliases inside the install tree so Web Console
# users can quickly find the live managed config without guessing HERMES_HOME.
ln -sfn "$HERMES_HOME" "$INSTALL_DIR/runtime-state"
ln -sfn "$HERMES_HOME/config.yaml" "$INSTALL_DIR/runtime-config.yaml"
ln -sfn "$HERMES_HOME/.env" "$INSTALL_DIR/runtime.env"

# Sync bundled skills (manifest-based so user edits are preserved)
if [ -d "$INSTALL_DIR/skills" ]; then
    python3 "$INSTALL_DIR/tools/skills_sync.py"
fi

exec hermes "$@"
