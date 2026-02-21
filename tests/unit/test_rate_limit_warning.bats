#!/usr/bin/env bats

# Tests for lib/rate_limit_warning.sh — Rate Limit Approach Warning

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    source "$REPO_ROOT/lib/rate_limit_warning.sh"
}

# --- check_rate_limit_warning ---

@test "check_rate_limit_warning returns none for low usage" {
    result=$(check_rate_limit_warning 10 100)
    [ "$result" = "none" ]
}

@test "check_rate_limit_warning returns warning at 80%" {
    result=$(check_rate_limit_warning 80 100)
    [ "$result" = "warning" ]
}

@test "check_rate_limit_warning returns critical at 95%" {
    result=$(check_rate_limit_warning 95 100)
    [ "$result" = "critical" ]
}

@test "check_rate_limit_warning returns critical at 100%" {
    result=$(check_rate_limit_warning 100 100)
    [ "$result" = "critical" ]
}

@test "check_rate_limit_warning handles zero max" {
    result=$(check_rate_limit_warning 0 0)
    [ "$result" = "none" ]
}

@test "check_rate_limit_warning returns warning at 85%" {
    result=$(check_rate_limit_warning 85 100)
    [ "$result" = "warning" ]
}

# --- format_rate_limit_warning ---

@test "format_rate_limit_warning returns empty for low usage" {
    result=$(format_rate_limit_warning 10 100)
    [ -z "$result" ]
}

@test "format_rate_limit_warning shows warning message" {
    result=$(format_rate_limit_warning 82 100)
    [[ "$result" == *"WARNING"* ]]
    [[ "$result" == *"82/100"* ]]
    [[ "$result" == *"18 remaining"* ]]
}

@test "format_rate_limit_warning shows critical message" {
    result=$(format_rate_limit_warning 97 100)
    [[ "$result" == *"CRITICAL"* ]]
    [[ "$result" == *"3 calls remaining"* ]]
}

# --- get_rate_limit_status ---

@test "get_rate_limit_status returns JSON" {
    result=$(get_rate_limit_status 50 100)
    echo "$result" | jq -e '.' > /dev/null
}

@test "get_rate_limit_status includes all fields" {
    result=$(get_rate_limit_status 50 100)
    [ "$(echo "$result" | jq -r '.current')" = "50" ]
    [ "$(echo "$result" | jq -r '.max')" = "100" ]
    [ "$(echo "$result" | jq -r '.remaining')" = "50" ]
    [ "$(echo "$result" | jq -r '.percentage')" = "50" ]
    [ "$(echo "$result" | jq -r '.warning_level')" = "none" ]
}

@test "get_rate_limit_status shows warning level" {
    result=$(get_rate_limit_status 90 100)
    [ "$(echo "$result" | jq -r '.warning_level')" = "warning" ]
}

# --- should_warn_rate_limit ---

@test "should_warn_rate_limit returns 1 for low usage" {
    run should_warn_rate_limit 10 100 "none"
    [ "$status" -eq 1 ]
}

@test "should_warn_rate_limit returns 0 for new warning" {
    run should_warn_rate_limit 85 100 "none"
    [ "$status" -eq 0 ]
}

@test "should_warn_rate_limit returns 1 if already warned at same level" {
    run should_warn_rate_limit 85 100 "warning"
    [ "$status" -eq 1 ]
}

@test "should_warn_rate_limit returns 0 for escalation to critical" {
    run should_warn_rate_limit 96 100 "warning"
    [ "$status" -eq 0 ]
}

@test "should_warn_rate_limit returns 1 if already at critical" {
    run should_warn_rate_limit 96 100 "critical"
    [ "$status" -eq 1 ]
}
