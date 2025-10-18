#!/usr/bin/env python3
"""
WasteFi Launcher Script
Handles virtual environment activation if needed
"""

import os
import sys
import subprocess

def find_python_with_flask():
    """Find a Python interpreter that has Flask installed"""
    
    # Try current Python first
    try:
        import flask
        return sys.executable
    except ImportError:
        pass
    
    # Try virtual environment
    venv_python = "/home/pi/wastefi/venv/bin/python3"
    if os.path.exists(venv_python):
        try:
            result = subprocess.run([venv_python, "-c", "import flask"], 
                                  capture_output=True, text=True)
            if result.returncode == 0:
                return venv_python
        except:
            pass
    
    # Try system python with --break-system-packages flag
    try:
        result = subprocess.run([sys.executable, "-c", "import flask"], 
                              capture_output=True, text=True)
        if result.returncode == 0:
            return sys.executable
    except:
        pass
    
    return None

def main():
    # Find suitable Python interpreter
    python_exe = find_python_with_flask()
    
    if not python_exe:
        print("ERROR: Flask not found in any Python environment")
        print("Please run: sudo /home/pi/wastefi/scripts/setup_python.sh")
        sys.exit(1)
    
    # Get the directory of this script
    script_dir = os.path.dirname(os.path.abspath(__file__))
    app_path = os.path.join(script_dir, "app.py")
    
    # Launch the Flask app
    print(f"Starting WasteFi with Python: {python_exe}")
    
    # Set environment variables
    env = os.environ.copy()
    env['PYTHONPATH'] = script_dir
    
    # Execute the Flask app
    os.execve(python_exe, [python_exe, app_path], env)

if __name__ == "__main__":
    main()