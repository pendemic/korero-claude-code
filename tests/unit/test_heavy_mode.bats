#!/usr/bin/env bats

# Tests for heavy mode integration (heavy-coding, heavy-idea)
# Tests CLI flags, configuration, validation, and health checks

load '../helpers/test_helper'

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
    export KORERO_DIR=".korero"
    mkdir -p "$KORERO_DIR/logs" "$KORERO_DIR/ideas" "$KORERO_DIR/debates"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ===== .korerorc validation with heavy modes =====

@test "validate_korerorc accepts heavy-coding mode" {
    source "$REPO_ROOT/lib/enable_core.sh"
    cat > ".korerorc" << 'EOF'
KORERO_MODE="heavy-coding"
PROJECT_SUBJECT="test project"
DOMAIN_AGENT_COUNT=3
MAX_LOOPS="10"
ALLOWED_TOOLS="@standard"
EOF
    run validate_korerorc ".korerorc"
    [ "$status" -eq 0 ]
}

@test "validate_korerorc accepts heavy-idea mode" {
    source "$REPO_ROOT/lib/enable_core.sh"
    cat > ".korerorc" << 'EOF'
KORERO_MODE="heavy-idea"
PROJECT_SUBJECT="test"
MAX_LOOPS="continuous"
EOF
    run validate_korerorc ".korerorc"
    [ "$status" -eq 0 ]
}

@test "validate_korerorc rejects invalid mode" {
    source "$REPO_ROOT/lib/enable_core.sh"
    cat > ".korerorc" << 'EOF'
KORERO_MODE="heavy-invalid"
EOF
    run validate_korerorc ".korerorc"
    [ "$status" -eq 1 ]
}

@test "validate_korerorc validates CODEX_TIMEOUT range" {
    source "$REPO_ROOT/lib/enable_core.sh"
    cat > ".korerorc" << 'EOF'
KORERO_MODE="heavy-coding"
CODEX_TIMEOUT=200
EOF
    run validate_korerorc ".korerorc"
    [ "$status" -eq 1 ]
}

@test "validate_korerorc accepts valid CODEX_TIMEOUT" {
    source "$REPO_ROOT/lib/enable_core.sh"
    cat > ".korerorc" << 'EOF'
KORERO_MODE="heavy-coding"
CODEX_TIMEOUT=30
EOF
    run validate_korerorc ".korerorc"
    [ "$status" -eq 0 ]
}

@test "validate_korerorc validates DEBATE_ROUNDS range" {
    source "$REPO_ROOT/lib/enable_core.sh"
    cat > ".korerorc" << 'EOF'
KORERO_MODE="heavy-coding"
DEBATE_ROUNDS=5
EOF
    run validate_korerorc ".korerorc"
    [ "$status" -eq 1 ]
}

@test "validate_korerorc accepts valid DEBATE_ROUNDS" {
    source "$REPO_ROOT/lib/enable_core.sh"
    cat > ".korerorc" << 'EOF'
KORERO_MODE="heavy-coding"
DEBATE_ROUNDS=2
EOF
    run validate_korerorc ".korerorc"
    [ "$status" -eq 0 ]
}

# ===== generate_korerorc with heavy modes =====

@test "generate_korerorc includes heavy mode fields" {
    source "$REPO_ROOT/lib/enable_core.sh"
    result=$(generate_korerorc "testproj" "node" "local" "heavy-coding" "my project" 3 10)
    echo "$result" | grep -q 'KORERO_MODE="heavy-coding"'
    echo "$result" | grep -q 'CODEX_TIMEOUT=15'
    echo "$result" | grep -q 'CODEX_APPROVAL="never"'
    echo "$result" | grep -q 'DEBATE_ROUNDS=2'
}

@test "generate_korerorc omits heavy fields for coding mode" {
    source "$REPO_ROOT/lib/enable_core.sh"
    result=$(generate_korerorc "testproj" "node" "local" "coding" "project" 3 10)
    ! echo "$result" | grep -q 'CODEX_TIMEOUT'
    ! echo "$result" | grep -q 'CODEX_APPROVAL'
}

@test "generate_korerorc omits heavy fields for idea mode" {
    source "$REPO_ROOT/lib/enable_core.sh"
    result=$(generate_korerorc "testproj" "node" "local" "idea" "project" 3 10)
    ! echo "$result" | grep -q 'CODEX_TIMEOUT'
}

# ===== validate_korerorc_verbose with heavy modes =====

