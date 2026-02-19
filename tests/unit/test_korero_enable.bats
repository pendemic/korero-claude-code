#!/usr/bin/env bats
# Integration tests for korero_enable.sh and korero_enable_ci.sh
# Tests the full enable wizard flow and CI version

load '../helpers/test_helper'
load '../helpers/fixtures'

# Paths to scripts
KORERO_ENABLE="${BATS_TEST_DIRNAME}/../../korero_enable.sh"
KORERO_ENABLE_CI="${BATS_TEST_DIRNAME}/../../korero_enable_ci.sh"

setup() {
    # Create temporary test directory
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"

    # Initialize git repo (required by some detection)
    git init > /dev/null 2>&1
    git config user.email "test@example.com"
    git config user.name "Test User"
}

teardown() {
    if [[ -n "$TEST_DIR" ]] && [[ -d "$TEST_DIR" ]]; then
        cd /
        rm -rf "$TEST_DIR"
    fi
}

# =============================================================================
# HELP AND VERSION (4 tests)
# =============================================================================

@test "korero enable --help shows usage information" {
    run bash "$KORERO_ENABLE" --help

    assert_success
    [[ "$output" =~ "Usage:" ]]
    [[ "$output" =~ "--from" ]]
    [[ "$output" =~ "--force" ]]
}

@test "korero enable --version shows version" {
    run bash "$KORERO_ENABLE" --version

    assert_success
    [[ "$output" =~ "version" ]]
}

@test "korero enable-ci --help shows usage information" {
    run bash "$KORERO_ENABLE_CI" --help

    assert_success
    [[ "$output" =~ "Usage:" ]]
    [[ "$output" =~ "Exit Codes:" ]]
}

@test "korero enable-ci --version shows version" {
    run bash "$KORERO_ENABLE_CI" --version

    assert_success
    [[ "$output" =~ "version" ]]
}

# =============================================================================
# CI VERSION TESTS (8 tests)
# =============================================================================

@test "korero enable-ci creates .korero structure in empty directory" {
    run bash "$KORERO_ENABLE_CI" --from none

    assert_success
    [[ -d ".korero" ]]
    [[ -f ".korero/PROMPT.md" ]]
    [[ -f ".korero/fix_plan.md" ]]
    [[ -f ".korero/AGENT.md" ]]
}

@test "korero enable-ci creates .korerorc configuration" {
    run bash "$KORERO_ENABLE_CI" --from none

    assert_success
    [[ -f ".korerorc" ]]
}

@test "korero enable-ci detects TypeScript project" {
    cat > package.json << 'EOF'
{
    "name": "test-ts-project",
    "devDependencies": {
        "typescript": "^5.0.0"
    }
}
EOF

    run bash "$KORERO_ENABLE_CI" --from none

    assert_success
    grep -q "PROJECT_TYPE=\"typescript\"" .korerorc
}

@test "korero enable-ci detects Python project" {
    cat > pyproject.toml << 'EOF'
[project]
name = "test-python-project"
EOF

    run bash "$KORERO_ENABLE_CI" --from none

    assert_success
    grep -q "PROJECT_TYPE=\"python\"" .korerorc
}

@test "korero enable-ci respects --project-name override" {
    run bash "$KORERO_ENABLE_CI" --from none --project-name "custom-name"

    assert_success
    grep -q "PROJECT_NAME=\"custom-name\"" .korerorc
}

@test "korero enable-ci respects --project-type override" {
    run bash "$KORERO_ENABLE_CI" --from none --project-type "rust"

    assert_success
    grep -q "PROJECT_TYPE=\"rust\"" .korerorc
}

@test "korero enable-ci returns exit code 2 when already enabled" {
    # First enable
    bash "$KORERO_ENABLE_CI" --from none >/dev/null 2>&1

    # Second enable without force
    run bash "$KORERO_ENABLE_CI" --from none

    assert_equal "$status" 2
}

