# 🌐 WasteFi - WiFi Vendo Portal

A complete captive portal system for Raspberry Pi that provides time-based internet access control. Perfect for creating WiFi vending machines or controlled internet access points.

## 🎯 Features

- **Time-based Access Control**: 3 different duration options (10s, 20s, 30s)
- **Captive Portal**: Automatic redirection for connected devices
- **Modern Web Interface**: Responsive design with smooth animations
- **Session Management**: Track and manage client sessions
- **Firewall Integration**: Automatic iptables rule management
- **Real-time Monitoring**: Live status updates and countdown timers
- **Easy Installation**: One-command setup script
- **Comprehensive Logging**: Detailed application and system logs

## 🏗️ Architecture

```
Internet (ISP) 
    ↓ (Ethernet)
Raspberry Pi
    ↓ (USB-to-LAN)
Comfast AP Device (AP Mode)
    ↓ (WiFi)
Client Devices
```

### Components

- **Flask Web Application**: Captive portal interface
- **hostapd**: WiFi access point management
- **dnsmasq**: DHCP and DNS services
- **iptables**: Firewall and traffic control
- **systemd**: Service management

## 📋 Prerequisites

### Hardware Requirements

- Raspberry Pi 3B+ or newer (recommended)
- MicroSD card (16GB minimum, Class 10)
- Ethernet connection to ISP
- USB to Ethernet adapter
- Comfast WiFi device (or similar AP-capable device)

### Software Requirements

- Raspberry Pi OS (Bullseye or newer)
- Python 3.7+
- Root access (sudo privileges)

## 🚀 Quick Start

### 1. Download and Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/wastefi.git
cd wastefi

# Or download as ZIP and extract
wget https://github.com/yourusername/wastefi/archive/main.zip
unzip main.zip
cd wastefi-main
```

### 2. Install

```bash
# Make install script executable
chmod +x scripts/install.sh

# Run installation (requires sudo)
sudo ./scripts/install.sh
```

### 3. Reboot

```bash
sudo reboot
```

### 4. Connect and Test

1. Connect your device to the "WasteFi-Portal" WiFi network
2. Open a web browser - you'll be automatically redirected to the portal
3. Select a duration option (Plastic/Metal/Paper)
4. Enjoy your internet access!

## 🔧 Configuration

### WiFi Settings

Edit `config/hostapd.conf`:

```conf
# Change network name
ssid=Your-Network-Name

# Add password protection (optional)
wpa=2
wpa_passphrase=YourSecurePassword
wpa_key_mgmt=WPA-PSK
```

### Duration Settings

Edit `app/app.py`:

```python
CONFIG = {
    'durations': {
        'plastic': 60,    # 1 minute
        'metal': 300,     # 5 minutes  
        'paper': 900      # 15 minutes
    }
}
```

### Network Configuration

Edit `config/dnsmasq.conf`:

```conf
# Change IP range
dhcp-range=192.168.4.10,192.168.4.100,255.255.255.0,2h

# Change gateway IP
dhcp-option=3,192.168.4.1
```

## 🛠️ Management

### Check Status

```bash
# View overall status
/home/pi/wastefi/scripts/status.sh

# Check specific services
sudo systemctl status wastefi
sudo systemctl status hostapd
sudo systemctl status dnsmasq
```

### View Logs

```bash
# Application logs
/home/pi/wastefi/scripts/logs.sh

# Real-time application logs
tail -f /home/pi/wastefi/logs/app.log

# System logs
sudo journalctl -u wastefi -f
```

### Restart Services

```bash
# Restart all services
/home/pi/wastefi/scripts/restart.sh

# Restart individual services
sudo systemctl restart wastefi
sudo systemctl restart hostapd
sudo systemctl restart dnsmasq
```

### Firewall Management

```bash
# View current rules
sudo wastefi-firewall show

# List clients with access
sudo wastefi-firewall list

# Grant access manually
sudo wastefi-firewall grant 192.168.4.100

# Revoke access manually  
sudo wastefi-firewall revoke 192.168.4.100

# Reset firewall
sudo wastefi-firewall reset
```

## 📊 Monitoring

### Active Sessions

```bash
# View active sessions
cat /tmp/wastefi_sessions.json | python3 -m json.tool
```

### Connected Clients

```bash
# View DHCP leases
cat /var/lib/dhcp/dhcpd.leases

