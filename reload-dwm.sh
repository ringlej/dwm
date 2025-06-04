#!/bin/bash
#
# reload-dwm.sh - A script to restart dwm after monitor configuration changes
#
# This script sends a signal to dwm to restart, which helps adapt to new monitor configurations
# It should be called after monitor-setup.sh if you want dwm to adapt to the new layout
#

# Find the dwm process ID
DWM_PID=$(pgrep -x dwm)

if [ -z "$DWM_PID" ]; then
    echo "dwm is not running"
    exit 1
fi

# Send SIGHUP to restart dwm
# Note: Make sure your dwm configuration is set up to handle SIGHUP for restarting
echo "Restarting dwm (PID: $DWM_PID)..."
kill -HUP $DWM_PID

echo "dwm restart signal sent"
