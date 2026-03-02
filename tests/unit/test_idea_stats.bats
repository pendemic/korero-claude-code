#!/usr/bin/env bats

load '../helpers/test_helper'

setup() {
    TEST_DIR=$(mktemp -d)
    export KORERO_DIR="$TEST_DIR/.korero"
    mkdir -p "$KORERO_DIR/ideas"

    KORERO_LOOP="$BATS_TEST_DIRNAME/../../korero_loop.sh"

    # Create individual idea files
    cat > "$KORERO_DIR/ideas/loop_1_idea.md" << 'EOF'
**Title:** Quick CLI Flag
**Type:** Usability Improvement
**Category:** CLI Ergonomics
**Proposed by:** CLI Designer

Effort: S (small)
EOF

    cat > "$KORERO_DIR/ideas/loop_2_idea.md" << 'EOF'
**Title:** Heavy Mode Feature
**Type:** New Feature
**Category:** Architecture
**Proposed by:** AI Architect

Effort: M (medium)
EOF

    cat > "$KORERO_DIR/ideas/loop_3_idea.md" << 'EOF'
**Title:** Better Test Coverage
**Type:** Usability Improvement
**Category:** Test Infrastructure
**Proposed by:** Test Architect

Effort: L (large)
EOF

    cat > "$KORERO_DIR/ideas/loop_4_idea.md" << 'EOF'
**Title:** Config Wizard
**Type:** New Feature
**Category:** CLI Ergonomics
**Proposed by:** CLI Designer

Effort: S (small)
EOF

    cat > "$KORERO_DIR/ideas/loop_5_idea.md" << 'EOF'
**Title:** Session Manager
**Type:** Usability Improvement
**Category:** Session
**Proposed by:** AI Architect

Effort: M (medium)
EOF
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ─── show_idea_stats: no data ────────────────────────────────────────────────

@test "show_idea_stats returns 1 when no ideas directory" {
    rm -rf "$KORERO_DIR/ideas"
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        show_idea_stats
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"No ideas directory found"* ]]
}

@test "show_idea_stats returns 1 when no idea files" {
    rm -f "$KORERO_DIR/ideas"/loop_*_idea.md
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        show_idea_stats
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"No idea files found"* ]]
}

# ─── show_idea_stats: header ─────────────────────────────────────────────────

@test "show_idea_stats shows header" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        show_idea_stats
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"KORERO IDEATION STATISTICS"* ]]
}

@test "show_idea_stats shows total count" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        show_idea_stats
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Total Ideas Generated: 5"* ]]
}

# ─── show_idea_stats: type balance ───────────────────────────────────────────

@test "show_idea_stats shows TYPE BALANCE section" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        show_idea_stats
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"TYPE BALANCE"* ]]
}

@test "show_idea_stats counts usability improvements correctly" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        show_idea_stats
    "
    [ "$status" -eq 0 ]
    # 3 usability out of 5 = 60%
    [[ "$output" == *"Usability Improvement: 3 (60%)"* ]]
}

@test "show_idea_stats counts new features correctly" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        show_idea_stats
    "
    [ "$status" -eq 0 ]
    # 2 new feature out of 5 = 40%
    [[ "$output" == *"New Feature:           2 (40%)"* ]]
}

@test "show_idea_stats shows target ratio" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        show_idea_stats
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Target:                60% / 40%"* ]]
}

# ─── show_idea_stats: agent productivity ─────────────────────────────────────

@test "show_idea_stats shows MOST PRODUCTIVE AGENTS section" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        show_idea_stats
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"MOST PRODUCTIVE AGENTS"* ]]
}

@test "show_idea_stats shows top agent with win count" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        show_idea_stats
    "
    [ "$status" -eq 0 ]
    # CLI Designer and AI Architect both have 2 wins
    [[ "$output" == *"2 wins"* ]]
}

@test "show_idea_stats shows CLI Designer agent" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        show_idea_stats
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLI Designer"* ]]
}

# ─── show_idea_stats: category coverage ──────────────────────────────────────

@test "show_idea_stats shows CATEGORY COVERAGE section" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        show_idea_stats
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"CATEGORY COVERAGE"* ]]
}

@test "show_idea_stats shows CLI Ergonomics category" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        show_idea_stats
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLI Ergonomics"* ]]
}

@test "show_idea_stats shows category win counts" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        show_idea_stats
    "
    [ "$status" -eq 0 ]
    # CLI Ergonomics has 2 wins
    [[ "$output" == *"CLI Ergonomics"*"2 wins"* ]]
}

# ─── show_idea_stats: recent trends ──────────────────────────────────────────

@test "show_idea_stats shows RECENT TRENDS section" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        show_idea_stats
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"RECENT TRENDS"* ]]
}

@test "show_idea_stats shows category diversity count" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        show_idea_stats
    "
    [ "$status" -eq 0 ]
    # 3 unique categories in last 5 loops (which is also last 10)
    [[ "$output" == *"Category diversity:"* ]]
}

@test "show_idea_stats shows recent type balance" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        show_idea_stats
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Type balance:"*"UI"*"NF"* ]]
}

# ─── show_idea_stats: footer ─────────────────────────────────────────────────

@test "show_idea_stats shows consolidate tip" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        show_idea_stats
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"korero --consolidate-ideas"* ]]
}

# ─── CLI integration ─────────────────────────────────────────────────────────

@test "--idea-stats flag is accepted in help text" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null" -- --help
    [[ "$output" == *"--idea-stats"* ]]
}

@test "--help idea-stats shows help topic" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        show_help_topic 'idea-stats'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"IDEA QUALITY RETROSPECTIVE"* ]]
}

@test "--help idea-stats lists type balance section" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        show_help_topic 'idea-stats'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Type Balance"* ]]
}

# ─── Edge cases ──────────────────────────────────────────────────────────────

@test "show_idea_stats with single idea file" {
    rm -f "$KORERO_DIR/ideas"/loop_{2,3,4,5}_idea.md
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        show_idea_stats
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Total Ideas Generated: 1"* ]]
}

@test "show_idea_stats handles ideas without Type field" {
    cat > "$KORERO_DIR/ideas/loop_6_idea.md" << 'EOF'
**Title:** No Type Idea
**Category:** Misc
**Proposed by:** Unknown Agent
EOF
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        show_idea_stats
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Total Ideas Generated: 6"* ]]
}

@test "show_idea_stats handles ideas without Category field" {
    cat > "$KORERO_DIR/ideas/loop_6_idea.md" << 'EOF'
**Title:** No Category Idea
**Type:** New Feature
**Proposed by:** Unknown Agent
EOF
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        show_idea_stats
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Total Ideas Generated: 6"* ]]
}

@test "show_idea_stats handles ideas without Proposed by field" {
    cat > "$KORERO_DIR/ideas/loop_6_idea.md" << 'EOF'
**Title:** No Agent Idea
**Type:** New Feature
**Category:** Misc
EOF
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        show_idea_stats
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Total Ideas Generated: 6"* ]]
}
