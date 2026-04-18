#!/bin/bash
# Docker entrypoint: bootstrap config files into the managed Hermes home, then run hermes.
set -e

# Respect an injected HERMES_HOME (for example THEVIBER's shared-PVC state mount)
# and fall back to the image default only when the runtime did not provide one.
DEFAULT_HERMES_HOME="/opt/data"
HERMES_HOME="${HERMES_HOME:-$DEFAULT_HERMES_HOME}"
export HERMES_HOME
INSTALL_DIR="/opt/hermes"

# --- Privilege dropping via gosu ---
# When started as root (the default for Docker, or fakeroot in rootless Podman),
# optionally remap the hermes user/group to match host-side ownership, fix volume
# permissions, then re-exec as hermes.
if [ "$(id -u)" = "0" ]; then
    if [ -n "$HERMES_UID" ] && [ "$HERMES_UID" != "$(id -u hermes)" ]; then
        echo "Changing hermes UID to $HERMES_UID"
        usermod -u "$HERMES_UID" hermes
    fi

    if [ -n "$HERMES_GID" ] && [ "$HERMES_GID" != "$(id -g hermes)" ]; then
        echo "Changing hermes GID to $HERMES_GID"
        # -o allows non-unique GID (e.g. macOS GID 20 "staff" may already exist
        # as "dialout" in the Debian-based container image)
        groupmod -o -g "$HERMES_GID" hermes 2>/dev/null || true
    fi

    actual_hermes_uid=$(id -u hermes)
    if [ "$(stat -c %u "$HERMES_HOME" 2>/dev/null)" != "$actual_hermes_uid" ]; then
        echo "$HERMES_HOME is not owned by $actual_hermes_uid, fixing"
        # In rootless Podman the container's "root" is mapped to an unprivileged
        # host UID — chown will fail.  That's fine: the volume is already owned
        # by the mapped user on the host side.
        chown -R hermes:hermes "$HERMES_HOME" 2>/dev/null || \
            echo "Warning: chown failed (rootless container?) — continuing anyway"
    fi

    echo "Dropping root privileges"
    exec gosu hermes "$0" "$@"
fi

# --- Running as hermes from here ---
source "${INSTALL_DIR}/.venv/bin/activate"

# Create essential directory structure.  Cache and platform directories
# (cache/images, cache/audio, platforms/whatsapp, etc.) are created on
# demand by the application — don't pre-create them here so new installs
# get the consolidated layout from get_hermes_dir().
# The "home/" subdirectory is a per-profile HOME for subprocesses (git,
# ssh, gh, npm …).  Without it those tools write to /root which is
# ephemeral and shared across profiles.  See issue #4426.
mkdir -p "$HERMES_HOME"/{cron,sessions,logs,hooks,memories,skills,skins,plans,workspace,home}

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

should_start_theviber_dashboard() {
    case "${THEVIBER_HERMES_DASHBOARD_ENABLED:-}" in
        1|true|TRUE|yes|YES|on|ON) ;;
        *) return 1 ;;
    esac
    [ "$#" -ge 3 ] || return 1
    [ "$1" = "gateway" ] || return 1
    [ "$2" = "run" ] || return 1
    [ "$3" = "--replace" ] || return 1
    return 0
}

if should_start_theviber_dashboard "$@"; then
    dashboard_host="${THEVIBER_HERMES_DASHBOARD_HOST:-0.0.0.0}"
    dashboard_port="${THEVIBER_HERMES_DASHBOARD_PORT:-9119}"
    gateway_restart_exit_code="${THEVIBER_HERMES_GATEWAY_RESTART_EXIT_CODE:-75}"
    gateway_cmd=("$@")
    dashboard_args=(dashboard --host "$dashboard_host" --port "$dashboard_port" --no-open)
    case "$dashboard_host" in
        127.0.0.1|localhost|::1) ;;
        *) dashboard_args+=(--insecure) ;;
    esac

    start_gateway() {
        hermes "${gateway_cmd[@]}" &
        gateway_pid=$!
    }

    hermes "${dashboard_args[@]}" &
    dashboard_pid=$!
    start_gateway

    terminate_children() {
        kill "$gateway_pid" "$dashboard_pid" 2>/dev/null || true
    }

    forward_gateway_reload_signal() {
        kill -USR1 "$gateway_pid" 2>/dev/null || true
    }

    trap terminate_children INT TERM
    trap forward_gateway_reload_signal USR1

    while true; do
        set +e
        wait -n "$gateway_pid" "$dashboard_pid"
        wait_status=$?
        set -e

        gateway_alive=1
        dashboard_alive=1
        kill -0 "$gateway_pid" 2>/dev/null || gateway_alive=0
        kill -0 "$dashboard_pid" 2>/dev/null || dashboard_alive=0

        if [ "$gateway_alive" -eq 0 ]; then
            gateway_exit="$wait_status"
            if [ "$gateway_exit" -eq "$gateway_restart_exit_code" ] && [ "$dashboard_alive" -eq 1 ]; then
                start_gateway
                continue
            fi
            terminate_children
            set +e
            wait "$gateway_pid" 2>/dev/null || true
            wait "$dashboard_pid" 2>/dev/null || true
            set -e
            exit "$gateway_exit"
        fi

        if [ "$dashboard_alive" -eq 0 ]; then
            dashboard_exit="$wait_status"
            terminate_children
            set +e
            wait "$gateway_pid" 2>/dev/null || true
            wait "$dashboard_pid" 2>/dev/null || true
            set -e
            exit "$dashboard_exit"
        fi
    done
fi

exec hermes "$@"
