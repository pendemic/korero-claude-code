#!/usr/bin/env bats

load '../helpers/test_helper'

setup() {
    KORERO_LOOP="$BATS_TEST_DIRNAME/../../korero_loop.sh"
}

# ─── levenshtein_distance ──────────────────────────────────────────────────

@test "levenshtein_distance returns 0 for identical strings" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; levenshtein_distance 'status' 'status'"
    assert_output "0"
}

@test "levenshtein_distance returns 1 for single substitution" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; levenshtein_distance 'help' 'kelp'"
    assert_output "1"
}

@test "levenshtein_distance returns correct distance for transposition" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; levenshtein_distance '--stauts' '--status'"
    # s↔a transposition = 2 edits (delete + insert)
    [ "$status" -eq 0 ]
    local d="$output"
    [[ "$d" -le 3 ]]
}

@test "levenshtein_distance handles empty first string" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; levenshtein_distance '' 'test'"
    assert_output "4"
}

@test "levenshtein_distance handles empty second string" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; levenshtein_distance 'test' ''"
    assert_output "4"
}

@test "levenshtein_distance handles both empty strings" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; levenshtein_distance '' ''"
    assert_output "0"
}

@test "levenshtein_distance returns length for completely different strings" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; levenshtein_distance 'abc' 'xyz'"
    assert_output "3"
}

@test "levenshtein_distance handles single character strings" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; levenshtein_distance 'a' 'b'"
    assert_output "1"
}

@test "levenshtein_distance returns 0 for same single character" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; levenshtein_distance 'a' 'a'"
    assert_output "0"
}

# ─── suggest_similar_option ────────────────────────────────────────────────

@test "suggest_similar_option returns --status for --stauts" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_similar_option '--stauts'"
    assert_output "--status"
}

@test "suggest_similar_option returns --monitor for --montor" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_similar_option '--montor'"
    assert_output "--monitor"
}

@test "suggest_similar_option returns --help for --hlep" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_similar_option '--hlep'"
    assert_output "--help"
}

@test "suggest_similar_option returns --validate for --valiate" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_similar_option '--valiate'"
    assert_output "--validate"
}

@test "suggest_similar_option returns --version for --verson" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_similar_option '--verson'"
    assert_output "--version"
}

@test "suggest_similar_option returns empty for completely unrelated string" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_similar_option '--xyzabc123'"
    assert_output ""
}

@test "suggest_similar_option returns empty for random short string" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_similar_option '--zzz'"
    assert_output ""
}

@test "suggest_similar_option returns --consolidate-ideas for close typo" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_similar_option '--consolidate-idea'"
    assert_output "--consolidate-ideas"
}

@test "suggest_similar_option returns --diagnose for --diagose" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_similar_option '--diagose'"
    assert_output "--diagnose"
}

@test "suggest_similar_option returns --dry-run for --dry-ru" {
    run bash -c "source '$KORERO_LOOP' 2>/dev/null; suggest_similar_option '--dry-ru'"
    assert_output "--dry-run"
}

# ─── CLI integration: unknown option with suggestion ──────────────────────

@test "unknown option shows 'Unknown option' message" {
    TEST_DIR=$(mktemp -d)
    run bash -c "
        export KORERO_DIR='$TEST_DIR/.korero'
        bash '$KORERO_LOOP' --stauts 2>&1 || true
    "
    rm -rf "$TEST_DIR"
    [[ "$output" == *"Unknown option"* ]]
}

@test "unknown option shows 'Did you mean' suggestion" {
    TEST_DIR=$(mktemp -d)
    run bash -c "
        export KORERO_DIR='$TEST_DIR/.korero'
        bash '$KORERO_LOOP' --stauts 2>&1 || true
    "
    rm -rf "$TEST_DIR"
    [[ "$output" == *"Did you mean"* ]]
}

@test "unknown option suggests --status for --stauts" {
    TEST_DIR=$(mktemp -d)
    run bash -c "
        export KORERO_DIR='$TEST_DIR/.korero'
        bash '$KORERO_LOOP' --stauts 2>&1 || true
    "
    rm -rf "$TEST_DIR"
    [[ "$output" == *"--status"* ]]
}

@test "unknown option with no close match shows no suggestion" {
    TEST_DIR=$(mktemp -d)
    run bash -c "
        export KORERO_DIR='$TEST_DIR/.korero'
        bash '$KORERO_LOOP' --xyzabc123 2>&1 || true
    "
    rm -rf "$TEST_DIR"
    [[ "$output" != *"Did you mean"* ]]
}

@test "unknown option exits with non-zero status" {
    TEST_DIR=$(mktemp -d)
    run bash -c "
        export KORERO_DIR='$TEST_DIR/.korero'
        bash '$KORERO_LOOP' --stauts 2>&1
    "
    rm -rf "$TEST_DIR"
    [ "$status" -ne 0 ]
}

@test "unknown option shows help info line" {
    TEST_DIR=$(mktemp -d)
    run bash -c "
        export KORERO_DIR='$TEST_DIR/.korero'
        bash '$KORERO_LOOP' --stauts 2>&1 || true
    "
    rm -rf "$TEST_DIR"
    [[ "$output" == *"korero --help"* ]]
}
