#!/usr/bin/env bats
# Integration tests for Korero project setup (setup.sh)
# Tests directory creation, template copying, git initialization, and README creation

load '../helpers/test_helper'
load '../helpers/fixtures'

# Store the path to setup.sh from the project root
SETUP_SCRIPT=""

setup() {
    # Create unique temporary test directory
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"

    # Store setup.sh path (relative to test directory)
    SETUP_SCRIPT="${BATS_TEST_DIRNAME}/../../setup.sh"

    # Set git author info via environment variables (avoids mutating global config)
    export GIT_AUTHOR_NAME="Test User"
    export GIT_AUTHOR_EMAIL="test@example.com"
    export GIT_COMMITTER_NAME="Test User"
    export GIT_COMMITTER_EMAIL="test@example.com"

    # Create mock templates directory (simulating ../templates relative to project being created)
    mkdir -p templates/specs

    # Create mock template files with minimal but valid content
    cat > templates/PROMPT.md << 'EOF'
# Korero Development Instructions

## Context
You are Korero, an autonomous AI development agent.

## Current Objectives
1. Follow fix_plan.md for current priorities
2. Implement using best practices
3. Run tests after each implementation
EOF

    cat > templates/fix_plan.md << 'EOF'
# Korero Fix Plan

## High Priority
- [ ] Initial setup task

## Medium Priority
- [ ] Secondary task

## Notes
- Focus on MVP functionality first
EOF

    cat > templates/AGENT.md << 'EOF'
# Agent Build Instructions

## Project Setup
```bash
npm install
```

## Running Tests
```bash
npm test
```
EOF

    # Create a sample spec file
    cat > templates/specs/sample_spec.md << 'EOF'
# Sample Specification
This is a sample spec file for testing.
EOF
}

teardown() {
    # Clean up test directory
    if [[ -n "$TEST_DIR" ]] && [[ -d "$TEST_DIR" ]]; then
        cd /
        rm -rf "$TEST_DIR"
    fi
}

# =============================================================================
# Test: Project Directory Creation
# =============================================================================

@test "setup.sh creates project directory" {
    run bash "$SETUP_SCRIPT" test-project

    assert_success
    assert_dir_exists "test-project"
}

@test "setup.sh handles project name with hyphens" {
    run bash "$SETUP_SCRIPT" my-test-project

    assert_success
    assert_dir_exists "my-test-project"
}

@test "setup.sh handles project name with underscores" {
    run bash "$SETUP_SCRIPT" my_test_project

    assert_success
    assert_dir_exists "my_test_project"
}

# =============================================================================
# Test: Subdirectory Structure (.korero/ subfolder)
# =============================================================================

@test "setup.sh creates .korero subdirectory for Korero-specific files" {
    run bash "$SETUP_SCRIPT" test-project

    assert_success
    assert_dir_exists "test-project/.korero"
}

@test "setup.sh creates all required subdirectories in .korero/" {
    run bash "$SETUP_SCRIPT" test-project

    assert_success
    # Korero-specific directories go inside .korero/
    assert_dir_exists "test-project/.korero/specs"
    assert_dir_exists "test-project/.korero/specs/stdlib"
    assert_dir_exists "test-project/.korero/examples"
    assert_dir_exists "test-project/.korero/logs"
    assert_dir_exists "test-project/.korero/docs"
    assert_dir_exists "test-project/.korero/docs/generated"
    # src/ stays at root per maintainer decision
    assert_dir_exists "test-project/src"
}

@test "setup.sh keeps src directory at project root (not in .korero/)" {
    run bash "$SETUP_SCRIPT" test-project

    assert_success
    # src should be at root, NOT inside .korero
    assert_dir_exists "test-project/src"
    [[ ! -d "test-project/.korero/src" ]]
}

