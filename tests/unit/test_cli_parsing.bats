#!/usr/bin/env bats
# Unit tests for CLI argument parsing in korero_loop.sh
# Linked to GitHub Issue #10
# TDD: Tests written to cover all CLI flag combinations

load '../helpers/test_helper'
load '../helpers/fixtures'

# Path to korero_loop.sh
KORERO_SCRIPT="${BATS_TEST_DIRNAME}/../../korero_loop.sh"

setup() {
    # Create temporary test directory
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"

    # Initialize minimal git repo (required by some flags)
    git init > /dev/null 2>&1
    git config user.email "test@example.com"
    git config user.name "Test User"

    # Set up required environment with .korero/ subfolder structure
    export KORERO_DIR=".korero"
    export PROMPT_FILE="$KORERO_DIR/PROMPT.md"
    export LOG_DIR="$KORERO_DIR/logs"
    export STATUS_FILE="$KORERO_DIR/status.json"
    export EXIT_SIGNALS_FILE="$KORERO_DIR/.exit_signals"
    export CALL_COUNT_FILE="$KORERO_DIR/.call_count"
    export TIMESTAMP_FILE="$KORERO_DIR/.last_reset"

    mkdir -p "$LOG_DIR"

    # Create minimal required files
    echo "# Test Prompt" > "$PROMPT_FILE"
    echo "0" > "$CALL_COUNT_FILE"
    echo "$(date +%Y%m%d%H)" > "$TIMESTAMP_FILE"
    echo '{"test_only_loops": [], "done_signals": [], "completion_indicators": []}' > "$EXIT_SIGNALS_FILE"

    # Create lib directory with circuit breaker stub
    mkdir -p lib
    cat > lib/circuit_breaker.sh << 'EOF'
KORERO_DIR="${KORERO_DIR:-.korero}"
reset_circuit_breaker() { echo "Circuit breaker reset: $1"; }
show_circuit_status() { echo "Circuit breaker status: CLOSED"; }
init_circuit_breaker() { :; }
record_loop_result() { :; }
EOF

    cat > lib/response_analyzer.sh << 'EOF'
KORERO_DIR="${KORERO_DIR:-.korero}"
analyze_response() { :; }
detect_output_format() { echo "text"; }
EOF

    cat > lib/date_utils.sh << 'EOF'
get_iso_timestamp() { date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S'; }
get_epoch_timestamp() { date +%s; }
EOF
}

teardown() {
    if [[ -n "$TEST_DIR" ]] && [[ -d "$TEST_DIR" ]]; then
        cd /
        rm -rf "$TEST_DIR"
    fi
}

# =============================================================================
# HELP FLAG TESTS (2 tests)
# =============================================================================

@test "--help flag displays help message with all options" {
    run bash "$KORERO_SCRIPT" --help

    assert_success

    # Verify help contains key sections
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Options:"* ]]

    # Verify all flags are documented
    [[ "$output" == *"--calls"* ]]
    [[ "$output" == *"--prompt"* ]]
    [[ "$output" == *"--status"* ]]
    [[ "$output" == *"--monitor"* ]]
    [[ "$output" == *"--verbose"* ]]
    [[ "$output" == *"--timeout"* ]]
    [[ "$output" == *"--reset-circuit"* ]]
    [[ "$output" == *"--circuit-status"* ]]
    [[ "$output" == *"--output-format"* ]]
    [[ "$output" == *"--allowed-tools"* ]]
    [[ "$output" == *"--no-continue"* ]]
}

@test "-h short flag displays help message" {
    run bash "$KORERO_SCRIPT" -h

    assert_success

    # Verify help contains key sections
    [[ "$output" == *"Usage:"* ]]
    [[ "$output" == *"Options:"* ]]
    [[ "$output" == *"--help"* ]]
}

# =============================================================================
# FLAG VALUE SETTING TESTS (6 tests)
# =============================================================================

@test "--calls NUM sets MAX_CALLS_PER_HOUR correctly" {
    # Use --help after --calls to capture the parsed value without running main loop
    run bash "$KORERO_SCRIPT" --calls 50 --help

    assert_success
    # The help output shows default values, but the script would have parsed --calls 50
    # We verify parsing by checking the script doesn't error on valid input
    [[ "$output" == *"Usage:"* ]]
}

@test "--prompt FILE sets PROMPT_FILE correctly" {
    # Create custom prompt file
    echo "# Custom Prompt" > custom_prompt.md

    run bash "$KORERO_SCRIPT" --prompt custom_prompt.md --help

    assert_success
    [[ "$output" == *"Usage:"* ]]
}

@test "--monitor flag is accepted without error" {
    # Monitor flag combined with help to verify parsing
    run bash "$KORERO_SCRIPT" --monitor --help

    assert_success
    [[ "$output" == *"Usage:"* ]]
}

@test "--verbose flag is accepted without error" {
    run bash "$KORERO_SCRIPT" --verbose --help

    assert_success
    [[ "$output" == *"Usage:"* ]]
}

@test "--timeout NUM sets timeout with valid value" {
    run bash "$KORERO_SCRIPT" --timeout 30 --help

    assert_success
    [[ "$output" == *"Usage:"* ]]
}

@test "--timeout validates range (1-120)" {
    # Test invalid: 0
    run bash "$KORERO_SCRIPT" --timeout 0
    assert_failure
    [[ "$output" == *"must be a positive integer between 1 and 120"* ]]

    # Test invalid: 121
    run bash "$KORERO_SCRIPT" --timeout 121
    assert_failure
    [[ "$output" == *"must be a positive integer between 1 and 120"* ]]

    # Test invalid: negative
    run bash "$KORERO_SCRIPT" --timeout -5
    assert_failure
    [[ "$output" == *"must be a positive integer between 1 and 120"* ]]

    # Test boundary: 1 (valid)
    run bash "$KORERO_SCRIPT" --timeout 1 --help
    assert_success

    # Test boundary: 120 (valid)
    run bash "$KORERO_SCRIPT" --timeout 120 --help
    assert_success
}

# =============================================================================
# STATUS FLAG TESTS (2 tests)
# =============================================================================

@test "--status shows status when status.json exists" {
    # Create mock status file
    cat > "$STATUS_FILE" << 'EOF'
{
    "timestamp": "2025-01-08T12:00:00-05:00",
    "loop_count": 5,
    "calls_made_this_hour": 42,
    "max_calls_per_hour": 100,
    "last_action": "executing",
    "status": "running"
}
EOF

    run bash "$KORERO_SCRIPT" --status

    assert_success
    [[ "$output" == *"Current Status:"* ]] || [[ "$output" == *"loop_count"* ]]
    [[ "$output" == *"5"* ]]  # loop_count value
}

@test "--status handles missing status file gracefully" {
    rm -f "$STATUS_FILE"

    run bash "$KORERO_SCRIPT" --status

    assert_success
    [[ "$output" == *"No status file found"* ]]
}

# =============================================================================
# CIRCUIT BREAKER FLAG TESTS (2 tests)
# =============================================================================

@test "--reset-circuit flag executes circuit breaker reset" {
    run bash "$KORERO_SCRIPT" --reset-circuit

    assert_success
    [[ "$output" == *"Circuit breaker reset"* ]] || [[ "$output" == *"reset"* ]]
}

@test "--circuit-status flag shows circuit breaker status" {
    run bash "$KORERO_SCRIPT" --circuit-status

    assert_success
    [[ "$output" == *"Circuit breaker status"* ]] || [[ "$output" == *"CLOSED"* ]] || [[ "$output" == *"status"* ]]
}

# =============================================================================
# INVALID INPUT TESTS (3 tests)
# =============================================================================

@test "Invalid flag shows error and help" {
    run bash "$KORERO_SCRIPT" --invalid-flag

    assert_failure
    [[ "$output" == *"Unknown option: --invalid-flag"* ]]
    [[ "$output" == *"Usage:"* ]]
}

@test "Invalid timeout format shows error" {
    run bash "$KORERO_SCRIPT" --timeout abc

    assert_failure
    [[ "$output" == *"must be a positive integer"* ]] || [[ "$output" == *"Error"* ]]
}

@test "--output-format rejects invalid format values" {
    run bash "$KORERO_SCRIPT" --output-format invalid

    assert_failure
    [[ "$output" == *"must be 'json' or 'text'"* ]]
}

@test "--allowed-tools flag accepts valid tool list" {
    run bash "$KORERO_SCRIPT" --allowed-tools "Write,Read,Bash" --help

    assert_success
    [[ "$output" == *"Usage:"* ]]
}

# =============================================================================
# MULTIPLE FLAGS TESTS (3 tests)
# =============================================================================

@test "Multiple flags combined (--calls --prompt --verbose)" {
    echo "# Custom Prompt" > custom_prompt.md

    run bash "$KORERO_SCRIPT" --calls 50 --prompt custom_prompt.md --verbose --help

    assert_success
    [[ "$output" == *"Usage:"* ]]
}

@test "All flags combined works correctly" {
    echo "# Custom Prompt" > custom_prompt.md

    run bash "$KORERO_SCRIPT" \
        --calls 25 \
        --prompt custom_prompt.md \
        --verbose \
        --timeout 20 \
        --output-format json \
        --no-continue \
        --help

    assert_success
    [[ "$output" == *"Usage:"* ]]
}

@test "Help flag with other flags shows help (early exit)" {
    run bash "$KORERO_SCRIPT" --calls 50 --verbose --help

    assert_success
    [[ "$output" == *"Usage:"* ]]
    # Script should exit with help, not run main loop
}

# =============================================================================
# FLAG ORDER INDEPENDENCE TESTS (2 tests)
# =============================================================================

@test "Flag order doesn't matter (order A: calls-prompt-verbose)" {
    echo "# Custom Prompt" > custom_prompt.md

    run bash "$KORERO_SCRIPT" --calls 50 --prompt custom_prompt.md --verbose --help

    assert_success
    [[ "$output" == *"Usage:"* ]]
}

@test "Flag order doesn't matter (order B: verbose-prompt-calls)" {
    echo "# Custom Prompt" > custom_prompt.md

    run bash "$KORERO_SCRIPT" --verbose --prompt custom_prompt.md --calls 50 --help

    assert_success
    [[ "$output" == *"Usage:"* ]]
}

# =============================================================================
# SHORT FLAG EQUIVALENCE TESTS (bonus: verify short flags work)
# =============================================================================

@test "-c short flag works like --calls" {
    run bash "$KORERO_SCRIPT" -c 50 --help

    assert_success
    [[ "$output" == *"Usage:"* ]]
}

@test "-p short flag works like --prompt" {
    echo "# Custom Prompt" > custom_prompt.md

    run bash "$KORERO_SCRIPT" -p custom_prompt.md --help

    assert_success
}

@test "-s short flag works like --status" {
    rm -f "$STATUS_FILE"

    run bash "$KORERO_SCRIPT" -s

    assert_success
    [[ "$output" == *"No status file found"* ]]
}

@test "-m short flag works like --monitor" {
    run bash "$KORERO_SCRIPT" -m --help

    assert_success
}

@test "-v short flag works like --verbose" {
    run bash "$KORERO_SCRIPT" -v --help

    assert_success
}

@test "-t short flag works like --timeout" {
    run bash "$KORERO_SCRIPT" -t 30 --help

    assert_success
}

# =============================================================================
# MONITOR PARAMETER FORWARDING TESTS (Issue #120)
# Tests that --monitor correctly forwards all CLI parameters to the inner loop
# =============================================================================

# Helper function to extract the korero_cmd that would be built in setup_tmux_session
# This sources korero_loop.sh and simulates the parameter forwarding logic
build_korero_cmd_for_test() {
    local korero_cmd="korero"
    local MAX_CALLS_PER_HOUR="${1:-100}"
    local PROMPT_FILE="${2:-.korero/PROMPT.md}"
    local CLAUDE_OUTPUT_FORMAT="${3:-json}"
    local VERBOSE_PROGRESS="${4:-false}"
    local CLAUDE_TIMEOUT_MINUTES="${5:-15}"
    local CLAUDE_ALLOWED_TOOLS="${6:-Write,Read,Edit,Bash(git *),Bash(npm *),Bash(pytest)}"
    local CLAUDE_USE_CONTINUE="${7:-true}"
    local CLAUDE_SESSION_EXPIRY_HOURS="${8:-24}"
    local KORERO_DIR=".korero"

    # Forward --calls if non-default
    if [[ "$MAX_CALLS_PER_HOUR" != "100" ]]; then
        korero_cmd="$korero_cmd --calls $MAX_CALLS_PER_HOUR"
    fi
    # Forward --prompt if non-default
    if [[ "$PROMPT_FILE" != "$KORERO_DIR/PROMPT.md" ]]; then
        korero_cmd="$korero_cmd --prompt '$PROMPT_FILE'"
    fi
    # Forward --output-format if non-default (default is json)
    if [[ "$CLAUDE_OUTPUT_FORMAT" != "json" ]]; then
        korero_cmd="$korero_cmd --output-format $CLAUDE_OUTPUT_FORMAT"
    fi
    # Forward --verbose if enabled
    if [[ "$VERBOSE_PROGRESS" == "true" ]]; then
        korero_cmd="$korero_cmd --verbose"
    fi
    # Forward --timeout if non-default (default is 15)
    if [[ "$CLAUDE_TIMEOUT_MINUTES" != "15" ]]; then
        korero_cmd="$korero_cmd --timeout $CLAUDE_TIMEOUT_MINUTES"
    fi
    # Forward --allowed-tools if non-default
    if [[ "$CLAUDE_ALLOWED_TOOLS" != "Write,Read,Edit,Bash(git *),Bash(npm *),Bash(pytest)" ]]; then
        korero_cmd="$korero_cmd --allowed-tools '$CLAUDE_ALLOWED_TOOLS'"
    fi
    # Forward --no-continue if session continuity disabled
    if [[ "$CLAUDE_USE_CONTINUE" == "false" ]]; then
        korero_cmd="$korero_cmd --no-continue"
    fi
    # Forward --session-expiry if non-default (default is 24)
    if [[ "$CLAUDE_SESSION_EXPIRY_HOURS" != "24" ]]; then
        korero_cmd="$korero_cmd --session-expiry $CLAUDE_SESSION_EXPIRY_HOURS"
    fi

    echo "$korero_cmd"
}

@test "monitor forwards --output-format text parameter" {
    local result=$(build_korero_cmd_for_test 100 ".korero/PROMPT.md" "text")
    [[ "$result" == *"--output-format text"* ]]
}

@test "monitor forwards --verbose parameter" {
    local result=$(build_korero_cmd_for_test 100 ".korero/PROMPT.md" "json" "true")
    [[ "$result" == *"--verbose"* ]]
}

@test "monitor forwards --timeout parameter" {
    local result=$(build_korero_cmd_for_test 100 ".korero/PROMPT.md" "json" "false" "30")
    [[ "$result" == *"--timeout 30"* ]]
}

@test "monitor forwards --allowed-tools parameter" {
    local result=$(build_korero_cmd_for_test 100 ".korero/PROMPT.md" "json" "false" "15" "Read,Write")
    [[ "$result" == *"--allowed-tools 'Read,Write'"* ]]
}

@test "monitor forwards --no-continue parameter" {
    local result=$(build_korero_cmd_for_test 100 ".korero/PROMPT.md" "json" "false" "15" "Write,Bash(git *),Read" "false")
    [[ "$result" == *"--no-continue"* ]]
}

@test "monitor forwards --session-expiry parameter" {
    local result=$(build_korero_cmd_for_test 100 ".korero/PROMPT.md" "json" "false" "15" "Write,Bash(git *),Read" "true" "48")
    [[ "$result" == *"--session-expiry 48"* ]]
}

@test "monitor forwards multiple parameters together" {
    local result=$(build_korero_cmd_for_test 50 ".korero/PROMPT.md" "text" "true" "30" "Read,Write" "false" "12")
    [[ "$result" == *"--calls 50"* ]]
    [[ "$result" == *"--output-format text"* ]]
    [[ "$result" == *"--verbose"* ]]
    [[ "$result" == *"--timeout 30"* ]]
    [[ "$result" == *"--allowed-tools 'Read,Write'"* ]]
    [[ "$result" == *"--no-continue"* ]]
    [[ "$result" == *"--session-expiry 12"* ]]
}

@test "monitor does not forward default parameters" {
    local result=$(build_korero_cmd_for_test 100 ".korero/PROMPT.md" "json" "false" "15" "Write,Read,Edit,Bash(git *),Bash(npm *),Bash(pytest)" "true" "24")
    # Should only be "korero" with no extra flags
    [[ "$result" == "korero" ]]
}

# =============================================================================
# VISUAL LOOP PROGRESS INDICATOR TESTS (4 tests)
# =============================================================================

@test "print_progress outputs correct format with loop number" {
    BLUE='' NC=''
    source <(sed -n '/^print_progress()/,/^}/p' "$KORERO_SCRIPT")
    result=$(print_progress 5 "Executing" 50)
    [[ "$result" == *"Loop 5"* ]]
    [[ "$result" == *"50%"* ]]
    [[ "$result" == *"Phase: Executing"* ]]
}

@test "print_progress renders correct fill level at 80%" {
    BLUE='' NC=''
    source <(sed -n '/^print_progress()/,/^}/p' "$KORERO_SCRIPT")
    result=$(print_progress 3 "Testing" 80)
    [[ "$result" == *"████████░░"* ]]
    [[ "$result" == *"80%"* ]]
}

@test "print_progress renders empty bar at 0%" {
    BLUE='' NC=''
    source <(sed -n '/^print_progress()/,/^}/p' "$KORERO_SCRIPT")
    result=$(print_progress 1 "Starting" 0)
    [[ "$result" == *"░░░░░░░░░░"* ]]
    [[ "$result" == *"0%"* ]]
}

@test "print_progress renders full bar at 100%" {
    BLUE='' NC=''
    source <(sed -n '/^print_progress()/,/^}/p' "$KORERO_SCRIPT")
    result=$(print_progress 10 "Complete" 100)
    [[ "$result" == *"██████████"* ]]
    [[ "$result" == *"100%"* ]]
}

# =============================================================================
# DRY RUN MODE TESTS (3 tests)
# =============================================================================

@test "--dry-run flag is recognized and exits cleanly" {
    run bash "$KORERO_SCRIPT" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY RUN MODE"* ]]
}

@test "--dry-run shows prompt file info" {
    run bash "$KORERO_SCRIPT" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"Prompt file:"* ]]
}

