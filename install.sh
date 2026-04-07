#!/bin/bash
# OMV NAS Setup - Master Installer
# Runs all configuration scripts sequentially
# Usage: bash install.sh [--skip N] to skip first N scripts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/root/omv-setup.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING:${NC} $*" | tee -a "$LOG_FILE"; }
err() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $*" | tee -a "$LOG_FILE"; }

# Check root
if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root"
    exit 1
fi

# Check we're on a Debian-based system
if ! command -v apt &>/dev/null; then
    err "This script requires a Debian-based system (apt not found)"
    exit 1
fi

# Parse skip argument
SKIP=${1:-0}
if [[ "$SKIP" == "--skip" ]]; then
    SKIP=${2:-0}
fi

log "========================================="
log "OMV NAS Setup - Starting installation"
log "========================================="
log "Log file: $LOG_FILE"

SCRIPTS=(
    "01-base.sh"
    "02-user.sh"
    "03-network.sh"
    "04-ssh.sh"
    "05-omv-config.sh"
    "06-claude-code.sh"
    "07-monitoring.sh"
)

TOTAL=${#SCRIPTS[@]}
COUNT=0

for script in "${SCRIPTS[@]}"; do
    COUNT=$((COUNT + 1))

    if [[ $COUNT -le $SKIP ]]; then
        log "[$COUNT/$TOTAL] Skipping $script"
        continue
    fi

    SCRIPT_PATH="$SCRIPT_DIR/scripts/$script"
    if [[ ! -f "$SCRIPT_PATH" ]]; then
        warn "[$COUNT/$TOTAL] Script not found: $script - skipping"
        continue
    fi

    log "[$COUNT/$TOTAL] Running $script..."
    if bash "$SCRIPT_PATH" 2>&1 | tee -a "$LOG_FILE"; then
        log "[$COUNT/$TOTAL] $script completed successfully"
    else
        err "[$COUNT/$TOTAL] $script failed with exit code $?"
        warn "Continuing with next script..."
    fi
done

log "========================================="
log "OMV NAS Setup - Installation complete!"
log "========================================="
log ""
log "Next steps:"
log "  1. Access OMV web UI at http://$(hostname -I | awk '{print $1}')"
log "     Default login: admin / openmediavault"
log "  2. SSH: ssh raschagas@$(hostname -I | awk '{print $1}')"
log "  3. When HDDs arrive, run: bash $SCRIPT_DIR/scripts/08-hdd-setup.sh"
log ""
log "Full log: $LOG_FILE"
