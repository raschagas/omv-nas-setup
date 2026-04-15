#!/bin/bash
# 02-user.sh - Create users and configure passwords
set -euo pipefail

MAIN_USER="raschagas"
MAIN_PASS="Openmediavault@2026!"

create_user() {
    local username="$1"
    local password="$2"
    local groups="$3"

    if id "$username" &>/dev/null; then
        echo ">>> User $username already exists, updating password..."
        echo "$username:$password" | chpasswd
    else
        echo ">>> Creating user $username..."
        useradd -m -s /bin/bash "$username"
        echo "$username:$password" | chpasswd
    fi

    for group in $groups; do
        if getent group "$group" &>/dev/null; then
            usermod -aG "$group" "$username"
            echo "    Added $username to group $group"
        fi
    done
}

# Create main user
create_user "$MAIN_USER" "$MAIN_PASS" "sudo users ssh"

# Ensure sudo group has NOPASSWD (optional, remove if you want password prompts)
if ! grep -q "^%sudo.*NOPASSWD" /etc/sudoers; then
    echo ">>> Configuring sudo group..."
    sed -i 's/^%sudo.*ALL=(ALL:ALL) ALL/%sudo   ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers
fi

echo ">>> User configured: $MAIN_USER"
