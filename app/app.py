#!/usr/bin/env python3
"""
WasteFi - WiFi Vendo Flask Application
A captive portal system for Raspberry Pi WiFi vending
"""

import os
import json
import time
import logging
import subprocess
import threading
from datetime import datetime, timedelta
from flask import Flask, render_template, request, jsonify, redirect, url_for
from werkzeug.serving import run_simple

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/home/pi/wastefi/logs/app.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

app = Flask(__name__)
app.secret_key = 'wastefi_secret_key_change_this_in_production'

# Configuration
CONFIG = {
    'interface_ap': 'wlan0',    # WiFi AP interface (built-in)
    'interface_wan': None,      # Auto-detected (wlan1 or eth0)
    'session_file': '/tmp/wastefi_sessions.json',
    'max_sessions': 50,
    'cleanup_interval': 60,  # seconds
    'durations': {
        'plastic': 10,
        'metal': 20,
        'paper': 30
    }
}

def detect_wan_interface():
    """Auto-detect WAN interface (prefer wlan1, fallback to eth0)"""
    try:
        # Check for default route
        result = subprocess.run(['ip', 'route'], capture_output=True, text=True)
        if result.returncode == 0:
            for line in result.stdout.split('\n'):
                if 'default' in line:
                    if 'wlan1' in line:
                        return 'wlan1'
                    elif 'eth0' in line:
                        return 'eth0'
        
        # Fallback: check if interfaces exist
        for interface in ['wlan1', 'eth0']:
            result = subprocess.run(['ip', 'link', 'show', interface], 
                                  capture_output=True, text=True)
            if result.returncode == 0:
                return interface
                
    except Exception as e:
        logger.error(f"Error detecting WAN interface: {e}")
    
    return 'eth0'  # final fallback

# Auto-detect WAN interface on startup
CONFIG['interface_wan'] = detect_wan_interface()
logger.info(f"Detected WAN interface: {CONFIG['interface_wan']}")

