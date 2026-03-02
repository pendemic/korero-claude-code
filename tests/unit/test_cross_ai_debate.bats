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

# ===== get_phase_icon =====

@test "get_phase_icon returns correct icon for proposal" {
    result=$(get_phase_icon "proposal")
    [ "$result" = "[>]" ]
}

@test "get_phase_icon returns correct icon for critique" {
    result=$(get_phase_icon "critique")
    [ "$result" = "[*]" ]
}

@test "get_phase_icon returns correct icon for defense" {
    result=$(get_phase_icon "defense")
    [ "$result" = "[#]" ]
}

@test "get_phase_icon returns correct icon for judgment" {
    result=$(get_phase_icon "judgment")
    [ "$result" = "[=]" ]
}

@test "get_phase_icon returns correct icon for complete" {
    result=$(get_phase_icon "complete")
    [ "$result" = "[+]" ]
}

@test "get_phase_icon returns correct icon for error" {
    result=$(get_phase_icon "error")
    [ "$result" = "[!]" ]
}

@test "get_phase_icon returns default icon for unknown phase" {
    result=$(get_phase_icon "unknown")
    [ "$result" = "[-]" ]
}

# ===== show_debate_progress =====

@test "show_debate_progress outputs to stderr" {
    run show_debate_progress "critique" "start" "testing"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Critique"* ]]
    [[ "$output" == *"IN PROGRESS"* ]]
}

@test "show_debate_progress shows DONE for end status" {
    run show_debate_progress "defense" "end" "complete"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DONE"* ]]
}

@test "show_debate_progress shows FAILED for error status" {
    run show_debate_progress "judgment" "error" "exit code 1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"FAILED"* ]]
}

@test "show_debate_progress includes elapsed time" {
    run show_debate_progress "critique" "end" "done" "42"
    [ "$status" -eq 0 ]
    [[ "$output" == *"42s"* ]]
}

@test "show_debate_progress includes detail message" {
    run show_debate_progress "defense" "start" "Claude + Codex in parallel"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Claude + Codex in parallel"* ]]
}

# ===== show_debate_summary =====

@test "show_debate_summary displays winner" {
    run show_debate_summary "claude" "Test Idea" "85" "120"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEBATE COMPLETE"* ]]
    [[ "$output" == *"Claude"* ]]
}

@test "show_debate_summary displays codex winner" {
    run show_debate_summary "codex" "Codex Idea" "90" "60"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Codex"* ]]
}

@test "show_debate_summary shows confidence and duration" {
    run show_debate_summary "claude" "Test" "75" "45"
    [ "$status" -eq 0 ]
    [[ "$output" == *"75%"* ]]
    [[ "$output" == *"45s"* ]]
}

@test "show_debate_summary shows idea title" {
    run show_debate_summary "claude" "Add streaming support" "80" "30"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Add streaming support"* ]]
}

# ===== run_cross_ai_debate fallback mode =====

@test "run_cross_ai_debate uses claude fallback when codex not installed" {
    echo "Claude proposal text" > "$TEST_DIR/claude_prop.log"
    echo "Codex proposal text" > "$TEST_DIR/codex_prop.log"
    init_debate_transcript 1 > /dev/null
    # Override PATH so codex is not found, set fallback mode
    run bash -c '
        export KORERO_DIR="'$KORERO_DIR'"
        export DEBATES_DIR="'$DEBATES_DIR'"
        export CODEX_FALLBACK="claude-only"
        PATH=/usr/bin:/bin
        source "'$REPO_ROOT'/lib/debate_transcript.sh"
        source "'$REPO_ROOT'/lib/codex_adapter.sh"
        source "'$REPO_ROOT'/lib/cross_ai_debate.sh"
        run_cross_ai_debate "'$TEST_DIR'/claude_prop.log" "'$TEST_DIR'/codex_prop.log" 1 "heavy-idea" "proj" 2
    '
    [ "$status" -eq 0 ]
    grep -q '"winner": "claude"' "$KORERO_DIR/.debate_result"
    grep -q '"fallback": true' "$KORERO_DIR/.debate_result"
}

@test "run_cross_ai_debate fallback records reason in result" {
    echo "Claude proposal text" > "$TEST_DIR/claude_prop.log"
    echo "" > "$TEST_DIR/codex_prop.log"
    init_debate_transcript 1 > /dev/null
    run bash -c '
        export KORERO_DIR="'$KORERO_DIR'"
        export DEBATES_DIR="'$DEBATES_DIR'"
        export CODEX_FALLBACK="silent"
        PATH=/usr/bin:/bin
        source "'$REPO_ROOT'/lib/debate_transcript.sh"
        source "'$REPO_ROOT'/lib/codex_adapter.sh"
        source "'$REPO_ROOT'/lib/cross_ai_debate.sh"
        run_cross_ai_debate "'$TEST_DIR'/claude_prop.log" "'$TEST_DIR'/codex_prop.log" 1 "heavy-idea" "proj" 2
    '
    [ "$status" -eq 0 ]
    grep -q '"fallback_reason": "not_installed"' "$KORERO_DIR/.debate_result"
}

