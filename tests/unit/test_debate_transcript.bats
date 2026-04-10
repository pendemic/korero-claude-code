#!/usr/bin/env bats

# Tests for lib/debate_transcript.sh — Debate transcript generation

load '../helpers/test_helper'

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
    export KORERO_DIR=".korero"
    export DEBATES_DIR="$KORERO_DIR/debates"
    source "$REPO_ROOT/lib/debate_transcript.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ===== init_debate_transcript =====

@test "init_debate_transcript creates transcript file" {
    result=$(init_debate_transcript 1)
    [ -f "$DEBATES_DIR/loop_1.md" ]
}

@test "init_debate_transcript includes loop number in header" {
    init_debate_transcript 5 > /dev/null
    grep -q "Debate Transcript: Loop 5" "$DEBATES_DIR/loop_5.md"
}

@test "init_debate_transcript includes date" {
    init_debate_transcript 1 > /dev/null
    grep -q "Date:" "$DEBATES_DIR/loop_1.md"
}

@test "init_debate_transcript sets status to In Progress" {
    init_debate_transcript 1 > /dev/null
    grep -q "In Progress" "$DEBATES_DIR/loop_1.md"
}

@test "init_debate_transcript creates debates directory" {
    [ ! -d "$DEBATES_DIR" ]
    init_debate_transcript 1 > /dev/null
    [ -d "$DEBATES_DIR" ]
}

# ===== append_transcript_section =====

@test "append_transcript_section adds section to transcript" {
    init_debate_transcript 1 > /dev/null
    append_transcript_section 1 "Phase 1: Idea Generation" "Agent A proposed X"
    grep -q "Phase 1: Idea Generation" "$DEBATES_DIR/loop_1.md"
    grep -q "Agent A proposed X" "$DEBATES_DIR/loop_1.md"
}

@test "append_transcript_section creates transcript if missing" {
    append_transcript_section 2 "Test Section" "Content"
    [ -f "$DEBATES_DIR/loop_2.md" ]
    grep -q "Test Section" "$DEBATES_DIR/loop_2.md"
}

@test "append_transcript_section appends multiple sections" {
    init_debate_transcript 1 > /dev/null
    append_transcript_section 1 "Phase 1" "Ideas here"
    append_transcript_section 1 "Phase 2" "Scores here"
    grep -q "Phase 1" "$DEBATES_DIR/loop_1.md"
    grep -q "Phase 2" "$DEBATES_DIR/loop_1.md"
}

# ===== finalize_debate_transcript =====

@test "finalize_debate_transcript marks as complete" {
    init_debate_transcript 1 > /dev/null
    finalize_debate_transcript 1
    grep -q "Complete" "$DEBATES_DIR/loop_1.md"
    ! grep -q "In Progress" "$DEBATES_DIR/loop_1.md"
}

@test "finalize_debate_transcript adds winner" {
    init_debate_transcript 1 > /dev/null
    finalize_debate_transcript 1 "Example Feature"
    grep -q "Winner.*Example Feature" "$DEBATES_DIR/loop_1.md"
}

@test "finalize_debate_transcript returns error for missing transcript" {
    run finalize_debate_transcript 99
    [ "$status" -eq 1 ]
}

# ===== get_latest_debate_loop =====

@test "get_latest_debate_loop returns empty when no debates" {
    run get_latest_debate_loop
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "get_latest_debate_loop returns highest loop number" {
    mkdir -p "$DEBATES_DIR"
    touch "$DEBATES_DIR/loop_1.md"
    touch "$DEBATES_DIR/loop_5.md"
    touch "$DEBATES_DIR/loop_3.md"
    result=$(get_latest_debate_loop)
    [ "$result" = "5" ]
}

# ===== show_debate_transcript =====

@test "show_debate_transcript displays transcript content" {
    init_debate_transcript 1 > /dev/null
    append_transcript_section 1 "Ideas" "Great idea here"
    run show_debate_transcript 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"Debate Transcript: Loop 1"* ]]
    [[ "$output" == *"Great idea here"* ]]
}

@test "show_debate_transcript latest shows most recent" {
    init_debate_transcript 1 > /dev/null
    init_debate_transcript 3 > /dev/null
    append_transcript_section 3 "Final" "Latest content"
    run show_debate_transcript latest
    [ "$status" -eq 0 ]
    [[ "$output" == *"Loop 3"* ]]
}

@test "show_debate_transcript shows error for missing loop" {
    run show_debate_transcript 99
    [ "$status" -eq 1 ]
    [[ "$output" == *"No debate transcript found"* ]]
}

# ===== list_debate_transcripts =====

@test "list_debate_transcripts shows available transcripts" {
    init_debate_transcript 1 > /dev/null
    init_debate_transcript 2 > /dev/null
    finalize_debate_transcript 1
    run list_debate_transcripts
    [[ "$output" == *"Loop"* ]]
    [[ "$output" == *"1"* ]]
    [[ "$output" == *"2"* ]]
}

