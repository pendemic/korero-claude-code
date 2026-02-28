#!/usr/bin/env bats

# Tests for lib/cost_estimator.sh — API cost estimation

load '../helpers/test_helper'

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
    export KORERO_DIR=".korero"
    export COST_LOG_DIR="$KORERO_DIR/logs"
    mkdir -p "$KORERO_DIR/logs" "$KORERO_DIR/debates"
    source "$REPO_ROOT/lib/cost_estimator.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ===== estimate_tokens_from_file =====

@test "estimate_tokens_from_file returns 0 for missing file" {
    result=$(estimate_tokens_from_file "/nonexistent/file.log")
    [ "$result" = "0" ]
}

@test "estimate_tokens_from_file returns 0 for empty file" {
    touch "$TEST_DIR/empty.log"
    result=$(estimate_tokens_from_file "$TEST_DIR/empty.log")
    [ "$result" = "0" ]
}

@test "estimate_tokens_from_file estimates tokens from file size" {
    # 400 characters should be ~100 tokens (at 4 chars/token)
    printf '%0.s.' $(seq 1 400) > "$TEST_DIR/test.log"
    result=$(estimate_tokens_from_file "$TEST_DIR/test.log")
    [ "$result" -eq 100 ]
}

@test "estimate_tokens_from_file handles large files" {
    # 4000 characters = ~1000 tokens
    printf '%0.s.' $(seq 1 4000) > "$TEST_DIR/large.log"
    result=$(estimate_tokens_from_file "$TEST_DIR/large.log")
    [ "$result" -eq 1000 ]
}

# ===== calculate_cost =====

@test "calculate_cost returns 0 for 0 tokens" {
    result=$(calculate_cost 0 3.00)
    [ "$result" = "0.000000" ]
}

@test "calculate_cost calculates correctly for 1M tokens" {
    result=$(calculate_cost 1000000 3.00)
    [ "$result" = "3.000000" ]
}

@test "calculate_cost handles fractional results" {
    result=$(calculate_cost 500000 3.00)
    [ "$result" = "1.500000" ]
}

@test "calculate_cost uses correct rate" {
    result=$(calculate_cost 1000000 15.00)
    [ "$result" = "15.000000" ]
}

# ===== estimate_api_costs =====

@test "estimate_api_costs returns error for missing directory" {
    run estimate_api_costs "/nonexistent/dir"
    [[ "$output" == *'"error"'* ]]
}

@test "estimate_api_costs returns 1 for missing directory" {
    run estimate_api_costs "/nonexistent/dir"
    [ "$status" -eq 1 ]
}

@test "estimate_api_costs returns 0 cost for empty log directory" {
    result=$(estimate_api_costs "$KORERO_DIR/logs")
    echo "$result" | grep -q '"total_cost": 0'
}

@test "estimate_api_costs counts claude output files" {
    printf '%0.s.' $(seq 1 4000) > "$KORERO_DIR/logs/claude_output_2026-01-01.log"
    result=$(estimate_api_costs "$KORERO_DIR/logs")
    echo "$result" | grep -q '"files_analyzed": 1'
    # Should have output tokens > 0
    local output_tokens
    output_tokens=$(echo "$result" | grep '"output_tokens"' | sed 's/.*: *//' | sed 's/,$//')
    [ "$output_tokens" -gt 0 ]
}

@test "estimate_api_costs counts claude proposal files" {
    printf '%0.s.' $(seq 1 4000) > "$KORERO_DIR/logs/claude_proposal_2026-01-01.log"
    result=$(estimate_api_costs "$KORERO_DIR/logs")
    echo "$result" | grep -q '"files_analyzed": 1'
}

@test "estimate_api_costs counts codex proposal files" {
    printf '%0.s.' $(seq 1 4000) > "$KORERO_DIR/logs/codex_proposal_2026-01-01.log"
    result=$(estimate_api_costs "$KORERO_DIR/logs")
    echo "$result" | grep -q '"files_analyzed": 1'
}

