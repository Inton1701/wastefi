#!/bin/bash

# WasteFi Uninstall Script
# This script removes WasteFi and restores system to original state

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

INSTALL_DIR="/home/pi/wastefi"

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

uninstall_wastefi() {
    log "Uninstalling WasteFi..."
    
    # Stop and disable services
    systemctl stop wastefi hostapd dnsmasq 2>/dev/null || true
    systemctl disable wastefi hostapd dnsmasq 2>/dev/null || true
    
    # Remove service file
    rm -f /etc/systemd/system/wastefi.service
    systemctl daemon-reload
    
    # Restore config files from backups
    if [[ -d "$INSTALL_DIR/backup" ]]; then
        for backup in "$INSTALL_DIR/backup"/*.backup.*; do
            if [[ -f "$backup" ]]; then
                original=$(basename "$backup" | sed 's/\.backup\..*//')
                case "$original" in
                    "hostapd.conf")
                        cp "$backup" "/etc/hostapd/hostapd.conf"
                        ;;
                    "dnsmasq.conf")
                        cp "$backup" "/etc/dnsmasq.conf"
                        ;;
                    "dhcpcd.conf")
                        cp "$backup" "/etc/dhcpcd.conf"
                        ;;
                esac
                log "Restored $original from backup"
            fi
        done
    fi
    
    # Reset firewall
    "$INSTALL_DIR/scripts/firewall.sh" reset 2>/dev/null || true
    
    # Remove symlinks
    rm -f /usr/local/bin/wastefi-firewall
    
    # Remove installation directory
    rm -rf "$INSTALL_DIR"
    
    # Re-enable wpa_supplicant
    systemctl enable wpa_supplicant.service
    
    log "WasteFi uninstalled successfully"
    
    warning "Please reboot your system to complete the uninstallation"
}

main() {
    check_root
    
    warning "This will completely remove WasteFi and restore your system."
    echo "Are you sure you want to continue? (y/N)"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        uninstall_wastefi
    else
        log "Uninstallation cancelled"
    fi
}

main "$@"