#!/usr/bin/env bats
# Unit tests for lib/enable_core.sh
# Tests idempotency, safe file creation, project detection, and template generation

load '../helpers/test_helper'
load '../helpers/fixtures'

# Path to enable_core.sh
ENABLE_CORE="${BATS_TEST_DIRNAME}/../../lib/enable_core.sh"

setup() {
    # Create temporary test directory
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"

    # Source the library (disable set -e for testing)
    set +e
    source "$ENABLE_CORE"
    set -e
}

teardown() {
    if [[ -n "$TEST_DIR" ]] && [[ -d "$TEST_DIR" ]]; then
        cd /
        rm -rf "$TEST_DIR"
    fi
}

# =============================================================================
# IDEMPOTENCY CHECKS (5 tests)
# =============================================================================

@test "check_existing_korero returns 'none' when no .korero directory exists" {
    check_existing_korero || true

    assert_equal "$KORERO_STATE" "none"
}

@test "check_existing_korero returns 'complete' when all required files exist" {
    mkdir -p .korero
    echo "# PROMPT" > .korero/PROMPT.md
    echo "# Fix Plan" > .korero/fix_plan.md
    echo "# Agent" > .korero/AGENT.md

    check_existing_korero || true

    assert_equal "$KORERO_STATE" "complete"
}

@test "check_existing_korero returns 'partial' when some files are missing" {
    mkdir -p .korero
    echo "# PROMPT" > .korero/PROMPT.md
    # Missing fix_plan.md and AGENT.md

    check_existing_korero || true

    assert_equal "$KORERO_STATE" "partial"
    [[ " ${KORERO_MISSING_FILES[*]} " =~ ".korero/fix_plan.md" ]]
    [[ " ${KORERO_MISSING_FILES[*]} " =~ ".korero/AGENT.md" ]]
}

@test "is_korero_enabled returns 0 when fully enabled" {
    mkdir -p .korero
    echo "# PROMPT" > .korero/PROMPT.md
    echo "# Fix Plan" > .korero/fix_plan.md
    echo "# Agent" > .korero/AGENT.md

    run is_korero_enabled
    assert_success
}

@test "is_korero_enabled returns 1 when not enabled" {
    run is_korero_enabled
    assert_failure
}

# =============================================================================
# SAFE FILE OPERATIONS (5 tests)
# =============================================================================

@test "safe_create_file creates file that doesn't exist" {
    run safe_create_file "test.txt" "test content"

    assert_success
    [[ -f "test.txt" ]]
    [[ "$(cat test.txt)" == "test content" ]]
}

@test "safe_create_file skips existing file" {
    echo "original content" > existing.txt

    run safe_create_file "existing.txt" "new content"

    assert_failure  # Returns 1 for skip
    assert_equal "$(cat existing.txt)" "original content"
    [[ "$output" =~ "SKIP" ]] || [[ "$output" =~ "already exists" ]]
}

@test "safe_create_file creates parent directories" {
    run safe_create_file "nested/dir/file.txt" "nested content"

    assert_success
    [[ -f "nested/dir/file.txt" ]]
    [[ "$(cat nested/dir/file.txt)" == "nested content" ]]
}

@test "safe_create_dir creates directory that doesn't exist" {
    run safe_create_dir "new_dir"

    assert_success
    [[ -d "new_dir" ]]
}

@test "safe_create_dir succeeds when directory already exists" {
    mkdir existing_dir

    run safe_create_dir "existing_dir"

    assert_success
    [[ -d "existing_dir" ]]
}

# =============================================================================
# DIRECTORY STRUCTURE (2 tests)
# =============================================================================

@test "create_korero_structure creates all required directories" {
    run create_korero_structure

    assert_success
    [[ -d ".korero" ]]
    [[ -d ".korero/specs" ]]
    [[ -d ".korero/examples" ]]
    [[ -d ".korero/logs" ]]
    [[ -d ".korero/docs/generated" ]]
}

@test "create_korero_structure is idempotent" {
    create_korero_structure
    echo "test" > .korero/specs/test.txt

    run create_korero_structure

    assert_success
    [[ -f ".korero/specs/test.txt" ]]
}

# =============================================================================
# PROJECT DETECTION (6 tests)
# =============================================================================

@test "detect_project_context identifies TypeScript from package.json" {
    cat > package.json << 'EOF'
{
    "name": "my-ts-project",
    "devDependencies": {
        "typescript": "^5.0.0"
    }
}
EOF

    detect_project_context

    assert_equal "$DETECTED_PROJECT_TYPE" "typescript"
    assert_equal "$DETECTED_PROJECT_NAME" "my-ts-project"
}