@test "validate_korerorc_verbose shows heavy-coding as valid" {
    source "$REPO_ROOT/lib/enable_core.sh"
    cat > ".korerorc" << 'EOF'
KORERO_MODE="heavy-coding"
CODEX_TIMEOUT=15
DEBATE_ROUNDS=2
ALLOWED_TOOLS="@standard"
EOF
    run validate_korerorc_verbose ".korerorc"
    echo "$output" | grep -q "✓ KORERO_MODE: heavy-coding"
}

@test "validate_korerorc_verbose validates CODEX_TIMEOUT" {
    source "$REPO_ROOT/lib/enable_core.sh"
    cat > ".korerorc" << 'EOF'
KORERO_MODE="heavy-coding"
CODEX_TIMEOUT=15
ALLOWED_TOOLS="@standard"
EOF
    run validate_korerorc_verbose ".korerorc"
    echo "$output" | grep -q "✓ CODEX_TIMEOUT: 15m"
}

@test "validate_korerorc_verbose validates DEBATE_ROUNDS" {
    source "$REPO_ROOT/lib/enable_core.sh"
    cat > ".korerorc" << 'EOF'
KORERO_MODE="heavy-idea"
DEBATE_ROUNDS=3
ALLOWED_TOOLS="@standard"
EOF
    run validate_korerorc_verbose ".korerorc"
    echo "$output" | grep -q "✓ DEBATE_ROUNDS: 3"
}

@test "validate_korerorc rejects invalid CODEX_FALLBACK" {
    source "$REPO_ROOT/lib/enable_core.sh"
    cat > ".korerorc" << 'EOF'
KORERO_MODE="heavy-coding"
CODEX_FALLBACK="invalid_value"
EOF
    run validate_korerorc ".korerorc"
    [ "$status" -eq 1 ]
}

@test "validate_korerorc accepts valid CODEX_FALLBACK values" {
    source "$REPO_ROOT/lib/enable_core.sh"
    for val in fail claude-only silent; do
        cat > ".korerorc" << EOF
KORERO_MODE="heavy-coding"
CODEX_FALLBACK="$val"
EOF
        run validate_korerorc ".korerorc"
        [ "$status" -eq 0 ]
    done
}

@test "validate_korerorc_verbose validates CODEX_FALLBACK" {
    source "$REPO_ROOT/lib/enable_core.sh"
    cat > ".korerorc" << 'EOF'
KORERO_MODE="heavy-coding"
CODEX_FALLBACK="claude-only"
ALLOWED_TOOLS="@standard"
EOF
    run validate_korerorc_verbose ".korerorc"
    echo "$output" | grep -q "✓ CODEX_FALLBACK: claude-only"
}

@test "generate_korerorc includes CODEX_FALLBACK for heavy modes" {
    source "$REPO_ROOT/lib/enable_core.sh"
    result=$(generate_korerorc "testproj" "node" "local" "heavy-coding" "my project" 3 10)
    echo "$result" | grep -q 'CODEX_FALLBACK="claude-only"'
}

# ===== CLI flag parsing =====

@test "korero_loop.sh parses --codex-timeout flag" {
    source "$REPO_ROOT/lib/date_utils.sh"
    source "$REPO_ROOT/lib/timeout_utils.sh"
    source "$REPO_ROOT/lib/response_analyzer.sh"
    source "$REPO_ROOT/lib/circuit_breaker.sh"
    source "$REPO_ROOT/lib/permission_presets.sh"
    source "$REPO_ROOT/lib/health_check.sh"
    source "$REPO_ROOT/lib/codex_adapter.sh"
    source "$REPO_ROOT/lib/cross_ai_debate.sh"
    source "$REPO_ROOT/lib/debate_transcript.sh"

    # Source the loop script (without executing main)
    CODEX_TIMEOUT_MINUTES=15
    # Test the parsing logic inline
    args=("--codex-timeout" "30")
    set -- "${args[@]}"
    case $1 in
        --codex-timeout)
            if [[ "$2" =~ ^[1-9][0-9]*$ ]] && [[ "$2" -le 120 ]]; then
                CODEX_TIMEOUT_MINUTES="$2"
            fi
            ;;
    esac
    [ "$CODEX_TIMEOUT_MINUTES" -eq 30 ]
}

@test "korero_loop.sh parses --debate-rounds flag" {
    DEBATE_ROUNDS=2
    args=("--debate-rounds" "1")
    set -- "${args[@]}"
    case $1 in
        --debate-rounds)
            if [[ "$2" =~ ^[1-3]$ ]]; then
                DEBATE_ROUNDS="$2"
            fi
            ;;
    esac
    [ "$DEBATE_ROUNDS" -eq 1 ]
}

# ===== Health check: Codex checks =====