class SessionManager:
    """Manages client sessions and internet access"""
    
    def __init__(self):
        self.sessions = {}
        self.load_sessions()
        self.start_cleanup_thread()
    
    def load_sessions(self):
        """Load sessions from file"""
        try:
            if os.path.exists(CONFIG['session_file']):
                with open(CONFIG['session_file'], 'r') as f:
                    data = json.load(f)
                    # Convert string timestamps back to datetime objects
                    for session_id, session in data.items():
                        session['start_time'] = datetime.fromisoformat(session['start_time'])
                        session['end_time'] = datetime.fromisoformat(session['end_time'])
                    self.sessions = data
                    logger.info(f"Loaded {len(self.sessions)} sessions from file")
        except Exception as e:
            logger.error(f"Error loading sessions: {e}")
            self.sessions = {}
    
    def save_sessions(self):
        """Save sessions to file"""
        try:
            # Convert datetime objects to strings for JSON serialization
            serializable_sessions = {}
            for session_id, session in self.sessions.items():
                serializable_session = session.copy()
                serializable_session['start_time'] = session['start_time'].isoformat()
                serializable_session['end_time'] = session['end_time'].isoformat()
                serializable_sessions[session_id] = serializable_session
            
            with open(CONFIG['session_file'], 'w') as f:
                json.dump(serializable_sessions, f, indent=2)
        except Exception as e:
            logger.error(f"Error saving sessions: {e}")
    
    def create_session(self, client_ip, client_mac, duration, session_type):
        """Create a new session for a client"""
        session_id = f"{client_mac}_{int(time.time())}"
        start_time = datetime.now()
        end_time = start_time + timedelta(seconds=duration)
        
        session = {
            'id': session_id,
            'client_ip': client_ip,
            'client_mac': client_mac,
            'duration': duration,
            'type': session_type,
            'start_time': start_time,
            'end_time': end_time,
            'active': True
        }
        
        self.sessions[session_id] = session
        self.save_sessions()
        
        # Grant internet access
        self.grant_access(client_ip, client_mac)
        
        logger.info(f"Created session {session_id} for {client_ip} ({client_mac}) - {session_type} {duration}s")
        return session
    
    def get_session(self, client_ip, client_mac):
        """Get active session for a client"""
        current_time = datetime.now()
        
        for session in self.sessions.values():
            if (session['client_ip'] == client_ip or session['client_mac'] == client_mac) and session['active']:
                if current_time <= session['end_time']:
                    return session
                else:
                    # Session expired
                    self.end_session(session['id'])
        
        return None
    
    def end_session(self, session_id):
        """End a session and revoke access"""
        if session_id in self.sessions:
            session = self.sessions[session_id]
            session['active'] = False
            
            # Revoke internet access
            self.revoke_access(session['client_ip'], session['client_mac'])
            
            self.save_sessions()
            logger.info(f"Ended session {session_id}")
    
    def cleanup_expired_sessions(self):
        """Remove expired sessions"""
        current_time = datetime.now()
        expired_sessions = []
        
        for session_id, session in self.sessions.items():
            if session['active'] and current_time > session['end_time']:
                expired_sessions.append(session_id)
        
        for session_id in expired_sessions:
            self.end_session(session_id)
        
        if expired_sessions:
            logger.info(f"Cleaned up {len(expired_sessions)} expired sessions")
    
    def start_cleanup_thread(self):
        """Start background thread for session cleanup"""
        def cleanup_worker():
            while True:
                time.sleep(CONFIG['cleanup_interval'])
                self.cleanup_expired_sessions()
        
        cleanup_thread = threading.Thread(target=cleanup_worker, daemon=True)
        cleanup_thread.start()
        logger.info("Started session cleanup thread")
    
    def grant_access(self, client_ip, client_mac):
        """Grant internet access using iptables"""
        try:
            # Allow internet access for this IP
            subprocess.run([
                'sudo', 'iptables', '-I', 'FORWARD', '1',
                '-s', client_ip, '-j', 'ACCEPT'
            ], check=True)
            
            subprocess.run([
                'sudo', 'iptables', '-I', 'FORWARD', '1',
                '-d', client_ip, '-j', 'ACCEPT'
            ], check=True)
            
            logger.info(f"Granted internet access to {client_ip} ({client_mac})")
        except subprocess.CalledProcessError as e:
            logger.error(f"Error granting access to {client_ip}: {e}")
    
    def revoke_access(self, client_ip, client_mac):
        """Revoke internet access using iptables"""
        try:
            # Remove access rules for this IP
            subprocess.run([
                'sudo', 'iptables', '-D', 'FORWARD',
                '-s', client_ip, '-j', 'ACCEPT'
            ], check=False)  # Don't fail if rule doesn't exist
            
            subprocess.run([
                'sudo', 'iptables', '-D', 'FORWARD',
                '-d', client_ip, '-j', 'ACCEPT'
            ], check=False)
            
            logger.info(f"Revoked internet access from {client_ip} ({client_mac})")
        except Exception as e:
            logger.error(f"Error revoking access from {client_ip}: {e}")

# Initialize session manager
session_manager = SessionManager()

def get_client_info(request):
    """Extract client IP and MAC address"""
    client_ip = request.environ.get('HTTP_X_FORWARDED_FOR', request.remote_addr)
    if client_ip and ',' in client_ip:
        client_ip = client_ip.split(',')[0].strip()
    
    # Try to get MAC address from ARP table
    client_mac = get_mac_address(client_ip)
    
    return client_ip, client_mac

def get_mac_address(ip):
    """Get MAC address from ARP table"""
    try:
        result = subprocess.run(['arp', '-n', ip], capture_output=True, text=True)
        if result.returncode == 0:
            lines = result.stdout.strip().split('\n')
            for line in lines:
                if ip in line:
                    parts = line.split()
                    if len(parts) >= 3:
                        return parts[2]  # MAC address is typically the 3rd field
    except Exception as e:
        logger.error(f"Error getting MAC address for {ip}: {e}")
    
    return "unknown"

@app.route('/')
def index():
    """Main captive portal page"""
    client_ip, client_mac = get_client_info(request)
    
    # Check if client already has an active session
    session = session_manager.get_session(client_ip, client_mac)
    if session:
        return redirect(url_for('success'))
    
    return render_template('index.html')

