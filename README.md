# OMV NAS Setup

Automated setup scripts for OpenMediaVault 7 NAS.

**Hardware:** ASRock B760M-ITX/D4 WiFi | Intel i3-12100F | 256GB NVMe (OS) | 2x4TB HDD (data + backup)

## Quick Start

After installing OMV from USB, run:

```bash
apt install -y git
git clone https://github.com/raschagas/omv-nas-setup /root/omv-nas-setup
bash /root/omv-nas-setup/install.sh
```

## What It Does

| Script | Purpose |
|--------|---------|
| `01-base.sh` | System update + essential packages |
| `02-user.sh` | Create users (raschagas, raschagasNAS) |
| `03-network.sh` | Convert DHCP to static IP, set hostname + DNS |
| `04-ssh.sh` | SSH hardening, key auth, fail2ban, UFW firewall |
| `05-omv-config.sh` | Enable SMB + NFS services in OMV |
| `06-claude-code.sh` | Node.js 22 + Claude Code CLI + git config |
| `07-monitoring.sh` | SMART monitoring + sensors |
| `08-hdd-setup.sh` | **Run manually when HDDs arrive** |

## When HDDs Arrive

```bash
bash /root/omv-nas-setup/scripts/08-hdd-setup.sh
```

This will:
- Format both 4TB drives (ext4)
- Mount as `/srv/data` and `/srv/backup`
- Create shares: media, nextcloud, documents, downloads, public
- Configure SMB + NFS for LAN access
- Set up daily rsync backup (critical files)
- Enable SMART health checks

## Storage Layout

```
Disk 1 (data):     media/ nextcloud/ documents/ downloads/ public/
Disk 2 (backup):   nextcloud/ documents/ (daily rsync from Disk 1)
Offsite:           Set up separately for critical files
```

## Access

- **Web UI:** http://<nas-ip> (admin / openmediavault)
- **SSH:** `ssh raschagas@<nas-ip>`
- **SMB:** `\\<nas-ip>\media`, `\\<nas-ip>\documents`, etc.
- **NFS:** `<nas-ip>:/srv/data/media`, etc.
