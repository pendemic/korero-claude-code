#!/bin/bash

# Korero for Claude Code - Uninstallation Script
set -e

# Configuration
INSTALL_DIR="$HOME/.local/bin"
KORERO_HOME="$HOME/.korero"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Log a message with timestamp and color coding
# Arguments:
#   $1 - Log level (INFO, WARN, ERROR, SUCCESS)
#   $2 - Message to log
# Output: Writes colored, timestamped message to stdout
# Uses: Color variables (RED, GREEN, YELLOW, BLUE, NC)
log() {
    local level=$1
    local message=$2
    local color=""

    case $level in
        "INFO")  color=$BLUE ;;
        "WARN")  color=$YELLOW ;;
        "ERROR") color=$RED ;;
        "SUCCESS") color=$GREEN ;;
    esac

    echo -e "${color}[$(date '+%H:%M:%S')] [$level] $message${NC}"
}

# Check if Korero is installed by verifying commands or home directory exist
# Uses: INSTALL_DIR, KORERO_HOME environment variables
# Behavior: Checks for any Korero command or home directory
# Exit: Exits with status 0 if not installed, displaying checked locations
check_installation() {
    local installed=false

    # Check for any of the Korero commands
    for cmd in korero korero-monitor korero-setup korero-import; do
        if [ -f "$INSTALL_DIR/$cmd" ]; then
            installed=true
            break
        fi
    done

    # Also check for Korero home directory
    if [ "$installed" = false ] && [ -d "$KORERO_HOME" ]; then
        installed=true
    fi

    if [ "$installed" = false ]; then
        log "WARN" "Korero does not appear to be installed"
        echo "Checked locations:"
        echo "  - $INSTALL_DIR/{korero,korero-monitor,korero-setup,korero-import}"
        echo "  - $KORERO_HOME"
        exit 0
    fi
}

# Display a plan of what will be removed during uninstallation
# Uses: INSTALL_DIR, KORERO_HOME environment variables
# Output: Prints list of Korero commands and home directory to stdout
# Behavior: Shows only items that actually exist on the system
show_removal_plan() {
    echo ""
    log "INFO" "The following will be removed:"
    echo ""

    # Commands
    echo "Commands in $INSTALL_DIR:"
    for cmd in korero korero-monitor korero-setup korero-import; do
        if [ -f "$INSTALL_DIR/$cmd" ]; then
            echo "  - $cmd"
        fi
    done

    # Korero home
    if [ -d "$KORERO_HOME" ]; then
        echo ""
        echo "Korero home directory:"
        echo "  - $KORERO_HOME (includes templates, scripts, and libraries)"
    fi

    echo ""
}

# Prompt user to confirm uninstallation
# Arguments:
#   $1 - Optional flag (-y or --yes) to skip confirmation prompt
# Behavior: Returns 0 if confirmed, exits with 0 if cancelled
# Exit: Exits with status 0 if user declines confirmation
confirm_uninstall() {
    if [ "${1:-}" = "-y" ] || [ "${1:-}" = "--yes" ]; then
        return 0
    fi

    read -p "Are you sure you want to uninstall Korero? [y/N] " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Uninstallation cancelled"
        exit 0
    fi
}

# Remove Korero commands from INSTALL_DIR
# Removes: korero, korero-monitor, korero-setup, korero-import
# Uses: INSTALL_DIR environment variable
# Output: Logs success with count of removed commands, or info if none found
remove_commands() {
    log "INFO" "Removing Korero commands..."

    local removed=0
    for cmd in korero korero-monitor korero-setup korero-import; do
        if [ -f "$INSTALL_DIR/$cmd" ]; then
            rm -f "$INSTALL_DIR/$cmd"
            removed=$((removed + 1))
        fi
    done

    if [ $removed -gt 0 ]; then
        log "SUCCESS" "Removed $removed command(s) from $INSTALL_DIR"
    else
        log "INFO" "No commands found in $INSTALL_DIR"
    fi
}

# Remove Korero home directory containing templates, scripts, and libraries
# Uses: KORERO_HOME environment variable
# Behavior: Removes directory recursively if it exists
# Output: Logs success if removed, or info if directory not found
remove_korero_home() {
    log "INFO" "Removing Korero home directory..."

    if [ -d "$KORERO_HOME" ]; then
        rm -rf "$KORERO_HOME"
        log "SUCCESS" "Removed $KORERO_HOME"
    else
        log "INFO" "Korero home directory not found"
    fi
}

# Main uninstallation flow for Korero for Claude Code
# Arguments:
#   $1 - Optional flag passed to confirm_uninstall (-y/--yes)
# Behavior: Orchestrates full uninstall by calling check, plan, confirm, and remove functions
# Note: Does not remove project directories created with korero-setup
main() {
    echo "🗑️  Uninstalling Korero for Claude Code..."

    check_installation
    show_removal_plan
    confirm_uninstall "$1"

    echo ""
    remove_commands
    remove_korero_home

    echo ""
    log "SUCCESS" "Korero for Claude Code has been uninstalled"
    echo ""
    echo "Note: Project files created with korero-setup are not removed."
    echo "You can safely delete those project directories manually if needed."
    echo ""
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        echo "Korero for Claude Code - Uninstallation Script"
        echo ""
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  -y, --yes    Skip confirmation prompt"
        echo "  -h, --help   Show this help message"
        echo ""
        echo "This script removes:"
        echo "  - Korero commands from $INSTALL_DIR"
        echo "  - Korero home directory ($KORERO_HOME)"
        echo ""
        echo "Project directories created with korero-setup are NOT removed."
        ;;
    *)
        main "$1"
        ;;
esac
