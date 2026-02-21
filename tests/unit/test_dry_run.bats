#!/usr/bin/env bats

# Tests for dry-run preview (show_dry_run_summary in lib/health_check.sh)

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
    source "$REPO_ROOT/lib/health_check.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "show_dry_run_summary shows header" {
    mkdir -p .korero
    echo "# Prompt" > .korero/PROMPT.md
    echo "# Plan" > .korero/fix_plan.md
    run show_dry_run_summary .korero 100 "Write,Read,Edit"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY RUN PREVIEW"* ]]
}

@test "show_dry_run_summary shows configuration section" {
    mkdir -p .korero
    echo "# Prompt" > .korero/PROMPT.md
    echo "# Plan" > .korero/fix_plan.md
    cat > .korerorc << 'EOF'
KORERO_MODE="idea"
PROJECT_SUBJECT="test project"
DOMAIN_AGENT_COUNT=5
MAX_LOOPS=20
EOF
    run show_dry_run_summary .korero 100 "@standard"
    [ "$status" -eq 0 ]
    [[ "$output" == *"idea"* ]]
    [[ "$output" == *"test project"* ]]
    [[ "$output" == *"5"* ]]
    [[ "$output" == *"20"* ]]
}

@test "show_dry_run_summary shows task summary" {
    mkdir -p .korero
    echo "# Prompt" > .korero/PROMPT.md
    cat > .korero/fix_plan.md << 'EOF'
- [x] Task 1
- [ ] Task 2
- [ ] Task 3
EOF
    run show_dry_run_summary .korero 100 "Write,Read,Edit"
    [ "$status" -eq 0 ]
    [[ "$output" == *"3 total"* ]]
    [[ "$output" == *"1 done"* ]]
    [[ "$output" == *"2 pending"* ]]
}

@test "show_dry_run_summary shows idea mode execution plan" {
    mkdir -p .korero
    echo "# Prompt" > .korero/PROMPT.md
    echo "# Plan" > .korero/fix_plan.md
    cat > .korerorc << 'EOF'
KORERO_MODE="idea"
EOF
    run show_dry_run_summary .korero 100 "Write,Read,Edit"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Save to"* ]]
}

@test "show_dry_run_summary shows coding mode execution plan" {
    mkdir -p .korero
    echo "# Prompt" > .korero/PROMPT.md
    echo "# Plan" > .korero/fix_plan.md
    cat > .korerorc << 'EOF'
KORERO_MODE="coding"
EOF
    run show_dry_run_summary .korero 100 "Write,Read,Edit"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Git commit"* ]]
}

@test "show_dry_run_summary shows resource projection" {
    mkdir -p .korero
    echo "# Prompt" > .korero/PROMPT.md
    echo "# Plan" > .korero/fix_plan.md
    cat > .korerorc << 'EOF'
MAX_LOOPS=10
EOF
    run show_dry_run_summary .korero 100 "Write,Read,Edit"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Projected"* ]]
}

@test "show_dry_run_summary includes health checks" {
    mkdir -p .korero
    echo "# Prompt" > .korero/PROMPT.md
    echo "# Plan" > .korero/fix_plan.md
    run show_dry_run_summary .korero 100 "Write,Read,Edit"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pre-Loop Health Check"* ]]
}

@test "show_dry_run_summary reports ready state" {
    mkdir -p .korero
    echo "# Prompt" > .korero/PROMPT.md
    echo "# Plan" > .korero/fix_plan.md
    run show_dry_run_summary .korero 100 "Write,Read,Edit"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ready to start"* ]]
}

@test "show_dry_run_summary reports issues" {
    mkdir -p .korero
    echo "100" > .korero/.call_count
    run show_dry_run_summary .korero 100 ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"Issues detected"* ]]
}

@test "show_dry_run_summary handles missing prompt file" {
    mkdir -p .korero
    echo "# Plan" > .korero/fix_plan.md
    run show_dry_run_summary .korero 100 "Write,Read,Edit"
    [ "$status" -eq 0 ]
    [[ "$output" == *"NOT FOUND"* ]]
}
