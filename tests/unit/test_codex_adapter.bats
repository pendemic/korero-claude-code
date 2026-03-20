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

@test "build_codex_command includes --skip-git-repo-check" {
    build_codex_command "test prompt" "heavy-idea" "/tmp/out.log"
    local found=false
    for arg in "${CODEX_CMD_ARGS[@]}"; do
        if [ "$arg" = "--skip-git-repo-check" ]; then
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

@test "build_codex_command does not include prompt text in argv" {
    build_codex_command "my test prompt" "heavy-idea" "/tmp/out.log"
    local cmd_string="${CODEX_CMD_ARGS[*]}"
    [[ "$cmd_string" != *"my test prompt"* ]]
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

@test "run_codex_with_prompt pipes prompt through stdin" {
    mkdir -p "$TEST_DIR/bin"
    echo '#!/bin/bash
cat' > "$TEST_DIR/bin/codex"
    chmod +x "$TEST_DIR/bin/codex"

    run bash -c 'PATH="'$TEST_DIR/bin':/usr/bin:/bin"; portable_timeout() { local duration=$1; shift; "$@"; }; export -f portable_timeout; source "'$REPO_ROOT'/lib/codex_adapter.sh"; build_codex_command "ignored" "heavy-idea"; run_codex_with_prompt "5s" "stdin prompt" "${CODEX_CMD_ARGS[@]}"'
    [ "$status" -eq 0 ]
    [ "$output" = "stdin prompt" ]
}

@test "resolve_codex_cli prefers codex.cmd on Windows_NT" {
    mkdir -p "$TEST_DIR/bin"
    echo '#!/bin/bash
echo "codex shell shim"' > "$TEST_DIR/bin/codex"
    echo '#!/bin/bash
echo "codex cmd shim"' > "$TEST_DIR/bin/codex.cmd"
    chmod +x "$TEST_DIR/bin/codex" "$TEST_DIR/bin/codex.cmd"

    run bash -c 'PATH="'$TEST_DIR/bin':/usr/bin:/bin"; export OS="Windows_NT"; source "'$REPO_ROOT'/lib/codex_adapter.sh"; resolve_codex_cli'
    [ "$status" -eq 0 ]
    [ "$output" = "codex.cmd" ]
}

@test "build_codex_command prefers codex.cmd on Windows_NT" {
    mkdir -p "$TEST_DIR/bin"
    echo '#!/bin/bash
echo "codex shell shim"' > "$TEST_DIR/bin/codex"
    echo '#!/bin/bash
echo "codex cmd shim"' > "$TEST_DIR/bin/codex.cmd"
    chmod +x "$TEST_DIR/bin/codex" "$TEST_DIR/bin/codex.cmd"

    run bash -c 'PATH="'$TEST_DIR/bin':/usr/bin:/bin"; export OS="Windows_NT"; source "'$REPO_ROOT'/lib/codex_adapter.sh"; build_codex_command "test prompt" "heavy-idea"; printf "%s" "${CODEX_CMD_ARGS[0]}"'
    [ "$status" -eq 0 ]
    [ "$output" = "codex.cmd" ]
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

@test "check_codex_ready returns 3 when codex launcher is broken" {
    mkdir -p "$TEST_DIR/bin"
    echo '#!/bin/bash
if [ "$1" = "--version" ]; then
  echo "MODULE_NOT_FOUND" >&2
  exit 1
fi
exit 0' > "$TEST_DIR/bin/codex"
    chmod +x "$TEST_DIR/bin/codex"

    export CODEX_HOME="$TEST_DIR/.codex_ok"
    mkdir -p "$CODEX_HOME"
    echo '{"token":"test"}' > "$CODEX_HOME/auth.json"

    run bash -c 'PATH="'$TEST_DIR/bin':/usr/bin:/bin"; export CODEX_HOME="'$CODEX_HOME'"; source "'$REPO_ROOT'/lib/codex_adapter.sh"; check_codex_ready'
    [ "$status" -eq 3 ]
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

# ===== should_fallback_to_claude =====

@test "should_fallback_to_claude returns 1 when CODEX_FALLBACK is fail" {
    export CODEX_FALLBACK="fail"
    run should_fallback_to_claude
    [ "$status" -eq 1 ]
}

@test "should_fallback_to_claude returns 0 with reason when codex not installed" {
    export CODEX_FALLBACK="claude-only"
    run bash -c 'PATH=/usr/bin:/bin; export CODEX_FALLBACK="claude-only"; source "'$REPO_ROOT'/lib/codex_adapter.sh"; should_fallback_to_claude'
    [ "$status" -eq 0 ]
    [[ "$output" == *"not_installed"* ]]
}

@test "should_fallback_to_claude returns 0 with not_authenticated when auth missing" {
    export CODEX_FALLBACK="claude-only"
    # Mock codex command that exists but auth fails
    mkdir -p "$TEST_DIR/bin"
    echo '#!/bin/bash
if [ "$1" = "login" ]; then exit 1; fi
echo "codex mock"' > "$TEST_DIR/bin/codex"
    chmod +x "$TEST_DIR/bin/codex"
    export CODEX_HOME="$TEST_DIR/.codex_empty"
    mkdir -p "$CODEX_HOME"
    run bash -c 'PATH="'$TEST_DIR/bin':/usr/bin:/bin"; export CODEX_FALLBACK="claude-only"; export CODEX_HOME="'$CODEX_HOME'"; source "'$REPO_ROOT'/lib/codex_adapter.sh"; should_fallback_to_claude'
    [ "$status" -eq 0 ]
    [[ "$output" == *"not_authenticated"* ]]
}

@test "should_fallback_to_claude returns 1 when codex is ready" {
    export CODEX_FALLBACK="claude-only"
    mkdir -p "$TEST_DIR/bin"
    echo '#!/bin/bash
echo "codex mock"' > "$TEST_DIR/bin/codex"
    chmod +x "$TEST_DIR/bin/codex"
    export CODEX_HOME="$TEST_DIR/.codex_ok"
    mkdir -p "$CODEX_HOME"
    echo '{"token":"test"}' > "$CODEX_HOME/auth.json"
    run bash -c 'PATH="'$TEST_DIR/bin':/usr/bin:/bin"; export CODEX_FALLBACK="claude-only"; export CODEX_HOME="'$CODEX_HOME'"; source "'$REPO_ROOT'/lib/codex_adapter.sh"; should_fallback_to_claude'
    [ "$status" -eq 1 ]
}

@test "should_fallback_to_claude returns broken_install when launcher is broken" {
    export CODEX_FALLBACK="claude-only"
    mkdir -p "$TEST_DIR/bin"
    echo '#!/bin/bash
if [ "$1" = "--version" ]; then
  echo "MODULE_NOT_FOUND" >&2
  exit 1
fi
exit 0' > "$TEST_DIR/bin/codex"
    chmod +x "$TEST_DIR/bin/codex"

    export CODEX_HOME="$TEST_DIR/.codex_ok"
    mkdir -p "$CODEX_HOME"
    echo '{"token":"test"}' > "$CODEX_HOME/auth.json"

    run bash -c 'PATH="'$TEST_DIR/bin':/usr/bin:/bin"; export CODEX_FALLBACK="claude-only"; export CODEX_HOME="'$CODEX_HOME'"; source "'$REPO_ROOT'/lib/codex_adapter.sh"; should_fallback_to_claude'
    [ "$status" -eq 0 ]
    [[ "$output" == *"broken_install"* ]]
}

@test "should_fallback_to_claude respects silent mode" {
    export CODEX_FALLBACK="silent"
    run bash -c 'PATH=/usr/bin:/bin; export CODEX_FALLBACK="silent"; source "'$REPO_ROOT'/lib/codex_adapter.sh"; should_fallback_to_claude'
    [ "$status" -eq 0 ]
    [[ "$output" == *"not_installed"* ]]
}

# ===== display_fallback_warning =====

@test "display_fallback_warning shows warning for not_installed" {
    run display_fallback_warning "not_installed" "claude-only"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CODEX FALLBACK"* ]]
    [[ "$output" == *"not installed"* ]]
}

@test "display_fallback_warning shows warning for not_authenticated" {
    run display_fallback_warning "not_authenticated" "claude-only"
    [ "$status" -eq 0 ]
    [[ "$output" == *"not authenticated"* ]]
}

@test "display_fallback_warning shows warning for broken_install" {
    run display_fallback_warning "broken_install" "claude-only"
    [ "$status" -eq 0 ]
    [[ "$output" == *"installed but broken"* ]]
    [[ "$output" == *"@openai/codex@latest"* ]]
}

@test "display_fallback_warning suppresses output in silent mode" {
    run display_fallback_warning "not_installed" "silent"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "display_fallback_warning shows fallback instructions" {
    run display_fallback_warning "not_installed" "claude-only"
    [[ "$output" == *"Falling back to Claude-only"* ]]
    [[ "$output" == *"CODEX_FALLBACK"* ]]
}