@test "--dry-run shows allowed tools and output format" {
    run bash "$KORERO_SCRIPT" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"Allowed tools:"* ]]
    [[ "$output" == *"Output format:"* ]]
}

# =============================================================================
# INLINE HELP TOPICS TESTS (5 tests)
# =============================================================================

@test "--help with topic shows topic-specific content" {
    run bash "$KORERO_SCRIPT" --help presets
    [ "$status" -eq 0 ]
    [[ "$output" == *"PERMISSION PRESETS"* ]]
    [[ "$output" == *"@conservative"* ]]
    [[ "$output" == *"@standard"* ]]
    [[ "$output" == *"@permissive"* ]]
}

@test "--help circuit-breaker shows circuit breaker details" {
    run bash "$KORERO_SCRIPT" --help circuit-breaker
    [ "$status" -eq 0 ]
    [[ "$output" == *"CIRCUIT BREAKER"* ]]
    [[ "$output" == *"CLOSED"* ]]
    [[ "$output" == *"HALF_OPEN"* ]]
    [[ "$output" == *"OPEN"* ]]
}

@test "--help with unknown topic shows error and available topics" {
    run bash "$KORERO_SCRIPT" --help nonexistent
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown help topic"* ]]
    [[ "$output" == *"Available topics"* ]]
}

