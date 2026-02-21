#!/bin/bash

# Korero for Claude Code - Global Installation Script
set -e

# Configuration
INSTALL_DIR="$HOME/.local/bin"
KORERO_HOME="$HOME/.korero"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Check dependencies
check_dependencies() {
    log "INFO" "Checking dependencies..."

    local missing_deps=()
    local os_type
    os_type=$(uname)

    if ! command -v node &> /dev/null && ! command -v npx &> /dev/null; then
        missing_deps+=("Node.js/npm")
    fi

    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi

    if ! command -v git &> /dev/null; then
        missing_deps+=("git")
    fi

    # Check for timeout command (platform-specific)
    if [[ "$os_type" == "Darwin" ]]; then
        # macOS: check for gtimeout from coreutils
        if ! command -v gtimeout &> /dev/null && ! command -v timeout &> /dev/null; then
            missing_deps+=("coreutils (for timeout command)")
        fi
    else
        # Linux: check for standard timeout command
        if ! command -v timeout &> /dev/null; then
            missing_deps+=("coreutils")
        fi
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log "ERROR" "Missing required dependencies: ${missing_deps[*]}"
        echo "Please install the missing dependencies:"
        echo "  Ubuntu/Debian: sudo apt-get install nodejs npm jq git coreutils"
        echo "  macOS: brew install node jq git coreutils"
        echo "  CentOS/RHEL: sudo yum install nodejs npm jq git coreutils"
        exit 1
    fi

    # Additional macOS-specific warning for coreutils
    if [[ "$os_type" == "Darwin" ]]; then
        if command -v gtimeout &> /dev/null; then
            log "INFO" "GNU coreutils detected (gtimeout available)"
        elif command -v timeout &> /dev/null; then
            log "INFO" "timeout command available"
        fi
    fi

    # Claude Code CLI will be downloaded automatically when first used
    log "INFO" "Claude Code CLI (@anthropic-ai/claude-code) will be downloaded when first used."

    # Check tmux (optional)
    if ! command -v tmux &> /dev/null; then
        log "WARN" "tmux not found. Install for integrated monitoring: apt-get install tmux / brew install tmux"
    fi

    log "SUCCESS" "Dependencies check completed"
}

# Create installation directory
create_install_dirs() {
    log "INFO" "Creating installation directories..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$KORERO_HOME"
    mkdir -p "$KORERO_HOME/templates"
    mkdir -p "$KORERO_HOME/lib"

    log "SUCCESS" "Directories created: $INSTALL_DIR, $KORERO_HOME"
}

