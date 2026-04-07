#!/usr/bin/env bash
# nas-net-autoconfig.sh — Hardware-independent network bootstrap for OMV NAS
# Runs every boot as systemd oneshot. Detects NICs from /sys/class/net/,
# picks the fastest wired link, falls back to WiFi, runs DHCP.
# Never writes to /etc/network/interfaces (OMV's territory).
set -euo pipefail

GUARD_DIR="/run/nas-net-autoconfig"
GUARD_FILE="${GUARD_DIR}/active"
WIFI_CONF="/etc/nas-net-autoconfig/wifi.conf"
LOG_TAG="nas-net-autoconfig"

log() { logger -t "$LOG_TAG" "$*"; echo "$*"; }

# --- Guard: already ran this boot ---
if [ -f "$GUARD_FILE" ]; then
    log "Guard file exists, already ran this boot. Exiting."
    exit 0
fi

# --- Guard: OMV managing a working interface? ---
omv_has_working_iface() {
    local iface_file="/etc/network/interfaces"
    [ -f "$iface_file" ] || return 1

    # Extract non-lo iface names configured by OMV
    local ifaces
    ifaces=$(grep -E '^iface\s+' "$iface_file" | awk '{print $2}' | grep -v '^lo$' || true)
    [ -z "$ifaces" ] && return 1

    for iface in $ifaces; do
        # Check if this interface exists and has an IP
        if ip -4 addr show dev "$iface" 2>/dev/null | grep -q 'inet '; then
            log "OMV interface $iface has an IP. Nothing to do."
            return 0
        fi
    done
    return 1
}

if omv_has_working_iface; then
    mkdir -p "$GUARD_DIR"
    touch "$GUARD_FILE"
    exit 0
fi

# --- Enumerate physical NICs ---
declare -a wired=()
declare -a wifi=()

for net_dir in /sys/class/net/*/; do
    iface=$(basename "$net_dir")

    # Skip virtual interfaces
    case "$iface" in
        lo|br*|veth*|docker*|tun*|tap*|virbr*) continue ;;
    esac

    # Must have a /device dir (physical device)
    [ -d "/sys/class/net/${iface}/device" ] || continue

    iface_type=$(cat "/sys/class/net/${iface}/type" 2>/dev/null || echo "0")

    case "$iface_type" in
        1)   wired+=("$iface") ;;
        801) wifi+=("$iface") ;;
    esac
done

log "Detected wired NICs: ${wired[*]:-none}"
log "Detected WiFi NICs: ${wifi[*]:-none}"

if [ ${#wired[@]} -eq 0 ] && [ ${#wifi[@]} -eq 0 ]; then
    log "ERROR: No physical network interfaces found."
    exit 1
fi

# --- Wired: bring up, check carrier, pick fastest ---
chosen=""
chosen_speed=0

for iface in "${wired[@]}"; do
    log "Bringing up $iface..."
    ip link set "$iface" up 2>/dev/null || continue

    # Poll for carrier up to 5 seconds
    carrier=0
    for i in $(seq 1 10); do
        if [ "$(cat /sys/class/net/${iface}/carrier 2>/dev/null)" = "1" ]; then
            carrier=1
            break
        fi
        sleep 0.5
    done

    if [ "$carrier" -eq 0 ]; then
        log "$iface: no carrier detected."
        ip link set "$iface" down 2>/dev/null || true
        continue
    fi

    speed=$(cat "/sys/class/net/${iface}/speed" 2>/dev/null || echo "0")
    # Kernel reports -1 for unknown speed
    [ "$speed" -lt 0 ] 2>/dev/null && speed=0
    log "$iface: carrier up, speed=${speed}Mbps"

    if [ "$speed" -gt "$chosen_speed" ] || \
       { [ "$speed" -eq "$chosen_speed" ] && [ -z "$chosen" ]; }; then
        # Release previous chosen if any
        if [ -n "$chosen" ] && [ "$chosen" != "$iface" ]; then
            ip link set "$chosen" down 2>/dev/null || true
        fi
        chosen="$iface"
        chosen_speed="$speed"
    else
        ip link set "$iface" down 2>/dev/null || true
    fi
done

# --- WiFi fallback ---
if [ -z "$chosen" ] && [ ${#wifi[@]} -gt 0 ]; then
    log "No wired carrier. Attempting WiFi fallback..."

    if [ ! -f "$WIFI_CONF" ]; then
        log "ERROR: WiFi fallback requested but $WIFI_CONF not found."
    elif ! command -v wpa_supplicant &>/dev/null; then
        log "ERROR: wpa_supplicant not installed."
    else
        wifi_iface="${wifi[0]}"
        log "Starting wpa_supplicant on $wifi_iface..."
        ip link set "$wifi_iface" up 2>/dev/null || true
        wpa_supplicant -B -i "$wifi_iface" -c "$WIFI_CONF" \
            -P "/run/nas-net-autoconfig/wpa_${wifi_iface}.pid" 2>/dev/null || true

        # Wait up to 30 seconds for association
        for i in $(seq 1 60); do
            if iw dev "$wifi_iface" link 2>/dev/null | grep -q 'Connected'; then
                log "$wifi_iface: WiFi associated."
                chosen="$wifi_iface"
                break
            fi
            sleep 0.5
        done

        if [ -z "$chosen" ]; then
            log "ERROR: WiFi association failed on $wifi_iface."
            # Clean up wpa_supplicant
            pid_file="/run/nas-net-autoconfig/wpa_${wifi_iface}.pid"
            if [ -f "$pid_file" ]; then
                kill "$(cat "$pid_file")" 2>/dev/null || true
                rm -f "$pid_file"
            fi
            ip link set "$wifi_iface" down 2>/dev/null || true
        fi
    fi
fi

if [ -z "$chosen" ]; then
    log "ERROR: No interface could be brought up."
    exit 1
fi

# --- DHCP on chosen interface ---
log "Running DHCP on $chosen..."

dhcp_ok=0
if command -v dhclient &>/dev/null; then
    dhclient -1 -timeout 30 \
        -lf "/run/nas-net-autoconfig/dhclient.${chosen}.lease" \
        -pf "/run/nas-net-autoconfig/dhclient.${chosen}.pid" \
        "$chosen" 2>&1 && dhcp_ok=1
fi

if [ "$dhcp_ok" -eq 0 ] && command -v dhcpcd &>/dev/null; then
    log "dhclient failed or not found, trying dhcpcd..."
    dhcpcd -1 -t 30 "$chosen" 2>/dev/null && dhcp_ok=1
fi

if [ "$dhcp_ok" -eq 0 ]; then
    log "ERROR: DHCP failed on $chosen."
    exit 1
fi

# Show result
ip_addr=$(ip -4 addr show dev "$chosen" | grep -oP 'inet \K[0-9.]+' | head -1)
log "SUCCESS: $chosen has IP $ip_addr"

# --- Write guard file ---
mkdir -p "$GUARD_DIR"
touch "$GUARD_FILE"
exit 0
