#!/bin/bash
# 07-monitoring.sh - SMART monitoring and basic system monitoring
set -euo pipefail

echo ">>> Configuring SMART monitoring..."

# Ensure smartmontools is installed
apt install -y smartmontools

# Enable and start smartd
systemctl enable smartmontools 2>/dev/null || systemctl enable smartd 2>/dev/null || true
systemctl start smartmontools 2>/dev/null || systemctl start smartd 2>/dev/null || true

# Configure smartd for all drives
cat > /etc/smartd.conf <<'EOF'
# Monitor all drives, run short self-test weekly (Sun 2am), long monthly (1st Sun 3am)
# Send warnings to syslog
DEVICESCAN -d removable -n standby -m root -M exec /usr/share/smartmontools/smartd-runner -s (S/../../7/02|L/../01/./03) -W 4,45,55
EOF

systemctl restart smartmontools 2>/dev/null || systemctl restart smartd 2>/dev/null || true

# Enable SMART monitoring in OMV if available
if command -v omv-rpc &>/dev/null; then
    echo ">>> Enabling SMART monitoring in OMV..."
    omv-rpc -u admin "Smart" "set" '{"enable":true,"interval":1800,"powermode":0,"tempdiff":0,"tempinfo":0,"tempcrit":0}' 2>/dev/null || {
        echo "    SMART RPC call failed - configure via web UI"
    }
    omv-salt deploy run smartmontools 2>/dev/null || true
fi

# --- System monitoring tools ---
echo ">>> Detecting sensors..."
sensors-detect --auto 2>/dev/null || true

echo ">>> Monitoring configured:"
echo "    SMART: enabled, weekly short test, monthly long test"
echo "    Sensors: detected"
echo "    Logs: /var/log/syslog, journalctl"
