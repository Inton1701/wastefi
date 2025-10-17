#!/bin/bash

# WasteFi Network Configuration Script
# Manages ISP connection via wlan1 (WiFi) or eth0 (Ethernet)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CONFIG_DIR="/home/pi/wastefi/config"
WPA_SUPPLICANT_CONF="/etc/wpa_supplicant/wpa_supplicant-wlan1.conf"

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Function to check if interface exists and is up
check_interface() {
    local interface="$1"
    if ip link show "$interface" >/dev/null 2>&1; then
        if ip link show "$interface" | grep -q "state UP"; then
            return 0
        fi
    fi
    return 1
}

# Function to get interface with default route
get_active_wan_interface() {
    local route_info=$(ip route | grep "^default")
    
    if echo "$route_info" | grep -q "wlan1"; then
        echo "wlan1"
    elif echo "$route_info" | grep -q "eth0"; then
        echo "eth0"
    else
        echo "none"
    fi
}

# Function to scan for WiFi networks
scan_wifi() {
    log "Scanning for available WiFi networks..."
    
    # Bring up wlan1 if it exists
    if ip link show wlan1 >/dev/null 2>&1; then
        sudo ip link set wlan1 up
        sleep 2
        
        echo "Available WiFi networks:"
        echo "========================"
        
        # Scan and display networks
        sudo iwlist wlan1 scan 2>/dev/null | grep -E "(ESSID|Quality|Encryption)" | \
        while read -r line; do
            if [[ $line =~ ESSID:\"(.*)\" ]]; then
                ssid="${BASH_REMATCH[1]}"
                if [[ -n "$ssid" ]]; then
                    echo "SSID: $ssid"
                fi
            elif [[ $line =~ Quality=([0-9]+/[0-9]+) ]]; then
                quality="${BASH_REMATCH[1]}"
                echo "  Signal: $quality"
            elif [[ $line =~ Encryption\ key:(on|off) ]]; then
                encryption="${BASH_REMATCH[1]}"
                if [[ "$encryption" == "on" ]]; then
                    echo "  Security: WPA/WPA2"
                else
                    echo "  Security: Open"
                fi
                echo ""
            fi
        done
    else
        error "wlan1 interface not found. Please connect a USB WiFi adapter."
        return 1
    fi
}

# Function to configure WiFi connection
configure_wifi() {
    local ssid="$1"
    local password="$2"
    
    if [[ -z "$ssid" ]]; then
        error "SSID is required"
        return 1
    fi
    
    log "Configuring WiFi connection to: $ssid"
    
    # Create wpa_supplicant configuration
    sudo mkdir -p $(dirname "$WPA_SUPPLICANT_CONF")
    
    cat > /tmp/wpa_supplicant_temp << EOF
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="$ssid"
EOF

    if [[ -n "$password" ]]; then
        echo "    psk=\"$password\"" >> /tmp/wpa_supplicant_temp
    else
        echo "    key_mgmt=NONE" >> /tmp/wpa_supplicant_temp
    fi
    
    echo "}" >> /tmp/wpa_supplicant_temp
    
    # Copy to system location
    sudo cp /tmp/wpa_supplicant_temp "$WPA_SUPPLICANT_CONF"
    rm /tmp/wpa_supplicant_temp
    
    # Enable wpa_supplicant for wlan1
    sudo systemctl enable wpa_supplicant@wlan1.service
    sudo systemctl restart wpa_supplicant@wlan1.service
    
    # Configure dhcpcd for wlan1
    if ! grep -q "interface wlan1" /etc/dhcpcd.conf; then
        sudo tee -a /etc/dhcpcd.conf > /dev/null << EOF

# ISP connection via wlan1
interface wlan1
# Use DHCP
EOF
    fi
    
    log "WiFi configuration complete. Restarting network..."
    sudo systemctl restart dhcpcd
    
    # Wait for connection
    sleep 10
    
    if check_connection "wlan1"; then
        log "WiFi connection successful!"
        return 0
    else
        error "WiFi connection failed"
        return 1
    fi
}

# Function to configure ethernet
configure_ethernet() {
    log "Configuring Ethernet connection..."
    
    # Configure dhcpcd for eth0
    if ! grep -q "interface eth0" /etc/dhcpcd.conf; then
        sudo tee -a /etc/dhcpcd.conf > /dev/null << EOF

# ISP connection via eth0
interface eth0
# Use DHCP (or configure static IP as needed)
# static ip_address=192.168.1.100/24
# static routers=192.168.1.1
# static domain_name_servers=8.8.8.8 8.8.4.4
EOF
    fi
    
    log "Ethernet configuration complete. Restarting network..."
    sudo systemctl restart dhcpcd
    
    # Wait for connection
    sleep 5
    
    if check_connection "eth0"; then
        log "Ethernet connection successful!"
        return 0
    else
        error "Ethernet connection failed"
        return 1
    fi
}

# Function to check internet connection
check_connection() {
    local interface="$1"
    
    # Check if interface has IP
    if ip addr show "$interface" | grep -q "inet.*scope global"; then
        # Check if we can reach the internet
        if ping -I "$interface" -c 2 8.8.8.8 >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# Function to show current network status
show_status() {
    echo "=== WasteFi Network Status ==="
    echo ""
    
    echo "Interfaces:"
    for interface in wlan0 wlan1 eth0; do
        if ip link show "$interface" >/dev/null 2>&1; then
            local status=$(ip link show "$interface" | grep -o "state [A-Z]*" | cut -d' ' -f2)
            local ip=$(ip addr show "$interface" | grep "inet.*scope global" | awk '{print $2}' | head -1)
            echo "  $interface: $status${ip:+ ($ip)}"
        else
            echo "  $interface: Not available"
        fi
    done
    
    echo ""
    echo "Active WAN Interface: $(get_active_wan_interface)"
    
    echo ""
    echo "Default Routes:"
    ip route | grep "^default" || echo "  No default routes found"
    
    echo ""
    echo "Internet Connectivity:"
    if ping -c 2 8.8.8.8 >/dev/null 2>&1; then
        echo "  ✓ Connected to Internet"
    else
        echo "  ✗ No Internet connection"
    fi
}

# Function to switch to WiFi ISP
switch_to_wifi() {
    log "Switching ISP connection to WiFi (wlan1)..."
    
    if [[ ! -f "$WPA_SUPPLICANT_CONF" ]]; then
        warning "No WiFi configuration found. Please configure WiFi first."
        return 1
    fi
    
    # Disable ethernet
    sudo ip link set eth0 down 2>/dev/null || true
    
    # Enable and start WiFi
    sudo systemctl enable wpa_supplicant@wlan1.service
    sudo systemctl start wpa_supplicant@wlan1.service
    sudo ip link set wlan1 up
    
    # Restart networking
    sudo systemctl restart dhcpcd
    
    sleep 10
    
    if check_connection "wlan1"; then
        log "Successfully switched to WiFi ISP connection"
        # Update firewall rules
        /home/pi/wastefi/scripts/firewall.sh setup
        return 0
    else
        error "Failed to switch to WiFi"
        return 1
    fi
}

# Function to switch to Ethernet ISP  
switch_to_ethernet() {
    log "Switching ISP connection to Ethernet (eth0)..."
    
    # Stop WiFi
    sudo systemctl stop wpa_supplicant@wlan1.service 2>/dev/null || true
    sudo ip link set wlan1 down 2>/dev/null || true
    
    # Enable ethernet
    sudo ip link set eth0 up
    
    # Restart networking
    sudo systemctl restart dhcpcd
    
    sleep 5
    
    if check_connection "eth0"; then
        log "Successfully switched to Ethernet ISP connection"
        # Update firewall rules
        /home/pi/wastefi/scripts/firewall.sh setup
        return 0
    else
        error "Failed to switch to Ethernet"
        return 1
    fi
}

# Function to auto-detect and configure best connection
auto_configure() {
    log "Auto-detecting best ISP connection..."
    
    # First try ethernet if cable is connected
    if ip link show eth0 >/dev/null 2>&1; then
        sudo ip link set eth0 up
        sleep 3
        
        if check_connection "eth0"; then
            log "Ethernet connection detected and working"
            switch_to_ethernet
            return 0
        fi
    fi
    
    # Try WiFi if configured
    if [[ -f "$WPA_SUPPLICANT_CONF" ]] && ip link show wlan1 >/dev/null 2>&1; then
        if switch_to_wifi; then
            return 0
        fi
    fi
    
    warning "No working ISP connection found"
    warning "Please configure WiFi or connect Ethernet cable"
    return 1
}

# Main function
main() {
    case "$1" in
        scan)
            scan_wifi
            ;;
        wifi)
            if [[ -z "$2" ]]; then
                error "Usage: $0 wifi <SSID> [PASSWORD]"
                exit 1
            fi
            configure_wifi "$2" "$3"
            ;;
        ethernet)
            configure_ethernet
            ;;
        switch-wifi)
            switch_to_wifi
            ;;
        switch-ethernet)
            switch_to_ethernet
            ;;
        auto)
            auto_configure
            ;;
        status)
            show_status
            ;;
        *)
            echo "WasteFi Network Configuration Manager"
            echo ""
            echo "Usage: $0 {scan|wifi|ethernet|switch-wifi|switch-ethernet|auto|status}"
            echo ""
            echo "Commands:"
            echo "  scan                    Scan for available WiFi networks"
            echo "  wifi <SSID> [PASSWORD] Configure WiFi ISP connection"
            echo "  ethernet                Configure Ethernet ISP connection"
            echo "  switch-wifi            Switch to WiFi ISP (wlan1)"
            echo "  switch-ethernet        Switch to Ethernet ISP (eth0)"
            echo "  auto                   Auto-detect and configure best connection"
            echo "  status                 Show current network status"
            echo ""
            echo "Examples:"
            echo "  $0 scan"
            echo "  $0 wifi \"MyISP-WiFi\" \"password123\""
            echo "  $0 ethernet"
            echo "  $0 auto"
            echo "  $0 status"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"