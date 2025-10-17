document.addEventListener('DOMContentLoaded', function() {
    // Get device information
    loadDeviceInfo();
    
    // Add click handlers to option cards
    const optionCards = document.querySelectorAll('.option-card');
    optionCards.forEach(card => {
        card.addEventListener('click', function() {
            const duration = this.dataset.duration;
            const type = this.dataset.type;
            selectOption(duration, type);
        });
    });
    
    // Modal close handlers
    document.getElementById('close-success').addEventListener('click', function() {
        document.getElementById('success-modal').style.display = 'none';
    });
});

function loadDeviceInfo() {
    // Get client IP and MAC address
    fetch('/api/device-info')
        .then(response => response.json())
        .then(data => {
            document.getElementById('device-ip').textContent = data.ip || 'Unknown';
            document.getElementById('device-mac').textContent = data.mac || 'Unknown';
        })
        .catch(error => {
            console.error('Error loading device info:', error);
            document.getElementById('device-ip').textContent = 'Error loading';
            document.getElementById('device-mac').textContent = 'Error loading';
        });
}

function selectOption(duration, type) {
    // Show loading modal
    document.getElementById('loading-modal').style.display = 'block';
    
    // Update loading message based on type
    const loadingMessage = document.getElementById('loading-message');
    loadingMessage.textContent = `Activating ${type} access for ${duration} seconds...`;
    
    // Send request to activate internet access
    fetch('/api/activate', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({
            duration: parseInt(duration),
            type: type
        })
    })
    .then(response => response.json())
    .then(data => {
        // Hide loading modal
        document.getElementById('loading-modal').style.display = 'none';
        
        if (data.success) {
            // Show success modal
            document.getElementById('success-modal').style.display = 'block';
            
            // Start countdown timer
            startCountdown(data.remaining_time || duration);
            
            // Redirect to success page after a short delay
            setTimeout(() => {
                window.location.href = '/success';
            }, 2000);
        } else {
            alert('Error: ' + (data.error || 'Failed to activate access'));
        }
    })
    .catch(error => {
        console.error('Error activating access:', error);
        document.getElementById('loading-modal').style.display = 'none';
        alert('Network error. Please try again.');
    });
}

function startCountdown(seconds) {
    const timerElement = document.getElementById('countdown-timer');
    let remaining = seconds;
    
    function updateTimer() {
        const minutes = Math.floor(remaining / 60);
        const secs = remaining % 60;
        timerElement.textContent = `${minutes.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
        
        if (remaining <= 0) {
            timerElement.textContent = 'Expired';
            timerElement.style.color = '#e53e3e';
            return;
        }
        
        remaining--;
        setTimeout(updateTimer, 1000);
    }
    
    updateTimer();
}

// Handle page visibility change to refresh device info
document.addEventListener('visibilitychange', function() {
    if (!document.hidden) {
        loadDeviceInfo();
    }
});

// Check connection status periodically
function checkConnectionStatus() {
    fetch('/api/status')
        .then(response => response.json())
        .then(data => {
            if (data.connected && data.remaining_time > 0) {
                // User still has active connection, redirect to status page
                window.location.href = '/status';
            }
        })
        .catch(error => {
            // Ignore errors for status checks
            console.log('Status check failed:', error);
        });
}

// Check status every 30 seconds
setInterval(checkConnectionStatus, 30000);

// Add visual feedback for card interactions
document.querySelectorAll('.option-card').forEach(card => {
    card.addEventListener('mouseenter', function() {
        this.style.transform = 'translateY(-5px) scale(1.02)';
    });
    
    card.addEventListener('mouseleave', function() {
        this.style.transform = 'translateY(0) scale(1)';
    });
    
    card.addEventListener('mousedown', function() {
        this.style.transform = 'translateY(-2px) scale(0.98)';
    });
    
    card.addEventListener('mouseup', function() {
        this.style.transform = 'translateY(-5px) scale(1.02)';
    });
});

// Add keyboard navigation
document.addEventListener('keydown', function(event) {
    if (event.key >= '1' && event.key <= '3') {
        const cardIndex = parseInt(event.key) - 1;
        const cards = document.querySelectorAll('.option-card');
        if (cards[cardIndex]) {
            cards[cardIndex].click();
        }
    }
});

// Handle form submission for any forms on the page
document.addEventListener('submit', function(event) {
    event.preventDefault();
    // Handle any form submissions here if needed
});