@test "run_cross_ai_debate fallback records in transcript" {
    echo "Claude proposal text" > "$TEST_DIR/claude_prop.log"
    echo "" > "$TEST_DIR/codex_prop.log"
    init_debate_transcript 1 > /dev/null
    run bash -c '
        export KORERO_DIR="'$KORERO_DIR'"
        export DEBATES_DIR="'$DEBATES_DIR'"
        export CODEX_FALLBACK="claude-only"
        PATH=/usr/bin:/bin
        source "'$REPO_ROOT'/lib/debate_transcript.sh"
        source "'$REPO_ROOT'/lib/codex_adapter.sh"
        source "'$REPO_ROOT'/lib/cross_ai_debate.sh"
        run_cross_ai_debate "'$TEST_DIR'/claude_prop.log" "'$TEST_DIR'/codex_prop.log" 1 "heavy-idea" "proj" 2
    '
    [ "$status" -eq 0 ]
    grep -q "fallback" "$DEBATES_DIR/loop_1.md"
}

# ===== show_debate_round_progress =====

@test "show_debate_round_progress displays correct bar for round 1 of 3" {
    run show_debate_round_progress 1 "Critique" 3
    [[ "$output" == *"Round 1/3"* ]]
    [[ "$output" == *"Critique"* ]]
    [[ "$output" == *"███"* ]]
}

@test "show_debate_round_progress displays correct bar for round 2 of 3" {
    run show_debate_round_progress 2 "Defense" 3
    [[ "$output" == *"Round 2/3"* ]]
    [[ "$output" == *"Defense"* ]]
    [[ "$output" == *"██████"* ]]
}

@test "show_debate_round_progress displays correct bar for round 3 of 3" {
    run show_debate_round_progress 3 "Judgment" 3
    [[ "$output" == *"Round 3/3"* ]]
    [[ "$output" == *"Judgment"* ]]
    [[ "$output" == *"██████████"* ]]
}

@test "show_debate_round_progress defaults to 3 total rounds" {
    run show_debate_round_progress 2 "Defense"
    [[ "$output" == *"Round 2/3"* ]]
}

@test "complete_debate_round_progress shows full bar with message" {
    run complete_debate_round_progress
    [[ "$output" == *"██████████"* ]]
    [[ "$output" == *"Debate complete!"* ]]
}

# ===== calculate_length_ratio =====

@test "calculate_length_ratio returns balanced ratio for similar-length files" {
    echo "This is a proposal with several words to test the length calculation" > "$TEST_DIR/claude.txt"
    echo "This codex proposal also has about the same number of words here" > "$TEST_DIR/codex.txt"
    run calculate_length_ratio "$TEST_DIR/claude.txt" "$TEST_DIR/codex.txt"
    [ "$status" -eq 0 ]
    # Should be close to 1.0 (non-empty output)
    [[ -n "$output" ]]
}