# View ARP table
arp -a
```

### Network Traffic

```bash
# Monitor interface traffic
sudo iftop -i wlan0

# View connection statistics
netstat -i
```

## 🔒 Security Considerations

### Access Control

- The system uses iptables to control internet access
- Default policy drops all traffic until explicitly allowed
- Sessions are time-limited and automatically expire

### Network Security

- Consider enabling WPA2 encryption on the access point
- Use strong passwords for system accounts
- Regularly update the system and dependencies

### Application Security

- Change the Flask secret key in production
- Consider implementing rate limiting
- Monitor logs for suspicious activity

## 🐛 Troubleshooting

### Common Issues

#### WiFi Interface Not Working

```bash
# Check interface status
ip link show wlan0

# Restart networking
sudo systemctl restart dhcpcd

# Check hostapd status
sudo systemctl status hostapd
```

#### Clients Can't Connect

```bash
# Check DHCP service
sudo systemctl status dnsmasq

# View DHCP logs
sudo journalctl -u dnsmasq

# Restart services
sudo systemctl restart hostapd dnsmasq
```

#### No Internet After Authorization

```bash
# Check firewall rules
sudo iptables -L FORWARD -n

# Check routing
ip route show

# Test connectivity
ping -c 3 8.8.8.8
```

#### Portal Not Loading

```bash
# Check Flask application
sudo systemctl status wastefi

# Check web server logs
tail -f /home/pi/wastefi/logs/app.log

# Test local connection
curl http://192.168.4.1
```

### Log Locations

- Application logs: `/home/pi/wastefi/logs/app.log`
- System logs: `journalctl -u wastefi`
- hostapd logs: `journalctl -u hostapd`
- dnsmasq logs: `journalctl -u dnsmasq`

### Recovery

If something goes wrong:

```bash
# Reset to default configuration
sudo /home/pi/wastefi/scripts/firewall.sh reset
sudo /home/pi/wastefi/scripts/restart.sh

# Complete uninstall
sudo /home/pi/wastefi/scripts/uninstall.sh
```

## 🔄 Updates

### Updating the Application

```bash
# Backup current installation
sudo cp -r /home/pi/wastefi /home/pi/wastefi.backup

# Download new version
git pull origin main

# Restart services
sudo systemctl restart wastefi
```

### System Updates

```bash
# Update system packages
sudo apt update && sudo apt upgrade

# Update Python packages
pip3 install --upgrade flask werkzeug
```

## 📝 Development

### Project Structure

```
wastefi/
├── app/                    # Flask application
│   ├── static/
│   │   ├── css/           # Stylesheets
│   │   └── js/            # JavaScript files
│   ├── templates/         # HTML templates
│   └── app.py            # Main application
├── config/               # Configuration files
│   ├── hostapd.conf      # WiFi AP configuration
│   ├── dnsmasq.conf      # DHCP/DNS configuration
│   ├── dhcpcd.conf       # Network interface configuration
│   └── wastefi.service   # Systemd service file
├── scripts/              # Management scripts
│   ├── install.sh        # Installation script
│   ├── uninstall.sh      # Uninstallation script
│   └── firewall.sh       # Firewall management
├── logs/                 # Application logs
└── README.md             # This file
```

### Adding Features

1. **New Duration Options**: Edit the durations in `app/app.py`
2. **Custom Styling**: Modify `app/static/css/style.css`
3. **Additional Pages**: Add templates in `app/templates/`
4. **API Endpoints**: Add routes in `app/app.py`

### Testing

```bash
# Test Flask application
cd /home/pi/wastefi/app
python3 app.py

# Test configuration
sudo hostapd -d /etc/hostapd/hostapd.conf
sudo dnsmasq --test
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For support, please:

1. Check the troubleshooting section
2. Review the logs for error messages
3. Open an issue on GitHub
4. Include system information and logs

## 🏆 Credits

- Built with Flask and modern web technologies
- Inspired by WiFi vending solutions
- Designed for Raspberry Pi platform

## 📈 Roadmap

- [ ] Payment integration (coin acceptor support)
- [ ] Usage statistics and reporting
- [ ] Multiple language support
- [ ] Mobile app for administration
- [ ] Advanced user management
- [ ] Bandwidth limiting per session
- [ ] SMS verification integration

---

**Made with ❤️ for the Raspberry Pi community**