@test "setup.sh creates nested docs/generated directory in .korero/" {
    run bash "$SETUP_SCRIPT" test-project

    assert_success
    # Verify the nested structure exists inside .korero
    [[ -d "test-project/.korero/docs/generated" ]]
}

@test "setup.sh creates nested specs/stdlib directory in .korero/" {
    run bash "$SETUP_SCRIPT" test-project

    assert_success
    [[ -d "test-project/.korero/specs/stdlib" ]]
}

# =============================================================================
# Test: Template Copying (to .korero/ subfolder)
# =============================================================================

@test "setup.sh copies PROMPT.md template to .korero/" {
    run bash "$SETUP_SCRIPT" test-project

    assert_success
    assert_file_exists "test-project/.korero/PROMPT.md"

    # Verify content matches source
    diff templates/PROMPT.md test-project/.korero/PROMPT.md
}

@test "setup.sh copies fix_plan.md to .korero/" {
    run bash "$SETUP_SCRIPT" test-project

    assert_success
    assert_file_exists "test-project/.korero/fix_plan.md"

    # Verify content matches source
    diff templates/fix_plan.md "test-project/.korero/fix_plan.md"
}

@test "setup.sh copies AGENT.md to .korero/" {
    run bash "$SETUP_SCRIPT" test-project

    assert_success
    assert_file_exists "test-project/.korero/AGENT.md"

    # Verify content matches source
    diff templates/AGENT.md "test-project/.korero/AGENT.md"
}

@test "setup.sh copies specs templates to .korero/specs/" {
    run bash "$SETUP_SCRIPT" test-project

    assert_success
    # Verify spec file was copied to .korero/specs/
    assert_file_exists "test-project/.korero/specs/sample_spec.md"
}

