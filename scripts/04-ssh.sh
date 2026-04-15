#!/bin/bash
# 04-ssh.sh - SSH hardening, key import, fail2ban, UFW firewall
set -euo pipefail

MAIN_USER="raschagas"
SSH_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJxEbHyQ9AjQ8cL2zowwoaYc2OyJMbzVWW9b/bOqoG9I rasch@laptop"

# --- Ensure SSH server is installed ---
echo ">>> Installing openssh-server..."
apt install -y openssh-server
systemctl enable ssh

# --- SSH Key Setup ---
echo ">>> Setting up SSH keys..."
for user in "$MAIN_USER" root; do
    if id "$user" &>/dev/null; then
        HOME_DIR=$(eval echo "~$user")
        SSH_DIR="$HOME_DIR/.ssh"
        AUTH_KEYS="$SSH_DIR/authorized_keys"

        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"

        if ! grep -qF "$SSH_PUBKEY" "$AUTH_KEYS" 2>/dev/null; then
            echo "$SSH_PUBKEY" >> "$AUTH_KEYS"
            echo "    Added key for $user"
        else
            echo "    Key already exists for $user"
        fi

        chmod 600 "$AUTH_KEYS"
        chown -R "$user:$(id -gn "$user")" "$SSH_DIR"
    fi
done

# --- SSH Hardening ---
echo ">>> Hardening SSH configuration..."
SSHD_CONFIG="/etc/ssh/sshd_config"
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak"

# Apply hardened settings
declare -A SSH_SETTINGS=(
    ["PermitRootLogin"]="prohibit-password"
    ["PasswordAuthentication"]="yes"
    ["PubkeyAuthentication"]="yes"
    ["MaxAuthTries"]="5"
    ["MaxSessions"]="10"
    ["X11Forwarding"]="no"
    ["AllowAgentForwarding"]="yes"
    ["ClientAliveInterval"]="300"
    ["ClientAliveCountMax"]="3"
)

for key in "${!SSH_SETTINGS[@]}"; do
    value="${SSH_SETTINGS[$key]}"
    if grep -qE "^#?${key}\s" "$SSHD_CONFIG"; then
        sed -i "s/^#*${key}\s.*/${key} ${value}/" "$SSHD_CONFIG"
    else
        echo "${key} ${value}" >> "$SSHD_CONFIG"
    fi
done

# Restart SSH
systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true

# --- Fail2ban ---
echo ">>> Installing and configuring fail2ban..."
apt install -y fail2ban

cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
backend = systemd

[sshd]
enabled = true
port = ssh
filter = sshd
maxretry = 5
bantime = 1h
EOF

systemctl enable fail2ban
systemctl restart fail2ban

# --- UFW Firewall ---
echo ">>> Configuring UFW firewall..."
apt install -y ufw

# Reset and configure
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# SSH
ufw allow 22/tcp comment 'SSH'
# OMV Web UI
ufw allow 80/tcp comment 'OMV Web UI'
ufw allow 443/tcp comment 'HTTPS'
# SMB
ufw allow 139/tcp comment 'SMB NetBIOS'
ufw allow 445/tcp comment 'SMB'
# NFS
ufw allow 111 comment 'NFS portmapper'
ufw allow 2049 comment 'NFS'
# Allow mDNS for local discovery
ufw allow 5353/udp comment 'mDNS/Avahi'

# Enable
ufw --force enable

echo ">>> SSH, fail2ban, and UFW configured successfully"
echo "    SSH: key-based auth enabled, root login via key only"
echo "    Fail2ban: 5 retries, 1h ban"
echo "    UFW: SSH(22), HTTP(80), HTTPS(443), SMB(139,445), NFS(111,2049)"