@test "estimate_api_costs counts debate files" {
    printf '%0.s.' $(seq 1 4000) > "$KORERO_DIR/debates/claude_critique_2026-01-01.log"
    printf '%0.s.' $(seq 1 4000) > "$KORERO_DIR/debates/judge_verdict_2026-01-01.log"
    result=$(estimate_api_costs "$KORERO_DIR/logs")
    echo "$result" | grep -q '"files_analyzed": 2'
}

@test "estimate_api_costs estimates input tokens at 2x output" {
    printf '%0.s.' $(seq 1 4000) > "$KORERO_DIR/logs/claude_output_2026-01-01.log"
    result=$(estimate_api_costs "$KORERO_DIR/logs")
    local input_tokens output_tokens
    output_tokens=$(echo "$result" | grep '"output_tokens"' | sed 's/.*: *//' | sed 's/,$//')
    input_tokens=$(echo "$result" | grep '"input_tokens"' | sed 's/.*: *//' | sed 's/,$//')
    [ "$input_tokens" -eq $(( output_tokens * 2 )) ]
}

@test "estimate_api_costs includes pricing rates" {
    result=$(estimate_api_costs "$KORERO_DIR/logs")
    echo "$result" | grep -q '"input_rate_per_1m"'
    echo "$result" | grep -q '"output_rate_per_1m"'
}

@test "estimate_api_costs aggregates multiple files" {
    printf '%0.s.' $(seq 1 4000) > "$KORERO_DIR/logs/claude_output_2026-01-01.log"
    printf '%0.s.' $(seq 1 4000) > "$KORERO_DIR/logs/claude_output_2026-01-02.log"
    printf '%0.s.' $(seq 1 4000) > "$KORERO_DIR/logs/claude_proposal_2026-01-01.log"
    result=$(estimate_api_costs "$KORERO_DIR/logs")
    echo "$result" | grep -q '"files_analyzed": 3'
    local output_tokens
    output_tokens=$(echo "$result" | grep '"output_tokens"' | sed 's/.*: *//' | sed 's/,$//')
    [ "$output_tokens" -eq 3000 ]
}

# ===== display_cost_report =====

@test "display_cost_report shows formatted output" {
    printf '%0.s.' $(seq 1 4000) > "$KORERO_DIR/logs/claude_output_2026-01-01.log"
    run display_cost_report "$KORERO_DIR/logs"
    [ "$status" -eq 0 ]
    [[ "$output" == *"API COST ESTIMATE"* ]]
    [[ "$output" == *"Token Usage"* ]]
    [[ "$output" == *"Cost Breakdown"* ]]
}

@test "display_cost_report returns 1 for missing directory" {
    run display_cost_report "/nonexistent/dir"
    [ "$status" -eq 1 ]
}

@test "display_cost_report shows token counts" {
    printf '%0.s.' $(seq 1 4000) > "$KORERO_DIR/logs/claude_output_2026-01-01.log"
    run display_cost_report "$KORERO_DIR/logs"
    [[ "$output" == *"Input tokens"* ]]
    [[ "$output" == *"Output tokens"* ]]
}

@test "display_cost_report shows files analyzed count" {
    printf '%0.s.' $(seq 1 4000) > "$KORERO_DIR/logs/claude_output_2026-01-01.log"
    run display_cost_report "$KORERO_DIR/logs"
    [[ "$output" == *"Files analyzed"* ]]
}

@test "display_cost_report shows pricing info" {
    printf '%0.s.' $(seq 1 4000) > "$KORERO_DIR/logs/claude_output_2026-01-01.log"
    run display_cost_report "$KORERO_DIR/logs"
    [[ "$output" == *"Pricing"* ]]
    [[ "$output" == *"/1M input"* ]]
}

@test "display_cost_report shows estimate note" {
    printf '%0.s.' $(seq 1 4000) > "$KORERO_DIR/logs/claude_output_2026-01-01.log"
    run display_cost_report "$KORERO_DIR/logs"
    [[ "$output" == *"Estimates based on log file sizes"* ]]
}