# Install Korero scripts
install_scripts() {
    log "INFO" "Installing Korero scripts..."
    
    # Copy templates to Korero home
    cp -r "$SCRIPT_DIR/templates/"* "$KORERO_HOME/templates/"

    # Copy lib scripts (response_analyzer.sh, circuit_breaker.sh)
    cp -r "$SCRIPT_DIR/lib/"* "$KORERO_HOME/lib/"
    
    # Create the main korero command
    cat > "$INSTALL_DIR/korero" << 'EOF'
#!/bin/bash
# Korero for Claude Code - Main Command

KORERO_HOME="$HOME/.korero"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the actual korero loop script with global paths
exec "$KORERO_HOME/korero_loop.sh" "$@"
EOF

    # Create korero-monitor command
    cat > "$INSTALL_DIR/korero-monitor" << 'EOF'
#!/bin/bash
# Korero Monitor - Global Command

KORERO_HOME="$HOME/.korero"

exec "$KORERO_HOME/korero_monitor.sh" "$@"
EOF

    # Create korero-setup command
    cat > "$INSTALL_DIR/korero-setup" << 'EOF'
#!/bin/bash
# Korero Project Setup - Global Command

KORERO_HOME="$HOME/.korero"

exec "$KORERO_HOME/setup.sh" "$@"
EOF

    # Create korero-import command
    cat > "$INSTALL_DIR/korero-import" << 'EOF'
#!/bin/bash
# Korero PRD Import - Global Command

KORERO_HOME="$HOME/.korero"

exec "$KORERO_HOME/korero_import.sh" "$@"
EOF

    # Create korero-migrate command
    cat > "$INSTALL_DIR/korero-migrate" << 'EOF'
#!/bin/bash
# Korero Migration - Global Command
# Migrates existing projects from flat structure to .korero/ subfolder

KORERO_HOME="$HOME/.korero"

exec "$KORERO_HOME/migrate_to_korero_folder.sh" "$@"
EOF

    # Create korero-enable command (interactive wizard)
    cat > "$INSTALL_DIR/korero-enable" << 'EOF'
#!/bin/bash
# Korero Enable - Interactive Wizard for Existing Projects
# Adds Korero configuration to an existing codebase

KORERO_HOME="$HOME/.korero"

exec "$KORERO_HOME/korero_enable.sh" "$@"
EOF

    # Create korero-enable-ci command (non-interactive)
    cat > "$INSTALL_DIR/korero-enable-ci" << 'EOF'
#!/bin/bash
# Korero Enable CI - Non-Interactive Version for Automation
# Adds Korero configuration with sensible defaults

KORERO_HOME="$HOME/.korero"

exec "$KORERO_HOME/korero_enable_ci.sh" "$@"
EOF

    # Copy actual script files to Korero home with modifications for global operation
    cp "$SCRIPT_DIR/korero_monitor.sh" "$KORERO_HOME/"

    # Copy PRD import script to Korero home
    cp "$SCRIPT_DIR/korero_import.sh" "$KORERO_HOME/"

    # Copy migration script to Korero home
    cp "$SCRIPT_DIR/migrate_to_korero_folder.sh" "$KORERO_HOME/"

    # Copy enable scripts to Korero home
    cp "$SCRIPT_DIR/korero_enable.sh" "$KORERO_HOME/"
    cp "$SCRIPT_DIR/korero_enable_ci.sh" "$KORERO_HOME/"

    # Copy status, config, and ideas scripts to Korero home
    cp "$SCRIPT_DIR/korero_status.sh" "$KORERO_HOME/"
    cp "$SCRIPT_DIR/korero_config.sh" "$KORERO_HOME/"
    cp "$SCRIPT_DIR/korero_ideas.sh" "$KORERO_HOME/"

    # Make all commands executable
    chmod +x "$INSTALL_DIR/korero"
    chmod +x "$INSTALL_DIR/korero-monitor"
    chmod +x "$INSTALL_DIR/korero-setup"
    chmod +x "$INSTALL_DIR/korero-import"
    chmod +x "$INSTALL_DIR/korero-migrate"
    chmod +x "$INSTALL_DIR/korero-enable"
    chmod +x "$INSTALL_DIR/korero-enable-ci"
    chmod +x "$KORERO_HOME/korero_monitor.sh"
    chmod +x "$KORERO_HOME/korero_import.sh"
    chmod +x "$KORERO_HOME/migrate_to_korero_folder.sh"
    chmod +x "$KORERO_HOME/korero_enable.sh"
    chmod +x "$KORERO_HOME/korero_enable_ci.sh"
    chmod +x "$KORERO_HOME/korero_status.sh"
    chmod +x "$KORERO_HOME/korero_config.sh"
    chmod +x "$KORERO_HOME/korero_ideas.sh"
    chmod +x "$KORERO_HOME/lib/"*.sh

    log "SUCCESS" "Korero scripts installed to $INSTALL_DIR"
}

