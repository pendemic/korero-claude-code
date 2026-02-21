#!/usr/bin/env bats

# Tests for korero_status.sh — Comprehensive status display

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"

    # Create minimal korero project structure
    mkdir -p .korero/logs .korero/ideas
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "korero_status shows KORERO STATUS header" {
    echo 'KORERO_MODE="coding"' > .korerorc
    run bash "$REPO_ROOT/korero_status.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"KORERO STATUS"* ]]
}

@test "korero_status shows project mode from .korerorc" {
    echo 'KORERO_MODE="idea"' > .korerorc
    run bash "$REPO_ROOT/korero_status.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Mode:"*"idea"* ]]
}

@test "korero_status defaults to coding mode when no .korerorc" {
    mkdir -p .korero
    run bash "$REPO_ROOT/korero_status.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Mode:"*"coding"* ]]
}

@test "korero_status shows loop progress from status.json" {
    echo 'KORERO_MODE="coding"' > .korerorc
    echo '{"loop": 7, "status": "running", "last_exit_reason": "none"}' > .korero/status.json
    run bash "$REPO_ROOT/korero_status.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Current: 7"* ]]
}

@test "korero_status shows circuit breaker state" {
    echo 'KORERO_MODE="coding"' > .korerorc
    cat > .korero/.circuit_breaker_state << 'EOF'
{
    "state": "CLOSED",
    "consecutive_no_progress": 1,
    "consecutive_same_error": 0,
    "total_opens": 0,
    "reason": ""
}
EOF
    run bash "$REPO_ROOT/korero_status.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Circuit Breaker"* ]]
    [[ "$output" == *"CLOSED"* ]]
}

@test "korero_status shows rate limit info" {
    echo 'KORERO_MODE="coding"' > .korerorc
    echo "25" > .korero/.call_count
    run bash "$REPO_ROOT/korero_status.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rate Limit"* ]]
    [[ "$output" == *"75"* ]]  # 100 - 25 = 75 remaining
}

@test "korero_status shows no active session when no session file" {
    echo 'KORERO_MODE="coding"' > .korerorc
    run bash "$REPO_ROOT/korero_status.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No active session"* ]]
}

@test "korero_status shows subject when configured" {
    cat > .korerorc << 'EOF'
KORERO_MODE="idea"
PROJECT_SUBJECT="data analysis tool"
EOF
    run bash "$REPO_ROOT/korero_status.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Subject:"*"data analysis tool"* ]]
}

@test "korero_status counts ideas in ideas directory" {
    echo 'KORERO_MODE="idea"' > .korerorc
    echo "idea 1" > .korero/ideas/loop_1_idea.md
    echo "idea 2" > .korero/ideas/loop_2_idea.md
    echo "idea 3" > .korero/ideas/loop_3_idea.md
    run bash "$REPO_ROOT/korero_status.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ideas"* ]]
    [[ "$output" == *"3"* ]]
}

@test "korero_status fails gracefully when not a korero project" {
    rm -rf .korero .korerorc
    run bash "$REPO_ROOT/korero_status.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Not a Korero project"* ]]
}

@test "korero_status shows task completion from fix_plan.md" {
    echo 'KORERO_MODE="coding"' > .korerorc
    cat > .korero/fix_plan.md << 'EOF'
- [x] Task 1 done
- [x] Task 2 done
- [ ] Task 3 pending
- [ ] Task 4 pending
EOF
    run bash "$REPO_ROOT/korero_status.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Tasks"* ]]
    [[ "$output" == *"2/4"* ]]
}
