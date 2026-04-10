#!/usr/bin/env bats
# Tests for Korero prompt template files in templates/ and templates/heavy_debate_prompts/
# Validates structure, placeholders, and markdown integrity of all template files

load '../helpers/test_helper'

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TEMPLATES_DIR="$PROJECT_ROOT/templates"
    HEAVY_TEMPLATES_DIR="$TEMPLATES_DIR/heavy_debate_prompts"
}

# =============================================================================
# Core Template Existence
# =============================================================================

@test "PROMPT.md template exists" {
    [[ -f "$TEMPLATES_DIR/PROMPT.md" ]]
}

@test "AGENT.md template exists" {
    [[ -f "$TEMPLATES_DIR/AGENT.md" ]]
}

@test "fix_plan.md template exists" {
    [[ -f "$TEMPLATES_DIR/fix_plan.md" ]]
}

@test "korerorc.template exists" {
    [[ -f "$TEMPLATES_DIR/korerorc.template" ]]
}

# =============================================================================
# PROMPT.md Template Structure
# =============================================================================

@test "PROMPT.md template has PROJECT_NAME reference" {
    grep -qi "project" "$TEMPLATES_DIR/PROMPT.md"
}

@test "PROMPT.md template has KORERO_STATUS block" {
    grep -q "KORERO_STATUS" "$TEMPLATES_DIR/PROMPT.md"
}

@test "PROMPT.md template has EXIT_SIGNAL field" {
    grep -q "EXIT_SIGNAL" "$TEMPLATES_DIR/PROMPT.md"
}

@test "PROMPT.md template has status reporting section" {
    grep -q "Status Reporting" "$TEMPLATES_DIR/PROMPT.md"
}

# =============================================================================
# AGENT.md Template Structure
# =============================================================================

@test "AGENT.md template has required sections" {
    run grep -E "^## " "$TEMPLATES_DIR/AGENT.md"
    [ "$status" -eq 0 ]
    [[ "$output" != "" ]]
}

@test "AGENT.md template has testing section" {
    grep -qi "test" "$TEMPLATES_DIR/AGENT.md"
}

@test "AGENT.md template has build commands section" {
    grep -qi "build" "$TEMPLATES_DIR/AGENT.md"
}

# =============================================================================
# fix_plan.md Template Structure
# =============================================================================

@test "fix_plan.md template has priority sections" {
    grep -q "Priority" "$TEMPLATES_DIR/fix_plan.md"
}

@test "fix_plan.md template has task checkboxes" {
    grep -qE '^\- \[' "$TEMPLATES_DIR/fix_plan.md"
}

# =============================================================================
# Shell Variable Escape Tests
# =============================================================================

@test "PROMPT.md has no unescaped HOME variable" {
    run grep -E '\$HOME[^}]' "$TEMPLATES_DIR/PROMPT.md"
    [ "$status" -ne 0 ]
}

@test "AGENT.md has no unescaped HOME variable" {
    run grep -E '\$HOME[^}]' "$TEMPLATES_DIR/AGENT.md"
    [ "$status" -ne 0 ]
}

@test "fix_plan.md has no unescaped HOME variable" {
    run grep -E '\$HOME[^}]' "$TEMPLATES_DIR/fix_plan.md"
    [ "$status" -ne 0 ]
}

@test "PROMPT.md has no unescaped USER variable" {
    run grep -E '\$USER[^}]' "$TEMPLATES_DIR/PROMPT.md"
    [ "$status" -ne 0 ]
}

@test "AGENT.md has no unescaped USER variable" {
    run grep -E '\$USER[^}]' "$TEMPLATES_DIR/AGENT.md"
    [ "$status" -ne 0 ]
}

@test "PROMPT.md has no unescaped PWD variable" {
    run grep -E '\$PWD[^}]' "$TEMPLATES_DIR/PROMPT.md"
    [ "$status" -ne 0 ]
}

# =============================================================================
# Markdown Validation
# =============================================================================

@test "PROMPT.md has balanced code blocks" {
    local count
    count=$(grep -c '```' "$TEMPLATES_DIR/PROMPT.md" 2>/dev/null || echo 0)
    [ $(( count % 2 )) -eq 0 ]
}

@test "AGENT.md has balanced code blocks" {
    local count
    count=$(grep -c '```' "$TEMPLATES_DIR/AGENT.md" 2>/dev/null || echo 0)
    [ $(( count % 2 )) -eq 0 ]
}

