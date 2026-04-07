#!/bin/bash
# 01-base.sh - System foundations: update, upgrade, essential packages
set -euo pipefail

echo ">>> Updating package lists..."
apt update

echo ">>> Upgrading all packages..."
apt full-upgrade -y

echo ">>> Installing essential packages..."
apt install -y \
    git \
    curl \
    wget \
    htop \
    tmux \
    vim \
    net-tools \
    lsb-release \
    gnupg \
    ca-certificates \
    sudo \
    ufw \
    jq \
    unzip \
    rsync \
    smartmontools \
    hdparm \
    lm-sensors \
    iotop \
    ncdu

echo ">>> Base packages installed successfully"
