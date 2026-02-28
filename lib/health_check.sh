#!/usr/bin/env bash
# health_check.sh — Environment health check for Korero
#
# Validates all prerequisites for running Korero:
# Claude CLI, required tools, git config, permissions, network, configuration.

KORERO_DIR="${KORERO_DIR:-.korero}"

# Run all health checks and print a formatted report
# Returns 0 if all checks pass, number of issues otherwise
run_health_check() {
    local issues=0

    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║          KORERO HEALTH CHECK                         ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""

    # Platform / environment
    echo "Environment:"
    local platform
    platform=$(uname -s 2>/dev/null || echo "unknown")
    local shell_ver
    shell_ver=$("${SHELL:-bash}" --version 2>/dev/null | head -1 || echo "unknown")
    echo "  ✓ Platform: $platform"
    echo "  ✓ Shell: $shell_ver"
    echo ""

    # Required tools
    echo "Required Tools:"
    local claude_hint="npm install -g @anthropic/claude-code"
    check_tool "claude" "Claude CLI" "$claude_hint" || issues=$((issues + 1))
    check_tool "jq" "jq" "brew install jq (macOS) or apt install jq (Ubuntu)" || issues=$((issues + 1))
    check_tool "git" "git" "Install from https://git-scm.com/" || issues=$((issues + 1))
    check_timeout_tool || issues=$((issues + 1))
    echo ""

    # Git configuration
    echo "Git Configuration:"
    check_git_config || issues=$((issues + 1))
    echo ""

    # Directory permissions
    echo "Permissions:"
    check_permissions || issues=$((issues + 1))
    echo ""

    # Network connectivity
    echo "Network:"
    check_network || issues=$((issues + 1))
    echo ""

    # Codex CLI (heavy modes only)
    local current_mode="${KORERO_MODE:-coding}"
    if [[ "$current_mode" == "heavy-coding" || "$current_mode" == "heavy-idea" ]]; then
        echo "Codex CLI (Heavy Mode):"
        check_codex_tool || issues=$((issues + 1))
        check_codex_auth_health || issues=$((issues + 1))
        check_codex_network || issues=$((issues + 1))
        echo ""
    fi

    # Configuration file (only if present)
    if [[ -f ".korerorc" ]]; then
        echo "Configuration:"
        check_config || issues=$((issues + 1))
        echo ""
    fi

    # Summary
    echo "═══════════════════════════════════════════════════════"
    if [[ $issues -eq 0 ]]; then
        echo "All checks passed. Korero is ready to run."
    else
        echo "$issues issue(s) found. Fix the above before running Korero."
    fi
    echo "═══════════════════════════════════════════════════════"
    echo ""

    return $issues
}

# Check if a command-line tool is installed
# Arguments: cmd, display_name, install_hint
check_tool() {
    local cmd="$1"
    local name="$2"
    local install_hint="$3"

    if command -v "$cmd" &>/dev/null; then
        local version
        version=$("$cmd" --version 2>/dev/null | head -1 || echo "available")
        echo "  ✓ $name: $version"
        return 0
    else
        echo "  ✗ $name: not found"
        echo "    → Install: $install_hint"
        return 1
    fi
}

# Check for timeout or gtimeout (cross-platform)
check_timeout_tool() {
    if command -v timeout &>/dev/null; then
        local ver
        ver=$(timeout --version 2>/dev/null | head -1 || echo "available")
        echo "  ✓ timeout: $ver"
        return 0
    elif command -v gtimeout &>/dev/null; then
        local ver
        ver=$(gtimeout --version 2>/dev/null | head -1 || echo "available")
        echo "  ✓ gtimeout: $ver"
        return 0
    else
        echo "  ✗ timeout: not found"
        echo "    → Install: brew install coreutils (macOS)"
        return 1
    fi
}

