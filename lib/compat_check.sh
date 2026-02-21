#!/usr/bin/env bash
# lib/compat_check.sh — Cross-platform compatibility detection
# Checks shell version, OS platform, and required utilities at startup

# Check if Bash version meets minimum requirement (4.0+)
check_bash_version() {
    local min_major=${1:-4}
    local min_minor=${2:-0}
    if [[ "${BASH_VERSINFO[0]}" -lt "$min_major" ]]; then
        return 1
    fi
    if [[ "${BASH_VERSINFO[0]}" -eq "$min_major" && "${BASH_VERSINFO[1]}" -lt "$min_minor" ]]; then
        return 1
    fi
    return 0
}

# Check for GNU coreutils (required for timeout on macOS)
check_gnu_utils() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if ! command -v gtimeout &>/dev/null && ! command -v timeout &>/dev/null; then
            return 1
        fi
    fi
    return 0
}

# Check for required commands
check_required_commands() {
    local missing=()
    for cmd in jq git; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "${missing[*]}"
        return 1
    fi
    return 0
}

# Detect the current platform
detect_platform() {
    case "$OSTYPE" in
        darwin*)  echo "macos" ;;
        linux*)   echo "linux" ;;
        msys*|cygwin*|mingw*) echo "windows" ;;
        *)        echo "unknown" ;;
    esac
}

# Run all compatibility checks and display warnings
# Returns 0 if all checks pass, 1 if warnings were emitted
# Pass --strict to make warnings fatal
run_compat_checks() {
    local strict=false
    [[ "${1:-}" == "--strict" ]] && strict=true

    local warnings=()
    local platform
    platform=$(detect_platform)

    # Check Bash version
    if ! check_bash_version 4 0; then
        warnings+=("WARNING: Bash ${BASH_VERSION} detected. Korero requires Bash 4.0+ for associative arrays.")
        case "$platform" in
            macos)   warnings+=("  Fix: brew install bash && add /opt/homebrew/bin/bash to /etc/shells") ;;
            windows) warnings+=("  Fix: Update Git Bash or use WSL with a recent Bash version") ;;
        esac
    fi

    # Check GNU coreutils
    if ! check_gnu_utils; then
        warnings+=("WARNING: GNU coreutils not found. Required for timeout functionality.")
        case "$platform" in
            macos) warnings+=("  Fix: brew install coreutils") ;;
        esac
    fi

    # Check required commands
    local missing_cmds
    if missing_cmds=$(check_required_commands); then
        : # all good
    else
        warnings+=("WARNING: Missing required commands: $missing_cmds")
        case "$platform" in
            macos)   warnings+=("  Fix: brew install $missing_cmds") ;;
            linux)   warnings+=("  Fix: sudo apt-get install $missing_cmds  (or equivalent for your distro)") ;;
        esac
    fi

    # Display warnings if any
    if [[ ${#warnings[@]} -gt 0 ]]; then
        echo ""
        echo "========================================="
        echo "  Korero Compatibility Warnings"
        echo "========================================="
        for w in "${warnings[@]}"; do
            echo "  $w"
        done
        echo "========================================="
        echo ""

        if [[ "$strict" == "true" ]]; then
            echo "ERROR: Compatibility checks failed in strict mode. Exiting."
            return 1
        fi
    fi

    return 0
}