# Install global korero_loop.sh
install_korero_loop() {
    log "INFO" "Installing global korero_loop.sh..."
    
    # Create modified korero_loop.sh for global operation
    sed \
        -e "s|KORERO_HOME=\"\$HOME/.korero\"|KORERO_HOME=\"\$HOME/.korero\"|g" \
        -e "s|\$script_dir/korero_monitor.sh|\$KORERO_HOME/korero_monitor.sh|g" \
        -e "s|\$script_dir/korero_loop.sh|\$KORERO_HOME/korero_loop.sh|g" \
        "$SCRIPT_DIR/korero_loop.sh" > "$KORERO_HOME/korero_loop.sh"
    
    chmod +x "$KORERO_HOME/korero_loop.sh"
    
    log "SUCCESS" "Global korero_loop.sh installed"
}

# Install global setup.sh
install_setup() {
    log "INFO" "Installing global setup script..."

    # Copy the actual setup.sh from korero-claude-code root directory so setup information will be consistent
    if [[ -f "$SCRIPT_DIR/setup.sh" ]]; then
        cp "$SCRIPT_DIR/setup.sh" "$KORERO_HOME/setup.sh"
        chmod +x "$KORERO_HOME/setup.sh"
        log "SUCCESS" "Global setup script installed (copied from $SCRIPT_DIR/setup.sh)"
    else
        log "ERROR" "setup.sh not found in $SCRIPT_DIR"
        return 1
    fi
}

# Check PATH
check_path() {
    log "INFO" "Checking PATH configuration..."
    
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        log "WARN" "$INSTALL_DIR is not in your PATH"
        echo ""
        echo "Add this to your ~/.bashrc, ~/.zshrc, or ~/.profile:"
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo ""
        echo "Then run: source ~/.bashrc (or restart your terminal)"
        echo ""
    else
        log "SUCCESS" "$INSTALL_DIR is already in PATH"
    fi
}

# Main installation
main() {
    echo "🚀 Installing Korero for Claude Code globally..."
    echo ""
    
    check_dependencies
    create_install_dirs
    install_scripts
    install_korero_loop
    install_setup
    check_path
    
    echo ""
    log "SUCCESS" "🎉 Korero for Claude Code installed successfully!"
    echo ""
    echo "Global commands available:"
    echo "  korero --monitor          # Start Korero with integrated monitoring"
    echo "  korero --help            # Show Korero options"
    echo "  korero-setup my-project  # Create new Korero project"
    echo "  korero-enable            # Enable Korero in existing project (interactive)"
    echo "  korero-enable-ci         # Enable Korero in existing project (non-interactive)"
    echo "  korero-import prd.md     # Convert PRD to Korero project"
    echo "  korero-migrate           # Migrate existing project to .korero/ structure"
    echo "  korero-monitor           # Manual monitoring dashboard"
    echo ""
    echo "Quick start:"
    echo "  1. korero-setup my-awesome-project"
    echo "  2. cd my-awesome-project"
    echo "  3. # Edit .korero/PROMPT.md with your requirements"
    echo "  4. korero --monitor"
    echo ""
    
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        echo "⚠️  Don't forget to add $INSTALL_DIR to your PATH (see above)"
    fi
}

# Handle command line arguments
case "${1:-install}" in
    install)
        main
        ;;
    uninstall)
        log "INFO" "Uninstalling Korero for Claude Code..."
        rm -f "$INSTALL_DIR/korero" "$INSTALL_DIR/korero-monitor" "$INSTALL_DIR/korero-setup" "$INSTALL_DIR/korero-import" "$INSTALL_DIR/korero-migrate" "$INSTALL_DIR/korero-enable" "$INSTALL_DIR/korero-enable-ci"
        rm -rf "$KORERO_HOME"
        log "SUCCESS" "Korero for Claude Code uninstalled"
        ;;
    --help|-h)
        echo "Korero for Claude Code Installation"
        echo ""
        echo "Usage: $0 [install|uninstall]"
        echo ""
        echo "Commands:"
        echo "  install    Install Korero globally (default)"
        echo "  uninstall  Remove Korero installation"
        echo "  --help     Show this help"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac