#!/usr/bin/env bats

load '../helpers/test_helper'

setup() {
    TEST_DIR=$(mktemp -d)
    export KORERO_DIR="$TEST_DIR/.korero"
    mkdir -p "$KORERO_DIR"
    export CALL_COUNT_FILE="$KORERO_DIR/.call_count"
    export MAX_CALLS_PER_HOUR=100
    KORERO_LOOP="$BATS_TEST_DIRNAME/../../korero_loop.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ─── get_budget_status ─────────────────────────────────────────────────────

@test "get_budget_status returns green at 0 calls" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; get_budget_status 0 100"
    assert_output "green"
}

@test "get_budget_status returns green at 50% usage" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; get_budget_status 50 100"
    assert_output "green"
}

@test "get_budget_status returns green at 79% usage" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; get_budget_status 79 100"
    assert_output "green"
}

@test "get_budget_status returns yellow at default 80% threshold" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; get_budget_status 80 100"
    assert_output "yellow"
}

@test "get_budget_status returns yellow at 90% usage" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; get_budget_status 90 100"
    assert_output "yellow"
}

@test "get_budget_status returns yellow at 94% usage" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; get_budget_status 94 100"
    assert_output "yellow"
}

@test "get_budget_status returns red at 95% usage" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; get_budget_status 95 100"
    assert_output "red"
}

@test "get_budget_status returns red at 100% usage" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; get_budget_status 100 100"
    assert_output "red"
}

@test "get_budget_status respects custom KORERO_BUDGET_ALERT threshold (50)" {
    run bash -c "
        source '$KORERO_LOOP' 2>/dev/null
        KORERO_BUDGET_ALERT=50
        get_budget_status 50 100
    "
    assert_output "yellow"
}

@test "get_budget_status returns green below custom threshold" {
    run bash -c "
        source '$KORERO_LOOP' 2>/dev/null
        KORERO_BUDGET_ALERT=90
        get_budget_status 80 100
    "
    assert_output "green"
}

@test "get_budget_status returns green when max_calls is 0" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; get_budget_status 0 0"
    assert_output "green"
}

@test "get_budget_status exits 0" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; get_budget_status 50 100"
    [ "$status" -eq 0 ]
}

# ─── print_progress with budget coloring ──────────────────────────────────

@test "print_progress shows loop number" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        export CALL_COUNT_FILE='${TEST_DIR}/.korero/.call_count'
        export MAX_CALLS_PER_HOUR=100
        echo '0' > '${TEST_DIR}/.korero/.call_count'
        source '$KORERO_LOOP' 2>/dev/null
        print_progress 5 'Executing' 50
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Loop 5"* ]]
}

@test "print_progress shows percentage" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        export CALL_COUNT_FILE='${TEST_DIR}/.korero/.call_count'
        export MAX_CALLS_PER_HOUR=100
        echo '0' > '${TEST_DIR}/.korero/.call_count'
        source '$KORERO_LOOP' 2>/dev/null
        print_progress 3 'Testing' 60
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"60%"* ]]
}

@test "print_progress shows phase name at normal usage" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        export CALL_COUNT_FILE='${TEST_DIR}/.korero/.call_count'
        export MAX_CALLS_PER_HOUR=100
        echo '10' > '${TEST_DIR}/.korero/.call_count'
        source '$KORERO_LOOP' 2>/dev/null
        print_progress 2 'Executing' 40
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Executing"* ]]
}

@test "print_progress appends Calls info at alert level" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        export CALL_COUNT_FILE='${TEST_DIR}/.korero/.call_count'
        export MAX_CALLS_PER_HOUR=100
        echo '85' > '${TEST_DIR}/.korero/.call_count'
        source '$KORERO_LOOP' 2>/dev/null
        print_progress 8 'Executing' 80
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Calls:"* ]]
    [[ "$output" == *"85/100"* ]]
}

@test "print_progress does not show Calls at normal usage" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        export CALL_COUNT_FILE='${TEST_DIR}/.korero/.call_count'
        export MAX_CALLS_PER_HOUR=100
        echo '30' > '${TEST_DIR}/.korero/.call_count'
        source '$KORERO_LOOP' 2>/dev/null
        print_progress 3 'Executing' 30
    "
    [ "$status" -eq 0 ]
    [[ "$output" != *"Calls:"* ]]
}

@test "print_progress appends Calls info at critical level (95%)" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        export CALL_COUNT_FILE='${TEST_DIR}/.korero/.call_count'
        export MAX_CALLS_PER_HOUR=100
        echo '96' > '${TEST_DIR}/.korero/.call_count'
        source '$KORERO_LOOP' 2>/dev/null
        print_progress 10 'Executing' 90
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"96/100"* ]]
}
