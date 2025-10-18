#!/bin/bash

# WasteFi Python Environment Setup
# Handles the externally-managed-environment issue

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

INSTALL_DIR="/home/pi/wastefi"

log "Setting up Python environment for WasteFi..."

# Method 1: Try system packages first (recommended)
log "Attempting to install via system packages..."
sudo apt update
sudo apt install -y python3-flask python3-werkzeug python3-pip python3-venv python3-full

# Test if Flask is working
if python3 -c "import flask; import werkzeug; print('System packages working!')" 2>/dev/null; then
    log "✅ System packages are sufficient!"
    log "WasteFi can run with system Python packages"
    exit 0
fi

# Method 2: Create virtual environment
warning "System packages insufficient, creating virtual environment..."

cd "$INSTALL_DIR"

# Create virtual environment
log "Creating virtual environment..."
python3 -m venv venv

# Activate and install packages
log "Installing packages in virtual environment..."
source venv/bin/activate
pip install --upgrade pip
pip install flask==2.3.3 werkzeug==2.3.7

# Test virtual environment
if ./venv/bin/python3 -c "import flask; import werkzeug; print('Virtual environment working!')" 2>/dev/null; then
    log "✅ Virtual environment created successfully!"
    
    # Update the systemd service file
    log "Updating systemd service to use virtual environment..."
    sudo sed -i "s|ExecStart=/usr/bin/python3.*|ExecStart=$INSTALL_DIR/venv/bin/python3 $INSTALL_DIR/app/app.py|g" /etc/systemd/system/wastefi.service
    sudo sed -i "s|Environment=PYTHONPATH=.*|Environment=PYTHONPATH=$INSTALL_DIR/app|g" /etc/systemd/system/wastefi.service
    
    # Reload systemd
    sudo systemctl daemon-reload
    
    log "✅ Virtual environment setup complete!"
    log "WasteFi will now use the virtual environment"
else
    error "❌ Virtual environment setup failed"
    exit 1
fi

# Method 3: Force system-wide install (not recommended but works)
if [[ "$1" == "--force-system" ]]; then
    warning "⚠️  FORCING system-wide install (not recommended)"
    warning "This may break your system Python installation"
    
    echo "Are you sure you want to continue? (y/N)"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        sudo pip3 install --break-system-packages flask werkzeug
        log "Forced system-wide installation complete"
    else
        log "Cancelled force installation"
        exit 1
    fi
fi

log "Python environment setup complete!"
echo ""
echo "To test the installation:"
echo "  cd $INSTALL_DIR"
echo "  ./venv/bin/python3 app/app.py"
echo ""
echo "Or start the service:"
echo "  sudo systemctl start wastefi"