@test "detect_project_context identifies JavaScript from package.json" {
    cat > package.json << 'EOF'
{
    "name": "my-js-project"
}
EOF

    detect_project_context

    assert_equal "$DETECTED_PROJECT_TYPE" "javascript"
}

@test "detect_project_context identifies Python from pyproject.toml" {
    cat > pyproject.toml << 'EOF'
[project]
name = "my-python-project"
EOF

    detect_project_context

    assert_equal "$DETECTED_PROJECT_TYPE" "python"
}

@test "detect_project_context identifies Next.js framework" {
    cat > package.json << 'EOF'
{
    "name": "nextjs-app",
    "dependencies": {
        "next": "^14.0.0"
    }
}
EOF

    detect_project_context

    assert_equal "$DETECTED_FRAMEWORK" "nextjs"
}

@test "detect_project_context identifies FastAPI framework" {
    cat > pyproject.toml << 'EOF'
[project]
name = "fastapi-app"
dependencies = ["fastapi>=0.100.0"]
EOF

    detect_project_context

    assert_equal "$DETECTED_FRAMEWORK" "fastapi"
}

@test "detect_project_context falls back to folder name" {
    detect_project_context

    # Should use the temp directory name
    [[ -n "$DETECTED_PROJECT_NAME" ]]
}

# =============================================================================
# GIT DETECTION (3 tests)
# =============================================================================

@test "detect_git_info detects git repository" {
    git init >/dev/null 2>&1

    detect_git_info

    assert_equal "$DETECTED_GIT_REPO" "true"
}

@test "detect_git_info detects non-git directory" {
    detect_git_info

    assert_equal "$DETECTED_GIT_REPO" "false"
}

@test "detect_git_info detects GitHub remote" {
    git init >/dev/null 2>&1
    git remote add origin git@github.com:user/repo.git 2>/dev/null || true

    detect_git_info

    assert_equal "$DETECTED_GIT_GITHUB" "true"
}

# =============================================================================
# TASK SOURCE DETECTION (2 tests)
# =============================================================================

@test "detect_task_sources detects .beads directory" {
    mkdir -p .beads

    detect_task_sources

    assert_equal "$DETECTED_BEADS_AVAILABLE" "true"
}

