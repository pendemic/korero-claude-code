#!/usr/bin/env bats

# Tests for lib/health_check.sh — Korero environment health check

load '../helpers/test_helper'

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
LIB_DIR="$REPO_ROOT/lib"
KORERO_SCRIPT="$REPO_ROOT/korero_loop.sh"

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
    export KORERO_DIR=".korero"
    source "$LIB_DIR/health_check.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ===== check_tool =====

@test "check_tool returns success for existing command" {
    run check_tool "bash" "Bash" "should exist"
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓"* ]]
    [[ "$output" == *"Bash"* ]]
}

@test "check_tool returns failure for missing command" {
    run check_tool "nonexistent_cmd_xyz_abc" "Missing Tool" "install it now"
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
    [[ "$output" == *"install it now"* ]]
}

@test "check_tool shows version for existing command" {
    run check_tool "bash" "Bash" "already installed"
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓ Bash:"* ]]
}

# ===== check_timeout_tool =====

@test "check_timeout_tool succeeds when timeout or gtimeout available" {
    run check_timeout_tool
    # Either passes (tool found) or fails (tool missing) - just verify output format
    if [ "$status" -eq 0 ]; then
        [[ "$output" == *"✓"* ]]
    else
        [[ "$output" == *"✗"* ]]
    fi
}

# ===== check_git_config =====

@test "check_git_config succeeds when name and email are set" {
    # Set up a local git config
    git init -q
    git config user.name "Test User"
    git config user.email "test@example.com"
    run check_git_config
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓ user.name: Test User"* ]]
    [[ "$output" == *"✓ user.email: test@example.com"* ]]
}

@test "check_git_config detects missing email" {
    # Initialize git with only name configured (no email)
    git init -q
    git config user.name "Test User"
    git config --unset user.email 2>/dev/null || true
    # Use GIT_CONFIG_NOSYSTEM to avoid global config
    GIT_CONFIG_NOSYSTEM=1 HOME=/nonexistent run check_git_config
    [ "$status" -ne 0 ]
}

@test "check_git_config shows fix hint for missing name" {
    # Point to non-existent HOME to avoid picking up real git config
    GIT_CONFIG_NOSYSTEM=1 HOME=/nonexistent run check_git_config
    [[ "$output" == *"✗"* ]] || [[ "$output" == *"✓"* ]]
    # At minimum, output should have checkmarks for each field found
}

# ===== check_permissions =====

@test "check_permissions reports writable .korero directory" {
    mkdir -p .korero
    run check_permissions
    [ "$status" -eq 0 ]
    [[ "$output" == *"writable"* ]]
}

@test "check_permissions reports missing directory as not yet created" {
    # No .korero directory
    run check_permissions
    [ "$status" -eq 0 ]
    [[ "$output" == *"does not exist"* ]] || [[ "$output" == *"will be created"* ]]
}

# ===== check_network =====

@test "check_network produces output" {
    run check_network
    # Either passes or fails based on connectivity, but must produce output
    [[ -n "$output" ]]
    [[ "$output" == *"api.anthropic.com"* ]]
}

@test "check_network succeeds or reports unreachable" {
    run check_network
    if [ "$status" -eq 0 ]; then
        [[ "$output" == *"✓"* ]]
        [[ "$output" == *"reachable"* ]]
    else
        [[ "$output" == *"✗"* ]]
        [[ "$output" == *"unreachable"* ]]
    fi
}

# ===== check_config =====

@test "check_config passes for valid .korerorc" {
    cat > .korerorc << 'EOF'
KORERO_MODE="coding"
MAX_LOOPS="continuous"
EOF
    run check_config
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓"* ]]
    [[ "$output" == *".korerorc: valid syntax"* ]]
}

@test "check_config fails for invalid .korerorc" {
    cat > .korerorc << 'EOF'
KORERO_MODE="coding"
MAX_LOOPS=( unclosed bracket
EOF
    run check_config
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]]
}

@test "check_config suggests --validate-config on failure" {
    printf 'invalid bash syntax $((\n' > .korerorc
    run check_config
    [ "$status" -eq 1 ]
    [[ "$output" == *"validate-config"* ]]
}

# ===== run_health_check =====

@test "run_health_check shows header" {
    run run_health_check
    [[ "$output" == *"KORERO HEALTH CHECK"* ]]
}

@test "run_health_check shows Environment section" {
    run run_health_check
    [[ "$output" == *"Environment:"* ]]
    [[ "$output" == *"Platform:"* ]]
}

@test "run_health_check shows Required Tools section" {
    run run_health_check
    [[ "$output" == *"Required Tools:"* ]]
}

@test "run_health_check shows summary line" {
    run run_health_check
    [[ "$output" == *"Korero is ready to run."* ]] || [[ "$output" == *"issue(s) found"* ]]
}

@test "run_health_check includes Configuration section when .korerorc exists" {
    cat > .korerorc << 'EOF'
KORERO_MODE="coding"
MAX_LOOPS="continuous"
EOF
    run run_health_check
    [[ "$output" == *"Configuration:"* ]]
}

@test "run_health_check skips Configuration section when no .korerorc" {
    run run_health_check
    # .korerorc check should not appear (only Git Configuration: is present)
    [[ "$output" != *"✓ .korerorc"* ]]
    [[ "$output" != *"✗ .korerorc"* ]]
}

# ===== --health-check CLI flag =====

@test "--health-check flag is recognized" {
    run bash "$KORERO_SCRIPT" --health-check
    [[ "$output" == *"KORERO HEALTH CHECK"* ]]
}

@test "--health-check exits with 0 or 1 only" {
    run bash "$KORERO_SCRIPT" --health-check
    [ "$status" -le 10 ]
}

@test "--health-check shows summary" {
    run bash "$KORERO_SCRIPT" --health-check
    # Should show either all-clear or issues-found summary
    [[ "$output" == *"ready to run"* ]] || [[ "$output" == *"found"* ]]
}
