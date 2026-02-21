#!/usr/bin/env bats

# Tests for korero_ideas.sh — Ideas browsing and search

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
    mkdir -p .korero

    # Create a sample IDEAS.md
    cat > .korero/IDEAS.md << 'IDEASEOF'
# Korero Idea Generation

═══════════════════════════════════════════════════════════
LOOP 1 WINNING IDEA
═══════════════════════════════════════════════════════════

**Title:** Shell Compatibility Detection
**Type:** Usability Improvement
**Category:** Cross-Platform Support

### Description
Test description for idea 1.

═══════════════════════════════════════════════════════════

═══════════════════════════════════════════════════════════
LOOP 2 WINNING IDEA
═══════════════════════════════════════════════════════════

**Title:** Permission Fix Suggestions
**Type:** New Feature
**Category:** CLI Integration

### Description
Test description for idea 2.

═══════════════════════════════════════════════════════════
IDEASEOF
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "korero ideas list shows ideas table" {
    run bash "$REPO_ROOT/korero_ideas.sh" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"WINNING IDEAS"* ]]
    [[ "$output" == *"2 total"* ]]
}

@test "korero ideas list shows idea titles" {
    run bash "$REPO_ROOT/korero_ideas.sh" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"Shell Compatibility Detection"* ]]
    [[ "$output" == *"Permission Fix Suggestions"* ]]
}

@test "korero ideas list shows loop numbers" {
    run bash "$REPO_ROOT/korero_ideas.sh" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"1"* ]]
    [[ "$output" == *"2"* ]]
}

@test "korero ideas list handles missing IDEAS.md" {
    rm .korero/IDEAS.md
    run bash "$REPO_ROOT/korero_ideas.sh" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No ideas file"* ]]
}

@test "korero ideas show displays specific idea" {
    run bash "$REPO_ROOT/korero_ideas.sh" show 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"LOOP 1"* ]]
    [[ "$output" == *"Shell Compatibility Detection"* ]]
}

@test "korero ideas show handles missing loop" {
    run bash "$REPO_ROOT/korero_ideas.sh" show 99
    [ "$status" -eq 1 ]
    [[ "$output" == *"No winning idea found"* ]]
}

@test "korero ideas search finds matching ideas" {
    run bash "$REPO_ROOT/korero_ideas.sh" search "Permission"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Permission Fix Suggestions"* ]]
}

@test "korero ideas search handles no matches" {
    run bash "$REPO_ROOT/korero_ideas.sh" search "nonexistent"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No ideas matching"* ]]
}

@test "korero ideas without subcommand shows usage" {
    run bash "$REPO_ROOT/korero_ideas.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "korero ideas help shows usage" {
    run bash "$REPO_ROOT/korero_ideas.sh" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"list"* ]]
    [[ "$output" == *"show"* ]]
    [[ "$output" == *"search"* ]]
}