@test "calculate_length_ratio returns 0 for empty codex file" {
    echo "Claude has content" > "$TEST_DIR/claude.txt"
    touch "$TEST_DIR/empty.txt"
    run calculate_length_ratio "$TEST_DIR/claude.txt" "$TEST_DIR/empty.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "calculate_length_ratio returns 0 for missing files" {
    run calculate_length_ratio "/nonexistent/a.txt" "/nonexistent/b.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

# ===== calculate_coverage =====

@test "calculate_coverage returns 0 for missing files" {
    run calculate_coverage "/nonexistent/proposal.txt" "/nonexistent/critique.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "calculate_coverage returns positive for matching terms" {
    echo "The implementation should use caching and Redis for performance optimization" > "$TEST_DIR/proposal.txt"
    echo "The critique addresses caching Redis implementation performance optimization concerns" > "$TEST_DIR/critique.txt"
    run calculate_coverage "$TEST_DIR/proposal.txt" "$TEST_DIR/critique.txt"
    [ "$status" -eq 0 ]
    [[ "$output" -gt 0 ]]
}

@test "calculate_coverage returns 0 for completely different content" {
    echo "aaaa bbbb cccc dddd eeee ffff" > "$TEST_DIR/proposal.txt"
    echo "zzzz yyyy xxxx wwww vvvv uuuu" > "$TEST_DIR/critique.txt"
    run calculate_coverage "$TEST_DIR/proposal.txt" "$TEST_DIR/critique.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

# ===== calculate_verdict_confidence =====

@test "calculate_verdict_confidence returns 90 for clearly superior language" {
    echo "Claude's proposal is clearly superior and is the obvious choice." > "$TEST_DIR/judgment.txt"
    run calculate_verdict_confidence "$TEST_DIR/judgment.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "90" ]
}

@test "calculate_verdict_confidence returns 75 for preferred language" {
    echo "Claude's proposal is better overall and more convincingly argued." > "$TEST_DIR/judgment.txt"
    run calculate_verdict_confidence "$TEST_DIR/judgment.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "75" ]
}

@test "calculate_verdict_confidence returns 40 for marginal language" {
    echo "Claude has a slight edge, though it was a close call." > "$TEST_DIR/judgment.txt"
    run calculate_verdict_confidence "$TEST_DIR/judgment.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "40" ]
}

@test "calculate_verdict_confidence returns 50 as default" {
    echo "Both proposals present interesting approaches." > "$TEST_DIR/judgment.txt"
    run calculate_verdict_confidence "$TEST_DIR/judgment.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "50" ]
}

@test "calculate_verdict_confidence returns 50 for missing file" {
    run calculate_verdict_confidence "/nonexistent/judgment.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "50" ]
}

# ===== calculate_debate_quality =====

@test "calculate_debate_quality returns score between 0 and 100" {
    echo "Claude proposes implementing feature X with approach Y" > "$TEST_DIR/claude.txt"
    echo "Codex proposes implementing feature X with approach Z" > "$TEST_DIR/codex.txt"
    echo "The critique addresses feature approach implementation" > "$TEST_DIR/claude_crit.txt"
    echo "The critique addresses feature approach implementation" > "$TEST_DIR/codex_crit.txt"
    echo "Claude's proposal is the preferred choice overall" > "$TEST_DIR/judgment.txt"
    run calculate_debate_quality \
        "$TEST_DIR/claude.txt" "$TEST_DIR/codex.txt" \
        "$TEST_DIR/claude_crit.txt" "$TEST_DIR/codex_crit.txt" \
        "$TEST_DIR/judgment.txt"
    [ "$status" -eq 0 ]
    [[ "$output" -ge 0 && "$output" -le 100 ]]
}

# ===== record_debate_quality =====

@test "record_debate_quality creates JSON file" {
    if ! command -v jq &>/dev/null; then skip "jq not available"; fi
    run record_debate_quality 1 75 "0.95" 80 70
    [ "$status" -eq 0 ]
    [ -f "$KORERO_DIR/.debate_quality.json" ]
}

@test "record_debate_quality stores correct quality score" {
    if ! command -v jq &>/dev/null; then skip "jq not available"; fi
    record_debate_quality 1 75 "0.95" 80 70
    local score
    score=$(jq '.debates[0].quality_score' "$KORERO_DIR/.debate_quality.json")
    [ "$score" -eq 75 ]
}

@test "record_debate_quality accumulates multiple debates" {
    if ! command -v jq &>/dev/null; then skip "jq not available"; fi
    record_debate_quality 1 70 "1.00" 60 80
    record_debate_quality 2 80 "0.90" 75 90
    local count
    count=$(jq '.debates | length' "$KORERO_DIR/.debate_quality.json")
    [ "$count" -eq 2 ]
}

@test "record_debate_quality includes timestamp" {
    if ! command -v jq &>/dev/null; then skip "jq not available"; fi
    record_debate_quality 1 75 "0.95" 80 70
    local ts
    ts=$(jq -r '.debates[0].timestamp' "$KORERO_DIR/.debate_quality.json")
    [[ "$ts" == *"T"* ]]
}

@test "run_cross_ai_debate silent fallback suppresses warning" {
    echo "Claude proposal text" > "$TEST_DIR/claude_prop.log"
    echo "" > "$TEST_DIR/codex_prop.log"
    init_debate_transcript 1 > /dev/null
    run bash -c '
        export KORERO_DIR="'$KORERO_DIR'"
        export DEBATES_DIR="'$DEBATES_DIR'"
        export CODEX_FALLBACK="silent"
        PATH=/usr/bin:/bin
        source "'$REPO_ROOT'/lib/debate_transcript.sh"
        source "'$REPO_ROOT'/lib/codex_adapter.sh"
        source "'$REPO_ROOT'/lib/cross_ai_debate.sh"
        run_cross_ai_debate "'$TEST_DIR'/claude_prop.log" "'$TEST_DIR'/codex_prop.log" 1 "heavy-idea" "proj" 2
    '
    [ "$status" -eq 0 ]
    # Silent mode should not show the CODEX FALLBACK banner
    [[ "$output" != *"CODEX FALLBACK"* ]]
}
