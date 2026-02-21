#!/usr/bin/env bats

# Tests for lib/health_check.sh — Pre-Loop Health Check

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
    source "$REPO_ROOT/lib/health_check.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# --- check_dependencies ---

@test "check_dependencies passes when jq and git present" {
    run check_dependencies
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# --- check_session_health ---

@test "check_session_health OK when no session file" {
    mkdir -p .korero
    run check_session_health .korero
    [ "$status" -eq 0 ]
    [[ "$output" == *"No active session"* ]]
}

@test "check_session_health WARN when session file is empty" {
    mkdir -p .korero
    touch .korero/.claude_session_id
    run check_session_health .korero
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
}

@test "check_session_health OK with valid session" {
    mkdir -p .korero
    echo "test-session-123" > .korero/.claude_session_id
    run check_session_health .korero
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# --- check_rate_limit_health ---

@test "check_rate_limit_health OK when no call count file" {
    mkdir -p .korero
    run check_rate_limit_health .korero 100
    [ "$status" -eq 0 ]
    [[ "$output" == *"0/100"* ]]
}

@test "check_rate_limit_health OK with low usage" {
    mkdir -p .korero
    echo "10" > .korero/.call_count
    run check_rate_limit_health .korero 100
    [ "$status" -eq 0 ]
    [[ "$output" == *"10/100"* ]]
}

@test "check_rate_limit_health WARN near capacity" {
    mkdir -p .korero
    echo "92" > .korero/.call_count
    run check_rate_limit_health .korero 100
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
}

@test "check_rate_limit_health ERROR when exhausted" {
    mkdir -p .korero
    echo "100" > .korero/.call_count
    run check_rate_limit_health .korero 100
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"exhausted"* ]]
}

# --- check_config_health ---

@test "check_config_health WARN when no config file" {
    run check_config_health nonexistent.rc
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
}

@test "check_config_health OK with valid config" {
    cat > .korerorc << 'EOF'
KORERO_MODE="coding"
MAX_LOOPS=10
EOF
    run check_config_health .korerorc
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "check_config_health ERROR with unmatched quotes" {
    cat > .korerorc << 'EOF'
KORERO_MODE="coding
EOF
    run check_config_health .korerorc
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"unmatched"* ]]
}

# --- check_tools_health ---

@test "check_tools_health WARN when empty" {
    run check_tools_health ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
}

@test "check_tools_health OK with preset" {
    run check_tools_health "@standard"
    [ "$status" -eq 0 ]
    [[ "$output" == *"preset"* ]]
}

@test "check_tools_health WARN with unknown preset" {
    run check_tools_health "@unknown"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
}

@test "check_tools_health OK with valid tool list" {
    run check_tools_health "Write,Read,Edit,Bash(git *)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "check_tools_health WARN when missing basic tools" {
    run check_tools_health "Bash(git *)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"missing basic"* ]]
}

# --- check_project_health ---

@test "check_project_health ERROR when no .korero dir" {
    run check_project_health .korero
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
}

@test "check_project_health OK with valid structure" {
    mkdir -p .korero
    echo "# Prompt" > .korero/PROMPT.md
    echo "# Plan" > .korero/fix_plan.md
    run check_project_health .korero
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "check_project_health WARN with missing files" {
    mkdir -p .korero
    run check_project_health .korero
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"PROMPT.md"* ]]
}

# --- run_health_checks ---

@test "run_health_checks shows header" {
    mkdir -p .korero
    echo "# Prompt" > .korero/PROMPT.md
    echo "# Plan" > .korero/fix_plan.md
    run run_health_checks .korero 100 "Write,Read,Edit"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pre-Loop Health Check"* ]]
}

@test "run_health_checks returns 1 on errors" {
    mkdir -p .korero
    echo "100" > .korero/.call_count
    run run_health_checks .korero 100 ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAILED"* ]]
}

@test "run_health_checks passes with clean environment" {
    mkdir -p .korero
    echo "# Prompt" > .korero/PROMPT.md
    echo "# Plan" > .korero/fix_plan.md
    cat > .korerorc << 'EOF'
KORERO_MODE="coding"
EOF
    run run_health_checks .korero 100 "Write,Read,Edit"
    [ "$status" -eq 0 ]
}
