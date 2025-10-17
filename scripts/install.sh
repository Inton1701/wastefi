#!/bin/bash

# WasteFi Installation Script for Raspberry Pi
# This script installs and configures all components needed for the WiFi vendo

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/home/pi/wastefi"
SERVICE_NAME="wastefi"
USER="pi"

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

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to check if running on Raspberry Pi
check_raspberry_pi() {
    if ! grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
        warning "This script is designed for Raspberry Pi. Continue anyway? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Function to update system
update_system() {
    log "Updating system packages..."
    apt update
    apt upgrade -y
    log "System updated successfully"
}

# Function to install required packages
install_packages() {
    log "Installing required packages..."
    
    # Required packages
    PACKAGES=(
        "hostapd"
        "dnsmasq" 
        "python3"
        "python3-pip"
        "python3-flask"
        "iptables-persistent"
        "git"
        "curl"
        "wget"
        "nano"
        "htop"
        "net-tools"
        "bridge-utils"
    )
    
    for package in "${PACKAGES[@]}"; do
        info "Installing $package..."
        apt install -y "$package"
    done
    
    log "All packages installed successfully"
}

# Function to install Python dependencies
install_python_deps() {
    log "Installing Python dependencies..."
    
    pip3 install --upgrade pip
    pip3 install flask werkzeug
    
    log "Python dependencies installed"
}

# Function to setup directory structure
setup_directories() {
    log "Setting up directory structure..."
    
    # Create main directory
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR/app"
    mkdir -p "$INSTALL_DIR/app/static/css"
    mkdir -p "$INSTALL_DIR/app/static/js"  
    mkdir -p "$INSTALL_DIR/app/templates"
    mkdir -p "$INSTALL_DIR/config"
    mkdir -p "$INSTALL_DIR/scripts"
    mkdir -p "$INSTALL_DIR/logs"
    mkdir -p "$INSTALL_DIR/backup"
    
    # Set ownership
    chown -R $USER:$USER "$INSTALL_DIR"
    
    log "Directory structure created"
}

# Function to copy configuration files
copy_configs() {
    log "Copying configuration files..."
    
    # Backup existing configs
    backup_config_file "/etc/hostapd/hostapd.conf"
    backup_config_file "/etc/dnsmasq.conf"
    backup_config_file "/etc/dhcpcd.conf"
    
    # Copy new configs
    cp "$INSTALL_DIR/config/hostapd.conf" "/etc/hostapd/"
    cp "$INSTALL_DIR/config/dnsmasq.conf" "/etc/"
    
    # Update dhcpcd.conf
    if ! grep -q "interface wlan0" /etc/dhcpcd.conf; then
        cat "$INSTALL_DIR/config/dhcpcd.conf" >> /etc/dhcpcd.conf
    fi
    
    # Set hostapd config path
    if ! grep -q "DAEMON_CONF=" /etc/default/hostapd; then
        echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' >> /etc/default/hostapd
    fi
    
    log "Configuration files copied"
}

# Function to backup config file
backup_config_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        cp "$file" "$INSTALL_DIR/backup/$(basename "$file").backup.$(date +%Y%m%d_%H%M%S)"
        log "Backed up $file"
    fi
}

# Function to setup systemd service
setup_service() {
    log "Setting up systemd service..."
    
    # Copy service file
    cp "$INSTALL_DIR/config/wastefi.service" "/etc/systemd/system/"
    
    # Reload systemd
    systemctl daemon-reload
    
    # Enable services
    systemctl enable hostapd
    systemctl enable dnsmasq
    systemctl enable wastefi
    
    log "Systemd service configured"
}

# Function to configure firewall
setup_firewall() {
    log "Setting up firewall..."
    
    # Make scripts executable
    chmod +x "$INSTALL_DIR/scripts/firewall.sh"
    chmod +x "$INSTALL_DIR/scripts/network.sh"
    
    # Create symlinks for easy access
    ln -sf "$INSTALL_DIR/scripts/firewall.sh" "/usr/local/bin/wastefi-firewall"
    ln -sf "$INSTALL_DIR/scripts/network.sh" "/usr/local/bin/wastefi-network"
    
    # Setup initial firewall rules
    "$INSTALL_DIR/scripts/firewall.sh" setup
    
    log "Firewall configured"
}

# Function to configure wireless interface
configure_wireless() {
    log "Configuring wireless interface..."
    
    # Disable wpa_supplicant for wlan0
    systemctl disable wpa_supplicant.service
    
    # Unmask hostapd
    systemctl unmask hostapd
    
    # Block wifi countries (optional)
    if command -v rfkill >/dev/null 2>&1; then
        rfkill unblock wlan
    fi
    
    log "Wireless interface configured"
}