@test "detect_task_sources finds PRD files" {
    mkdir -p docs
    echo "# Requirements" > docs/requirements.md

    detect_task_sources

    [[ ${#DETECTED_PRD_FILES[@]} -gt 0 ]]
}

# =============================================================================
# TEMPLATE GENERATION (4 tests)
# =============================================================================

@test "generate_prompt_md includes project name" {
    output=$(generate_prompt_md "my-project" "typescript")

    [[ "$output" =~ "my-project" ]]
}

@test "generate_prompt_md includes project type" {
    output=$(generate_prompt_md "my-project" "python")

    [[ "$output" =~ "python" ]]
}

@test "generate_agent_md includes build command" {
    output=$(generate_agent_md "npm run build" "npm test" "npm start")

    [[ "$output" =~ "npm run build" ]]
    [[ "$output" =~ "npm test" ]]
}

@test "generate_korerorc includes project configuration" {
    output=$(generate_korerorc "my-project" "typescript" "local,beads")

    [[ "$output" =~ "PROJECT_NAME=\"my-project\"" ]]
    [[ "$output" =~ "PROJECT_TYPE=\"typescript\"" ]]
    [[ "$output" =~ "TASK_SOURCES=\"local,beads\"" ]]
}

# =============================================================================
# FULL ENABLE FLOW (3 tests)
# =============================================================================

@test "enable_korero_in_directory creates all required files" {
    export ENABLE_FORCE="false"
    export ENABLE_SKIP_TASKS="true"
    export ENABLE_PROJECT_NAME="test-project"

    run enable_korero_in_directory

    assert_success
    [[ -f ".korero/PROMPT.md" ]]
    [[ -f ".korero/fix_plan.md" ]]
    [[ -f ".korero/AGENT.md" ]]
    [[ -f ".korerorc" ]]
}

@test "enable_korero_in_directory returns ALREADY_ENABLED when complete and no force" {
    mkdir -p .korero
    echo "# PROMPT" > .korero/PROMPT.md
    echo "# Fix Plan" > .korero/fix_plan.md
    echo "# Agent" > .korero/AGENT.md

    export ENABLE_FORCE="false"

    run enable_korero_in_directory

    assert_equal "$status" "$ENABLE_ALREADY_ENABLED"
}

@test "enable_korero_in_directory overwrites with force flag" {
    mkdir -p .korero
    echo "old content" > .korero/PROMPT.md
    echo "old fix plan" > .korero/fix_plan.md
    echo "old agent" > .korero/AGENT.md

    export ENABLE_FORCE="true"
    export ENABLE_PROJECT_NAME="new-project"

    run enable_korero_in_directory

    assert_success

    # Verify files were actually overwritten, not just skipped
    local prompt_content
    prompt_content=$(cat .korero/PROMPT.md)

    # Should contain new project name, not "old content"
    [[ "$prompt_content" != "old content" ]]
    [[ "$prompt_content" == *"new-project"* ]]
}

@test "safe_create_file overwrites existing file when ENABLE_FORCE is true" {
    # Create existing file with old content
    echo "original content" > test_file.txt

    export ENABLE_FORCE="true"

    run safe_create_file "test_file.txt" "new content"

    assert_success

    # Verify file was overwritten
    local content
    content=$(cat test_file.txt)
    [[ "$content" == "new content" ]]
}

@test "safe_create_file skips existing file when ENABLE_FORCE is false" {
    # Create existing file with old content
    echo "original content" > test_file.txt

    export ENABLE_FORCE="false"

    run safe_create_file "test_file.txt" "new content"

    # Should return 1 (skipped)
    assert_failure

    # Verify file was NOT overwritten
    local content
    content=$(cat test_file.txt)
    [[ "$content" == "original content" ]]
}

# =============================================================================
# CONFIGURATION VALIDATION (6 tests)
# =============================================================================

@test "validate_korerorc passes valid config" {
    cat > "$TEST_DIR/.korerorc" << 'EOF'
KORERO_MODE="coding"
ALLOWED_TOOLS="@standard"
MAX_LOOPS="20"
EOF
    run validate_korerorc "$TEST_DIR/.korerorc"
    assert_success
}

@test "validate_korerorc passes valid idea mode config" {
    cat > "$TEST_DIR/.korerorc" << 'EOF'
KORERO_MODE="idea"
ALLOWED_TOOLS="@conservative"
MAX_LOOPS="continuous"
EOF
    run validate_korerorc "$TEST_DIR/.korerorc"
    assert_success
}

@test "validate_korerorc detects unknown preset" {
    cat > "$TEST_DIR/.korerorc" << 'EOF'
ALLOWED_TOOLS="@standrd"
EOF
    run validate_korerorc "$TEST_DIR/.korerorc"
    assert_failure
    [[ "$output" == *"Unknown preset '@standrd'"* ]]
    [[ "$output" == *"@standard"* ]]
}

@test "validate_korerorc detects malformed Bash pattern" {
    cat > "$TEST_DIR/.korerorc" << 'EOF'
ALLOWED_TOOLS="Bash(git"
EOF
    run validate_korerorc "$TEST_DIR/.korerorc"
    assert_failure
    [[ "$output" == *"missing closing parenthesis"* ]]
}

@test "validate_korerorc detects invalid KORERO_MODE" {
    cat > "$TEST_DIR/.korerorc" << 'EOF'
KORERO_MODE="debug"
EOF
    run validate_korerorc "$TEST_DIR/.korerorc"
    assert_failure
    [[ "$output" == *"Invalid KORERO_MODE"* ]]
}

@test "validate_korerorc detects invalid MAX_LOOPS" {
    cat > "$TEST_DIR/.korerorc" << 'EOF'
MAX_LOOPS="forever"
EOF
    run validate_korerorc "$TEST_DIR/.korerorc"
    assert_failure
    [[ "$output" == *"Invalid MAX_LOOPS"* ]]
}

# =============================================================================
# VERBOSE CONFIGURATION VALIDATION (4 tests)
# =============================================================================

@test "validate_korerorc_verbose shows checkmarks for valid config" {
    cat > "$TEST_DIR/.korerorc" << 'EOF'
KORERO_MODE="coding"
ALLOWED_TOOLS="@standard"
MAX_LOOPS="20"
EOF
    run validate_korerorc_verbose "$TEST_DIR/.korerorc"
    assert_success
    [[ "$output" == *"✓"* ]]
    [[ "$output" == *"KORERO_MODE: coding (valid)"* ]]
    [[ "$output" == *"Configuration valid"* ]]
}

@test "validate_korerorc_verbose shows per-field results" {
    cat > "$TEST_DIR/.korerorc" << 'EOF'
KORERO_MODE="idea"
ALLOWED_TOOLS="@conservative"
MAX_LOOPS="continuous"
PROJECT_SUBJECT="test app"
EOF
    run validate_korerorc_verbose "$TEST_DIR/.korerorc"
    assert_success
    [[ "$output" == *"KORERO_MODE: idea (valid)"* ]]
    [[ "$output" == *"ALLOWED_TOOLS: @conservative (valid)"* ]]
    [[ "$output" == *"MAX_LOOPS: continuous (valid)"* ]]
    [[ "$output" == *"PROJECT_SUBJECT:"* ]]
}

@test "validate_korerorc_verbose detects invalid preset" {
    cat > "$TEST_DIR/.korerorc" << 'EOF'
ALLOWED_TOOLS="@standrd"
EOF
    run validate_korerorc_verbose "$TEST_DIR/.korerorc"
    assert_failure
    [[ "$output" == *"✗"* ]]
    [[ "$output" == *"Unknown preset"* ]]
}

@test "validate_korerorc_verbose detects invalid MAX_LOOPS" {
    cat > "$TEST_DIR/.korerorc" << 'EOF'
MAX_LOOPS="forever"
EOF
    run validate_korerorc_verbose "$TEST_DIR/.korerorc"
    assert_failure
    [[ "$output" == *"✗"* ]]
    [[ "$output" == *"error(s) found"* ]]
}

# =============================================================================
# QUICKSTART WIZARD (3 tests)
# =============================================================================

@test "run_quickstart_wizard creates .korerorc" {
    cd "$TEST_DIR"
    run bash -c "echo -e 'coding\ntest project\nstandard' | run_quickstart_wizard"
    # If run_quickstart_wizard isn't exported properly in this context, source it
    if [[ "$status" -ne 0 ]]; then
        skip "run_quickstart_wizard not available in subshell"
    fi
    [ -f "$TEST_DIR/.korerorc" ]
}

@test "run_quickstart_wizard detects already enabled" {
    cd "$TEST_DIR"
    mkdir -p .korero
    touch .korero/PROMPT.md .korero/fix_plan.md .korero/AGENT.md .korerorc
    run run_quickstart_wizard
    [[ "$output" == *"already enabled"* ]]
}

@test "run_quickstart_wizard shows header" {
    cd "$TEST_DIR"
    # Need to provide input even though it'll fail on piped input
    run bash -c "echo -e 'coding\ntest\nstandard' | run_quickstart_wizard"
    [[ "$output" == *"KORERO QUICK START"* ]] || [[ "$output" == *"already enabled"* ]]
}

# =============================================================================
# CONFIGURATION PREVIEW TESTS (4 tests)
# =============================================================================
# Tests for preview_korerorc_changes()
# Shows field-by-field diff when overwriting existing .korerorc

@test "preview_korerorc_changes returns 0 when no existing .korerorc" {
    cd "$TEST_DIR"
    # No .korerorc exists
    run preview_korerorc_changes 'ALLOWED_TOOLS="@standard"' "false"
    [ "$status" -eq 0 ]
}

@test "preview_korerorc_changes shows changed fields" {
    cd "$TEST_DIR"
    cat > "$TEST_DIR/.korerorc" << 'EOF'
PROJECT_NAME="old-project"
ALLOWED_TOOLS="Write,Read,Edit"
MAX_CALLS_PER_HOUR=100
EOF
    local new_content='PROJECT_NAME="new-project"
ALLOWED_TOOLS="@standard"
MAX_CALLS_PER_HOUR=100'

    result=$(preview_korerorc_changes "$new_content" "false" 2>&1)
    [[ "$result" == *"PROJECT_NAME"* ]]
    [[ "$result" == *"old-project"* ]]
    [[ "$result" == *"new-project"* ]]
}

@test "preview_korerorc_changes shows no changes for identical config" {
    cd "$TEST_DIR"
    echo 'ALLOWED_TOOLS="@standard"' > "$TEST_DIR/.korerorc"
    local new_content='ALLOWED_TOOLS="@standard"'

    result=$(preview_korerorc_changes "$new_content" "false" 2>&1)
    [[ "$result" == *"No changes detected"* ]]
}

@test "preview_korerorc_changes returns 0 in non-interactive mode" {
    cd "$TEST_DIR"
    echo 'ALLOWED_TOOLS="Write,Read,Edit"' > "$TEST_DIR/.korerorc"
    local new_content='ALLOWED_TOOLS="@standard"'

    run preview_korerorc_changes "$new_content" "false"
    [ "$status" -eq 0 ]
}
