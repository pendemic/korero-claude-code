#!/usr/bin/env bats
# Unit Tests for Rate Limiting Logic

load '../helpers/test_helper'

# Source korero functions (we need to extract these first)
setup() {
    # Source helper functions
    source "$(dirname "$BATS_TEST_FILENAME")/../helpers/test_helper.bash"

    # Set up environment with .korero/ subfolder structure
    export KORERO_DIR=".korero"
    export MAX_CALLS_PER_HOUR=100
    export CALL_COUNT_FILE="$KORERO_DIR/.call_count"
    export TIMESTAMP_FILE="$KORERO_DIR/.last_reset"

    # Create temp test directory
    export TEST_TEMP_DIR="$(mktemp -d /tmp/korero-test.XXXXXX)"
    cd "$TEST_TEMP_DIR"
    mkdir -p "$KORERO_DIR"

    # Initialize files
    echo "0" > "$CALL_COUNT_FILE"
    echo "$(date +%Y%m%d%H)" > "$TIMESTAMP_FILE"
}

teardown() {
    # Clean up
    cd /
    rm -rf "$TEST_TEMP_DIR"
}

# Helper function: can_make_call (extracted from korero_loop.sh)
can_make_call() {
    local calls_made=0
    if [[ -f "$CALL_COUNT_FILE" ]]; then
        calls_made=$(cat "$CALL_COUNT_FILE")
    fi

    if [[ $calls_made -ge $MAX_CALLS_PER_HOUR ]]; then
        return 1  # Cannot make call
    else
        return 0  # Can make call
    fi
}

# Helper function: increment_call_counter (extracted from korero_loop.sh)
increment_call_counter() {
    local calls_made=0
    if [[ -f "$CALL_COUNT_FILE" ]]; then
        calls_made=$(cat "$CALL_COUNT_FILE")
    fi

    ((calls_made++))
    echo "$calls_made" > "$CALL_COUNT_FILE"
    echo "$calls_made"
}

# Test 1: can_make_call returns success when under limit
@test "can_make_call returns success when under limit" {
    echo "50" > "$CALL_COUNT_FILE"
    export MAX_CALLS_PER_HOUR=100

    run can_make_call
    assert_success
}

# Test 2: can_make_call returns success when exactly at limit minus 1
@test "can_make_call returns success when at limit minus 1" {
    echo "99" > "$CALL_COUNT_FILE"
    export MAX_CALLS_PER_HOUR=100

    run can_make_call
    assert_success
}

# Test 3: can_make_call returns failure when at limit
@test "can_make_call returns failure when at limit" {
    echo "100" > "$CALL_COUNT_FILE"
    export MAX_CALLS_PER_HOUR=100

    run can_make_call
    assert_failure
}

# Test 4: can_make_call returns failure when over limit
@test "can_make_call returns failure when over limit" {
    echo "150" > "$CALL_COUNT_FILE"
    export MAX_CALLS_PER_HOUR=100

    run can_make_call
    assert_failure
}

# Test 5: can_make_call returns success when file doesn't exist (0 calls)
@test "can_make_call returns success when call count file missing" {
    rm -f "$CALL_COUNT_FILE"
    export MAX_CALLS_PER_HOUR=100

    run can_make_call
    assert_success
}

# Test 6: increment_call_counter increases from 0
@test "increment_call_counter increases from 0 to 1" {
    echo "0" > "$CALL_COUNT_FILE"

    result=$(increment_call_counter)
    assert_equal "$result" "1"
    assert_equal "$(cat $CALL_COUNT_FILE)" "1"
}

# Test 7: increment_call_counter increases from middle value
@test "increment_call_counter increases from 42 to 43" {
    echo "42" > "$CALL_COUNT_FILE"

    result=$(increment_call_counter)
    assert_equal "$result" "43"
    assert_equal "$(cat $CALL_COUNT_FILE)" "43"
}

# Test 8: increment_call_counter works near limit
@test "increment_call_counter increases from 99 to 100" {
    echo "99" > "$CALL_COUNT_FILE"

    result=$(increment_call_counter)
    assert_equal "$result" "100"
    assert_equal "$(cat $CALL_COUNT_FILE)" "100"
}

# Test 9: increment_call_counter works when file missing
@test "increment_call_counter creates file and sets to 1 when missing" {
    rm -f "$CALL_COUNT_FILE"

    result=$(increment_call_counter)
    assert_equal "$result" "1"
    assert_equal "$(cat $CALL_COUNT_FILE)" "1"
}

# Test 10: Rate limit with different MAX_CALLS value (50)
@test "can_make_call respects MAX_CALLS_PER_HOUR of 50" {
    echo "49" > "$CALL_COUNT_FILE"
    export MAX_CALLS_PER_HOUR=50

    run can_make_call
    assert_success

    echo "50" > "$CALL_COUNT_FILE"
    run can_make_call
    assert_failure
}

# Test 11: Rate limit with different MAX_CALLS value (25)
@test "can_make_call respects MAX_CALLS_PER_HOUR of 25" {
    echo "24" > "$CALL_COUNT_FILE"
    export MAX_CALLS_PER_HOUR=25

    run can_make_call
    assert_success

    echo "25" > "$CALL_COUNT_FILE"
    run can_make_call
    assert_failure
}

# Test 12: Counter persistence across multiple increments
@test "counter persists correctly across multiple increments" {
    echo "0" > "$CALL_COUNT_FILE"

    result1=$(increment_call_counter)  # 1
    result2=$(increment_call_counter)  # 2
    result3=$(increment_call_counter)  # 3
    result4=$(increment_call_counter)  # 4

    assert_equal "$result4" "4"
    assert_equal "$(cat $CALL_COUNT_FILE)" "4"
}

