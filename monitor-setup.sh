#!/bin/bash
#
# monitor-setup.sh - A robust script for managing external monitor configurations
#
# Usage:
#   ./monitor-setup.sh [single|triple|auto|save|load|clean] [name]
#     single: Configure for a single external monitor above laptop
#     triple: Configure for triple monitor setup (left, laptop, right)
#     auto: Auto-detect and apply best configuration
#     clean: Clean up ghost monitors and reset to only connected monitors
#     save <name>: Save current configuration with a name
#     load <name>: Load a previously saved configuration
#
# Author: GitHub Copilot

# Exit immediately if a command exits with a non-zero status
set -e

# Lock file to prevent multiple simultaneous executions
LOCK_FILE="/tmp/monitor-setup.lock"

# Terminal colors for better feedback
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log function for better feedback
log() {
    local level=$1
    local message=$2
    local color=$NC

    case $level in
        "INFO") color=$GREEN ;;
        "WARN") color=$YELLOW ;;
        "ERROR") color=$RED ;;
        "DEBUG") color=$BLUE ;;
    esac

    echo -e "${color}[$(date '+%H:%M:%S')] [$level] $message${NC}"
}

# Create a lock file to prevent multiple script executions
create_lock() {
    if [ -e "$LOCK_FILE" ]; then
        pid=$(cat "$LOCK_FILE")
        if ps -p "$pid" > /dev/null; then
            log "WARN" "Another instance is already running with PID $pid"
            exit 1
        else
            log "WARN" "Found stale lock file. Removing."
            rm -f "$LOCK_FILE"
        fi
    fi
    echo $$ > "$LOCK_FILE"
    log "DEBUG" "Lock file created"
}

# Remove the lock file
remove_lock() {
    rm -f "$LOCK_FILE"
    log "DEBUG" "Lock file removed"
}

# Function to get connected monitors
get_connected_monitors() {
    xrandr --query | grep " connected" | awk '{print $1}'
}

# Function to get disconnected monitors
get_disconnected_monitors() {
    xrandr --query | grep " disconnected" | awk '{print $1}'
}

# Function to get all monitors that show up in xrandr --listmonitors
get_active_monitors() {
    xrandr --listmonitors | grep -v "^Monitors:" | awk '{print $NF}'
}

# Function to detect ghost monitors (monitors that appear active but are actually disconnected)
get_ghost_monitors() {
    local active_monitors=($(get_active_monitors))
    local connected_monitors=($(get_connected_monitors))
    local ghost_monitors=()

    # Check if any active monitors are not in the connected list
    for active in "${active_monitors[@]}"; do
        local is_connected=false
        for connected in "${connected_monitors[@]}"; do
            if [[ "$active" == "$connected" ]]; then
                is_connected=true
                break
            fi
        done
        if [[ "$is_connected" == false ]]; then
            ghost_monitors+=("$active")
        fi
    done

    echo "${ghost_monitors[@]}"
}

# Function to get the primary monitor (usually the laptop)
get_primary_monitor() {
    xrandr --query | grep "primary" | awk '{print $1}'
}

# Function to get the best resolution for a monitor
get_best_resolution() {
    local monitor=$1
    local preferred_res=""

    # Get all available resolutions for this monitor
    local resolutions=$(xrandr --query | grep -A 50 "^$monitor connected" | grep "^ " | grep -E "[0-9]+x[0-9]+" | awk '{print $1}')

    # Check if 4K resolution is available and prefer it
    for res in $resolutions; do
        local width=$(echo "$res" | cut -d'x' -f1)
        if [ "$width" -ge 3840 ]; then
            preferred_res="$res"
            break
        fi
    done

    # If no 4K found, try to find the preferred resolution (marked with +)
    if [ -z "$preferred_res" ]; then
        preferred_res=$(xrandr --query | grep -A 50 "^$monitor connected" | grep -m 1 "+" | tr -s ' ' | cut -d' ' -f2)
    fi

    # If still no preferred resolution found, get the highest resolution available
    if [ -z "$preferred_res" ]; then
        preferred_res=$(echo "$resolutions" | head -1)
    fi

    echo "$preferred_res"
}

