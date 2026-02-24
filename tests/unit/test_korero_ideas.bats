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
Detect shell type and version at startup to provide compatibility warnings.
This improves the user experience on different operating systems.

═══════════════════════════════════════════════════════════

═══════════════════════════════════════════════════════════
LOOP 2 WINNING IDEA
═══════════════════════════════════════════════════════════

**Title:** Permission Fix Suggestions
**Type:** New Feature
**Category:** CLI Integration

### Description
When permission denials occur, suggest exact ALLOWED_TOOLS patterns
to resolve the issue. Maps commands to wildcard configurations.

═══════════════════════════════════════════════════════════

═══════════════════════════════════════════════════════════
LOOP 3 WINNING IDEA
═══════════════════════════════════════════════════════════

**Title:** Automated Database Migration Runner
**Type:** New Feature
**Category:** DevOps

### Description
Run database schema migrations automatically before each deployment.
Supports rollback on failure and integrates with CI pipelines.

═══════════════════════════════════════════════════════════
IDEASEOF
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ===== List subcommand =====

@test "korero ideas list shows ideas table with count" {
    run bash "$REPO_ROOT/korero_ideas.sh" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"WINNING IDEAS"* ]]
    [[ "$output" == *"3 total"* ]]
}

@test "korero ideas list shows idea titles" {
    run bash "$REPO_ROOT/korero_ideas.sh" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"Shell Compatibility Detection"* ]]
    [[ "$output" == *"Permission Fix Suggestions"* ]]
    [[ "$output" == *"Automated Database Migration Run"* ]]
}

@test "korero ideas list shows loop numbers" {
    run bash "$REPO_ROOT/korero_ideas.sh" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"1"* ]]
    [[ "$output" == *"2"* ]]
    [[ "$output" == *"3"* ]]
}

@test "korero ideas list shows column headers" {
    run bash "$REPO_ROOT/korero_ideas.sh" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"Loop"* ]]
    [[ "$output" == *"Title"* ]]
    [[ "$output" == *"Type"* ]]
}

@test "korero ideas list handles missing IDEAS.md" {
    rm .korero/IDEAS.md
    run bash "$REPO_ROOT/korero_ideas.sh" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No ideas file"* ]]
}

@test "korero ideas list handles empty IDEAS.md" {
    echo "# Korero Idea Generation" > .korero/IDEAS.md
    run bash "$REPO_ROOT/korero_ideas.sh" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"No winning ideas found"* ]]
}

@test "korero ideas list truncates long titles" {
    # Replace title with a very long one
    sed -i 's/Shell Compatibility Detection/This Is A Very Long Title That Should Be Truncated When Displayed In The Table/' .korero/IDEAS.md
    run bash "$REPO_ROOT/korero_ideas.sh" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"..."* ]]
}

# ===== Show subcommand =====

@test "korero ideas show displays specific idea" {
    run bash "$REPO_ROOT/korero_ideas.sh" show 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"LOOP 1"* ]]
    [[ "$output" == *"Shell Compatibility Detection"* ]]
}

@test "korero ideas show displays idea description" {
    run bash "$REPO_ROOT/korero_ideas.sh" show 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"Permission Fix Suggestions"* ]]
    [[ "$output" == *"ALLOWED_TOOLS"* ]]
}

@test "korero ideas show handles missing loop" {
    run bash "$REPO_ROOT/korero_ideas.sh" show 99
    [ "$status" -eq 1 ]
    [[ "$output" == *"No winning idea found"* ]]
}

@test "korero ideas show requires loop number" {
    run bash "$REPO_ROOT/korero_ideas.sh" show
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "korero ideas show handles missing IDEAS.md" {
    rm .korero/IDEAS.md
    run bash "$REPO_ROOT/korero_ideas.sh" show 1
    [ "$status" -eq 1 ]
    [[ "$output" == *"No ideas file"* ]]
}

# ===== Search subcommand =====

@test "korero ideas search finds matching ideas by title" {
    run bash "$REPO_ROOT/korero_ideas.sh" search "Permission"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Permission Fix Suggestions"* ]]
}

@test "korero ideas search is case-insensitive" {
    run bash "$REPO_ROOT/korero_ideas.sh" search "permission"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Permission Fix Suggestions"* ]]
}

@test "korero ideas search finds matches in description" {
    run bash "$REPO_ROOT/korero_ideas.sh" search "rollback"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Automated Database Migration Runner"* ]]
    [[ "$output" == *"matched in description"* ]]
}

@test "korero ideas search shows match location" {
    run bash "$REPO_ROOT/korero_ideas.sh" search "Shell"
    [ "$status" -eq 0 ]
    [[ "$output" == *"matched in"* ]]
}

@test "korero ideas search shows snippet for description matches" {
    run bash "$REPO_ROOT/korero_ideas.sh" search "wildcard"
    [ "$status" -eq 0 ]
    [[ "$output" == *">"* ]]
}

@test "korero ideas search handles no matches" {
    run bash "$REPO_ROOT/korero_ideas.sh" search "nonexistent"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No ideas matching"* ]]
}

@test "korero ideas search requires pattern argument" {
    run bash "$REPO_ROOT/korero_ideas.sh" search
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "korero ideas search handles missing IDEAS.md" {
    rm .korero/IDEAS.md
    run bash "$REPO_ROOT/korero_ideas.sh" search "test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No ideas file"* ]]
}

# ===== Usage / help =====

@test "korero ideas without subcommand shows usage" {
    run bash "$REPO_ROOT/korero_ideas.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "korero ideas help shows all commands" {
    run bash "$REPO_ROOT/korero_ideas.sh" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"list"* ]]
    [[ "$output" == *"show"* ]]
    [[ "$output" == *"search"* ]]
}

@test "korero ideas --help shows usage" {
    run bash "$REPO_ROOT/korero_ideas.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

# ===== Integration with korero_loop.sh =====

@test "korero_loop.sh routes ideas subcommand" {
    # Verify the ideas routing exists in korero_loop.sh
    grep -q "ideas)" "$REPO_ROOT/korero_loop.sh"
    grep -q "korero_ideas.sh" "$REPO_ROOT/korero_loop.sh"
}

@test "korero_loop.sh help mentions ideas command" {
    grep -q "ideas" "$REPO_ROOT/korero_loop.sh"
}