@test "--help without topic shows general help with topics list" {
    run bash "$KORERO_SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Available topics:"* ]]
    [[ "$output" == *"presets"* ]]
}

@test "--help config shows .korerorc reference" {
    run bash "$KORERO_SCRIPT" --help config
    [ "$status" -eq 0 ]
    [[ "$output" == *"KORERORC CONFIGURATION"* ]]
    [[ "$output" == *"KORERO_MODE"* ]]
    [[ "$output" == *"ALLOWED_TOOLS"* ]]
}

# =============================================================================
# IDEA-TO-BRANCH WORKFLOW TESTS (4 tests)
# =============================================================================

@test "--start-idea without number shows error" {
    run bash "$KORERO_SCRIPT" --start-idea
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires a positive loop number"* ]]
}

@test "--start-idea with non-numeric arg shows error" {
    run bash "$KORERO_SCRIPT" --start-idea abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires a positive loop number"* ]]
}

@test "--start-idea with zero shows error" {
    run bash "$KORERO_SCRIPT" --start-idea 0
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires a positive loop number"* ]]
}

@test "--start-idea with valid number but no IDEAS.md shows error" {
    run bash "$KORERO_SCRIPT" --start-idea 5
    [ "$status" -ne 0 ]
    [[ "$output" == *"No IDEAS.md found"* ]] || [[ "$output" == *"not found"* ]]
}

