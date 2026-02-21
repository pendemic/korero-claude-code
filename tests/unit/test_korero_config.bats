#!/usr/bin/env bats

# Tests for korero_config.sh — Configuration display

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
    mkdir -p .korero
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "korero_config show displays KORERO CONFIGURATION header" {
    run bash "$REPO_ROOT/korero_config.sh" show
    [ "$status" -eq 0 ]
    [[ "$output" == *"KORERO CONFIGURATION"* ]]
}

@test "korero_config show displays known options" {
    run bash "$REPO_ROOT/korero_config.sh" show
    [ "$status" -eq 0 ]
    [[ "$output" == *"KORERO_MODE"* ]]
    [[ "$output" == *"MAX_CALLS_PER_HOUR"* ]]
    [[ "$output" == *"CB_NO_PROGRESS_THRESHOLD"* ]]
}

@test "korero_config show defaults to show when no arg given" {
    run bash "$REPO_ROOT/korero_config.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"KORERO CONFIGURATION"* ]]
}

@test "korero_config show reads values from .korerorc" {
    cat > .korerorc << 'EOF'
KORERO_MODE="idea"
MAX_CALLS_PER_HOUR=200
EOF
    run bash "$REPO_ROOT/korero_config.sh" show
    [ "$status" -eq 0 ]
    [[ "$output" == *"idea"* ]]
    [[ "$output" == *"200"* ]]
    [[ "$output" == *".korerorc"* ]]
}

@test "korero_config show indicates default source" {
    run bash "$REPO_ROOT/korero_config.sh" show
    [ "$status" -eq 0 ]
    [[ "$output" == *"default"* ]]
}

@test "korero_config show works without .korerorc" {
    rm -f .korerorc
    run bash "$REPO_ROOT/korero_config.sh" show
    [ "$status" -eq 0 ]
    [[ "$output" == *"coding"* ]]  # Default mode
}

@test "korero_config help shows option descriptions" {
    run bash "$REPO_ROOT/korero_config.sh" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"KORERO_MODE"* ]]
    [[ "$output" == *"Default:"* ]]
}

@test "korero_config shows legend" {
    run bash "$REPO_ROOT/korero_config.sh" show
    [ "$status" -eq 0 ]
    [[ "$output" == *"Legend"* ]]
    [[ "$output" == *"default"* ]]
    [[ "$output" == *".korerorc"* ]]
    [[ "$output" == *"env"* ]]
}

@test "korero_config invalid subcommand shows usage" {
    run bash "$REPO_ROOT/korero_config.sh" invalid
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}