# Check git user.name and user.email are configured
check_git_config() {
    local issues=0
    local name
    name=$(git config user.name 2>/dev/null || echo "")
    local email
    email=$(git config user.email 2>/dev/null || echo "")

    if [[ -n "$name" ]]; then
        echo "  ✓ user.name: $name"
    else
        echo "  ✗ user.name: not set"
        echo "    → Run: git config --global user.name \"Your Name\""
        issues=$((issues + 1))
    fi

    if [[ -n "$email" ]]; then
        echo "  ✓ user.email: $email"
    else
        echo "  ✗ user.email: not set"
        echo "    → Run: git config --global user.email \"you@example.com\""
        issues=$((issues + 1))
    fi

    return $issues
}

# Check write permissions on the .korero directory
check_permissions() {
    local korero_dir="${KORERO_DIR:-.korero}"

    if [[ -d "$korero_dir" ]]; then
        if [[ -w "$korero_dir" ]]; then
            echo "  ✓ $korero_dir/: writable"
        else
            echo "  ✗ $korero_dir/: not writable"
            echo "    → Check directory permissions: ls -la $korero_dir"
            return 1
        fi
    else
        echo "  ○ $korero_dir/: does not exist (will be created on first run)"
    fi
    return 0
}

# Check network connectivity to api.anthropic.com
check_network() {
    if ! command -v curl &>/dev/null; then
        echo "  ○ api.anthropic.com: skipped (curl not available)"
        return 0
    fi

    local start_ms end_ms latency
    start_ms=$(date +%s%3N 2>/dev/null || date +%s)

    if curl -s --max-time 5 "https://api.anthropic.com" >/dev/null 2>&1; then
        end_ms=$(date +%s%3N 2>/dev/null || date +%s)
        latency=$((end_ms - start_ms))
        echo "  ✓ api.anthropic.com: reachable (${latency}ms)"
        return 0
    else
        echo "  ✗ api.anthropic.com: unreachable"
        echo "    → Check internet connection or proxy settings"
        echo "    → If behind corporate proxy, set HTTPS_PROXY environment variable"
        return 1
    fi
}

# Check .korerorc syntax validity
check_config() {
    if bash -n .korerorc 2>/dev/null; then
        echo "  ✓ .korerorc: valid syntax"
        return 0
    else
        echo "  ✗ .korerorc: syntax error"
        echo "    → Run: korero --validate-config for details"
        return 1
    fi
}

# Check if Codex CLI is installed (heavy modes)
check_codex_tool() {
    if command -v codex &>/dev/null; then
        local version
        version=$(codex --version 2>/dev/null | head -1 || echo "available")
        echo "  ✓ Codex CLI: $version"
        return 0
    else
        echo "  ✗ Codex CLI: not found"
        echo "    → Install: npm install -g @openai/codex"
        return 1
    fi
}

# Check Codex authentication status (heavy modes)
check_codex_auth_health() {
    local codex_home="${CODEX_HOME:-$HOME/.codex}"

    if [[ -f "$codex_home/auth.json" ]]; then
        echo "  ✓ Codex auth: configured (file)"
        return 0
    fi

    # Fallback: try codex login status
    if command -v codex &>/dev/null; then
        if codex login status &>/dev/null 2>&1; then
            echo "  ✓ Codex auth: configured (keyring)"
            return 0
        fi
    fi

    echo "  ✗ Codex auth: not configured"
    echo "    → Run: codex login --device-auth"
    return 1
}

# Check network connectivity to api.openai.com (heavy modes)
check_codex_network() {
    if ! command -v curl &>/dev/null; then
        echo "  ○ api.openai.com: skipped (curl not available)"
        return 0
    fi

    local start_ms end_ms latency
    start_ms=$(date +%s%3N 2>/dev/null || date +%s)

    if curl -s --max-time 5 "https://api.openai.com" >/dev/null 2>&1; then
        end_ms=$(date +%s%3N 2>/dev/null || date +%s)
        latency=$((end_ms - start_ms))
        echo "  ✓ api.openai.com: reachable (${latency}ms)"
        return 0
    else
        echo "  ✗ api.openai.com: unreachable"
        echo "    → Check internet connection or proxy settings"
        return 1
    fi
}

export -f run_health_check
export -f check_tool
export -f check_timeout_tool
export -f check_git_config
export -f check_permissions
export -f check_network
export -f check_config
export -f check_codex_tool
export -f check_codex_auth_health
export -f check_codex_network
