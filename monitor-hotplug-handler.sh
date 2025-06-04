#!/bin/bash
#
# monitor-hotplug-handler.sh - Handle monitor hotplug events from udev
#
# This script is called by udev and properly sets up the X11 environment
# to run the monitor-setup script

# Log file for debugging
LOG_FILE="/tmp/monitor-hotplug.log"

# Function to log messages
log_msg() {
    echo "$(date): $1" >> "$LOG_FILE"
}

log_msg "Monitor hotplug event detected"

# Find the user who owns the X session and their display
X_SESSION=$(who | grep -E ":\d+" | head -1)
X_USER=$(echo "$X_SESSION" | awk '{print $1}')
X_DISPLAY=$(echo "$X_SESSION" | grep -o '(:[0-9]*)' | tr -d '()')

# Fallbacks if detection fails
if [ -z "$X_USER" ] || [ "$X_USER" = "root" ]; then
    X_USER="jringle"  # fallback to your username
fi
if [ -z "$X_DISPLAY" ]; then
    X_DISPLAY=":1"  # fallback to your display
fi

log_msg "X_USER detected as: $X_USER"
log_msg "X_DISPLAY detected as: $X_DISPLAY"

# Get the user's home directory
USER_HOME=$(getent passwd "$X_USER" | cut -d: -f6)
log_msg "USER_HOME: $USER_HOME"

# Set up the environment for X11
export DISPLAY="$X_DISPLAY"

# Try to find the correct XAUTHORITY file
if [ -f "$USER_HOME/.Xauthority" ]; then
    export XAUTHORITY="$USER_HOME/.Xauthority"
elif [ -f "/tmp/.X11-unix/X0" ]; then
    # Try the session manager's auth file
    export XAUTHORITY="$(find /tmp -name "*X11-auth*" -user "$X_USER" 2>/dev/null | head -1)"
    if [ -z "$XAUTHORITY" ]; then
        export XAUTHORITY="$USER_HOME/.Xauthority"
    fi
else
    export XAUTHORITY="$USER_HOME/.Xauthority"
fi

log_msg "Environment set: DISPLAY=$DISPLAY, XAUTHORITY=$XAUTHORITY"

# Test if we can access X11
if sudo -u "$X_USER" xrandr --query > /dev/null 2>&1; then
    log_msg "X11 access successful, running monitor-setup"

    # Run the monitor setup as the correct user
    sudo -u "$X_USER" /usr/local/bin/monitor-setup auto >> "$LOG_FILE" 2>&1

    # Send notification if notify-send is available
    if command -v notify-send > /dev/null; then
        sudo -u "$X_USER" notify-send -i display "Monitor Change" "Display configuration updated" 2>/dev/null || true
    fi

    log_msg "Monitor setup completed"
else
    log_msg "Failed to access X11 display"
fi