@test "setup.sh handles empty specs directory gracefully" {
    # Remove spec files
    rm -f templates/specs/*

    run bash "$SETUP_SCRIPT" test-project

    # Should not fail (|| true in script handles this)
    assert_success
    assert_dir_exists "test-project/.korero/specs"
}

@test "setup.sh handles missing specs directory gracefully" {
    # Remove specs directory entirely
    rm -rf templates/specs

    run bash "$SETUP_SCRIPT" test-project

    # Should not fail due to || true in script
    assert_success
    assert_dir_exists "test-project/.korero/specs"
}

# =============================================================================
# Test: Git Initialization
# =============================================================================

@test "setup.sh initializes git repository" {
    run bash "$SETUP_SCRIPT" test-project

    assert_success
    assert_dir_exists "test-project/.git"
}

@test "setup.sh creates valid git repository" {
    bash "$SETUP_SCRIPT" test-project

    cd test-project
    run command git rev-parse --git-dir

    assert_success
    assert_equal "$output" ".git"
}

@test "setup.sh creates initial git commit" {
    bash "$SETUP_SCRIPT" test-project

    cd test-project
    run command git log --oneline

    assert_success
    # Should have at least one commit
    [[ -n "$output" ]]
}

@test "setup.sh uses correct initial commit message" {
    bash "$SETUP_SCRIPT" test-project

    cd test-project
    run command git log -1 --pretty=%B

    assert_success
    # Remove trailing whitespace for comparison
    local commit_msg=$(echo "$output" | tr -d '\n')
    assert_equal "$commit_msg" "Initial Korero project setup"
}

@test "setup.sh commits all files in initial commit" {
    bash "$SETUP_SCRIPT" test-project

    cd test-project
    run command git status --porcelain

    assert_success
    # Working tree should be clean (no uncommitted changes)
    assert_equal "$output" ""
}

# =============================================================================
# Test: README Creation
# =============================================================================

@test "setup.sh creates README.md" {
    run bash "$SETUP_SCRIPT" test-project

    assert_success
    assert_file_exists "test-project/README.md"
}

@test "setup.sh README contains project name" {
    bash "$SETUP_SCRIPT" test-project

    # Verify README contains the project name as heading
    grep -q "# test-project" test-project/README.md
}

@test "setup.sh README is not empty" {
    bash "$SETUP_SCRIPT" test-project

    # File should have content
    [[ -s "test-project/README.md" ]]
}

# =============================================================================
# Test: Custom Project Name
# =============================================================================

@test "setup.sh accepts custom project name as argument" {
    run bash "$SETUP_SCRIPT" custom-project-name

    assert_success
    assert_dir_exists "custom-project-name"
}

@test "setup.sh custom project has correct README heading" {
    bash "$SETUP_SCRIPT" custom-project-name

    grep -q "# custom-project-name" custom-project-name/README.md
}

@test "setup.sh custom project has all subdirectories in .korero/" {
    bash "$SETUP_SCRIPT" my-custom-app

    # Korero-specific dirs in .korero/
    assert_dir_exists "my-custom-app/.korero/specs/stdlib"
    assert_dir_exists "my-custom-app/.korero/examples"
    assert_dir_exists "my-custom-app/.korero/logs"
    assert_dir_exists "my-custom-app/.korero/docs/generated"
    # src stays at root
    assert_dir_exists "my-custom-app/src"
}

@test "setup.sh custom project has all template files in .korero/" {
    bash "$SETUP_SCRIPT" my-custom-app

    assert_file_exists "my-custom-app/.korero/PROMPT.md"
    assert_file_exists "my-custom-app/.korero/fix_plan.md"
    assert_file_exists "my-custom-app/.korero/AGENT.md"
}

# =============================================================================
# Test: Default Project Name
# =============================================================================

@test "setup.sh uses default project name when none provided" {
    run bash "$SETUP_SCRIPT"

    assert_success
    # Default name is "my-project" per line 6 of setup.sh
    assert_dir_exists "my-project"
}

@test "setup.sh default project has correct README heading" {
    bash "$SETUP_SCRIPT"

    grep -q "# my-project" my-project/README.md
}

@test "setup.sh default project has all required structure in .korero/" {
    bash "$SETUP_SCRIPT"

    # Verify .korero directory exists
    assert_dir_exists "my-project/.korero"

    # Verify all directories in .korero/
    assert_dir_exists "my-project/.korero/specs/stdlib"
    assert_dir_exists "my-project/.korero/examples"
    assert_dir_exists "my-project/.korero/logs"
    assert_dir_exists "my-project/.korero/docs/generated"
    # src stays at root
    assert_dir_exists "my-project/src"

    # Verify all files in .korero/
    assert_file_exists "my-project/.korero/PROMPT.md"
    assert_file_exists "my-project/.korero/fix_plan.md"
    assert_file_exists "my-project/.korero/AGENT.md"
    # README stays at root
    assert_file_exists "my-project/README.md"
}

# =============================================================================
# Test: Working Directory Behavior
# =============================================================================

@test "setup.sh works from nested directory" {
    # Create a separate working area nested inside TEST_DIR
    mkdir -p work-area/subdir1/subdir2

    # setup.sh does: cd $PROJECT_NAME && cp ../templates/PROMPT.md .
    # So templates needs to be in the SAME directory where we run setup.sh
    # (i.e., a sibling of the project directory that gets created)
    cp -r templates work-area/subdir1/subdir2/

    cd work-area/subdir1/subdir2

    run bash "$SETUP_SCRIPT" nested-project

    assert_success
    assert_dir_exists "nested-project"
}

@test "setup.sh creates project in current directory" {
    # Project should be created relative to where script is run, not where script lives
    mkdir -p work-area
    cd work-area

    # Copy templates so they're accessible
    cp -r "$TEST_DIR/templates" .

    run bash "$SETUP_SCRIPT" local-project

    assert_success
    # Project should be in work-area directory
    assert_dir_exists "local-project"
}

# =============================================================================
# Test: Output Messages
# =============================================================================

@test "setup.sh outputs startup message with project name" {
    run bash "$SETUP_SCRIPT" test-project

    assert_success
    [[ "$output" == *"Setting up Korero project: test-project"* ]]
}

@test "setup.sh outputs completion message" {
    run bash "$SETUP_SCRIPT" test-project

    assert_success
    [[ "$output" == *"Project test-project created"* ]]
}

@test "setup.sh outputs next steps guidance with .korero paths" {
    run bash "$SETUP_SCRIPT" test-project

    assert_success
    [[ "$output" == *"Next steps:"* ]]
    [[ "$output" == *".korero/PROMPT.md"* ]]
}

# =============================================================================
# Test: Error Handling
# =============================================================================

@test "setup.sh fails if templates directory missing" {
    # Remove local templates directory
    rm -rf templates

    # Also hide global templates by overriding HOME to a temp location
    local original_home="$HOME"
    export HOME="$(mktemp -d)"

    run bash "$SETUP_SCRIPT" test-project

    # Restore HOME
    export HOME="$original_home"

    assert_failure
}

@test "setup.sh fails if PROMPT.md template missing" {
    # Remove PROMPT.md template
    rm -f templates/PROMPT.md

    run bash "$SETUP_SCRIPT" test-project

    assert_failure
}

# =============================================================================
# Test: Idempotency and Edge Cases
# =============================================================================

@test "setup.sh succeeds when run in an existing directory (idempotent)" {
    # Create project directory first
    mkdir -p existing-project

    run bash "$SETUP_SCRIPT" existing-project

    # The script uses mkdir -p which is idempotent, and git init works in existing dirs
    # Templates will be copied over existing files, so this should succeed
    [[ $status -eq 0 ]]
}

@test "setup.sh handles project name with spaces by creating directory" {
    # Project names with spaces should work since the script uses "$PROJECT_NAME" with quotes
    run bash "$SETUP_SCRIPT" "project with spaces"

    # The script properly quotes variables, so spaces should be handled correctly
    [[ $status -eq 0 ]]
}

# =============================================================================
# Test: .korerorc Generation (Issue #136)
# =============================================================================

@test "setup.sh creates .korerorc file" {
    run bash "$SETUP_SCRIPT" test-project

    assert_success
    assert_file_exists "test-project/.korerorc"
}

@test "setup.sh .korerorc contains ALLOWED_TOOLS with Edit" {
    bash "$SETUP_SCRIPT" test-project

    # .korerorc should include Edit tool
    grep -q "Edit" test-project/.korerorc
}

@test "setup.sh .korerorc contains ALLOWED_TOOLS with test execution capabilities" {
    bash "$SETUP_SCRIPT" test-project

    # .korerorc should include Bash(npm *) or Bash(pytest) for test execution
    grep -qE 'Bash\(npm \*\)|Bash\(pytest\)' test-project/.korerorc
}

@test "setup.sh .korerorc ALLOWED_TOOLS matches korero-enable defaults" {
    bash "$SETUP_SCRIPT" test-project

    # The expected ALLOWED_TOOLS value that korero-enable uses
    local expected_tools='ALLOWED_TOOLS="Write,Read,Edit,Bash(git *),Bash(npm *),Bash(pytest)"'

    # Check that .korerorc contains the expected ALLOWED_TOOLS line
    # Use grep -F for literal string matching (avoids regex interpretation of *)
    grep -qF "$expected_tools" test-project/.korerorc
}

@test "setup.sh .korerorc is committed in initial git commit" {
    bash "$SETUP_SCRIPT" test-project

    cd test-project
    # Verify .korerorc is tracked by git (not in untracked files)
    run command git ls-files .korerorc

    assert_success
    assert_equal "$output" ".korerorc"
}

@test "setup.sh .korerorc contains project name" {
    bash "$SETUP_SCRIPT" my-custom-project

    # .korerorc should reference the project name
    grep -q "my-custom-project" my-custom-project/.korerorc
}
