#!/bin/bash

# WasteFi Firewall Management Script
# This script sets up and manages iptables rules for the captive portal

# Auto-detect WAN interface (prefer wlan1, fallback to eth0)
detect_wan_interface() {
    if ip link show wlan1 >/dev/null 2>&1 && ip route | grep -q "default.*wlan1"; then
        echo "wlan1"
    elif ip link show eth0 >/dev/null 2>&1 && ip route | grep -q "default.*eth0"; then
        echo "eth0"
    elif ip link show wlan1 >/dev/null 2>&1; then
        echo "wlan1"
    elif ip link show eth0 >/dev/null 2>&1; then
        echo "eth0"
    else
        echo "eth0"  # fallback
    fi
}

INTERFACE_WAN=$(detect_wan_interface)
INTERFACE_WLAN="wlan0"    # WiFi AP interface (built-in)
CAPTIVE_PORTAL_IP="192.168.4.1"  # AP IP address
PORTAL_PORT="80"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to setup initial firewall rules
setup_firewall() {
    log "Setting up WasteFi firewall rules..."
    log "Detected WAN interface: $INTERFACE_WAN"
    log "Using AP interface: $INTERFACE_WLAN"
    
    # Flush existing rules
    iptables -F
    iptables -t nat -F
    iptables -t mangle -F
    
    # Set default policies
    iptables -P INPUT ACCEPT
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT
    
    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    
    # Allow established and related connections
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    
    # Allow SSH (be careful with this in production)
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    
    # Allow DHCP
    iptables -A INPUT -p udp --dport 67:68 -j ACCEPT
    iptables -A OUTPUT -p udp --dport 67:68 -j ACCEPT
    
    # Allow DNS queries to the local server
    iptables -A INPUT -p udp --dport 53 -j ACCEPT
    iptables -A INPUT -p tcp --dport 53 -j ACCEPT
    
    # Allow web server for captive portal
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT
    
    # NAT rules for internet sharing
    iptables -t nat -A POSTROUTING -o $INTERFACE_WAN -j MASQUERADE
    
    # Redirect HTTP requests to captive portal
    iptables -t nat -A PREROUTING -i $INTERFACE_WLAN -p tcp --dport 80 \
        -j DNAT --to-destination $CAPTIVE_PORTAL_IP:$PORTAL_PORT
    
    # Redirect HTTPS requests to captive portal (HTTP)
    iptables -t nat -A PREROUTING -i $INTERFACE_WLAN -p tcp --dport 443 \
        -j DNAT --to-destination $CAPTIVE_PORTAL_IP:$PORTAL_PORT
    
    # Block all forwarding by default (clients have no internet access initially)
    iptables -A FORWARD -i $INTERFACE_WLAN -o $INTERFACE_WAN -j DROP
    iptables -A FORWARD -i $INTERFACE_WAN -o $INTERFACE_WLAN -j DROP
    
    # Allow local communication for captive portal
    iptables -A FORWARD -i $INTERFACE_WLAN -d $CAPTIVE_PORTAL_IP -j ACCEPT
    
    log "Firewall rules setup complete"
}

# Function to grant internet access to a specific IP
grant_access() {
    local client_ip="$1"
    
    if [[ -z "$client_ip" ]]; then
        error "No IP address provided"
        return 1
    fi
    
    # Check if IP is valid
    if ! [[ $client_ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        error "Invalid IP address format: $client_ip"
        return 1
    fi
    
    log "Granting internet access to $client_ip"
    
    # Insert rules at the beginning to take precedence
    iptables -I FORWARD 1 -s $client_ip -o $INTERFACE_WAN -j ACCEPT
    iptables -I FORWARD 1 -d $client_ip -i $INTERFACE_WAN -j ACCEPT
    
    log "Access granted to $client_ip"
}

# Function to revoke internet access from a specific IP
revoke_access() {
    local client_ip="$1"
    
    if [[ -z "$client_ip" ]]; then
        error "No IP address provided"
        return 1
    fi
    
    log "Revoking internet access from $client_ip"
    
    # Remove rules for this IP
    iptables -D FORWARD -s $client_ip -o $INTERFACE_WAN -j ACCEPT 2>/dev/null
    iptables -D FORWARD -d $client_ip -i $INTERFACE_WAN -j ACCEPT 2>/dev/null
    
    log "Access revoked from $client_ip"
}

# Function to list all clients with internet access
list_access() {
    log "Clients with internet access:"
    
    iptables -L FORWARD -n --line-numbers | grep ACCEPT | grep $INTERFACE_WAN | while read line; do
        if [[ $line =~ ([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}) ]]; then
            echo "  - ${BASH_REMATCH[1]}"
        fi
    done
}

# Function to save iptables rules
save_rules() {
    log "Saving iptables rules..."
    
    if command -v iptables-save >/dev/null 2>&1; then
        iptables-save > /etc/iptables/rules.v4
        log "Rules saved to /etc/iptables/rules.v4"
    else
        warning "iptables-persistent not installed, rules will not persist after reboot"
    fi
}

# Function to restore iptables rules
restore_rules() {
    log "Restoring iptables rules..."
    
    if [[ -f /etc/iptables/rules.v4 ]]; then
        iptables-restore < /etc/iptables/rules.v4
        log "Rules restored from /etc/iptables/rules.v4"
    else
        warning "No saved rules found, setting up default rules"
        setup_firewall
    fi
}

# Function to reset all rules
reset_firewall() {
    log "Resetting firewall rules..."
    
    iptables -F
    iptables -t nat -F
    iptables -t mangle -F
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    
    log "Firewall reset complete"
}

# Function to show current rules
show_rules() {
    echo "=== FILTER TABLE ==="
    iptables -L -n --line-numbers
    echo ""
    echo "=== NAT TABLE ==="
    iptables -t nat -L -n --line-numbers
}

# Function to enable IP forwarding
enable_forwarding() {
    log "Enabling IP forwarding..."
    
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # Make it persistent
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    
    log "IP forwarding enabled"
}

# Function to check if user is root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
        exit 1
    fi
}

# Main function
main() {
    check_root
    
    case "$1" in
        setup)
            enable_forwarding
            setup_firewall
            save_rules
            ;;
        grant)
            grant_access "$2"
            ;;
        revoke)
            revoke_access "$2"
            ;;
        list)
            list_access
            ;;
        save)
            save_rules
            ;;
        restore)
            restore_rules
            ;;
        reset)
            reset_firewall
            ;;
        show)
            show_rules
            ;;
        *)
            echo "WasteFi Firewall Management Script"
            echo ""
            echo "Usage: $0 {setup|grant|revoke|list|save|restore|reset|show}"
            echo ""
            echo "Commands:"
            echo "  setup          Setup initial firewall rules"
            echo "  grant <ip>     Grant internet access to IP address"
            echo "  revoke <ip>    Revoke internet access from IP address"
            echo "  list           List all clients with internet access"
            echo "  save           Save current rules to persist after reboot"
            echo "  restore        Restore saved rules"
            echo "  reset          Reset all firewall rules to defaults"
            echo "  show           Show current firewall rules"
            echo ""
            echo "Examples:"
            echo "  $0 setup"
            echo "  $0 grant 192.168.4.100"
            echo "  $0 revoke 192.168.4.100"
            echo "  $0 list"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"