@app.route('/success')
def success():
    """Success page after activation"""
    client_ip, client_mac = get_client_info(request)
    session = session_manager.get_session(client_ip, client_mac)
    
    if not session:
        return redirect(url_for('index'))
    
    # Calculate remaining time
    current_time = datetime.now()
    remaining_seconds = max(0, int((session['end_time'] - current_time).total_seconds()))
    session['remaining_time'] = remaining_seconds
    
    return render_template('success.html', session=session)

@app.route('/status')
def status():
    """Status page"""
    client_ip, client_mac = get_client_info(request)
    session = session_manager.get_session(client_ip, client_mac)
    
    return render_template('status.html', session=session)

@app.route('/network')
def network_management():
    """Network management page"""
    return render_template('network.html')

@app.route('/api/device-info')
def api_device_info():
    """API endpoint to get device information"""
    client_ip, client_mac = get_client_info(request)
    
    return jsonify({
        'ip': client_ip,
        'mac': client_mac,
        'timestamp': datetime.now().isoformat(),
        'system': {
            'ap_interface': CONFIG['interface_ap'],
            'wan_interface': CONFIG['interface_wan']
        }
    })

@app.route('/api/network-status')
def api_network_status():
    """API endpoint to get network interface status"""
    try:
        # Get interface information
        interfaces = {}
        
        for interface in ['wlan0', 'wlan1', 'eth0']:
            try:
                result = subprocess.run(['ip', 'addr', 'show', interface], 
                                      capture_output=True, text=True)
                if result.returncode == 0:
                    # Extract IP address
                    ip = None
                    for line in result.stdout.split('\n'):
                        if 'inet ' in line and 'scope global' in line:
                            ip = line.strip().split()[1]
                            break
                    
                    # Check if interface is up
                    link_result = subprocess.run(['ip', 'link', 'show', interface], 
                                               capture_output=True, text=True)
                    is_up = 'state UP' in link_result.stdout if link_result.returncode == 0 else False
                    
                    interfaces[interface] = {
                        'exists': True,
                        'up': is_up,
                        'ip': ip,
                        'role': 'AP' if interface == 'wlan0' else ('WAN' if interface == CONFIG['interface_wan'] else 'Available')
                    }
                else:
                    interfaces[interface] = {'exists': False}
            except Exception as e:
                logger.error(f"Error checking interface {interface}: {e}")
                interfaces[interface] = {'exists': False, 'error': str(e)}
        
        # Check internet connectivity
        internet_ok = False
        try:
            result = subprocess.run(['ping', '-c', '1', '-W', '2', '8.8.8.8'], 
                                  capture_output=True, text=True)
            internet_ok = result.returncode == 0
        except:
            pass
        
        return jsonify({
            'interfaces': interfaces,
            'wan_interface': CONFIG['interface_wan'],
            'internet_connectivity': internet_ok,
            'timestamp': datetime.now().isoformat()
        })
        
    except Exception as e:
        logger.error(f"Error getting network status: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/activate', methods=['POST'])
def api_activate():
    """API endpoint to activate internet access"""
    try:
        data = request.get_json()
        duration = data.get('duration')
        session_type = data.get('type')
        
        if not duration or not session_type:
            return jsonify({'success': False, 'error': 'Missing duration or type'})
        
        if session_type not in CONFIG['durations']:
            return jsonify({'success': False, 'error': 'Invalid session type'})
        
        # Validate duration matches expected value
        expected_duration = CONFIG['durations'][session_type]
        if duration != expected_duration:
            return jsonify({'success': False, 'error': 'Invalid duration for session type'})
        
        client_ip, client_mac = get_client_info(request)
        
        # Check if client already has an active session
        existing_session = session_manager.get_session(client_ip, client_mac)
        if existing_session:
            remaining_time = max(0, int((existing_session['end_time'] - datetime.now()).total_seconds()))
            return jsonify({
                'success': True,
                'message': 'Session already active',
                'remaining_time': remaining_time
            })
        
        # Create new session
        session = session_manager.create_session(client_ip, client_mac, duration, session_type)
        
        return jsonify({
            'success': True,
            'message': 'Access activated successfully',
            'session_id': session['id'],
            'remaining_time': duration
        })
        
    except Exception as e:
        logger.error(f"Error activating access: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/status')
def api_status():
    """API endpoint to check connection status"""
    client_ip, client_mac = get_client_info(request)
    session = session_manager.get_session(client_ip, client_mac)
    
    if session:
        current_time = datetime.now()
        remaining_time = max(0, int((session['end_time'] - current_time).total_seconds()))
        
        return jsonify({
            'connected': True,
            'session_type': session['type'],
            'duration': session['duration'],
            'remaining_time': remaining_time,
            'start_time': session['start_time'].isoformat()
        })
    
    return jsonify({'connected': False})

@app.route('/api/configure-wifi', methods=['POST'])
def api_configure_wifi():
    """API endpoint to configure WiFi connection"""
    try:
        data = request.get_json()
        ssid = data.get('ssid')
        password = data.get('password', '')
        
        if not ssid:
            return jsonify({'success': False, 'error': 'SSID is required'})
        
        # Call network configuration script
        cmd = ['/home/pi/wastefi/scripts/network.sh', 'wifi', ssid]
        if password:
            cmd.append(password)
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode == 0:
            # Update WAN interface configuration
            CONFIG['interface_wan'] = 'wlan1'
            return jsonify({
                'success': True, 
                'message': 'WiFi configured successfully'
            })
        else:
            return jsonify({
                'success': False, 
                'error': result.stderr or 'Configuration failed'
            })
            
    except Exception as e:
        logger.error(f"Error configuring WiFi: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/configure-ethernet', methods=['POST'])
def api_configure_ethernet():
    """API endpoint to configure Ethernet connection"""
    try:
        result = subprocess.run(['/home/pi/wastefi/scripts/network.sh', 'ethernet'], 
                               capture_output=True, text=True)
        
        if result.returncode == 0:
            CONFIG['interface_wan'] = 'eth0'
            return jsonify({
                'success': True, 
                'message': 'Ethernet configured successfully'
            })
        else:
            return jsonify({
                'success': False, 
                'error': result.stderr or 'Configuration failed'
            })
            
    except Exception as e:
        logger.error(f"Error configuring Ethernet: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/switch-wan', methods=['POST'])
def api_switch_wan():
    """API endpoint to switch WAN interface"""
    try:
        data = request.get_json()
        interface = data.get('interface')
        
        if interface not in ['wlan1', 'eth0']:
            return jsonify({'success': False, 'error': 'Invalid interface'})
        
        if interface == 'wlan1':
            cmd = '/home/pi/wastefi/scripts/network.sh switch-wifi'
        else:
            cmd = '/home/pi/wastefi/scripts/network.sh switch-ethernet'
        
        result = subprocess.run(cmd.split(), capture_output=True, text=True)
        
        if result.returncode == 0:
            CONFIG['interface_wan'] = interface
            return jsonify({
                'success': True, 
                'message': f'Switched to {interface} successfully'
            })
        else:
            return jsonify({
                'success': False, 
                'error': result.stderr or 'Switch failed'
            })
            
    except Exception as e:
        logger.error(f"Error switching WAN interface: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/auto-detect', methods=['POST'])
def api_auto_detect():
    """API endpoint to auto-detect and configure best connection"""
    try:
        result = subprocess.run(['/home/pi/wastefi/scripts/network.sh', 'auto'], 
                               capture_output=True, text=True)
        
        if result.returncode == 0:
            # Re-detect WAN interface
            CONFIG['interface_wan'] = detect_wan_interface()
            return jsonify({
                'success': True, 
                'interface': CONFIG['interface_wan'],
                'message': 'Auto-detection completed successfully'
            })
        else:
            return jsonify({
                'success': False, 
                'error': result.stderr or 'Auto-detection failed'
            })
            
    except Exception as e:
        logger.error(f"Error in auto-detection: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.errorhandler(404)
def not_found(error):
    """Redirect all 404s to captive portal"""
    return redirect(url_for('index'))

@app.errorhandler(500)
def server_error(error):
    """Handle server errors"""
    logger.error(f"Server error: {error}")
    return "Server error. Please try again.", 500

if __name__ == '__main__':
    # Ensure log directory exists
    os.makedirs(os.path.dirname(CONFIG['session_file']), exist_ok=True)
    os.makedirs('/home/pi/wastefi/logs', exist_ok=True)
    
    logger.info("Starting WasteFi application")
    
    # Run Flask app
    app.run(
        host='0.0.0.0',
        port=80,
        debug=False,
        threaded=True
    )