@test "korero enable-ci --force overwrites existing configuration" {
    # First enable
    bash "$KORERO_ENABLE_CI" --from none --project-name "old-name" >/dev/null 2>&1

    # Second enable with force
    run bash "$KORERO_ENABLE_CI" --from none --force --project-name "new-name"

    assert_success
}

# =============================================================================
# JSON OUTPUT TESTS (3 tests)
# =============================================================================

@test "korero enable-ci --json outputs valid JSON on success" {
    run bash "$KORERO_ENABLE_CI" --from none --json

    assert_success
    # Validate JSON structure
    echo "$output" | jq -e '.success == true'
    echo "$output" | jq -e '.project_name'
    echo "$output" | jq -e '.files_created'
}

@test "korero enable-ci --json includes project info" {
    cat > package.json << 'EOF'
{"name": "json-test"}
EOF

    run bash "$KORERO_ENABLE_CI" --from none --json

    assert_success
    echo "$output" | jq -e '.project_name == "json-test"'
}

@test "korero enable-ci --json returns proper structure when already enabled" {
    bash "$KORERO_ENABLE_CI" --from none >/dev/null 2>&1

    run bash "$KORERO_ENABLE_CI" --from none --json

    assert_equal "$status" 2
    echo "$output" | jq -e '.code == 2'
}

# =============================================================================
# PRD IMPORT TESTS (2 tests)
# =============================================================================

@test "korero enable-ci imports tasks from PRD file" {
    mkdir -p docs
    cat > docs/requirements.md << 'EOF'
# Project Requirements

- [ ] Implement user authentication
- [ ] Add API endpoints
- [ ] Create database schema
EOF

    run bash "$KORERO_ENABLE_CI" --from prd --prd docs/requirements.md

    assert_success
    # Check that tasks were imported
    grep -q "authentication\|API\|database" .korero/fix_plan.md
}

@test "korero enable-ci fails gracefully with missing PRD file" {
    run bash "$KORERO_ENABLE_CI" --from prd --prd nonexistent.md

    assert_failure
}

# =============================================================================
# IDEMPOTENCY TESTS (3 tests)
# =============================================================================

@test "korero enable-ci is idempotent with force flag" {
    bash "$KORERO_ENABLE_CI" --from none >/dev/null 2>&1

    # Add a file to .korero
    echo "custom file" > .korero/custom.txt

    run bash "$KORERO_ENABLE_CI" --from none --force

    assert_success
    # Custom file should still exist (we don't delete extra files)
    [[ -f ".korero/custom.txt" ]]
}

@test "korero enable-ci preserves existing .korero subdirectories" {
    bash "$KORERO_ENABLE_CI" --from none >/dev/null 2>&1

    # Add custom content
    echo "spec content" > .korero/specs/custom_spec.md

    run bash "$KORERO_ENABLE_CI" --from none --force

    assert_success
    [[ -f ".korero/specs/custom_spec.md" ]]
}

@test "korero enable-ci does not overwrite existing files without force" {
    mkdir -p .korero
    echo "original prompt" > .korero/PROMPT.md
    echo "original fix plan" > .korero/fix_plan.md
    echo "original agent" > .korero/AGENT.md

    run bash "$KORERO_ENABLE_CI" --from none

    assert_equal "$status" 2
    # Verify original content preserved
    assert_equal "$(cat .korero/PROMPT.md)" "original prompt"
}

# =============================================================================
# QUIET MODE TESTS (2 tests)
# =============================================================================

@test "korero enable-ci --quiet suppresses output" {
    run bash "$KORERO_ENABLE_CI" --from none --quiet

    assert_success
    # Output should be minimal
    [[ -z "$output" ]] || [[ ! "$output" =~ "Detected" ]]
}

@test "korero enable-ci --quiet still creates files" {
    run bash "$KORERO_ENABLE_CI" --from none --quiet

    assert_success
    [[ -f ".korero/PROMPT.md" ]]
}
