#!/usr/bin/env bats

# Tests for lib/progress_display.sh — Loop progress visualization

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
    mkdir -p .korero
    export KORERO_DIR=".korero"
    source "$REPO_ROOT/lib/progress_display.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "render_progress_bar shows 0% correctly" {
    result=$(render_progress_bar 0)
    [[ "$result" == *"0%"* ]]
    [[ "$result" == *"["* ]]
    [[ "$result" == *"]"* ]]
}

@test "render_progress_bar shows 50% correctly" {
    result=$(render_progress_bar 50)
    [[ "$result" == *"50%"* ]]
    [[ "$result" == *"#"* ]]
    [[ "$result" == *"-"* ]]
}

@test "render_progress_bar shows 100% correctly" {
    result=$(render_progress_bar 100)
    [[ "$result" == *"100%"* ]]
    [[ "$result" == *"#"* ]]
}

@test "render_progress_bar clamps negative to 0" {
    result=$(render_progress_bar -5)
    [[ "$result" == *"0%"* ]]
}

@test "render_progress_bar clamps over 100" {
    result=$(render_progress_bar 150)
    [[ "$result" == *"100%"* ]]
}

@test "render_phase_list marks current phase" {
    result=$(render_phase_list "DEBATE")
    [[ "$result" == *"* GENERATION (done)"* ]]
    [[ "$result" == *"* EVALUATION (done)"* ]]
    [[ "$result" == *"> DEBATE (in progress)"* ]]
    [[ "$result" == *"- IMPLEMENTATION"* ]]
}

@test "render_phase_list handles GENERATION phase" {
    result=$(render_phase_list "GENERATION")
    [[ "$result" == *"> GENERATION (in progress)"* ]]
    [[ "$result" == *"- EVALUATION"* ]]
}

@test "render_phase_list handles COMPLETE phase" {
    result=$(render_phase_list "COMPLETE")
    [[ "$result" == *"* GENERATION (done)"* ]]
    [[ "$result" == *"* IMPLEMENTATION (done)"* ]]
}

@test "get_phase_progress returns 25 for GENERATION" {
    result=$(get_phase_progress "GENERATION")
    [ "$result" = "25" ]
}

@test "get_phase_progress returns 75 for DEBATE" {
    result=$(get_phase_progress "DEBATE")
    [ "$result" = "75" ]
}

@test "get_phase_progress returns 100 for COMPLETE" {
    result=$(get_phase_progress "COMPLETE")
    [ "$result" = "100" ]
}

@test "get_phase_progress returns 0 for unknown phase" {
    result=$(get_phase_progress "UNKNOWN")
    [ "$result" = "0" ]
}

@test "extract_loop_phase defaults to GENERATION" {
    echo "some random output" > "$TEST_DIR/output.log"
    result=$(extract_loop_phase "$TEST_DIR/output.log")
    [ "$result" = "GENERATION" ]
}

@test "extract_loop_phase detects EVALUATION after GENERATION complete" {
    echo "PHASE_COMPLETED: GENERATION" > "$TEST_DIR/output.log"
    result=$(extract_loop_phase "$TEST_DIR/output.log")
    [ "$result" = "EVALUATION" ]
}

@test "extract_loop_phase detects DEBATE after EVALUATION complete" {
    echo "PHASE_COMPLETED: EVALUATION" > "$TEST_DIR/output.log"
    result=$(extract_loop_phase "$TEST_DIR/output.log")
    [ "$result" = "DEBATE" ]
}

@test "extract_loop_phase returns GENERATION for missing file" {
    result=$(extract_loop_phase "/nonexistent/file")
    [ "$result" = "GENERATION" ]
}

@test "render_progress_widget shows No active loop for missing status" {
    run render_progress_widget "/nonexistent/status.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"No active loop"* ]]
}

@test "render_progress_widget renders from status.json" {
    echo '{"loop": 5, "phase": "DEBATE", "phase_progress": 75}' > .korero/status.json
    result=$(render_progress_widget ".korero/status.json")
    [[ "$result" == *"Loop 5"* ]]
    [[ "$result" == *"75%"* ]]
}
