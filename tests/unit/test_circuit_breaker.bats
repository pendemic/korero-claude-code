#!/usr/bin/env bats

# Tests for lib/circuit_breaker.sh — Circuit breaker and recovery suggestions

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"

    export KORERO_DIR=".korero"
    mkdir -p "$KORERO_DIR"

    source "$REPO_ROOT/lib/date_utils.sh"
    source "$REPO_ROOT/lib/circuit_breaker.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# =============================================================================
# format_recovery_suggestion tests
# =============================================================================

@test "format_recovery_suggestion shows no_progress guidance" {
    result=$(format_recovery_suggestion "No progress detected in 3 consecutive loops")
    [[ "$result" == *"No file changes"* ]]
    [[ "$result" == *"ALLOWED_TOOLS"* ]]
    [[ "$result" == *"fix_plan.md"* ]]
}

@test "format_recovery_suggestion shows same_error guidance" {
    result=$(format_recovery_suggestion "Same error repeated in 5 consecutive loops")
    [[ "$result" == *"Same error pattern"* ]]
    [[ "$result" == *"test failure"* ]]
    [[ "$result" == *"git log"* ]]
}

@test "format_recovery_suggestion shows permission guidance" {
    result=$(format_recovery_suggestion "Permission denied in 2 consecutive loops")
    [[ "$result" == *"Permission denied"* ]]
    [[ "$result" == *"ALLOWED_TOOLS"* ]]
}

@test "format_recovery_suggestion shows output decline guidance" {
    result=$(format_recovery_suggestion "Output volume declined by 75%")
    [[ "$result" == *"Output volume"* ]] || [[ "$result" == *"declined"* ]]
    [[ "$result" == *"reset-session"* ]]
}

@test "format_recovery_suggestion shows generic guidance for unknown reasons" {
    result=$(format_recovery_suggestion "Some unknown reason")
    [[ "$result" == *"Some unknown reason"* ]]
    [[ "$result" == *"Review recent logs"* ]]
}

@test "format_recovery_suggestion always shows recovery steps" {
    result=$(format_recovery_suggestion "No progress detected in 3 consecutive loops")
    [[ "$result" == *"reset-circuit"* ]]
    [[ "$result" == *"Restart the loop"* ]]
}

@test "format_recovery_suggestion handles No recovery reason" {
    result=$(format_recovery_suggestion "No recovery, opening circuit after 3 loops")
    [[ "$result" == *"No file changes"* ]]
}

# =============================================================================
# init_circuit_breaker tests
# =============================================================================

@test "init_circuit_breaker creates state file" {
    init_circuit_breaker
    [[ -f "$CB_STATE_FILE" ]]
}

@test "init_circuit_breaker sets initial state to CLOSED" {
    init_circuit_breaker
    local state=$(jq -r '.state' "$CB_STATE_FILE")
    [[ "$state" == "CLOSED" ]]
}

# =============================================================================
# get_circuit_state tests
# =============================================================================

@test "get_circuit_state returns CLOSED for new circuit" {
    init_circuit_breaker
    result=$(get_circuit_state)
    [[ "$result" == "CLOSED" ]]
}

@test "get_circuit_state returns CLOSED when no state file exists" {
    result=$(get_circuit_state)
    [[ "$result" == "CLOSED" ]]
}

# =============================================================================
# can_execute tests
# =============================================================================

@test "can_execute returns 0 when circuit is closed" {
    init_circuit_breaker
    run can_execute
    [ "$status" -eq 0 ]
}

# =============================================================================
# should_halt_execution tests
# =============================================================================

@test "should_halt_execution returns 1 (no halt) when circuit closed" {
    init_circuit_breaker
    run should_halt_execution
    [ "$status" -eq 1 ]
}

@test "should_halt_execution returns 0 (halt) when circuit open" {
    init_circuit_breaker
    # Force circuit to OPEN
    cat > "$CB_STATE_FILE" << EOF
{
    "state": "OPEN",
    "last_change": "2024-01-01T00:00:00",
    "consecutive_no_progress": 3,
    "consecutive_same_error": 0,
    "consecutive_permission_denials": 0,
    "last_progress_loop": 0,
    "total_opens": 1,
    "reason": "No progress detected in 3 consecutive loops",
    "current_loop": 3
}
EOF
    run should_halt_execution
    [ "$status" -eq 0 ]
    [[ "$output" == *"No file changes"* ]]
    [[ "$output" == *"reset-circuit"* ]]
}

@test "should_halt_execution shows permission guidance when circuit opens for permission denial" {
    init_circuit_breaker
    cat > "$CB_STATE_FILE" << EOF
{
    "state": "OPEN",
    "last_change": "2024-01-01T00:00:00",
    "consecutive_no_progress": 0,
    "consecutive_same_error": 0,
    "consecutive_permission_denials": 2,
    "last_progress_loop": 0,
    "total_opens": 1,
    "reason": "Permission denied in 2 consecutive loops - update ALLOWED_TOOLS in .korerorc",
    "current_loop": 2
}
EOF
    run should_halt_execution
    [ "$status" -eq 0 ]
    [[ "$output" == *"Permission denied"* ]]
    [[ "$output" == *"ALLOWED_TOOLS"* ]]
}