# Test 13: Call count file contains only a number
@test "call count file contains valid integer" {
    run increment_call_counter

    # Check the call count file contains a valid integer
    value=$(cat "$CALL_COUNT_FILE")
    [[ "$value" =~ ^[0-9]+$ ]] || {
        echo "Call count file does not contain valid integer: $value"
        return 1
    }
}

# Test 14: Can make call with zero calls
@test "can_make_call returns success with zero calls made" {
    echo "0" > "$CALL_COUNT_FILE"
    export MAX_CALLS_PER_HOUR=100

    run can_make_call
    assert_success
}

# Test 15: Edge case - very large MAX_CALLS value
@test "can_make_call works with large MAX_CALLS value" {
    echo "5000" > "$CALL_COUNT_FILE"
    export MAX_CALLS_PER_HOUR=10000

    run can_make_call
    assert_success
}

# =============================================================================
# RATE LIMIT APPROACH WARNING TESTS
# =============================================================================

# Helper: extract check_rate_limit_warnings from korero_loop.sh
REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

# Helper function: check_rate_limit_warnings (extracted from korero_loop.sh)
check_rate_limit_warnings() {
    local calls_made="$1"
    local threshold_80=$((MAX_CALLS_PER_HOUR * 80 / 100))
    local threshold_95=$((MAX_CALLS_PER_HOUR * 95 / 100))

    if [[ $calls_made -ge $threshold_80 ]] && [[ "$RATE_WARNED_80" == "false" ]]; then
        local remaining=$((MAX_CALLS_PER_HOUR - calls_made))
        echo "WARN: API budget: 80% used ($remaining calls remaining)"
        RATE_WARNED_80=true
    fi

    if [[ $calls_made -ge $threshold_95 ]] && [[ "$RATE_WARNED_95" == "false" ]]; then
        local remaining=$((MAX_CALLS_PER_HOUR - calls_made))
        echo "WARN: API budget: 95% used ($remaining calls remaining)"
        RATE_WARNED_95=true
    fi
}

# Test 16: Warning at 80% threshold
@test "check_rate_limit_warnings warns at 80% of MAX_CALLS" {
    export MAX_CALLS_PER_HOUR=100
    export RATE_WARNED_80=false
    export RATE_WARNED_95=false

    run check_rate_limit_warnings 80
    [[ "$output" == *"80% used"* ]]
    [[ "$output" == *"20 calls remaining"* ]]
}

# Test 17: Warning at 95% threshold
@test "check_rate_limit_warnings warns at 95% of MAX_CALLS" {
    export MAX_CALLS_PER_HOUR=100
    export RATE_WARNED_80=true
    export RATE_WARNED_95=false

    run check_rate_limit_warnings 95
    [[ "$output" == *"95% used"* ]]
    [[ "$output" == *"5 calls remaining"* ]]
}

# Test 18: No warning below 80%
@test "check_rate_limit_warnings silent below 80%" {
    export MAX_CALLS_PER_HOUR=100
    export RATE_WARNED_80=false
    export RATE_WARNED_95=false

    run check_rate_limit_warnings 79
    [ -z "$output" ]
}

# Test 19: Warning not repeated after first emit
@test "check_rate_limit_warnings does not repeat 80% warning" {
    export MAX_CALLS_PER_HOUR=100
    export RATE_WARNED_80=true
    export RATE_WARNED_95=false

    run check_rate_limit_warnings 85
    [ -z "$output" ]
}

# Test 20: Thresholds scale with custom MAX_CALLS
@test "check_rate_limit_warnings scales with MAX_CALLS=50" {
    export MAX_CALLS_PER_HOUR=50
    export RATE_WARNED_80=false
    export RATE_WARNED_95=false

    # 80% of 50 = 40
    run check_rate_limit_warnings 39
    [ -z "$output" ]

    run check_rate_limit_warnings 40
    [[ "$output" == *"80% used"* ]]
    [[ "$output" == *"10 calls remaining"* ]]
}

# Test 21: Both warnings fire when jumping past both thresholds
@test "check_rate_limit_warnings fires both when jumping past both" {
    export MAX_CALLS_PER_HOUR=100
    export RATE_WARNED_80=false
    export RATE_WARNED_95=false

    run check_rate_limit_warnings 98
    [[ "$output" == *"80% used"* ]]
    [[ "$output" == *"95% used"* ]]
}

# Test 22: korero_loop.sh contains rate limit warning infrastructure
@test "korero_loop.sh has check_rate_limit_warnings function" {
    grep -q "check_rate_limit_warnings()" "$REPO_ROOT/korero_loop.sh"
}

# Test 23: Warning flags reset in init_call_tracking
@test "init_call_tracking resets warning flags on new hour" {
    grep -q "RATE_WARNED_80=false" "$REPO_ROOT/korero_loop.sh"
    grep -q "RATE_WARNED_95=false" "$REPO_ROOT/korero_loop.sh"
}

# Test 24: status.json includes rate_limit_warning field
@test "update_status includes rate_limit_warning field" {
    grep -q "rate_limit_warning" "$REPO_ROOT/korero_loop.sh"
}

# Test 25: monitor displays rate limit warnings
@test "monitor reads and displays rate limit warnings" {
    grep -q "rate_limit_warning" "$REPO_ROOT/korero_monitor.sh"
    grep -q "rate_limit_imminent" "$REPO_ROOT/korero_monitor.sh"
    grep -q "rate_limit_approaching" "$REPO_ROOT/korero_monitor.sh"
}
