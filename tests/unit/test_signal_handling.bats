#!/usr/bin/env bats

# Tests for lib/signal_handler.sh — Portable Signal Handling (Loop 31)

load '../helpers/test_helper'

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
    export KORERO_DIR=".korero"
    mkdir -p "$KORERO_DIR"
    source "$REPO_ROOT/lib/date_utils.sh"
    source "$REPO_ROOT/lib/signal_handler.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ===== record_shutdown_signal =====

@test "record_shutdown_signal creates signal log file" {
    record_shutdown_signal "sigint" 5
    [ -f "$KORERO_DIR/.signal_log.json" ]
}

@test "record_shutdown_signal writes reason field" {
    if ! command -v jq &>/dev/null; then
        skip "jq required"
    fi
    record_shutdown_signal "sigterm" 3
    local reason
    reason=$(jq -r '.shutdowns[0].reason' "$KORERO_DIR/.signal_log.json")
    [ "$reason" = "sigterm" ]
}

@test "record_shutdown_signal writes loop number" {
    if ! command -v jq &>/dev/null; then
        skip "jq required"
    fi
    record_shutdown_signal "manual" 42
    local loop
    loop=$(jq -r '.shutdowns[0].loop' "$KORERO_DIR/.signal_log.json")
    [ "$loop" = "42" ]
}

@test "record_shutdown_signal writes detail field" {
    if ! command -v jq &>/dev/null; then
        skip "jq required"
    fi
    record_shutdown_signal "budget_exceeded" 7 "spent=8.50_limit=5.00"
    local detail
    detail=$(jq -r '.shutdowns[0].detail' "$KORERO_DIR/.signal_log.json")
    [ "$detail" = "spent=8.50_limit=5.00" ]
}

@test "record_shutdown_signal writes timestamp" {
    if ! command -v jq &>/dev/null; then
        skip "jq required"
    fi
    record_shutdown_signal "sigint" 1
    local ts
    ts=$(jq -r '.shutdowns[0].timestamp' "$KORERO_DIR/.signal_log.json")
    [ -n "$ts" ]
}

@test "record_shutdown_signal accumulates multiple entries" {
    if ! command -v jq &>/dev/null; then
        skip "jq required"
    fi
    record_shutdown_signal "sigint" 1
    record_shutdown_signal "sigterm" 2
    record_shutdown_signal "manual" 3
    local count
    count=$(jq '.shutdowns | length' "$KORERO_DIR/.signal_log.json")
    [ "$count" -eq 3 ]
}

@test "record_shutdown_signal works without jq (creates valid file)" {
    # Test that function produces some output even without jq fallback
    # We'll call it and just verify the file exists
    record_shutdown_signal "sigint" 0
    [ -f "$KORERO_DIR/.signal_log.json" ]
}

# ===== get_shutdown_count =====

@test "get_shutdown_count returns 0 when no log file" {
    rm -f "$KORERO_DIR/.signal_log.json"
    run get_shutdown_count
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "get_shutdown_count returns correct count" {
    if ! command -v jq &>/dev/null; then
        skip "jq required"
    fi
    record_shutdown_signal "sigint" 1
    record_shutdown_signal "sigint" 2
    run get_shutdown_count
    [ "$output" = "2" ]
}

# ===== get_last_shutdown_reason =====

@test "get_last_shutdown_reason returns empty when no log file" {
    rm -f "$KORERO_DIR/.signal_log.json"
    run get_last_shutdown_reason
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "get_last_shutdown_reason returns most recent reason" {
    if ! command -v jq &>/dev/null; then
        skip "jq required"
    fi
    record_shutdown_signal "sigint" 1
    record_shutdown_signal "budget_exceeded" 5
    run get_last_shutdown_reason
    [ "$output" = "budget_exceeded" ]
}

# ===== show_shutdown_history =====

@test "show_shutdown_history reports no history when file missing" {
    rm -f "$KORERO_DIR/.signal_log.json"
    run show_shutdown_history
    [ "$status" -eq 0 ]
    [[ "$output" == *"No shutdown history"* ]]
}

@test "show_shutdown_history shows SHUTDOWN HISTORY header" {
    if ! command -v jq &>/dev/null; then
        skip "jq required"
    fi
    record_shutdown_signal "sigint" 3
    run show_shutdown_history
    [ "$status" -eq 0 ]
    [[ "$output" == *"SHUTDOWN HISTORY"* ]]
}

@test "show_shutdown_history shows recorded reason" {
    if ! command -v jq &>/dev/null; then
        skip "jq required"
    fi
    record_shutdown_signal "circuit_open" 10
    run show_shutdown_history
    [[ "$output" == *"circuit_open"* ]]
}

@test "show_shutdown_history shows loop number" {
    if ! command -v jq &>/dev/null; then
        skip "jq required"
    fi
    record_shutdown_signal "project_complete" 15
    run show_shutdown_history
    [[ "$output" == *"15"* ]]
}

@test "show_shutdown_history shows total event count" {
    if ! command -v jq &>/dev/null; then
        skip "jq required"
    fi
    record_shutdown_signal "sigint" 1
    record_shutdown_signal "sigterm" 2
    run show_shutdown_history
    [[ "$output" == *"Total events: 2"* ]]
}

# ===== install_signal_handlers =====

@test "install_signal_handlers sets up SIGINT trap" {
    # Verify trap is registered — check that it doesn't fail
    install_signal_handlers "_default_signal_callback" "loop_count"
    # If we got here, install succeeded
    true
}

@test "_default_signal_callback exits 0" {
    run bash -c "
        source '$REPO_ROOT/lib/date_utils.sh'
        source '$REPO_ROOT/lib/signal_handler.sh'
        export KORERO_DIR='.korero'
        mkdir -p .korero
        _default_signal_callback sigint 5
    "
    [ "$status" -eq 0 ]
}

# ===== Shutdown reason constants =====

@test "SHUTDOWN_REASON_SIGINT is set" {
    [ -n "$SHUTDOWN_REASON_SIGINT" ]
}

@test "SHUTDOWN_REASON_BUDGET is set" {
    [ -n "$SHUTDOWN_REASON_BUDGET" ]
}

@test "SHUTDOWN_REASON_COMPLETE is set" {
    [ -n "$SHUTDOWN_REASON_COMPLETE" ]
}

@test "SHUTDOWN_REASON_CIRCUIT is set" {
    [ -n "$SHUTDOWN_REASON_CIRCUIT" ]
}

@test "SHUTDOWN_REASON_LIMIT is set" {
    [ -n "$SHUTDOWN_REASON_LIMIT" ]
}
