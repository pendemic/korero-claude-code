#!/usr/bin/env bats

# Tests for lib/security_scanner.sh — Sensitive Config Pattern Scanner

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
    source "$REPO_ROOT/lib/security_scanner.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "scan_sensitive_patterns returns 0 for clean config" {
    cat > .korerorc << 'EOF'
KORERO_MODE="coding"
PROJECT_SUBJECT="test project"
MAX_LOOPS=10
ALLOWED_TOOLS="@standard"
EOF
    run scan_sensitive_patterns .korerorc
    [ "$status" -eq 0 ]
}

@test "scan_sensitive_patterns detects OpenAI API key" {
    cat > .korerorc << 'EOF'
OPENAI_KEY="sk-abcdefghijklmnopqrstuvwxyz1234567890"
EOF
    run scan_sensitive_patterns .korerorc
    [ "$status" -eq 1 ]
    [[ "$output" == *"OpenAI API Key"* ]]
}

@test "scan_sensitive_patterns detects GitHub token" {
    cat > .korerorc << 'EOF'
GH_TOKEN="ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij1234"
EOF
    run scan_sensitive_patterns .korerorc
    [ "$status" -eq 1 ]
    [[ "$output" == *"GitHub Token"* ]]
}

@test "scan_sensitive_patterns detects AWS access key" {
    cat > .korerorc << 'EOF'
AWS_KEY="AKIAIOSFODNN7EXAMPLE"
EOF
    run scan_sensitive_patterns .korerorc
    [ "$status" -eq 1 ]
    [[ "$output" == *"AWS Access Key"* ]]
}

@test "scan_sensitive_patterns detects Bearer token" {
    cat > .korerorc << 'EOF'
AUTH="Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.long.token"
EOF
    run scan_sensitive_patterns .korerorc
    [ "$status" -eq 1 ]
    [[ "$output" == *"Bearer Token"* ]]
}

@test "scan_sensitive_patterns detects long encoded strings" {
    cat > .korerorc << 'EOF'
SECRET="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnop1234567890"
EOF
    run scan_sensitive_patterns .korerorc
    [ "$status" -eq 1 ]
    [[ "$output" == *"secret/token"* ]]
}

@test "scan_sensitive_patterns skips trusted lines" {
    cat > .korerorc << 'EOF'
OPENAI_KEY="sk-abcdefghijklmnopqrstuvwxyz1234567890" # korero: trusted
EOF
    run scan_sensitive_patterns .korerorc
    [ "$status" -eq 0 ]
}

@test "scan_sensitive_patterns skips comments" {
    cat > .korerorc << 'EOF'
# OPENAI_KEY="sk-abcdefghijklmnopqrstuvwxyz1234567890"
KORERO_MODE="coding"
EOF
    run scan_sensitive_patterns .korerorc
    [ "$status" -eq 0 ]
}

@test "scan_sensitive_patterns skips preset values" {
    cat > .korerorc << 'EOF'
ALLOWED_TOOLS="@permissive"
KORERO_MODE="idea"
MAX_LOOPS="continuous"
EOF
    run scan_sensitive_patterns .korerorc
    [ "$status" -eq 0 ]
}

@test "scan_sensitive_patterns returns 0 for missing file" {
    run scan_sensitive_patterns nonexistent.rc
    [ "$status" -eq 0 ]
}

@test "scan_sensitive_patterns shows line numbers" {
    cat > .korerorc << 'EOF'
KORERO_MODE="coding"
SECRET="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnop1234567890"
EOF
    run scan_sensitive_patterns .korerorc
    [ "$status" -eq 1 ]
    [[ "$output" == *"Line 2"* ]]
}

@test "scan_sensitive_patterns suggests environment variables" {
    cat > .korerorc << 'EOF'
KEY="sk-abcdefghijklmnopqrstuvwxyz1234567890"
EOF
    run scan_sensitive_patterns .korerorc
    [ "$status" -eq 1 ]
    [[ "$output" == *"environment variables"* ]]
}

@test "run_security_scan outputs warnings to stderr" {
    cat > .korerorc << 'EOF'
KEY="sk-abcdefghijklmnopqrstuvwxyz1234567890"
EOF
    run run_security_scan .korerorc
    [ "$status" -eq 1 ]
    [[ "$output" == *"Potential secrets"* ]]
}
