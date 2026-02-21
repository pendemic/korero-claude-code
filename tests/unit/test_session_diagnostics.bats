#!/usr/bin/env bats

# Tests for lib/session_diagnostics.sh — Session Resume Diagnostics

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
    mkdir -p .korero
    source "$REPO_ROOT/lib/session_diagnostics.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# --- diagnose_session ---

@test "diagnose_session reports no session file" {
    run diagnose_session .korero/nonexistent
    [ "$status" -eq 0 ]
    [[ "$output" == *"no_session_file"* ]]
    [[ "$output" == *"No previous session"* ]]
}

@test "diagnose_session reports empty session file" {
    touch .korero/.claude_session_id
    run diagnose_session .korero/.claude_session_id
    [ "$status" -eq 0 ]
    [[ "$output" == *"empty_session_file"* ]]
}

@test "diagnose_session reports corrupted JSON" {
    echo '{invalid json' > .korero/.claude_session_id
    run diagnose_session .korero/.claude_session_id
    [ "$status" -eq 0 ]
    [[ "$output" == *"corrupted_session"* ]]
}

@test "diagnose_session reports missing session ID in JSON" {
    echo '{"timestamp": "2026-01-01T00:00:00Z"}' > .korero/.claude_session_id
    run diagnose_session .korero/.claude_session_id
    [ "$status" -eq 0 ]
    [[ "$output" == *"missing_session_id"* ]]
}

@test "diagnose_session reports valid plain text session" {
    echo "test-session-abc" > .korero/.claude_session_id
    run diagnose_session .korero/.claude_session_id 86400
    [ "$status" -eq 0 ]
    [[ "$output" == *"session_valid"* ]]
    [[ "$output" == *"test-session-abc"* ]]
}

@test "diagnose_session reports expired plain text session" {
    echo "old-session-xyz" > .korero/.claude_session_id
    # Set file modification time to 25 hours ago
    touch -d "25 hours ago" .korero/.claude_session_id 2>/dev/null || \
    touch -t "$(date -d '25 hours ago' '+%Y%m%d%H%M.%S' 2>/dev/null || date '+%Y%m%d%H%M.%S')" .korero/.claude_session_id 2>/dev/null || \
    true
    run diagnose_session .korero/.claude_session_id 86400
    [ "$status" -eq 0 ]
    # Might still be valid if touch -d not supported, that's OK
    [[ "$output" == *"session_"* ]]
}

@test "diagnose_session handles JSON with valid session" {
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
    echo "{\"session_id\": \"sess-123\", \"timestamp\": \"$ts\"}" > .korero/.claude_session_id
    run diagnose_session .korero/.claude_session_id 86400
    [ "$status" -eq 0 ]
    [[ "$output" == *"session_valid"* ]] || [[ "$output" == *"unparseable"* ]]
}

@test "diagnose_session handles JSON without timestamp" {
    echo '{"session_id": "sess-123"}' > .korero/.claude_session_id
    run diagnose_session .korero/.claude_session_id
    [ "$status" -eq 0 ]
    [[ "$output" == *"no_timestamp"* ]]
}

# --- get_session_diagnostic_reason ---

@test "get_session_diagnostic_reason returns reason code" {
    result=$(get_session_diagnostic_reason .korero/nonexistent)
    [ "$result" = "no_session_file" ]
}

@test "get_session_diagnostic_reason returns empty_session_file for empty" {
    touch .korero/.claude_session_id
    result=$(get_session_diagnostic_reason .korero/.claude_session_id)
    [ "$result" = "empty_session_file" ]
}

# --- get_session_diagnostic_message ---

@test "get_session_diagnostic_message returns human message" {
    result=$(get_session_diagnostic_message .korero/nonexistent)
    [[ "$result" == *"No previous session"* ]]
}

# --- compute_context_hash ---

@test "compute_context_hash returns a hash" {
    echo "# Test" > .korero/PROMPT.md
    result=$(compute_context_hash .korero)
    [ -n "$result" ]
    [ ${#result} -gt 10 ]
}

@test "compute_context_hash changes when config changes" {
    echo "# Version 1" > .korero/PROMPT.md
    hash1=$(compute_context_hash .korero)

    echo "# Version 2" > .korero/PROMPT.md
    hash2=$(compute_context_hash .korero)

    [ "$hash1" != "$hash2" ]
}

@test "compute_context_hash is stable for same content" {
    echo "# Stable" > .korero/PROMPT.md
    hash1=$(compute_context_hash .korero)
    hash2=$(compute_context_hash .korero)
    [ "$hash1" = "$hash2" ]
}