@test "list_debate_transcripts shows empty message" {
    run list_debate_transcripts
    [[ "$output" == *"No debate"* ]]
}

# ===== get_debate_stats (Loop 35) =====

@test "get_debate_stats returns JSON with correct total" {
    mkdir -p "$DEBATES_DIR"
    # Transcript with winner
    cat > "$DEBATES_DIR/loop_1.md" << 'EOF'
## Final Judgment

**Winner:** claude
**Confidence:** 85
EOF
    cat > "$DEBATES_DIR/loop_2.md" << 'EOF'
## Final Judgment

**Winner:** codex
**Confidence:** 72
EOF
    run get_debate_stats
    [ "$status" -eq 0 ]
    [[ "$output" == *'"total":2'* ]]
}

@test "get_debate_stats counts claude wins" {
    mkdir -p "$DEBATES_DIR"
    cat > "$DEBATES_DIR/loop_1.md" << 'EOF'
## Final Judgment

**Winner:** claude
**Confidence:** 80
EOF
    run get_debate_stats
    [ "$status" -eq 0 ]
    [[ "$output" == *'"claude_wins":1'* ]]
}

@test "get_debate_stats counts codex wins" {
    mkdir -p "$DEBATES_DIR"
    cat > "$DEBATES_DIR/loop_1.md" << 'EOF'
## Final Judgment

**Winner:** codex
**Confidence:** 75
EOF
    run get_debate_stats
    [ "$status" -eq 0 ]
    [[ "$output" == *'"codex_wins":1'* ]]
}

@test "get_debate_stats counts timed_out for missing winner" {
    mkdir -p "$DEBATES_DIR"
    cat > "$DEBATES_DIR/loop_1.md" << 'EOF'
# Debate Transcript: Loop 1
**Status:** In Progress
EOF
    run get_debate_stats
    [ "$status" -eq 0 ]
    [[ "$output" == *'"timed_out":1'* ]]
}

@test "get_debate_stats returns 0-total JSON when no transcripts" {
    mkdir -p "$DEBATES_DIR"
    run get_debate_stats
    [ "$status" -eq 0 ]
    [[ "$output" == *'"total":0'* ]]
}

@test "get_debate_stats returns 1 when debates dir missing" {
    run get_debate_stats
    [ "$status" -eq 1 ]
}

@test "get_debate_stats calculates avg_confidence" {
    mkdir -p "$DEBATES_DIR"
    cat > "$DEBATES_DIR/loop_1.md" << 'EOF'
## Final Judgment

**Winner:** claude
**Confidence:** 80
EOF
    cat > "$DEBATES_DIR/loop_2.md" << 'EOF'
## Final Judgment

**Winner:** codex
**Confidence:** 60
EOF
    run get_debate_stats
    [ "$status" -eq 0 ]
    [[ "$output" == *'"avg_confidence":70'* ]]
}

# ===== display_debate_stats (Loop 35) =====

@test "display_debate_stats shows CROSS-AI DEBATE STATISTICS header" {
    mkdir -p "$DEBATES_DIR"
    cat > "$DEBATES_DIR/loop_1.md" << 'EOF'
## Final Judgment

**Winner:** claude
**Confidence:** 85
EOF
    run display_debate_stats
    [ "$status" -eq 0 ]
    [[ "$output" == *"CROSS-AI DEBATE STATISTICS"* ]]
}

@test "display_debate_stats shows WIN DISTRIBUTION" {
    mkdir -p "$DEBATES_DIR"
    cat > "$DEBATES_DIR/loop_1.md" << 'EOF'
## Final Judgment

**Winner:** claude
**Confidence:** 85
EOF
    run display_debate_stats
    [[ "$output" == *"WIN DISTRIBUTION"* ]]
}

@test "display_debate_stats shows Claude win count" {
    mkdir -p "$DEBATES_DIR"
    cat > "$DEBATES_DIR/loop_1.md" << 'EOF'
## Final Judgment

**Winner:** claude
**Confidence:** 85
EOF
    run display_debate_stats
    [[ "$output" == *"Claude"* ]]
}

@test "display_debate_stats shows CONFIDENCE ANALYSIS section" {
    mkdir -p "$DEBATES_DIR"
    cat > "$DEBATES_DIR/loop_1.md" << 'EOF'
## Final Judgment

**Winner:** claude
**Confidence:** 85
EOF
    run display_debate_stats
    [[ "$output" == *"CONFIDENCE ANALYSIS"* ]]
}

@test "display_debate_stats shows message when no debates dir" {
    run display_debate_stats
    [ "$status" -eq 1 ]
}

@test "display_debate_stats shows message when no transcripts" {
    mkdir -p "$DEBATES_DIR"
    run display_debate_stats
    [ "$status" -eq 0 ]
    [[ "$output" == *"No debate transcripts found"* ]]
}