# Function to check if the resolution is 4K
is_4k_resolution() {
    local resolution=$1
    local width=$(echo "$resolution" | cut -d'x' -f1)

    if [ "$width" -ge 3840 ]; then
        return 0  # true in bash
    else
        return 1  # false in bash
    fi
}

# Function to reset all monitors to a clean state
reset_monitors() {
    log "INFO" "Resetting all monitor configurations..."

    # First, handle ghost monitors that might be showing up as active but disconnected
    local ghost_monitors=($(get_ghost_monitors))
    if [ ${#ghost_monitors[@]} -gt 0 ]; then
        log "WARN" "Found ${#ghost_monitors[@]} ghost monitor(s): ${ghost_monitors[*]}"
        for ghost in "${ghost_monitors[@]}"; do
            log "DEBUG" "Disabling ghost monitor: $ghost"
            xrandr --output "$ghost" --off 2>/dev/null || true
        done
    fi

    # Disable all disconnected monitors to clean up any remaining ghosts
    for monitor in $(get_disconnected_monitors); do
        log "DEBUG" "Disabling disconnected monitor: $monitor"
        xrandr --output $monitor --off 2>/dev/null || true
    done

    # Reset all connected monitors to their defaults
    for monitor in $(get_connected_monitors); do
        log "DEBUG" "Resetting connected monitor: $monitor"
        xrandr --output $monitor --auto
    done

    # Force a final cleanup by turning off all outputs and then re-enabling connected ones
    log "DEBUG" "Performing final cleanup of all outputs..."
    xrandr --auto
}

# Function to clean up ghost monitors and disconnected displays
clean_ghost_monitors() {
    log "INFO" "Cleaning up ghost monitors and resetting display configuration..."

    # Temporarily disable exit-on-error to handle potential xrandr failures gracefully
    set +e

    # Get current state
    local ghost_monitors=($(get_ghost_monitors))
    local disconnected_monitors=($(get_disconnected_monitors))
    local connected_monitors=($(get_connected_monitors))

    log "INFO" "Current status:"
    log "INFO" "  Connected monitors: ${#connected_monitors[@]} (${connected_monitors[*]})"
    log "INFO" "  Disconnected monitors: ${#disconnected_monitors[@]} (${disconnected_monitors[*]})"
    log "INFO" "  Ghost monitors: ${#ghost_monitors[@]} (${ghost_monitors[*]})"

    # Turn off all ghost monitors
    if [ ${#ghost_monitors[@]} -gt 0 ]; then
        for ghost in "${ghost_monitors[@]}"; do
            log "DEBUG" "Turning off ghost monitor: $ghost"
            xrandr --output "$ghost" --off 2>/dev/null || true
        done
    fi

    # Turn off all disconnected monitors
    if [ ${#disconnected_monitors[@]} -gt 0 ]; then
        for monitor in "${disconnected_monitors[@]}"; do
            log "DEBUG" "Turning off disconnected monitor: $monitor"
            xrandr --output "$monitor" --off 2>/dev/null || true
        done
    fi

    # Reset connected monitors to auto configuration
    if [ ${#connected_monitors[@]} -gt 0 ]; then
        for monitor in "${connected_monitors[@]}"; do
            log "DEBUG" "Resetting connected monitor: $monitor"
            xrandr --output "$monitor" --auto
        done
    fi

    # Force a complete reset
    log "DEBUG" "Forcing complete xrandr reset..."
    xrandr --auto

    # Re-enable exit-on-error
    set -e

    # Verify cleanup
    local remaining_ghosts=($(get_ghost_monitors))
    if [ ${#remaining_ghosts[@]} -eq 0 ]; then
        log "INFO" "Ghost monitor cleanup completed successfully"
    else
        log "WARN" "Some ghost monitors may still remain: ${remaining_ghosts[*]}"
    fi
}

# Function to configure a single external monitor above laptop
configure_single_monitor() {
    log "INFO" "Configuring single external monitor setup..."

    local primary=$(get_primary_monitor)
    local connected=($(get_connected_monitors))

    if [ ${#connected[@]} -lt 2 ]; then
        log "ERROR" "Not enough monitors connected for single monitor setup. Found: ${#connected[@]}"
        log "INFO" "Using only the primary monitor."
        reset_monitors
        return 1
    fi

    # Find the external monitor (the one that is not the primary)
    local external=""
    for monitor in "${connected[@]}"; do
        if [ "$monitor" != "$primary" ]; then
            external=$monitor
            break
        fi
    done

    if [ -z "$external" ]; then
        log "ERROR" "Could not identify external monitor."
        reset_monitors
        return 1
    fi

    # Get the best resolution for each monitor
    local primary_res=$(get_best_resolution "$primary")
    local external_res=$(get_best_resolution "$external")

    log "INFO" "Primary monitor: $primary ($primary_res)"
    log "INFO" "External monitor: $external ($external_res)"

    # Apply the configuration
    xrandr --output "$primary" --auto --primary

    # Try up to 3 times in case of failure
    local attempt=1
    local max_attempts=3
    local success=false

    while [ $attempt -le $max_attempts ] && [ "$success" = false ]; do
        log "DEBUG" "Attempt $attempt of $max_attempts..."

        # Set specific resolution for external monitor if we found one, otherwise use auto
        if [ -n "$external_res" ] && [ "$external_res" != "connected" ]; then
            if xrandr --output "$external" --mode "$external_res" --above "$primary"; then
                log "INFO" "Successfully configured external monitor above primary at $external_res."
                success=true
            else
                log "WARN" "Failed to set $external_res, trying auto mode..."
                if xrandr --output "$external" --auto --above "$primary"; then
                    log "INFO" "Successfully configured external monitor above primary with auto resolution."
                    success=true
                fi
            fi
        else
            if xrandr --output "$external" --auto --above "$primary"; then
                log "INFO" "Successfully configured external monitor above primary."
                success=true
            fi
        fi

        if [ "$success" = false ]; then
            log "WARN" "Failed to configure monitors on attempt $attempt. Retrying..."
            sleep 1
            attempt=$((attempt + 1))
        fi
    done

    if [ "$success" = false ]; then
        log "ERROR" "Failed to configure single monitor setup after $max_attempts attempts."
        reset_monitors
        return 1
    fi

    return 0
}

# Function to configure triple monitor setup
configure_triple_monitor() {
    log "INFO" "Configuring triple monitor setup..."

    local primary=$(get_primary_monitor)
    local connected=($(get_connected_monitors))

    if [ ${#connected[@]} -lt 3 ]; then
        log "ERROR" "Not enough monitors connected for triple monitor setup. Found: ${#connected[@]}"
        log "INFO" "Falling back to single monitor setup if possible."
        configure_single_monitor
        return 1
    fi

    # We need to identify the left and right monitors
    # For simplicity, we'll assume the first non-primary monitor is left and the second is right
    local left=""
    local right=""

    for monitor in "${connected[@]}"; do
        if [ "$monitor" != "$primary" ]; then
            if [ -z "$left" ]; then
                left=$monitor
            elif [ -z "$right" ]; then
                right=$monitor
            fi
        fi
    done

    if [ -z "$left" ] || [ -z "$right" ]; then
        log "ERROR" "Could not identify left and right monitors."
        reset_monitors
        return 1
    fi

    # Get the best resolution for each monitor
    local primary_res=$(get_best_resolution "$primary")
    local left_res=$(get_best_resolution "$left")
    local right_res=$(get_best_resolution "$right")

    log "INFO" "Primary monitor: $primary ($primary_res)"
    log "INFO" "Left monitor: $left ($left_res)"
    log "INFO" "Right monitor: $right ($right_res)"

    # Apply the configuration
    xrandr --output "$primary" --auto --primary

    # Try up to 3 times in case of failure
    local attempt=1
    local max_attempts=3
    local success=false

    while [ $attempt -le $max_attempts ] && [ "$success" = false ]; do
        log "DEBUG" "Attempt $attempt of $max_attempts..."

        if xrandr --output "$left" --auto --left-of "$primary" && \
           xrandr --output "$right" --auto --right-of "$primary"; then
            log "INFO" "Successfully configured triple monitor setup."
            success=true
        else
            log "WARN" "Failed to configure monitors on attempt $attempt. Retrying..."
            sleep 1
            attempt=$((attempt + 1))
        fi
    done

    if [ "$success" = false ]; then
        log "ERROR" "Failed to configure triple monitor setup after $max_attempts attempts."
        reset_monitors
        return 1
    fi

    return 0
}

# Function to auto-detect and apply the best configuration
auto_detect_configuration() {
    log "INFO" "Auto-detecting best monitor configuration..."

    local connected=($(get_connected_monitors))
    local num_connected=${#connected[@]}

    log "INFO" "Detected $num_connected connected monitors."

    case $num_connected in
        1)
            log "INFO" "Only one monitor detected. Using basic setup."
            reset_monitors
            ;;
        2)
            log "INFO" "Two monitors detected. Using single external monitor setup."
            configure_single_monitor
            ;;
        3)
            log "INFO" "Three monitors detected. Using triple monitor setup."
            configure_triple_monitor
            ;;
        *)
            log "WARN" "Unusual number of monitors: $num_connected. Using auto configuration."
            reset_monitors
            ;;
    esac
}

# Function to save the current configuration
save_configuration() {
    local mode=$1
    local config_dir="$HOME/.config/monitor-setup"
    local config_file="$config_dir/$mode.conf"

    mkdir -p "$config_dir"

    log "INFO" "Saving current configuration as '$mode'..."

    # Save the xrandr output
    xrandr --query > "$config_file"

    log "INFO" "Configuration saved to $config_file"
}

# Function to load a saved configuration
load_configuration() {
    local mode=$1
    local config_dir="$HOME/.config/monitor-setup"
    local config_file="$config_dir/$mode.conf"

    if [ ! -f "$config_file" ]; then
        log "ERROR" "No saved configuration found for '$mode'"
        return 1
    fi

    log "INFO" "Loading configuration from $config_file..."

    # Extract the monitor setup commands from the saved configuration
    # This is a basic implementation - might need adjustments based on the saved format
    local commands=$(grep -E "^Screen |^  [0-9]+" "$config_file" | grep -v "disconnected")

    if [ -z "$commands" ]; then
        log "ERROR" "Failed to extract configuration from $config_file"
        return 1
    fi

    # Apply the commands
    # Note: This is a simplified implementation - you might need to parse the output more carefully
    xrandr --auto  # Reset first

    for line in $commands; do
        if [[ $line =~ ^Screen ]]; then
            continue  # Skip Screen lines
        fi

        # Parse resolution line and apply
        local output=$(echo "$line" | awk '{print $1}')
        local resolution=$(echo "$line" | awk '{print $2}')

        log "DEBUG" "Setting $output to $resolution"
        xrandr --output "$output" --mode "$resolution"
    done

    log "INFO" "Configuration loaded successfully"
    return 0
}

# Main function
main() {
    local mode=${1:-"auto"}
    local action=$2

    log "INFO" "Starting monitor setup in '$mode' mode..."

    # Handle special actions
    if [ "$mode" = "save" ]; then
        if [ -z "$action" ]; then
            log "ERROR" "Save requires a name parameter"
            log "INFO" "Usage: ./monitor-setup.sh save <name>"
            exit 1
        fi
        save_configuration "$action"
        return
    elif [ "$mode" = "load" ]; then
        if [ -z "$action" ]; then
            log "ERROR" "Load requires a name parameter"
            log "INFO" "Usage: ./monitor-setup.sh load <name>"
            exit 1
        fi
        load_configuration "$action"
        return
    elif [ "$mode" = "clean" ]; then
        clean_ghost_monitors
        return
    fi

    # First, reset all monitors to clean state
    reset_monitors

    # Then apply the requested configuration
    case $mode in
        "single")
            configure_single_monitor
            ;;
        "triple")
            configure_triple_monitor
            ;;
        "auto")
            auto_detect_configuration
            ;;
        *)
            log "ERROR" "Unknown mode: $mode"
            log "INFO" "Available modes: single, triple, auto, clean, save, load"
            exit 1
            ;;
    esac

    log "INFO" "Monitor setup completed."
}

# Execute the main function with the provided argument
create_lock
trap remove_lock EXIT
main "$@"
