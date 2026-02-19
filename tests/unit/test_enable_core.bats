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