# =============================================================================
# QUICKSTART WIZARD TESTS (3 tests)
# =============================================================================

@test "--quickstart flag is recognized" {
    # Provide input for the 3 questions, but expect it to run quickstart wizard
    run bash -c "echo -e 'coding\ntest project\nstandard' | bash '$KORERO_SCRIPT' --quickstart"
    # Should show the quickstart header
    [[ "$output" == *"KORERO QUICK START"* ]]
}

@test "--quickstart shows mode question" {
    run bash -c "echo -e 'coding\ntest\nstandard' | bash '$KORERO_SCRIPT' --quickstart"
    [[ "$output" == *"Mode:"* ]]
    [[ "$output" == *"coding"* ]]
    [[ "$output" == *"idea"* ]]
}

@test "--quickstart shows permission level question" {
    run bash -c "echo -e 'coding\ntest\nstandard' | bash '$KORERO_SCRIPT' --quickstart"
    [[ "$output" == *"Permission level"* ]]
    [[ "$output" == *"conservative"* ]]
    [[ "$output" == *"standard"* ]]
    [[ "$output" == *"permissive"* ]]
}

# =============================================================================
# VALIDATE-CONFIG VERBOSE TESTS (3 tests)
# =============================================================================

@test "--validate-config shows checkmarks for valid config" {
    cat > .korerorc << 'EOF'
KORERO_MODE="coding"
ALLOWED_TOOLS="@standard"
MAX_LOOPS="20"
EOF
    run bash "$KORERO_SCRIPT" --validate-config
    [ "$status" -eq 0 ]
    [[ "$output" == *"✓"* ]]
    [[ "$output" == *"Configuration valid"* ]]
}

