#!/bin/bash
#
# monitor-control.sh - A frontend for monitor-setup.sh with a simple menu
#
# This script provides a dmenu/rofi interface for selecting monitor configurations
# It can be bound to a keyboard shortcut in dwm for quick access
#

# Check if dmenu or rofi is installed
if command -v rofi >/dev/null 2>&1; then
    MENU_CMD="rofi -dmenu -p 'Monitor Setup:'"
elif command -v dmenu >/dev/null 2>&1; then
    MENU_CMD="dmenu -p 'Monitor Setup:'"
else
    echo "Error: Neither rofi nor dmenu is installed"
    exit 1
fi

# Path to the monitor setup script
MONITOR_SCRIPT="/home/jringle/git/dwm/monitor-setup.sh"

# Check if the script exists
if [ ! -f "$MONITOR_SCRIPT" ]; then
    echo "Error: Monitor setup script not found at $MONITOR_SCRIPT"
    exit 1
fi

# Get list of saved configurations
CONFIG_DIR="$HOME/.config/monitor-setup"
SAVED_CONFIGS=""
if [ -d "$CONFIG_DIR" ]; then
    SAVED_CONFIGS=$(find "$CONFIG_DIR" -type f -name "*.conf" | sed 's/.*\/\(.*\)\.conf/load \1/')
fi

# Build menu options
OPTIONS="auto\nsingle\ntriple"

# Add save option
OPTIONS="$OPTIONS\nsave"

# Add saved configurations if any
if [ -n "$SAVED_CONFIGS" ]; then
    OPTIONS="$OPTIONS\n$SAVED_CONFIGS"
fi

# Display menu and get user selection
SELECTION=$(echo -e "$OPTIONS" | eval "$MENU_CMD")

# Exit if no selection was made
if [ -z "$SELECTION" ]; then
    exit 0
fi

# Handle "save" option specially
if [ "$SELECTION" = "save" ]; then
    # Ask for a name for the configuration
    CONFIG_NAME=$(echo "" | eval "$MENU_CMD -p 'Save as:'")
    if [ -n "$CONFIG_NAME" ]; then
        $MONITOR_SCRIPT save "$CONFIG_NAME"
        # Optionally notify the user
        if command -v notify-send >/dev/null 2>&1; then
            notify-send "Monitor Setup" "Configuration saved as '$CONFIG_NAME'"
        fi
    fi
    exit 0
fi

# Handle "load" options
if [[ "$SELECTION" == load* ]]; then
    CONFIG_NAME=$(echo "$SELECTION" | cut -d' ' -f2)
    $MONITOR_SCRIPT load "$CONFIG_NAME"
else
    # Run the monitor setup script with the selected option
    $MONITOR_SCRIPT "$SELECTION"
fi

# Restart dwm to adapt to new layout
/home/jringle/git/dwm/reload-dwm.sh

# Optionally notify the user
if command -v notify-send >/dev/null 2>&1; then
    notify-send "Monitor Setup" "Applied configuration: $SELECTION"
fi
