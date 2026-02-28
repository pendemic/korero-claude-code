#!/usr/bin/env bats

# Tests for lib/cross_ai_debate.sh — Cross-AI debate orchestrator

load '../helpers/test_helper'

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
    export KORERO_DIR=".korero"
    export DEBATES_DIR="$KORERO_DIR/debates"
    mkdir -p "$KORERO_DIR" "$DEBATES_DIR"
    source "$REPO_ROOT/lib/debate_transcript.sh"
    source "$REPO_ROOT/lib/codex_adapter.sh"
    source "$REPO_ROOT/lib/cross_ai_debate.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ===== build_critique_prompt =====

@test "build_critique_prompt includes both proposals" {
    result=$(build_critique_prompt "my proposal" "their proposal" "Claude" "Codex" "testproject")
    echo "$result" | grep -q "my proposal"
    echo "$result" | grep -q "their proposal"
}

@test "build_critique_prompt includes AI names" {
    result=$(build_critique_prompt "prop1" "prop2" "Claude" "Codex" "testproject")
    echo "$result" | grep -q "Claude"
    echo "$result" | grep -q "Codex"
}

@test "build_critique_prompt includes project name" {
    result=$(build_critique_prompt "prop1" "prop2" "Claude" "Codex" "myproject")
    echo "$result" | grep -q "myproject"
}

@test "build_critique_prompt produces non-empty output" {
    result=$(build_critique_prompt "p1" "p2" "Claude" "Codex" "proj")
    [ -n "$result" ]
}

# ===== build_defense_prompt =====

@test "build_defense_prompt includes original proposal" {
    result=$(build_defense_prompt "my proposal" "their critique" "Claude" "Codex" "proj")
    echo "$result" | grep -q "my proposal"
}

@test "build_defense_prompt includes critique text" {
    result=$(build_defense_prompt "prop" "this is a critique" "Claude" "Codex" "proj")
    echo "$result" | grep -q "this is a critique"
}

@test "build_defense_prompt includes defender AI name" {
    result=$(build_defense_prompt "prop" "crit" "Claude" "Codex" "proj")
    echo "$result" | grep -q "Claude"
}

# ===== build_judge_prompt =====

@test "build_judge_prompt includes all six artifacts" {
    result=$(build_judge_prompt "cp" "xp" "cc" "xc" "cd" "xd" "heavy-coding" "proj")
    echo "$result" | grep -q "cp"
    echo "$result" | grep -q "xp"
    echo "$result" | grep -q "cc"
    echo "$result" | grep -q "xc"
    echo "$result" | grep -q "cd"
    echo "$result" | grep -q "xd"
}

@test "build_judge_prompt includes mode" {
    result=$(build_judge_prompt "cp" "xp" "cc" "xc" "cd" "xd" "heavy-idea" "proj")
    echo "$result" | grep -q "heavy-idea"
}

@test "build_judge_prompt includes DEBATE_VERDICT format" {
    result=$(build_judge_prompt "cp" "xp" "cc" "xc" "cd" "xd" "heavy-coding" "proj")
    echo "$result" | grep -q "DEBATE_VERDICT"
}

@test "build_judge_prompt includes scoring criteria" {
    result=$(build_judge_prompt "cp" "xp" "cc" "xc" "cd" "xd" "heavy-coding" "proj")
    echo "$result" | grep -q "User Impact"
    echo "$result" | grep -q "Technical Feasibility"
}