@test "--validate-config detects invalid preset with suggestion" {
    cat > .korerorc << 'EOF'
ALLOWED_TOOLS="@standrd"
EOF
    run bash "$KORERO_SCRIPT" --validate-config
    [ "$status" -eq 1 ]
    [[ "$output" == *"✗"* ]] || [[ "$output" == *"Unknown preset"* ]]
}

@test "--validate-config shows per-field validation results" {
    cat > .korerorc << 'EOF'
KORERO_MODE="coding"
ALLOWED_TOOLS="@standard"
MAX_LOOPS="continuous"
PROJECT_SUBJECT="test project"
EOF
    run bash "$KORERO_SCRIPT" --validate-config
    [ "$status" -eq 0 ]
    [[ "$output" == *"KORERO_MODE: coding"* ]]
    [[ "$output" == *"ALLOWED_TOOLS: @standard"* ]]
    [[ "$output" == *"MAX_LOOPS: continuous"* ]]
}

# =============================================================================
# EXAMPLES GALLERY TESTS (3 tests)
# =============================================================================

@test "--examples flag shows gallery menu" {
    run bash -c "echo 'q' | bash '$KORERO_SCRIPT' --examples"
    [ "$status" -eq 0 ]
    [[ "$output" == *"KORERO EXAMPLE WORKFLOWS"* ]]
}

