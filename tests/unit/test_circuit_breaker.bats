#!/usr/bin/env bats

# Tests for lib/circuit_breaker.sh — Budget Alert System (Loop 28)

load '../helpers/test_helper'

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

# ===== check_budget_threshold =====

@test "check_budget_threshold returns 0 when no budget set" {
    unset KORERO_BUDGET_USD
    run check_budget_threshold
    [ "$status" -eq 0 ]
}

@test "check_budget_threshold returns 0 when KORERO_BUDGET_USD is empty string" {
    export KORERO_BUDGET_USD=""
    run check_budget_threshold
    [ "$status" -eq 0 ]
}

@test "check_budget_threshold returns 0 when no cost_history.json exists" {
    export KORERO_BUDGET_USD="10.00"
    rm -f "$KORERO_DIR/cost_history.json"
    run check_budget_threshold
    [ "$status" -eq 0 ]
}

@test "check_budget_threshold returns 0 when under budget" {
    if ! command -v jq &>/dev/null || ! command -v bc &>/dev/null; then
        skip "jq and bc required"
    fi
    export KORERO_BUDGET_USD="10.00"
    echo '{"session_total_usd": 5.00, "session_total_tokens": 0, "loops": []}' \
        > "$KORERO_DIR/cost_history.json"
    run check_budget_threshold
    [ "$status" -eq 0 ]
}

@test "check_budget_threshold returns 1 when over budget" {
    if ! command -v jq &>/dev/null || ! command -v bc &>/dev/null; then
        skip "jq and bc required"
    fi
    export KORERO_BUDGET_USD="5.00"
    echo '{"session_total_usd": 7.50, "session_total_tokens": 0, "loops": []}' \
        > "$KORERO_DIR/cost_history.json"
    run check_budget_threshold
    [ "$status" -eq 1 ]
}

@test "check_budget_threshold returns 1 when exactly at budget" {
    if ! command -v jq &>/dev/null || ! command -v bc &>/dev/null; then
        skip "jq and bc required"
    fi
    export KORERO_BUDGET_USD="5.00"
    echo '{"session_total_usd": 5.00, "session_total_tokens": 0, "loops": []}' \
        > "$KORERO_DIR/cost_history.json"
    run check_budget_threshold
    [ "$status" -eq 1 ]
}

# ===== get_budget_percentage =====

@test "get_budget_percentage returns 0 when no budget set" {
    unset KORERO_BUDGET_USD
    run get_budget_percentage
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "get_budget_percentage returns 0 when no cost file" {
    export KORERO_BUDGET_USD="10.00"
    rm -f "$KORERO_DIR/cost_history.json"
    run get_budget_percentage
    [ "$output" = "0" ]
}

@test "get_budget_percentage calculates 80 percent correctly" {
    if ! command -v jq &>/dev/null || ! command -v bc &>/dev/null; then
        skip "jq and bc required"
    fi
    export KORERO_BUDGET_USD="10.00"
    echo '{"session_total_usd": 8.00, "session_total_tokens": 0, "loops": []}' \
        > "$KORERO_DIR/cost_history.json"
    run get_budget_percentage
    [ "$status" -eq 0 ]
    [ "$output" = "80" ]
}

@test "get_budget_percentage calculates 50 percent correctly" {
    if ! command -v jq &>/dev/null || ! command -v bc &>/dev/null; then
        skip "jq and bc required"
    fi
    export KORERO_BUDGET_USD="10.00"
    echo '{"session_total_usd": 5.00, "session_total_tokens": 0, "loops": []}' \
        > "$KORERO_DIR/cost_history.json"
    run get_budget_percentage
    [ "$status" -eq 0 ]
    [ "$output" = "50" ]
}

# ===== prompt_budget_exceeded =====

@test "prompt_budget_exceeded returns 0 for option 1 (continue)" {
    run bash -c "source \"$REPO_ROOT/lib/date_utils.sh\" && source \"$REPO_ROOT/lib/circuit_breaker.sh\" && echo '1' | prompt_budget_exceeded 7.50 5.00"
    [ "$status" -eq 0 ]
}

@test "prompt_budget_exceeded returns 0 for option 2 (reduce rate)" {
    run bash -c "source \"$REPO_ROOT/lib/date_utils.sh\" && source \"$REPO_ROOT/lib/circuit_breaker.sh\" && export MAX_CALLS_PER_HOUR=100 && echo '2' | prompt_budget_exceeded 7.50 5.00"
    [ "$status" -eq 0 ]
}

@test "prompt_budget_exceeded returns 1 for option 3 (exit)" {
    run bash -c "
        source '$REPO_ROOT/lib/date_utils.sh'
        source '$REPO_ROOT/lib/circuit_breaker.sh'
        echo '3' | prompt_budget_exceeded 7.50 5.00
    "
    [ "$status" -eq 1 ]
}

@test "prompt_budget_exceeded returns 1 on empty input" {
    run bash -c "
        source '$REPO_ROOT/lib/date_utils.sh'
        source '$REPO_ROOT/lib/circuit_breaker.sh'
        echo '' | prompt_budget_exceeded 7.50 5.00
    "
    [ "$status" -eq 1 ]
}

@test "prompt_budget_exceeded shows budget alert header" {
    run bash -c "
        source '$REPO_ROOT/lib/date_utils.sh'
        source '$REPO_ROOT/lib/circuit_breaker.sh'
        echo '1' | prompt_budget_exceeded 7.50 5.00
    "
    [[ "$output" == *"BUDGET ALERT"* ]]
}

@test "prompt_budget_exceeded shows current spending amount" {
    run bash -c "
        source '$REPO_ROOT/lib/date_utils.sh'
        source '$REPO_ROOT/lib/circuit_breaker.sh'
        echo '1' | prompt_budget_exceeded 7.50 5.00
    "
    [[ "$output" == *"7.50"* ]]
    [[ "$output" == *"5.00"* ]]
}
