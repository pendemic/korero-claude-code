#!/usr/bin/env bats

load '../helpers/test_helper'

setup() {
    TEST_DIR=$(mktemp -d)
    export KORERO_DIR="$TEST_DIR/.korero"
    mkdir -p "$KORERO_DIR/ideas"

    KORERO_LOOP="$BATS_TEST_DIRNAME/../../korero_loop.sh"

    # Create a mock IDEAS.md
    cat > "$KORERO_DIR/ideas/IDEAS.md" << 'EOF'
═══════════════════════════════════════════════════════════
LOOP 1 WINNING IDEA
═══════════════════════════════════════════════════════════

**Title:** Quick CLI Flag
**Type:** Usability Improvement
**Category:** CLI Ergonomics

Effort: S (small)

### Files Most Likely Affected
- korero_loop.sh
EOF

    # Create individual idea files for per-loop parsing
    cat > "$KORERO_DIR/ideas/loop_1_idea.md" << 'EOF'
**Title:** Quick CLI Flag
**Type:** Usability Improvement
**Category:** CLI Ergonomics
**Proposed by:** CLI Designer

Effort: S (small)

### Files Most Likely Affected
- korero_loop.sh
EOF

    cat > "$KORERO_DIR/ideas/loop_2_idea.md" << 'EOF'
**Title:** Heavy Mode Feature
**Type:** New Feature
**Category:** CLI Ergonomics
**Proposed by:** AI Architect

Effort: M (medium)

### Files Most Likely Affected
- lib/cross_ai_debate.sh
EOF

    cat > "$KORERO_DIR/ideas/loop_3_idea.md" << 'EOF'
**Title:** Large Refactor Task
**Type:** Usability Improvement
**Category:** Test Infrastructure
**Proposed by:** Test Architect

Effort: L (large)

### Files Most Likely Affected
- tests/unit/
EOF
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ─── consolidate_ideas ──────────────────────────────────────────────────────

@test "consolidate_ideas returns 1 when no IDEAS.md found" {
    rm -f "$KORERO_DIR/ideas/IDEAS.md"
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        consolidate_ideas
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"No IDEAS.md found"* ]]
}

@test "consolidate_ideas shows report header" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        consolidate_ideas
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"IDEA CONSOLIDATION REPORT"* ]]
}

@test "consolidate_ideas shows Generated date" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        consolidate_ideas
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Generated:"* ]]
}

@test "consolidate_ideas counts total ideas correctly" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        consolidate_ideas
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Total Ideas: 3"* ]]
}

@test "consolidate_ideas shows Quick Wins section" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        consolidate_ideas
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Quick Wins"* ]]
}

@test "consolidate_ideas lists S-effort idea in Quick Wins" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        consolidate_ideas
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Quick CLI Flag"* ]]
}

@test "consolidate_ideas shows Medium Effort section" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        consolidate_ideas
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Medium Effort"* ]]
}

@test "consolidate_ideas lists M-effort idea in Medium Effort" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        consolidate_ideas
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Heavy Mode Feature"* ]]
}

@test "consolidate_ideas shows Theme Clusters section" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        consolidate_ideas
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Theme Clusters"* ]]
}

@test "consolidate_ideas shows category cluster header" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        consolidate_ideas
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLI Ergonomics Cluster"* ]]
}

@test "consolidate_ideas shows Implementation Priority Matrix" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        consolidate_ideas
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Priority Matrix"* ]]
}

@test "consolidate_ideas shows P1 for S-effort idea in matrix" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        consolidate_ideas
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"P1"* ]]
}

@test "consolidate_ideas shows P2 for M-effort idea in matrix" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        consolidate_ideas
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"P2"* ]]
}

@test "consolidate_ideas shows Category Distribution section" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        consolidate_ideas
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Category Distribution"* ]]
}

@test "consolidate_ideas shows bar chart for categories" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        consolidate_ideas
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"█"* ]]
}

@test "consolidate_ideas shows tip about search-ideas" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        consolidate_ideas
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"--search-ideas"* ]]
}

@test "consolidate_ideas writes to output file with --output flag" {
    local out_file="${TEST_DIR}/report.md"
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        consolidate_ideas --output '${out_file}'
    "
    [ "$status" -eq 0 ]
    [ -f "$out_file" ]
    grep -q "IDEA CONSOLIDATION REPORT" "$out_file"
}

@test "consolidate_ideas shows written message with --output flag" {
    local out_file="${TEST_DIR}/report.md"
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        consolidate_ideas --output '${out_file}'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"report.md"* ]]
}

@test "consolidate_ideas handles no idea files gracefully" {
    rm -f "$KORERO_DIR/ideas/loop_"*"_idea.md"
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        consolidate_ideas
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Total Ideas: 0"* ]]
}

@test "consolidate_ideas shows none for quick wins when no S ideas" {
    rm -f "$KORERO_DIR/ideas/loop_1_idea.md"
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        consolidate_ideas
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"(none found)"* ]]
}

# ─── _consolidate_by_effort ────────────────────────────────────────────────

@test "_consolidate_by_effort lists S-effort ideas" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        _consolidate_by_effort '${TEST_DIR}/.korero/ideas' 'S'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Quick CLI Flag"* ]]
}

@test "_consolidate_by_effort returns none when no match" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        _consolidate_by_effort '${TEST_DIR}/.korero/ideas' 'XL'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"(none found)"* ]]
}

# ─── _consolidate_category_clusters ───────────────────────────────────────

@test "_consolidate_category_clusters shows CLI Ergonomics Cluster" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        _consolidate_category_clusters '${TEST_DIR}/.korero/ideas'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLI Ergonomics Cluster"* ]]
}

@test "_consolidate_category_clusters shows Test Infrastructure Cluster" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        _consolidate_category_clusters '${TEST_DIR}/.korero/ideas'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Test Infrastructure Cluster"* ]]
}

@test "_consolidate_category_clusters lists idea title in cluster" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        _consolidate_category_clusters '${TEST_DIR}/.korero/ideas'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Quick CLI Flag"* ]]
}

# ─── _consolidate_priority_matrix ─────────────────────────────────────────

@test "_consolidate_priority_matrix shows table header" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        _consolidate_priority_matrix '${TEST_DIR}/.korero/ideas'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Priority"* ]]
    [[ "$output" == *"Effort"* ]]
}

@test "_consolidate_priority_matrix shows P1 row for S effort" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        _consolidate_priority_matrix '${TEST_DIR}/.korero/ideas'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"P1"* ]]
}

@test "_consolidate_priority_matrix shows P3 row for L effort" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        _consolidate_priority_matrix '${TEST_DIR}/.korero/ideas'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"P3"* ]]
}

# ─── _consolidate_category_distribution ───────────────────────────────────

@test "_consolidate_category_distribution shows bar chart" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        _consolidate_category_distribution '${TEST_DIR}/.korero/ideas'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"█"* ]]
}

@test "_consolidate_category_distribution shows category names" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        _consolidate_category_distribution '${TEST_DIR}/.korero/ideas'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLI Ergonomics"* ]]
}

@test "_consolidate_category_distribution shows counts" {
    run bash -c "
        export KORERO_DIR='${TEST_DIR}/.korero'
        source '$KORERO_LOOP' 2>/dev/null
        _consolidate_category_distribution '${TEST_DIR}/.korero/ideas'
    "
    [ "$status" -eq 0 ]
    # CLI Ergonomics has 2 ideas (loops 1 and 2)
    [[ "$output" == *"(2)"* ]]
}
