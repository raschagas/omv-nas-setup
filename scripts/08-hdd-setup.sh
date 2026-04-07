#!/bin/bash
# 08-hdd-setup.sh - HDD setup: format, mount, create shares, configure SMB/NFS
# Run this script MANUALLY when the 2x4TB HDDs arrive
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MAIN_USER="raschagas"
LAN_SUBNET="192.168.15.0/24"

echo -e "${CYAN}=========================================${NC}"
echo -e "${CYAN}  HDD Setup - 2x4TB Configuration${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""

# --- Detect SATA drives ---
echo -e "${GREEN}>>> Detecting SATA drives...${NC}"
SATA_DRIVES=()
for disk in /dev/sd?; do
    if [[ -b "$disk" ]]; then
        SIZE=$(lsblk -bno SIZE "$disk" 2>/dev/null | head -1)
        SIZE_TB=$(echo "scale=2; $SIZE / 1000000000000" | bc 2>/dev/null || echo "unknown")
        MODEL=$(lsblk -no MODEL "$disk" 2>/dev/null | head -1 | xargs)
        echo "    Found: $disk - ${SIZE_TB}TB - $MODEL"
        SATA_DRIVES+=("$disk")
    fi
done

if [[ ${#SATA_DRIVES[@]} -lt 2 ]]; then
    echo -e "${RED}ERROR: Expected 2 SATA drives, found ${#SATA_DRIVES[@]}${NC}"
    echo "Connect both 4TB drives and try again."
    exit 1
fi

DISK_DATA="${SATA_DRIVES[0]}"
DISK_BACKUP="${SATA_DRIVES[1]}"

echo ""
echo -e "${YELLOW}>>> Drive assignment:${NC}"
echo "    Disk 1 (data):   $DISK_DATA"
echo "    Disk 2 (backup): $DISK_BACKUP"
echo ""
echo -e "${RED}WARNING: This will ERASE ALL DATA on both drives!${NC}"
read -p "Continue? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborted."
    exit 0
fi

# --- Format drives ---
echo -e "${GREEN}>>> Creating partitions and formatting...${NC}"

for disk in "$DISK_DATA" "$DISK_BACKUP"; do
    echo "    Partitioning $disk..."
    # Create GPT partition table and single partition
    parted -s "$disk" mklabel gpt
    parted -s "$disk" mkpart primary ext4 0% 100%
    sleep 2

    PART="${disk}1"
    echo "    Formatting $PART as ext4..."
    mkfs.ext4 -F -L "$(basename "$disk")-storage" "$PART"
done

# Label drives
e2label "${DISK_DATA}1" "data"
e2label "${DISK_BACKUP}1" "backup"

# --- Mount drives ---
echo -e "${GREEN}>>> Mounting drives...${NC}"
DATA_MOUNT="/srv/data"
BACKUP_MOUNT="/srv/backup"

mkdir -p "$DATA_MOUNT" "$BACKUP_MOUNT"

# Add to fstab if not already there
DATA_UUID=$(blkid -s UUID -o value "${DISK_DATA}1")
BACKUP_UUID=$(blkid -s UUID -o value "${DISK_BACKUP}1")

if ! grep -q "$DATA_UUID" /etc/fstab; then
    echo "UUID=$DATA_UUID $DATA_MOUNT ext4 defaults,noatime 0 2" >> /etc/fstab
fi
if ! grep -q "$BACKUP_UUID" /etc/fstab; then
    echo "UUID=$BACKUP_UUID $BACKUP_MOUNT ext4 defaults,noatime 0 2" >> /etc/fstab
fi

mount -a

# --- Create directory structure ---
echo -e "${GREEN}>>> Creating directory structure...${NC}"

# Data drive folders
FOLDERS=("media" "nextcloud" "documents" "downloads" "public")
for folder in "${FOLDERS[@]}"; do
    mkdir -p "$DATA_MOUNT/$folder"
    chown "$MAIN_USER:users" "$DATA_MOUNT/$folder"
    chmod 775 "$DATA_MOUNT/$folder"
    echo "    Created $DATA_MOUNT/$folder"
done

# Media subfolders
mkdir -p "$DATA_MOUNT/media"/{movies,tv,music,books,photos}
chown -R "$MAIN_USER:users" "$DATA_MOUNT/media"

# Backup drive mirrors critical folders
BACKUP_FOLDERS=("nextcloud" "documents")
for folder in "${BACKUP_FOLDERS[@]}"; do
    mkdir -p "$BACKUP_MOUNT/$folder"
    chown "$MAIN_USER:users" "$BACKUP_MOUNT/$folder"
    chmod 775 "$BACKUP_MOUNT/$folder"
    echo "    Created $BACKUP_MOUNT/$folder"
done

# --- Configure SMB shares ---
echo -e "${GREEN}>>> Configuring SMB shares...${NC}"

# Write Samba config additions
cat >> /etc/samba/smb.conf <<EOF

# OMV NAS Shares - Auto-configured
[media]
    path = $DATA_MOUNT/media
    browseable = yes
    read only = no
    valid users = $MAIN_USER
    create mask = 0664
    directory mask = 0775

[documents]
    path = $DATA_MOUNT/documents
    browseable = yes
    read only = no
    valid users = $MAIN_USER
    create mask = 0664
    directory mask = 0775

[downloads]
    path = $DATA_MOUNT/downloads
    browseable = yes
    read only = no
    valid users = $MAIN_USER
    create mask = 0664
    directory mask = 0775

[public]
    path = $DATA_MOUNT/public
    browseable = yes
    read only = no
    guest ok = yes
    create mask = 0664
    directory mask = 0775

[nextcloud]
    path = $DATA_MOUNT/nextcloud
    browseable = yes
    read only = no
    valid users = $MAIN_USER
    create mask = 0664
    directory mask = 0775
EOF

# Set SMB password for main user
echo -e "${YELLOW}>>> Setting SMB password for $MAIN_USER...${NC}"
(echo "Openmediavault@2026!"; echo "Openmediavault@2026!") | smbpasswd -a "$MAIN_USER" -s

systemctl restart smbd 2>/dev/null || systemctl restart smb 2>/dev/null || true

# --- Configure NFS exports ---
echo -e "${GREEN}>>> Configuring NFS exports...${NC}"

cat >> /etc/exports <<EOF

# OMV NAS Exports - Auto-configured
$DATA_MOUNT/media      $LAN_SUBNET(rw,sync,no_subtree_check,no_root_squash)
$DATA_MOUNT/documents  $LAN_SUBNET(rw,sync,no_subtree_check,no_root_squash)
$DATA_MOUNT/downloads  $LAN_SUBNET(rw,sync,no_subtree_check,no_root_squash)
$DATA_MOUNT/public     $LAN_SUBNET(rw,sync,no_subtree_check,no_root_squash)
$DATA_MOUNT/nextcloud  $LAN_SUBNET(rw,sync,no_subtree_check,no_root_squash)
EOF

exportfs -ra

# --- Setup backup cron ---
echo -e "${GREEN}>>> Setting up daily backup (rsync critical files)...${NC}"

cat > /etc/cron.daily/backup-critical <<'CRONEOF'
#!/bin/bash
# Daily backup: critical folders from data -> backup drive
LOG="/var/log/backup-critical.log"
echo "$(date) - Starting backup" >> "$LOG"

rsync -avh --delete /srv/data/nextcloud/ /srv/backup/nextcloud/ >> "$LOG" 2>&1
rsync -avh --delete /srv/data/documents/ /srv/backup/documents/ >> "$LOG" 2>&1

echo "$(date) - Backup complete" >> "$LOG"
CRONEOF
chmod +x /etc/cron.daily/backup-critical

# --- SMART tests ---
echo -e "${GREEN}>>> Scheduling SMART tests...${NC}"
# Short test every Sunday at 2 AM, Long test first Sunday at 3 AM
# (already configured in 07-monitoring.sh via smartd.conf, but ensure drives are monitored)
for disk in "$DISK_DATA" "$DISK_BACKUP"; do
    smartctl -s on "$disk" 2>/dev/null || true
done

echo ""
echo -e "${CYAN}=========================================${NC}"
echo -e "${CYAN}  HDD Setup Complete!${NC}"
echo -e "${CYAN}=========================================${NC}"
echo ""
echo "  Data drive:   $DATA_MOUNT (UUID: $DATA_UUID)"
echo "  Backup drive: $BACKUP_MOUNT (UUID: $BACKUP_UUID)"
echo ""
echo "  SMB shares: media, documents, downloads, public, nextcloud"
echo "  NFS exports: all folders exported to $LAN_SUBNET"
echo "  Backup cron: daily rsync of nextcloud + documents to backup drive"
echo ""
echo -e "${YELLOW}  REMINDER: Set up offsite backup for critical files!${NC}"
echo "  Options: rclone to cloud, rsync to remote server, duplicati, etc."
