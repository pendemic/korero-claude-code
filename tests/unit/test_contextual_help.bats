#!/usr/bin/env bats

load '../helpers/test_helper'

setup() {
    KORERO_LOOP="$BATS_TEST_DIRNAME/../../korero_loop.sh"
}

# ─── suggest_help_for_error ────────────────────────────────────────────────

@test "suggest_help_for_error shows circuit-breaker help topic" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_help_for_error 'circuit_breaker'" 2>&1
    [[ "$output" == *"circuit-breaker"* ]]
}

@test "suggest_help_for_error shows reset-circuit action for circuit_breaker" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_help_for_error 'circuit_breaker'" 2>&1
    [[ "$output" == *"reset-circuit"* ]]
}

@test "suggest_help_for_error shows Tip prefix" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_help_for_error 'circuit_breaker'" 2>&1
    [[ "$output" == *"Tip:"* ]]
}

@test "suggest_help_for_error shows rate-limiting help topic" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_help_for_error 'rate_limit'" 2>&1
    [[ "$output" == *"rate-limiting"* ]]
}

@test "suggest_help_for_error shows --calls action for rate_limit" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_help_for_error 'rate_limit'" 2>&1
    [[ "$output" == *"--calls"* ]]
}

@test "suggest_help_for_error shows presets help for permission_denied" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_help_for_error 'permission_denied'" 2>&1
    [[ "$output" == *"presets"* ]]
}

@test "suggest_help_for_error shows ALLOWED_TOOLS action for permission_denied" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_help_for_error 'permission_denied'" 2>&1
    [[ "$output" == *"ALLOWED_TOOLS"* ]]
}

@test "suggest_help_for_error shows session help for session_expired" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_help_for_error 'session_expired'" 2>&1
    [[ "$output" == *"session"* ]]
}

@test "suggest_help_for_error shows reset-session action for session_expired" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_help_for_error 'session_expired'" 2>&1
    [[ "$output" == *"reset-session"* ]]
}

@test "suggest_help_for_error shows config help for config_invalid" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_help_for_error 'config_invalid'" 2>&1
    [[ "$output" == *"config"* ]]
}

@test "suggest_help_for_error shows validate-config action for config_invalid" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_help_for_error 'config_invalid'" 2>&1
    [[ "$output" == *"validate-config"* ]]
}

@test "suggest_help_for_error shows modes help for codex_auth" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_help_for_error 'codex_auth'" 2>&1
    [[ "$output" == *"modes"* ]]
}

@test "suggest_help_for_error outputs nothing for unknown error type" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_help_for_error 'totally_unknown_error_xyz'" 2>&1
    [ -z "$output" ]
}

@test "suggest_help_for_error exits 0 for unknown error type" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_help_for_error 'totally_unknown_error_xyz'"
    [ "$status" -eq 0 ]
}

@test "suggest_help_for_error exits 0 for known error type" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_help_for_error 'circuit_breaker'"
    [ "$status" -eq 0 ]
}

@test "suggest_help_for_error shows budget_exceeded help tip" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_help_for_error 'budget_exceeded'" 2>&1
    [[ "$output" == *"Tip:"* ]]
    [[ "$output" == *"rate-limiting"* ]]
}

@test "suggest_help_for_error korero --help command is properly quoted" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_help_for_error 'rate_limit'" 2>&1
    [[ "$output" == *"korero --help"* ]]
}