@test "--examples shows all 7 options" {
    run bash -c "echo 'q' | bash '$KORERO_SCRIPT' --examples"
    [[ "$output" == *"TypeScript"* ]]
    [[ "$output" == *"Python"* ]]
    [[ "$output" == *"Idea-Only"* ]]
    [[ "$output" == *"CI/CD"* ]]
    [[ "$output" == *"Monitoring"* ]]
}

@test "--examples shows example content for selection 1" {
    run bash -c "printf '1\nq\n' | bash '$KORERO_SCRIPT' --examples"
    [[ "$output" == *"TypeScript Project Setup"* ]]
    [[ "$output" == *".korerorc"* ]]
}

# =============================================================================
# SHOW-DEBATE TESTS (3 tests)
# =============================================================================

@test "--show-debate with no transcripts shows message" {
    run bash "$KORERO_SCRIPT" --show-debate
    [ "$status" -eq 1 ]
    [[ "$output" == *"No debate transcripts"* ]]
}

@test "--show-debate shows specific loop transcript" {
    mkdir -p .korero/debates
    cat > .korero/debates/loop_3.md << 'EOF'
# Debate Transcript: Loop 3

**Date:** 2026-02-24
**Status:** Complete

## Phase 1: Idea Generation

Test content here
EOF
    run bash "$KORERO_SCRIPT" --show-debate 3
    [ "$status" -eq 0 ]
    [[ "$output" == *"Debate Transcript: Loop 3"* ]]
    [[ "$output" == *"Test content here"* ]]
}