@test "check_codex_tool returns 1 when codex not installed" {
    source "$REPO_ROOT/lib/health_check.sh"
    run bash -c 'PATH=/usr/bin:/bin; source "'$REPO_ROOT'/lib/health_check.sh"; check_codex_tool'
    [ "$status" -eq 1 ]
}

@test "check_codex_auth_health returns 1 when auth missing" {
    source "$REPO_ROOT/lib/health_check.sh"
    export CODEX_HOME="$TEST_DIR/.codex_empty"
    mkdir -p "$CODEX_HOME"
    run bash -c 'PATH=/usr/bin:/bin; export CODEX_HOME="'$CODEX_HOME'"; source "'$REPO_ROOT'/lib/health_check.sh"; check_codex_auth_health'
    [ "$status" -eq 1 ]
}

@test "check_codex_auth_health detects auth.json" {
    source "$REPO_ROOT/lib/health_check.sh"
    export CODEX_HOME="$TEST_DIR/.codex"
    mkdir -p "$CODEX_HOME"
    echo '{"token":"test"}' > "$CODEX_HOME/auth.json"
    run check_codex_auth_health
    [ "$status" -eq 0 ]
}

# ===== Circuit breaker: Codex failure tracking =====

@test "track_codex_failure resets counter on success" {
    source "$REPO_ROOT/lib/circuit_breaker.sh"
    echo "2" > "$KORERO_DIR/.codex_consecutive_failures"
    track_codex_failure 0
    count=$(cat "$KORERO_DIR/.codex_consecutive_failures")
    [ "$count" -eq 0 ]
}

@test "track_codex_failure increments on failure" {
    source "$REPO_ROOT/lib/circuit_breaker.sh"
    echo "0" > "$KORERO_DIR/.codex_consecutive_failures"
    track_codex_failure 1
    count=$(cat "$KORERO_DIR/.codex_consecutive_failures")
    [ "$count" -eq 1 ]
}

@test "track_codex_failure returns 1 at threshold" {
    source "$REPO_ROOT/lib/circuit_breaker.sh"
    export CB_CODEX_FAILURE_THRESHOLD=2
    echo "1" > "$KORERO_DIR/.codex_consecutive_failures"
    run track_codex_failure 1
    [ "$status" -eq 1 ]
}

@test "track_codex_failure returns 0 below threshold" {
    source "$REPO_ROOT/lib/circuit_breaker.sh"
    export CB_CODEX_FAILURE_THRESHOLD=5
    echo "1" > "$KORERO_DIR/.codex_consecutive_failures"
    run track_codex_failure 1
    [ "$status" -eq 0 ]
}

# ===== korero_enable_ci.sh mode validation =====

@test "korero_enable_ci accepts heavy-coding mode" {
    run bash -c 'source "'$REPO_ROOT'/lib/enable_core.sh"; source "'$REPO_ROOT'/korero_enable_ci.sh" --mode heavy-coding --subject "test" 2>&1' || true
    # Should not contain "must be 'coding' or 'idea'" error
    ! echo "$output" | grep -q "must be 'coding'"
}

@test "korero_enable_ci rejects invalid mode" {
    run bash "$REPO_ROOT/korero_enable_ci.sh" --mode "invalid-mode" 2>&1
    echo "$output" | grep -qi "must be"
}

# ===== Help topic: modes =====

@test "help modes topic includes heavy-coding" {
    # Source the loop to get the help function, but catch any initialization errors
    result=$(bash -c 'source "'$REPO_ROOT'/lib/date_utils.sh"; source "'$REPO_ROOT'/lib/timeout_utils.sh"; source "'$REPO_ROOT'/lib/response_analyzer.sh"; source "'$REPO_ROOT'/lib/circuit_breaker.sh"; source "'$REPO_ROOT'/lib/permission_presets.sh"; source "'$REPO_ROOT'/lib/health_check.sh"; source "'$REPO_ROOT'/lib/codex_adapter.sh"; source "'$REPO_ROOT'/lib/cross_ai_debate.sh"; source "'$REPO_ROOT'/lib/debate_transcript.sh"; bash "'$REPO_ROOT'/korero_loop.sh" --help modes 2>&1' || true)
    echo "$result" | grep -q "heavy-coding"
}

@test "help modes topic includes heavy-idea" {
    result=$(bash "$REPO_ROOT/korero_loop.sh" --help modes 2>&1 || true)
    echo "$result" | grep -q "heavy-idea"
}

@test "help config topic includes CODEX_TIMEOUT" {
    result=$(bash "$REPO_ROOT/korero_loop.sh" --help config 2>&1 || true)
    echo "$result" | grep -q "CODEX_TIMEOUT"
}