# Function to create startup script
create_startup_script() {
    log "Creating startup script..."
    
    cat > "$INSTALL_DIR/scripts/start_wastefi.sh" << 'EOF'
#!/bin/bash

# WasteFi Startup Script

# Wait for interfaces to be ready
sleep 5

# Start hostapd
systemctl start hostapd

# Start dnsmasq  
systemctl start dnsmasq

# Setup firewall
/home/pi/wastefi/scripts/firewall.sh setup

# Start wastefi service
systemctl start wastefi

echo "WasteFi started successfully"
EOF

    chmod +x "$INSTALL_DIR/scripts/start_wastefi.sh"
    
    log "Startup script created"
}

# Function to create useful utility scripts
create_utility_scripts() {
    log "Creating utility scripts..."
    
    # Status script
    cat > "$INSTALL_DIR/scripts/status.sh" << 'EOF'
#!/bin/bash

echo "=== WasteFi Status ==="
echo ""

echo "Services:"
systemctl is-active hostapd dnsmasq wastefi

echo ""
echo "Network Interfaces:"
ip addr show wlan0 | grep inet

echo ""  
echo "Connected Clients:"
arp -a | grep "192.168.4"

echo ""
echo "Network Interfaces:"
/home/pi/wastefi/scripts/network.sh status

echo ""
echo "Active Sessions:"
if [[ -f /tmp/wastefi_sessions.json ]]; then
    cat /tmp/wastefi_sessions.json | python3 -m json.tool
else
    echo "No active sessions"
fi
EOF

    chmod +x "$INSTALL_DIR/scripts/status.sh"
    
    # Log viewer script
    cat > "$INSTALL_DIR/scripts/logs.sh" << 'EOF'
#!/bin/bash

echo "=== WasteFi Logs ==="
echo ""

echo "Application Logs:"
tail -20 /home/pi/wastefi/logs/app.log

echo ""
echo "System Logs:"
journalctl -u wastefi -n 20 --no-pager
EOF

    chmod +x "$INSTALL_DIR/scripts/logs.sh"
    
    # Restart script
    cat > "$INSTALL_DIR/scripts/restart.sh" << 'EOF'
#!/bin/bash

echo "Restarting WasteFi services..."

systemctl restart hostapd
systemctl restart dnsmasq
systemctl restart wastefi

echo "Services restarted"
EOF

    chmod +x "$INSTALL_DIR/scripts/restart.sh"
    
    log "Utility scripts created"
}

# Function to set file permissions
set_permissions() {
    log "Setting file permissions..."
    
    # Set ownership
    chown -R $USER:$USER "$INSTALL_DIR"
    
    # Make scripts executable
    find "$INSTALL_DIR/scripts" -name "*.sh" -exec chmod +x {} \;
    
    # Set log directory permissions
    chmod 755 "$INSTALL_DIR/logs"
    
    log "Permissions set"
}

# Function to test installation
test_installation() {
    log "Testing installation..."
    
    # Check if services can start
    if systemctl start hostapd; then
        info "hostapd: OK"
        systemctl stop hostapd
    else
        error "hostapd: FAILED"
    fi
    
    if systemctl start dnsmasq; then
        info "dnsmasq: OK"
        systemctl stop dnsmasq
    else
        error "dnsmasq: FAILED"
    fi
    
    # Check if Python app can start
    if python3 -c "import flask; print('Flask: OK')"; then
        info "Python dependencies: OK"
    else
        error "Python dependencies: FAILED"
    fi
    
    log "Installation test completed"
}

# Main installation function
main() {
    log "Starting WasteFi installation..."
    
    check_root
    check_raspberry_pi
    
    update_system
    install_packages
    install_python_deps
    setup_directories
    copy_configs
    setup_service
    configure_wireless
    setup_firewall
    create_startup_script
    create_utility_scripts
    set_permissions
    test_installation
    
    log "Installation completed successfully!"
    
    echo ""
    echo -e "${GREEN}===========================================${NC}"
    echo -e "${GREEN}     WasteFi Installation Complete!      ${NC}"
    echo -e "${GREEN}===========================================${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Reboot your Raspberry Pi: sudo reboot"
    echo "2. After reboot, check status: $INSTALL_DIR/scripts/status.sh"
    echo "3. View logs: $INSTALL_DIR/scripts/logs.sh"
    echo "4. Connect to WiFi network: WasteFi-Portal"
    echo ""
    echo "Configuration files are in: $INSTALL_DIR/config/"
    echo "Application files are in: $INSTALL_DIR/app/"
    echo "Scripts are in: $INSTALL_DIR/scripts/"
    echo ""
    echo "To start manually: $INSTALL_DIR/scripts/start_wastefi.sh"
    echo "To restart services: $INSTALL_DIR/scripts/restart.sh"
    echo ""
    warning "Please reboot your system now!"
}

# Run main function
main "$@"