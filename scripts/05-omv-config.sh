#!/bin/bash
# 05-omv-config.sh - Enable SMB and NFS services in OMV
set -euo pipefail

# Check if OMV is available
if ! command -v omv-rpc &>/dev/null; then
    echo "WARNING: omv-rpc not found. OMV may not be installed."
    echo "    SMB/NFS will need to be enabled manually via web UI."
    exit 0
fi

echo ">>> Enabling SMB/CIFS service..."
# Enable SMB via OMV RPC
omv-rpc -u admin "SMB" "set" '{"enable":true,"workgroup":"WORKGROUP","serverstring":"%h - OMV NAS","loglevel":0,"usesendfile":true,"aio":true,"nullpasswords":false,"localmaster":false,"timeserver":false,"winssupport":false,"winsserver":"","homesenable":false,"homesbrowseable":true,"extraoptions":""}' 2>/dev/null || {
    echo "    SMB RPC call failed - will configure via web UI"
}

echo ">>> Enabling NFS service..."
# Enable NFS via OMV RPC
omv-rpc -u admin "NFS" "set" '{"enable":true,"numproc":8}' 2>/dev/null || {
    echo "    NFS RPC call failed - will configure via web UI"
}

echo ">>> Applying OMV configuration..."
omv-salt stage run prepare 2>/dev/null || true
omv-salt deploy run samba 2>/dev/null || true
omv-salt deploy run nfs 2>/dev/null || true

echo ">>> SMB and NFS services configured"
echo "    Shares will be created when HDDs are connected (run 08-hdd-setup.sh)"