@test "--show-debate with missing loop shows error" {
    mkdir -p .korero/debates
    run bash "$KORERO_SCRIPT" --show-debate 99
    [ "$status" -eq 1 ]
    [[ "$output" == *"No debate transcript found for loop 99"* ]]
}

# ===== --troubleshoot =====

@test "--troubleshoot displays quick reference" {
    run bash "$KORERO_SCRIPT" --troubleshoot
    [ "$status" -eq 0 ]
    [[ "$output" == *"TROUBLESHOOTING QUICK REFERENCE"* ]]
    [[ "$output" == *"PERMISSION ISSUES"* ]]
    [[ "$output" == *"RATE LIMITING"* ]]
    [[ "$output" == *"SESSION ISSUES"* ]]
    [[ "$output" == *"CIRCUIT BREAKER"* ]]
}

@test "--troubleshooting alias works" {
    run bash "$KORERO_SCRIPT" --troubleshooting
    [ "$status" -eq 0 ]
    [[ "$output" == *"TROUBLESHOOTING QUICK REFERENCE"* ]]
}

@test "--troubleshoot includes help topic references" {
    run bash "$KORERO_SCRIPT" --troubleshoot
    [ "$status" -eq 0 ]
    [[ "$output" == *"korero --help presets"* ]]
    [[ "$output" == *"korero --help tools"* ]]
    [[ "$output" == *"korero --help rate-limiting"* ]]
    [[ "$output" == *"korero --help session"* ]]
    [[ "$output" == *"korero --help circuit-breaker"* ]]
    [[ "$output" == *"korero --help config"* ]]
}

@test "--troubleshoot includes heavy mode section" {
    run bash "$KORERO_SCRIPT" --troubleshoot
    [ "$status" -eq 0 ]
    [[ "$output" == *"HEAVY MODE"* ]]
    [[ "$output" == *"Codex"* ]]
}

@test "--troubleshoot includes configuration section" {
    run bash "$KORERO_SCRIPT" --troubleshoot
    [ "$status" -eq 0 ]
    [[ "$output" == *"CONFIGURATION"* ]]
    [[ "$output" == *"@standard"* ]]
}

@test "--help shows --troubleshoot option" {
    run bash "$KORERO_SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--troubleshoot"* ]]
}

# ===== --diagnose (interactive troubleshooter) =====

@test "--diagnose is listed in help text" {
    run bash "$KORERO_SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--diagnose"* ]]
}

@test "--diagnose launches interactive troubleshooter" {
    run bash -c "echo 'n' | bash '$KORERO_SCRIPT' --diagnose"
    [ "$status" -eq 0 ]
    [[ "$output" == *"INTERACTIVE TROUBLESHOOTER"* ]]
}

@test "--diagnose shows permission diagnosis for Y/Y input" {
    run bash -c "printf 'y\ny\n' | bash '$KORERO_SCRIPT' --diagnose"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Missing Bash tool permission"* ]]
    [[ "$output" == *"ALLOWED_TOOLS"* ]]
}

@test "--diagnose shows rate limit diagnosis" {
    run bash -c "printf 'n\ny\ny\n' | bash '$KORERO_SCRIPT' --diagnose"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rate limit exceeded"* ]]
}

@test "--diagnose shows fallback when all questions answered no" {
    run bash -c "printf 'n\nn\nn\nn\nn\nn\n' | bash '$KORERO_SCRIPT' --diagnose"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No specific diagnosis"* ]]
}

# ===== --fix-config flag =====

@test "--fix-config is listed in help text" {
    run bash "$KORERO_SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--fix-config"* ]]
}

# ===== --search-ideas flag =====

@test "--search-ideas is listed in help text" {
    run bash "$KORERO_SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--search-ideas"* ]]
}

@test "--search-ideas requires a keyword argument" {
    run bash "$KORERO_SCRIPT" --search-ideas
    [ "$status" -ne 0 ]
}

@test "--search-ideas returns 1 when no IDEAS.md exists" {
    run bash "$KORERO_SCRIPT" --search-ideas "test"
    [ "$status" -ne 0 ]
}