@test "build_judge_prompt truncates long artifacts" {
    # Generate a 3000-char proposal
    local long_text=""
    for i in $(seq 1 300); do
        long_text+="0123456789"
    done
    result=$(build_judge_prompt "$long_text" "short" "cc" "xc" "cd" "xd" "heavy-coding" "proj")
    # The 3000-char text should be truncated to 2000
    [ ${#result} -lt 15000 ]
}

# ===== parse_debate_verdict =====

@test "parse_debate_verdict extracts winner from verdict block" {
    cat > "$TEST_DIR/judge_output.log" << 'EOF'
Some preamble text.

---DEBATE_VERDICT---
WINNER: codex
TITLE: Add streaming support
CONFIDENCE: 85
RATIONALE: Codex proposal was more practical and addressed edge cases better.
RUNNER_UP_INSIGHT: Claude's approach to error handling was innovative.
---END_DEBATE_VERDICT---
EOF
    parse_debate_verdict "$TEST_DIR/judge_output.log" "$KORERO_DIR/.debate_result"
    grep -q '"winner": "codex"' "$KORERO_DIR/.debate_result"
}

@test "parse_debate_verdict extracts title" {
    cat > "$TEST_DIR/judge.log" << 'EOF'
---DEBATE_VERDICT---
WINNER: claude
TITLE: Implement caching layer
CONFIDENCE: 90
RATIONALE: Better approach.
RUNNER_UP_INSIGHT: Good ideas.
---END_DEBATE_VERDICT---
EOF
    parse_debate_verdict "$TEST_DIR/judge.log" "$KORERO_DIR/.debate_result"
    grep -q '"title": "Implement caching layer"' "$KORERO_DIR/.debate_result"
}

@test "parse_debate_verdict extracts confidence score" {
    cat > "$TEST_DIR/judge.log" << 'EOF'
---DEBATE_VERDICT---
WINNER: claude
TITLE: Test feature
CONFIDENCE: 75
RATIONALE: Solid proposal.
RUNNER_UP_INSIGHT: N/A.
---END_DEBATE_VERDICT---
EOF
    parse_debate_verdict "$TEST_DIR/judge.log" "$KORERO_DIR/.debate_result"
    grep -q '"confidence": 75' "$KORERO_DIR/.debate_result"
}

@test "parse_debate_verdict defaults to claude on missing verdict block" {
    echo "No verdict here" > "$TEST_DIR/judge.log"
    parse_debate_verdict "$TEST_DIR/judge.log" "$KORERO_DIR/.debate_result" || true
    grep -q '"winner": "claude"' "$KORERO_DIR/.debate_result"
}

@test "parse_debate_verdict defaults to claude on empty file" {
    echo "notempty" > "$TEST_DIR/judge.log"
    parse_debate_verdict "$TEST_DIR/judge.log" "$KORERO_DIR/.debate_result" || true
    grep -q '"winner": "claude"' "$KORERO_DIR/.debate_result"
}

@test "parse_debate_verdict defaults to claude for missing file" {
    parse_debate_verdict "$TEST_DIR/nonexistent.log" "$KORERO_DIR/.debate_result" || true
    grep -q '"winner": "claude"' "$KORERO_DIR/.debate_result"
}

@test "parse_debate_verdict returns 1 for missing verdict block" {
    echo "No verdict" > "$TEST_DIR/judge.log"
    run parse_debate_verdict "$TEST_DIR/judge.log" "$KORERO_DIR/.debate_result"
    [ "$status" -eq 1 ]
}

@test "parse_debate_verdict returns 0 for valid verdict" {
    cat > "$TEST_DIR/judge.log" << 'EOF'
---DEBATE_VERDICT---
WINNER: claude
TITLE: Test
CONFIDENCE: 80
RATIONALE: Good.
RUNNER_UP_INSIGHT: N/A.
---END_DEBATE_VERDICT---
EOF
    run parse_debate_verdict "$TEST_DIR/judge.log" "$KORERO_DIR/.debate_result"
    [ "$status" -eq 0 ]
}

@test "parse_debate_verdict normalizes winner to lowercase" {
    cat > "$TEST_DIR/judge.log" << 'EOF'
---DEBATE_VERDICT---
WINNER: CLAUDE
TITLE: Test
CONFIDENCE: 80
RATIONALE: Good.
RUNNER_UP_INSIGHT: N/A.
---END_DEBATE_VERDICT---
EOF
    parse_debate_verdict "$TEST_DIR/judge.log" "$KORERO_DIR/.debate_result"
    grep -q '"winner": "claude"' "$KORERO_DIR/.debate_result"
}

# ===== get_debate_winner =====

@test "get_debate_winner returns winner from result file" {
    echo '{"winner":"codex","title":"test"}' > "$KORERO_DIR/.debate_result"
    result=$(get_debate_winner)
    [ "$result" = "codex" ]
}

@test "get_debate_winner defaults to claude when file missing" {
    run get_debate_winner
    [ "$output" = "claude" ]
}

@test "get_debate_winner defaults to claude for malformed JSON" {
    echo "not json" > "$KORERO_DIR/.debate_result"
    result=$(get_debate_winner)
    [ "$result" = "claude" ]
}

# ===== run_cross_ai_debate (single-AI fallback) =====

@test "run_cross_ai_debate handles empty claude proposal" {
    echo "" > "$TEST_DIR/claude_prop.log"
    echo "Codex proposal content" > "$TEST_DIR/codex_prop.log"
    init_debate_transcript 1 > /dev/null
    run_cross_ai_debate "$TEST_DIR/claude_prop.log" "$TEST_DIR/codex_prop.log" 1 "heavy-idea" "proj" 2
    grep -q '"winner": "codex"' "$KORERO_DIR/.debate_result"
}

@test "run_cross_ai_debate handles empty codex proposal" {
    echo "Claude proposal content" > "$TEST_DIR/claude_prop.log"
    echo "" > "$TEST_DIR/codex_prop.log"
    init_debate_transcript 1 > /dev/null
    run_cross_ai_debate "$TEST_DIR/claude_prop.log" "$TEST_DIR/codex_prop.log" 1 "heavy-idea" "proj" 2
    grep -q '"winner": "claude"' "$KORERO_DIR/.debate_result"
}

@test "run_cross_ai_debate returns 1 when both proposals empty" {
    echo "" > "$TEST_DIR/claude_prop.log"
    echo "" > "$TEST_DIR/codex_prop.log"
    init_debate_transcript 1 > /dev/null
    run run_cross_ai_debate "$TEST_DIR/claude_prop.log" "$TEST_DIR/codex_prop.log" 1 "heavy-idea" "proj" 2
    [ "$status" -eq 1 ]
}

@test "run_cross_ai_debate records fallback in transcript" {
    echo "Claude proposal" > "$TEST_DIR/claude_prop.log"
    echo "" > "$TEST_DIR/codex_prop.log"
    init_debate_transcript 1 > /dev/null
    run_cross_ai_debate "$TEST_DIR/claude_prop.log" "$TEST_DIR/codex_prop.log" 1 "heavy-idea" "proj" 2
    grep -q "default" "$DEBATES_DIR/loop_1.md"
}
