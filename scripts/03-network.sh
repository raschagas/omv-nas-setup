#!/bin/bash
# 03-network.sh - Detect DHCP IP, convert to static, set hostname and DNS
set -euo pipefail

HOSTNAME="omv-nas"
DNS_PRIMARY="192.168.15.10"   # Pi-hole on existing homeserver
DNS_FALLBACK="1.1.1.1"

echo ">>> Detecting primary network interface..."
IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
if [[ -z "$IFACE" ]]; then
    echo "ERROR: No default network interface found"
    exit 1
fi
echo "    Interface: $IFACE"

echo ">>> Detecting current IP configuration..."
CURRENT_IP=$(ip -4 addr show "$IFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
CURRENT_MASK=$(ip -4 addr show "$IFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | cut -d/ -f2)
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)

if [[ -z "$CURRENT_IP" ]]; then
    echo "ERROR: Could not detect current IP"
    exit 1
fi

echo "    Current IP: $CURRENT_IP/$CURRENT_MASK"
echo "    Gateway: $GATEWAY"
echo "    Will set as static"

# Set hostname
echo ">>> Setting hostname to $HOSTNAME..."
hostnamectl set-hostname "$HOSTNAME"
sed -i "s/127\.0\.1\.1.*/127.0.1.1\t$HOSTNAME/" /etc/hosts
if ! grep -q "$HOSTNAME" /etc/hosts; then
    echo "127.0.1.1	$HOSTNAME" >> /etc/hosts
fi

# Configure static IP via /etc/network/interfaces
# OMV manages this file, but we write it directly for initial setup
echo ">>> Configuring static IP..."
cat > /etc/network/interfaces <<EOF
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# Primary network interface - static
auto $IFACE
iface $IFACE inet static
    address $CURRENT_IP/$CURRENT_MASK
    gateway $GATEWAY
    dns-nameservers $DNS_PRIMARY $DNS_FALLBACK
EOF

# Also set DNS in resolv.conf
echo ">>> Configuring DNS..."
cat > /etc/resolv.conf <<EOF
nameserver $DNS_PRIMARY
nameserver $DNS_FALLBACK
EOF

# Apply OMV network config if omv-rpc is available
if command -v omv-rpc &>/dev/null; then
    echo ">>> Syncing with OMV configuration database..."
    omv-salt stage run prepare 2>/dev/null || true
    omv-salt deploy run systemd-networkd 2>/dev/null || true
fi

echo ">>> Network configured:"
echo "    Hostname: $HOSTNAME"
echo "    Static IP: $CURRENT_IP/$CURRENT_MASK"
echo "    Gateway: $GATEWAY"
echo "    DNS: $DNS_PRIMARY, $DNS_FALLBACK"
echo ""
echo "    NOTE: Network changes take effect on next reboot or 'systemctl restart networking'"

# --- Install network autoconfig service (boot-time fallback) ---
echo ">>> Installing nas-net-autoconfig service..."
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

install -m 755 "${REPO_DIR}/config/nas-net-autoconfig.sh" /usr/local/bin/nas-net-autoconfig.sh
install -m 644 "${REPO_DIR}/config/nas-net-autoconfig.service" /etc/systemd/system/nas-net-autoconfig.service

mkdir -p /etc/nas-net-autoconfig
if [ ! -f /etc/nas-net-autoconfig/wifi.conf ]; then
    install -m 600 "${REPO_DIR}/config/wifi.conf" /etc/nas-net-autoconfig/wifi.conf
    echo "    wifi.conf template installed — edit /etc/nas-net-autoconfig/wifi.conf for WiFi fallback"
else
    echo "    wifi.conf already exists, skipping (won't overwrite credentials)"
fi

systemctl daemon-reload
systemctl enable nas-net-autoconfig.service
echo "    nas-net-autoconfig service enabled (boot-time network fallback)"
