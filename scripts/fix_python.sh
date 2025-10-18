#!/bin/bash

# Quick Fix for externally-managed-environment Error
# Run this on your Raspberry Pi

echo "🔧 Fixing Python externally-managed-environment error..."

# Option 1: Install system packages (recommended)
echo "📦 Installing system packages..."
sudo apt update
sudo apt install -y python3-flask python3-werkzeug python3-pip python3-venv python3-full

# Test if it works
if python3 -c "import flask; print('✅ Flask working!')" 2>/dev/null; then
    echo "✅ System packages working! You can proceed with installation."
    exit 0
fi

# Option 2: Create virtual environment
echo "🔧 Creating virtual environment..."
cd /home/pi/wastefi
python3 -m venv venv
source venv/bin/activate
pip install flask werkzeug

echo "✅ Virtual environment created!"
echo ""
echo "Now you can run:"
echo "  cd /home/pi/wastefi"
echo "  sudo ./scripts/install.sh"
echo ""
echo "Or manually start the app:"
echo "  source venv/bin/activate"
echo "  python3 app/app.py"