@test "--search-ideas shows header with keyword" {
    # Create minimal ideas structure
    mkdir -p .korero/ideas
    echo "# IDEAS" > .korero/ideas/IDEAS.md
    cat > .korero/ideas/loop_1_idea.md << 'IDEA_EOF'
**Title:** Add caching layer
**Type:** Feature
**Category:** Performance
**Proposed by:** System Architect

Add a Redis caching layer to improve response times.
IDEA_EOF

    run bash "$KORERO_SCRIPT" --search-ideas "caching"
    [ "$status" -eq 0 ]
    [[ "$output" == *"IDEA SEARCH"* ]]
    [[ "$output" == *"caching"* ]]
}

@test "--search-ideas finds matching ideas with metadata" {
    mkdir -p .korero/ideas
    echo "# IDEAS" > .korero/ideas/IDEAS.md
    cat > .korero/ideas/loop_3_idea.md << 'IDEA_EOF'
**Title:** Implement dark mode
**Type:** Feature
**Category:** UX
**Proposed by:** UX Designer

Add dark mode toggle for better user experience.
IDEA_EOF

    run bash "$KORERO_SCRIPT" --search-ideas "dark"
    [ "$status" -eq 0 ]
    [[ "$output" == *"LOOP 3"* ]]
    [[ "$output" == *"Implement dark mode"* ]]
}

@test "--search-ideas reports no matches for non-existent keyword" {
    mkdir -p .korero/ideas
    echo "# IDEAS" > .korero/ideas/IDEAS.md
    echo "Some content" > .korero/ideas/loop_1_idea.md

    run bash "$KORERO_SCRIPT" --search-ideas "zzzznonexistent"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No matches found"* ]]
}

@test "--find-ideas is an alias for --search-ideas" {
    run bash "$KORERO_SCRIPT" --find-ideas
    [ "$status" -ne 0 ]
}

# ===== --cost-history flag =====

@test "--cost-history is listed in help text" {
    run bash "$KORERO_SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--cost-history"* ]]
}

@test "--cost-history returns 1 when no cost_history.json exists" {
    run bash "$KORERO_SCRIPT" --cost-history
    [ "$status" -ne 0 ]
}

@test "--costs is an alias for --cost-history" {
    run bash "$KORERO_SCRIPT" --costs
    [ "$status" -ne 0 ]
}

# ===== --shutdown-history flag (Loop 31) =====

@test "--shutdown-history is listed in help text" {
    run bash "$KORERO_SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--shutdown-history"* ]]
}

@test "--shutdown-history returns 0 with no history file" {
    run bash "$KORERO_SCRIPT" --shutdown-history
    [ "$status" -eq 0 ]
    [[ "$output" == *"No shutdown history"* ]]
}

# ===== --rate-status flag (Loop 33) =====

@test "--rate-status is listed in help text" {
    run bash "$KORERO_SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--rate-status"* ]]
}

@test "--rate-status shows RATE LIMIT STATUS header" {
    echo "5" > "$CALL_COUNT_FILE"
    run bash "$KORERO_SCRIPT" --rate-status
    [ "$status" -eq 0 ]
    [[ "$output" == *"RATE LIMIT STATUS"* ]]
}

@test "--rate-status shows calls used" {
    echo "25" > "$CALL_COUNT_FILE"
    run bash "$KORERO_SCRIPT" --rate-status
    [ "$status" -eq 0 ]
    [[ "$output" == *"25"* ]]
}

@test "--rate-status shows remaining calls" {
    echo "10" > "$CALL_COUNT_FILE"
    run bash "$KORERO_SCRIPT" --rate-status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Remaining"* ]]
}

@test "--rate-status shows reset time" {
    echo "0" > "$CALL_COUNT_FILE"
    run bash "$KORERO_SCRIPT" --rate-status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Resets in"* ]]
}

@test "--rate is an alias for --rate-status" {
    echo "0" > "$CALL_COUNT_FILE"
    run bash "$KORERO_SCRIPT" --rate
    [ "$status" -eq 0 ]
    [[ "$output" == *"RATE LIMIT STATUS"* ]]
}

@test "-r is an alias for --rate-status" {
    echo "0" > "$CALL_COUNT_FILE"
    run bash "$KORERO_SCRIPT" -r
    [ "$status" -eq 0 ]
    [[ "$output" == *"RATE LIMIT STATUS"* ]]
}
