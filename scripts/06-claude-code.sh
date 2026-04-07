#!/bin/bash
# 06-claude-code.sh - Install Node.js 22 LTS, Claude Code CLI, configure git
set -euo pipefail

MAIN_USER="raschagas"
GIT_NAME="raschagas"
GIT_EMAIL="raschagas@users.noreply.github.com"

# --- Node.js 22 LTS via NodeSource ---
echo ">>> Installing Node.js 22 LTS..."
if command -v node &>/dev/null && node --version | grep -q "v22"; then
    echo "    Node.js 22 already installed: $(node --version)"
else
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt install -y nodejs
    echo "    Installed Node.js $(node --version)"
fi

echo "    npm version: $(npm --version)"

# --- Claude Code CLI ---
echo ">>> Installing Claude Code CLI..."
npm install -g @anthropic-ai/claude-code
echo "    Claude Code version: $(claude --version 2>/dev/null || echo 'installed, run claude to verify')"

# --- Git Configuration ---
echo ">>> Configuring git..."
# Global git config for root
git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main

# Git config for main user
HOME_DIR=$(eval echo "~$MAIN_USER")
su - "$MAIN_USER" -c "git config --global user.name '$GIT_NAME'"
su - "$MAIN_USER" -c "git config --global user.email '$GIT_EMAIL'"
su - "$MAIN_USER" -c "git config --global init.defaultBranch main"

echo ">>> Dev tools installed:"
echo "    Node.js: $(node --version)"
echo "    npm: $(npm --version)"
echo "    Claude Code: installed"
echo "    Git: configured for $GIT_NAME"
