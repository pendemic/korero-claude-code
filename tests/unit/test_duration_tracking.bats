#!/usr/bin/env bats

# Tests for lib/duration_tracker.sh — Loop Duration Tracking

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
    mkdir -p .korero
    source "$REPO_ROOT/lib/duration_tracker.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# --- format_duration ---

@test "format_duration formats seconds" {
    result=$(format_duration 45)
    [ "$result" = "45s" ]
}

@test "format_duration formats minutes and seconds" {
    result=$(format_duration 125)
    [ "$result" = "2m 5s" ]
}

@test "format_duration formats hours and minutes" {
    result=$(format_duration 3725)
    [ "$result" = "1h 2m" ]
}

@test "format_duration handles zero" {
    result=$(format_duration 0)
    [ "$result" = "0s" ]
}

@test "format_duration handles empty input" {
    result=$(format_duration "")
    [ "$result" = "0s" ]
}

# --- record_loop_start / record_loop_end ---

@test "record_loop_start creates start time file" {
    record_loop_start .korero
    [ -f ".korero/.loop_start_time" ]
}

@test "record_loop_end creates duration file" {
    echo "$(( $(date +%s) - 30 ))" > .korero/.loop_start_time
    record_loop_end .korero
    [ -f ".korero/.last_loop_duration" ]
    local dur
    dur=$(cat .korero/.last_loop_duration | tr -d '[:space:]')
    [ "$dur" -ge 28 ]
    [ "$dur" -le 35 ]
}

@test "record_loop_end appends to history" {
    echo "$(( $(date +%s) - 10 ))" > .korero/.loop_start_time
    record_loop_end .korero
    [ -f ".korero/.duration_history" ]
    local lines
    lines=$(wc -l < .korero/.duration_history | tr -d '[:space:]')
    [ "$lines" -eq 1 ]
}

@test "record_loop_end keeps only last 10 entries" {
    for i in $(seq 1 12); do
        echo "$((i * 10))" >> .korero/.duration_history
    done
    echo "$(( $(date +%s) - 5 ))" > .korero/.loop_start_time
    record_loop_end .korero
    local lines
    lines=$(wc -l < .korero/.duration_history | tr -d '[:space:]')
    [ "$lines" -eq 10 ]
}

@test "record_loop_end removes start time file" {
    echo "$(date +%s)" > .korero/.loop_start_time
    record_loop_end .korero
    [ ! -f ".korero/.loop_start_time" ]
}

# --- get_last_duration ---

@test "get_last_duration returns 0 when no file" {
    result=$(get_last_duration .korero)
    [ "$result" = "0" ]
}

@test "get_last_duration returns stored value" {
    echo "42" > .korero/.last_loop_duration
    result=$(get_last_duration .korero)
    [ "$result" = "42" ]
}

# --- get_average_duration ---

@test "get_average_duration returns 0 when no history" {
    result=$(get_average_duration .korero)
    [ "$result" = "0" ]
}

@test "get_average_duration computes correct average" {
    printf "10\n20\n30\n" > .korero/.duration_history
    result=$(get_average_duration .korero)
    [ "$result" = "20" ]
}

@test "get_average_duration respects count parameter" {
    printf "100\n200\n10\n20\n" > .korero/.duration_history
    result=$(get_average_duration .korero 2)
    [ "$result" = "15" ]
}

# --- get_elapsed_time ---

@test "get_elapsed_time returns 0 when no start file" {
    result=$(get_elapsed_time .korero)
    [ "$result" = "0" ]
}

@test "get_elapsed_time returns elapsed seconds" {
    echo "$(( $(date +%s) - 15 ))" > .korero/.loop_start_time
    result=$(get_elapsed_time .korero)
    [ "$result" -ge 13 ]
    [ "$result" -le 20 ]
}

# --- render_duration_widget ---

@test "render_duration_widget shows header" {
    run render_duration_widget .korero
    [ "$status" -eq 0 ]
    [[ "$output" == *"Loop Timing"* ]]
}

@test "render_duration_widget shows idle when no loop running" {
    run render_duration_widget .korero
    [ "$status" -eq 0 ]
    [[ "$output" == *"idle"* ]]
}

@test "render_duration_widget shows running when loop active" {
    echo "$(date +%s)" > .korero/.loop_start_time
    run render_duration_widget .korero
    [ "$status" -eq 0 ]
    [[ "$output" == *"running"* ]]
}
