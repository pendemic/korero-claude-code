#!/usr/bin/env bats

# Tests for lib/codex_adapter.sh — Codex CLI adapter for heavy modes

load '../helpers/test_helper'

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
    export KORERO_DIR=".korero"
    mkdir -p "$KORERO_DIR"
    source "$REPO_ROOT/lib/codex_adapter.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ===== build_codex_command =====

@test "build_codex_command populates CODEX_CMD_ARGS array" {
    build_codex_command "test prompt" "heavy-idea" "/tmp/out.log"
    [ ${#CODEX_CMD_ARGS[@]} -gt 0 ]
}

@test "build_codex_command starts with codex exec" {
    build_codex_command "test prompt" "heavy-idea" "/tmp/out.log"
    [ "${CODEX_CMD_ARGS[0]}" = "codex" ]
    [ "${CODEX_CMD_ARGS[1]}" = "exec" ]
}

@test "build_codex_command includes --json flag" {
    build_codex_command "test prompt" "heavy-idea" "/tmp/out.log"
    local found=false
    for arg in "${CODEX_CMD_ARGS[@]}"; do
        if [ "$arg" = "--json" ]; then
            found=true
            break
        fi
    done
    [ "$found" = "true" ]
}

@test "build_codex_command uses read-only sandbox for heavy-idea" {
    build_codex_command "test prompt" "heavy-idea" "/tmp/out.log"
    local found_sandbox=false
    local sandbox_value=""
    for i in "${!CODEX_CMD_ARGS[@]}"; do
        if [ "${CODEX_CMD_ARGS[$i]}" = "--sandbox" ]; then
            sandbox_value="${CODEX_CMD_ARGS[$((i+1))]}"
            found_sandbox=true
            break
        fi
    done
    [ "$found_sandbox" = "true" ]
    [ "$sandbox_value" = "read-only" ]
}

@test "build_codex_command uses read-only sandbox for heavy-coding" {
    build_codex_command "test prompt" "heavy-coding" "/tmp/out.log"
    local sandbox_value=""
    for i in "${!CODEX_CMD_ARGS[@]}"; do
        if [ "${CODEX_CMD_ARGS[$i]}" = "--sandbox" ]; then
            sandbox_value="${CODEX_CMD_ARGS[$((i+1))]}"
            break
        fi
    done
    [ "$sandbox_value" = "read-only" ]
}

@test "build_codex_command does not include unsupported exec flags" {
    build_codex_command "test prompt" "heavy-idea"
    local found_approval=false
    local found_output_last=false
    for arg in "${CODEX_CMD_ARGS[@]}"; do
        if [ "$arg" = "--ask-for-approval" ]; then found_approval=true; fi
        if [ "$arg" = "--output-last-message" ]; then found_output_last=true; fi
    done
    [ "$found_approval" = "false" ]
    [ "$found_output_last" = "false" ]
}

@test "build_codex_command includes --model gpt-5.3-codex by default" {
    build_codex_command "test prompt" "heavy-idea" "/tmp/out.log"
    local found=false
    local model_value=""
    for i in "${!CODEX_CMD_ARGS[@]}"; do
        if [ "${CODEX_CMD_ARGS[$i]}" = "--model" ]; then
            model_value="${CODEX_CMD_ARGS[$((i+1))]}"
            found=true
            break
        fi
    done
    [ "$found" = "true" ]
    [ "$model_value" = "gpt-5.3-codex" ]
}

@test "build_codex_command respects CODEX_MODEL override" {
    CODEX_MODEL="o4-mini"
    build_codex_command "test prompt" "heavy-idea" "/tmp/out.log"
    local model_value=""
    for i in "${!CODEX_CMD_ARGS[@]}"; do
        if [ "${CODEX_CMD_ARGS[$i]}" = "--model" ]; then
            model_value="${CODEX_CMD_ARGS[$((i+1))]}"
            break
        fi
    done
    [ "$model_value" = "o4-mini" ]
    CODEX_MODEL="gpt-5.3-codex"
}

@test "build_codex_command includes prompt as last argument" {
    build_codex_command "my test prompt" "heavy-idea" "/tmp/out.log"
    [ "${CODEX_CMD_ARGS[-1]}" = "my test prompt" ]
}

@test "build_codex_command returns 0" {
    run build_codex_command "test prompt" "heavy-idea" "/tmp/out.log"
    [ "$status" -eq 0 ]
}

@test "build_codex_command resets array on each call" {
    build_codex_command "prompt1" "heavy-idea" "/tmp/out1.log"
    local count1=${#CODEX_CMD_ARGS[@]}
    build_codex_command "prompt2" "heavy-idea" "/tmp/out2.log"
    local count2=${#CODEX_CMD_ARGS[@]}
    [ "$count1" -eq "$count2" ]
}

# ===== extract_codex_proposal =====

@test "extract_codex_proposal returns content from ndjson file" {
    echo "This is the proposal" > "$TEST_DIR/ndjson.log"
    result=$(extract_codex_proposal "$TEST_DIR/ndjson.log")
    [ "$result" = "This is the proposal" ]
}

@test "extract_codex_proposal returns empty for missing file" {
    run extract_codex_proposal "$TEST_DIR/nonexistent.log"
    [ -z "$output" ]
}

@test "extract_codex_proposal falls back to last message file" {
    echo "from lastmsg" > "$TEST_DIR/lastmsg.log"
    result=$(extract_codex_proposal "$TEST_DIR/nonexistent.log" "$TEST_DIR/lastmsg.log")
    [ "$result" = "from lastmsg" ]
}

@test "extract_codex_proposal returns 0 on success" {
    echo "proposal" > "$TEST_DIR/ndjson.log"
    run extract_codex_proposal "$TEST_DIR/ndjson.log"
    [ "$status" -eq 0 ]
}

@test "extract_codex_proposal returns 1 on failure" {
    run extract_codex_proposal "$TEST_DIR/nonexistent.log"
    [ "$status" -eq 1 ]
}

# ===== parse_codex_response =====

@test "parse_codex_response creates result file from ndjson output" {
    echo "proposal text here" > "$TEST_DIR/ndjson.log"
    parse_codex_response "$TEST_DIR/ndjson.log" "" "$KORERO_DIR/.codex_parse_result"
    [ -f "$KORERO_DIR/.codex_parse_result" ]
}

@test "parse_codex_response result contains source codex" {
    echo "proposal text" > "$TEST_DIR/ndjson.log"
    parse_codex_response "$TEST_DIR/ndjson.log" "" "$KORERO_DIR/.codex_parse_result"
    grep -q '"source": "codex"' "$KORERO_DIR/.codex_parse_result"
}

@test "parse_codex_response result contains status success" {
    echo "proposal text" > "$TEST_DIR/ndjson.log"
    parse_codex_response "$TEST_DIR/ndjson.log" "" "$KORERO_DIR/.codex_parse_result"
    grep -q '"status": "success"' "$KORERO_DIR/.codex_parse_result"
}

@test "parse_codex_response returns 1 for empty output" {
    echo "" > "$TEST_DIR/lastmsg.log"
    echo "" > "$TEST_DIR/ndjson.log"
    run parse_codex_response "$TEST_DIR/ndjson.log" "$TEST_DIR/lastmsg.log" "$KORERO_DIR/.codex_parse_result"
    [ "$status" -eq 1 ]
}

@test "parse_codex_response writes error status for empty output" {
    echo "" > "$TEST_DIR/lastmsg.log"
    echo "" > "$TEST_DIR/ndjson.log"
    parse_codex_response "$TEST_DIR/ndjson.log" "$TEST_DIR/lastmsg.log" "$KORERO_DIR/.codex_parse_result" || true
    grep -q '"status":"error"' "$KORERO_DIR/.codex_parse_result"
}

# ===== check_codex_ready =====

@test "check_codex_ready returns 1 when codex not installed" {
    # Override PATH to exclude codex
    run bash -c 'PATH=/usr/bin:/bin; source "'$REPO_ROOT'/lib/codex_adapter.sh"; check_codex_ready'
    [ "$status" -eq 1 ]
}

# ===== check_codex_auth =====

@test "check_codex_auth detects auth.json file" {
    export CODEX_HOME="$TEST_DIR/.codex"
    mkdir -p "$CODEX_HOME"
    echo '{"token":"test"}' > "$CODEX_HOME/auth.json"
    run check_codex_auth
    [ "$status" -eq 0 ]
}

@test "check_codex_auth returns 1 when auth.json missing" {
    export CODEX_HOME="$TEST_DIR/.codex_empty"
    mkdir -p "$CODEX_HOME"
    # No auth.json created, and codex command not available in test
    run bash -c 'PATH=/usr/bin:/bin; export CODEX_HOME="'$CODEX_HOME'"; source "'$REPO_ROOT'/lib/codex_adapter.sh"; check_codex_auth'
    [ "$status" -eq 1 ]
}

# ===== run_codex_login =====

@test "run_codex_login returns 1 when codex not installed" {
    run bash -c 'PATH=/usr/bin:/bin; source "'$REPO_ROOT'/lib/codex_adapter.sh"; run_codex_login device'
    [ "$status" -eq 1 ]
}

@test "run_codex_login rejects unknown method" {
    # Create a mock codex command
    mkdir -p "$TEST_DIR/bin"
    echo '#!/bin/bash
echo "mock codex"' > "$TEST_DIR/bin/codex"
    chmod +x "$TEST_DIR/bin/codex"
    run bash -c 'PATH="'$TEST_DIR/bin':/usr/bin:/bin"; source "'$REPO_ROOT'/lib/codex_adapter.sh"; run_codex_login invalid_method'
    [ "$status" -eq 1 ]
}