@test "PROMPT.md has no TODO markers" {
    run grep -i "^TODO:" "$TEMPLATES_DIR/PROMPT.md"
    [ "$status" -ne 0 ]
}

@test "AGENT.md has no TODO markers" {
    run grep -i "^TODO:" "$TEMPLATES_DIR/AGENT.md"
    [ "$status" -ne 0 ]
}

# =============================================================================
# Heavy Mode Template Directory
# =============================================================================

@test "heavy_debate_prompts directory exists" {
    [[ -d "$HEAVY_TEMPLATES_DIR" ]]
}

@test "critique.md template exists" {
    [[ -f "$HEAVY_TEMPLATES_DIR/critique.md" ]]
}

@test "defense.md template exists" {
    [[ -f "$HEAVY_TEMPLATES_DIR/defense.md" ]]
}

@test "judge.md template exists" {
    [[ -f "$HEAVY_TEMPLATES_DIR/judge.md" ]]
}

# =============================================================================
# Heavy Mode Template Structure
# =============================================================================

@test "critique.md has PROPOSAL placeholder" {
    grep -qE "\{(OWN_|OTHER_)?PROPOSAL\}" "$HEAVY_TEMPLATES_DIR/critique.md"
}

@test "critique.md has AI_NAME placeholder" {
    grep -q "{AI_NAME}" "$HEAVY_TEMPLATES_DIR/critique.md"
}

@test "critique.md has PROJECT_NAME placeholder" {
    grep -q "{PROJECT_NAME}" "$HEAVY_TEMPLATES_DIR/critique.md"
}

@test "defense.md has CRITIQUE placeholder" {
    grep -q "{CRITIQUE}" "$HEAVY_TEMPLATES_DIR/defense.md"
}

@test "defense.md has AI_NAME placeholder" {
    grep -q "{AI_NAME}" "$HEAVY_TEMPLATES_DIR/defense.md"
}

@test "defense.md has OWN_PROPOSAL placeholder" {
    grep -q "{OWN_PROPOSAL}" "$HEAVY_TEMPLATES_DIR/defense.md"
}

@test "judge.md has CLAUDE_PROPOSAL placeholder" {
    grep -q "{CLAUDE_PROPOSAL}" "$HEAVY_TEMPLATES_DIR/judge.md"
}

@test "judge.md has CODEX_PROPOSAL placeholder" {
    grep -q "{CODEX_PROPOSAL}" "$HEAVY_TEMPLATES_DIR/judge.md"
}

@test "judge.md has verdict marker" {
    grep -qE "DEBATE_VERDICT|VERDICT|winner|WINNER" "$HEAVY_TEMPLATES_DIR/judge.md"
}

@test "judge.md has scoring criteria" {
    grep -q "Scoring Criteria\|Weight\|weight" "$HEAVY_TEMPLATES_DIR/judge.md"
}

@test "judge.md has WINNER output format" {
    grep -q "WINNER:" "$HEAVY_TEMPLATES_DIR/judge.md"
}

# =============================================================================
# Template Consistency
# =============================================================================

@test "critique.md has balanced code blocks" {
    local count
    count=$(grep -c '```' "$HEAVY_TEMPLATES_DIR/critique.md" 2>/dev/null) || count=0
    [ $(( count % 2 )) -eq 0 ]
}

@test "defense.md has balanced code blocks" {
    local count
    count=$(grep -c '```' "$HEAVY_TEMPLATES_DIR/defense.md" 2>/dev/null) || count=0
    [ $(( count % 2 )) -eq 0 ]
}

@test "judge.md has balanced code blocks" {
    local count
    count=$(grep -c '```' "$HEAVY_TEMPLATES_DIR/judge.md" 2>/dev/null) || count=0
    [ $(( count % 2 )) -eq 0 ]
}

@test "korerorc.template has KORERO_MODE field" {
    grep -q "KORERO_MODE" "$TEMPLATES_DIR/korerorc.template"
}

@test "korerorc.template has MAX_CALLS_PER_HOUR field" {
    grep -q "MAX_CALLS_PER_HOUR" "$TEMPLATES_DIR/korerorc.template"
}

@test "korerorc.template has ALLOWED_TOOLS field" {
    grep -q "ALLOWED_TOOLS" "$TEMPLATES_DIR/korerorc.template"
}
