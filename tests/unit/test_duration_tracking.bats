#!/usr/bin/env bats

# Tests for loop duration tracking functionality

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
    mkdir -p .korero/logs

    KORERO_DIR=".korero"
    DURATION_HISTORY_FILE="$KORERO_DIR/.loop_durations"
    MAX_DURATION_ENTRIES=10
    STATUS_FILE="$KORERO_DIR/status.json"

    # Source only the functions we need from korero_loop.sh
    # Extract format_duration, update_loop_duration, get_average_duration
    eval "$(sed -n '/^format_duration()/,/^}/p' "$REPO_ROOT/korero_loop.sh")"
    eval "$(sed -n '/^update_loop_duration()/,/^}/p' "$REPO_ROOT/korero_loop.sh")"
    eval "$(sed -n '/^get_average_duration()/,/^}/p' "$REPO_ROOT/korero_loop.sh")"

    # Source format_duration from monitor too (verify it exists)
    MONITOR_SCRIPT="$REPO_ROOT/korero_monitor.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ===== format_duration =====

@test "format_duration formats seconds only" {
    result=$(format_duration 45)
    [ "$result" = "45s" ]
}

@test "format_duration formats zero seconds" {
    result=$(format_duration 0)
    [ "$result" = "0s" ]
}

@test "format_duration formats minutes and seconds" {
    result=$(format_duration 125)
    [ "$result" = "2m 5s" ]
}

@test "format_duration formats exact minutes" {
    result=$(format_duration 120)
    [ "$result" = "2m 0s" ]
}

@test "format_duration formats large durations" {
    result=$(format_duration 3661)
    [ "$result" = "61m 1s" ]
}

# ===== update_loop_duration =====

@test "update_loop_duration creates history file" {
    update_loop_duration 120
    [ -f "$DURATION_HISTORY_FILE" ]
}

@test "update_loop_duration appends duration to file" {
    update_loop_duration 100
    update_loop_duration 200
    local count
    count=$(wc -l < "$DURATION_HISTORY_FILE")
    [ "$count" -eq 2 ]
}

@test "update_loop_duration maintains max entries" {
    for i in $(seq 1 15); do
        update_loop_duration $((i * 10))
    done
    local count
    count=$(wc -l < "$DURATION_HISTORY_FILE")
    [ "$count" -eq "$MAX_DURATION_ENTRIES" ]
}

@test "update_loop_duration keeps most recent entries" {
    for i in $(seq 1 15); do
        update_loop_duration $((i * 10))
    done
    # First entry should be entry 6 (60), last should be 15 (150)
    local first
    first=$(head -1 "$DURATION_HISTORY_FILE")
    [ "$first" = "60" ]
    local last
    last=$(tail -1 "$DURATION_HISTORY_FILE")
    [ "$last" = "150" ]
}

# ===== get_average_duration =====

@test "get_average_duration returns 0 when no history" {
    result=$(get_average_duration)
    [ "$result" = "0" ]
}

@test "get_average_duration calculates average" {
    echo "100" > "$DURATION_HISTORY_FILE"
    echo "200" >> "$DURATION_HISTORY_FILE"
    echo "300" >> "$DURATION_HISTORY_FILE"
    result=$(get_average_duration)
    [ "$result" = "200" ]
}

@test "get_average_duration with single entry" {
    echo "150" > "$DURATION_HISTORY_FILE"
    result=$(get_average_duration)
    [ "$result" = "150" ]
}

# ===== update_status integration =====

@test "status.json includes duration fields" {
    # Verify update_status in korero_loop.sh outputs duration fields
    grep -q "loop_start_time" "$REPO_ROOT/korero_loop.sh"
    grep -q "last_loop_duration_sec" "$REPO_ROOT/korero_loop.sh"
    grep -q "average_loop_duration_sec" "$REPO_ROOT/korero_loop.sh"
}

# ===== korero_monitor.sh integration =====

@test "monitor has format_duration function" {
    grep -q "format_duration()" "$MONITOR_SCRIPT"
}

@test "monitor reads duration fields from status.json" {
    grep -q "loop_start_time" "$MONITOR_SCRIPT"
    grep -q "last_loop_duration_sec" "$MONITOR_SCRIPT"
    grep -q "average_loop_duration_sec" "$MONITOR_SCRIPT"
}

@test "monitor displays duration info" {
    grep -q "Duration:" "$MONITOR_SCRIPT"
    grep -q "Last Loop:" "$MONITOR_SCRIPT"
}
