#!/usr/bin/env bash

# enable_core.sh - Shared logic for korero enable commands
# Provides idempotency checks, safe file creation, and project detection
#
# Used by:
#   - korero_enable.sh (interactive wizard)
#   - korero_enable_ci.sh (non-interactive CI version)

# Exit codes - specific codes for different failure types
export ENABLE_SUCCESS=0           # Successful completion
export ENABLE_ERROR=1             # General error
export ENABLE_ALREADY_ENABLED=2   # Korero already enabled (use --force)
export ENABLE_INVALID_ARGS=3      # Invalid command line arguments
export ENABLE_FILE_NOT_FOUND=4    # Required file not found (e.g., PRD file)
export ENABLE_DEPENDENCY_MISSING=5 # Required dependency missing (e.g., jq for --json)
export ENABLE_PERMISSION_DENIED=6 # Cannot create files/directories

# Colors (can be disabled for non-interactive mode)
export ENABLE_USE_COLORS="${ENABLE_USE_COLORS:-true}"

_color() {
    if [[ "$ENABLE_USE_COLORS" == "true" ]]; then
        echo -e "$1"
    else
        echo -e "$2"
    fi
}

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging function
enable_log() {
    local level=$1
    local message=$2
    local color=""

    case $level in
        "INFO")  color=$BLUE ;;
        "WARN")  color=$YELLOW ;;
        "ERROR") color=$RED ;;
        "SUCCESS") color=$GREEN ;;
        "SKIP") color=$CYAN ;;
    esac

    if [[ "$ENABLE_USE_COLORS" == "true" ]]; then
        echo -e "${color}[$level]${NC} $message"
    else
        echo "[$level] $message"
    fi
}

# =============================================================================
# IDEMPOTENCY CHECKS
# =============================================================================

# check_existing_korero - Check if .korero directory exists and its state
#
# Returns:
#   0 - No .korero directory, safe to proceed
#   1 - .korero exists but incomplete (partial setup)
#   2 - .korero exists and fully initialized
#
# Outputs:
#   Sets global KORERO_STATE: "none" | "partial" | "complete"
#   Sets global KORERO_MISSING_FILES: array of missing files if partial
#
check_existing_korero() {
    KORERO_STATE="none"
    KORERO_MISSING_FILES=()

    if [[ ! -d ".korero" ]]; then
        KORERO_STATE="none"
        return 0
    fi

    # Check for required files
    local required_files=(
        ".korero/PROMPT.md"
        ".korero/fix_plan.md"
        ".korero/AGENT.md"
    )

    local missing=()
    local found=0

    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            found=$((found + 1))
        else
            missing+=("$file")
        fi
    done

    KORERO_MISSING_FILES=("${missing[@]}")

    if [[ $found -eq 0 ]]; then
        KORERO_STATE="none"
        return 0
    elif [[ ${#missing[@]} -gt 0 ]]; then
        KORERO_STATE="partial"
        return 1
    else
        KORERO_STATE="complete"
        return 2
    fi
}

# is_korero_enabled - Simple check if Korero is fully enabled
#
# Returns:
#   0 - Korero is fully enabled
#   1 - Korero is not enabled or only partially
#
is_korero_enabled() {
    check_existing_korero || true
    [[ "$KORERO_STATE" == "complete" ]]
}

# =============================================================================
# SAFE FILE OPERATIONS
# =============================================================================

# safe_create_file - Create a file only if it doesn't exist (or force overwrite)
#
# Parameters:
#   $1 (target) - Target file path
#   $2 (content) - Content to write (can be empty string)
#
# Environment:
#   ENABLE_FORCE - If "true", overwrites existing files instead of skipping
#
# Returns:
#   0 - File created/overwritten successfully
#   1 - File already exists (skipped, only when ENABLE_FORCE is not true)
#   2 - Error creating file
#
# Side effects:
#   Logs [CREATE], [OVERWRITE], or [SKIP] message
#
safe_create_file() {
    local target=$1
    local content=$2
    local force="${ENABLE_FORCE:-false}"

    if [[ -f "$target" ]]; then
        if [[ "$force" == "true" ]]; then
            # Force mode: overwrite existing file
            enable_log "INFO" "Overwriting $target (--force)"
        else
            # Normal mode: skip existing file
            enable_log "SKIP" "$target already exists"
            return 1
        fi
    fi

    # Create parent directory if needed
    local parent_dir
    parent_dir=$(dirname "$target")
    if [[ ! -d "$parent_dir" ]]; then
        if ! mkdir -p "$parent_dir" 2>/dev/null; then
            enable_log "ERROR" "Failed to create directory: $parent_dir"
            return 2
        fi
    fi

    # Write content to file using printf to avoid shell injection
    # printf '%s\n' is safer than echo for arbitrary content (handles backslashes, -n, etc.)
    if printf '%s\n' "$content" > "$target" 2>/dev/null; then
        if [[ -f "$target" ]] && [[ "$force" == "true" ]]; then
            enable_log "SUCCESS" "Overwrote $target"
        else
            enable_log "SUCCESS" "Created $target"
        fi
        return 0
    else
        enable_log "ERROR" "Failed to create: $target"
        return 2
    fi
}

# safe_create_dir - Create a directory only if it doesn't exist
#
# Parameters:
#   $1 (target) - Target directory path
#
# Returns:
#   0 - Directory created or already exists
#   1 - Error creating directory
#
safe_create_dir() {
    local target=$1

    if [[ -d "$target" ]]; then
        return 0
    fi

    if mkdir -p "$target" 2>/dev/null; then
        enable_log "SUCCESS" "Created directory: $target"
        return 0
    else
        enable_log "ERROR" "Failed to create directory: $target"
        return 1
    fi
}

# =============================================================================
# DIRECTORY STRUCTURE
# =============================================================================

# create_korero_structure - Create the .korero/ directory structure
#
# Creates:
#   .korero/
#   .korero/specs/
#   .korero/examples/
#   .korero/logs/
#   .korero/docs/generated/
#
# Returns:
#   0 - Structure created successfully
#   1 - Error creating structure
#
create_korero_structure() {
    local korero_mode="${ENABLE_KORERO_MODE:-}"

    local dirs=(
        ".korero"
        ".korero/specs"
        ".korero/examples"
        ".korero/logs"
        ".korero/docs/generated"
    )

    # Add ideas directory for ideation modes
    if [[ "$korero_mode" == "idea" || "$korero_mode" == "coding" ]]; then
        dirs+=(".korero/ideas")
    fi

    for dir in "${dirs[@]}"; do
        if ! safe_create_dir "$dir"; then
            return 1
        fi
    done

    return 0
}

# =============================================================================
# PROJECT DETECTION
# =============================================================================

# Exported detection results
export DETECTED_PROJECT_NAME=""
export DETECTED_PROJECT_TYPE=""
export DETECTED_FRAMEWORK=""
export DETECTED_BUILD_CMD=""
export DETECTED_TEST_CMD=""
export DETECTED_RUN_CMD=""

# detect_project_context - Detect project type, name, and build commands
#
# Detects:
#   - Project type: javascript, typescript, python, rust, go, unknown
#   - Framework: nextjs, fastapi, express, etc.
#   - Build/test/run commands based on detected tooling
#
# Sets globals:
#   DETECTED_PROJECT_NAME - Project name (from package.json, folder, etc.)
#   DETECTED_PROJECT_TYPE - Language/type
#   DETECTED_FRAMEWORK - Framework if detected
#   DETECTED_BUILD_CMD - Build command
#   DETECTED_TEST_CMD - Test command
#   DETECTED_RUN_CMD - Run/start command
#
detect_project_context() {
    # Reset detection results
    DETECTED_PROJECT_NAME=""
    DETECTED_PROJECT_TYPE="unknown"
    DETECTED_FRAMEWORK=""
    DETECTED_BUILD_CMD=""
    DETECTED_TEST_CMD=""
    DETECTED_RUN_CMD=""

    # Detect from package.json (JavaScript/TypeScript)
    if [[ -f "package.json" ]]; then
        DETECTED_PROJECT_TYPE="javascript"

        # Check for TypeScript
        if grep -q '"typescript"' package.json 2>/dev/null || \
           [[ -f "tsconfig.json" ]]; then
            DETECTED_PROJECT_TYPE="typescript"
        fi

        # Extract project name
        if command -v jq &>/dev/null; then
            DETECTED_PROJECT_NAME=$(jq -r '.name // empty' package.json 2>/dev/null)
        else
            # Fallback: grep for name field
            DETECTED_PROJECT_NAME=$(grep -m1 '"name"' package.json | sed 's/.*: *"\([^"]*\)".*/\1/' 2>/dev/null)
        fi

        # Detect framework
        if grep -q '"next"' package.json 2>/dev/null; then
            DETECTED_FRAMEWORK="nextjs"
        elif grep -q '"express"' package.json 2>/dev/null; then
            DETECTED_FRAMEWORK="express"
        elif grep -q '"react"' package.json 2>/dev/null; then
            DETECTED_FRAMEWORK="react"
        elif grep -q '"vue"' package.json 2>/dev/null; then
            DETECTED_FRAMEWORK="vue"
        fi

        # Set build commands
        DETECTED_BUILD_CMD="npm run build"
        DETECTED_TEST_CMD="npm test"
        DETECTED_RUN_CMD="npm start"

        # Check for yarn
        if [[ -f "yarn.lock" ]]; then
            DETECTED_BUILD_CMD="yarn build"
            DETECTED_TEST_CMD="yarn test"
            DETECTED_RUN_CMD="yarn start"
        fi

        # Check for pnpm
        if [[ -f "pnpm-lock.yaml" ]]; then
            DETECTED_BUILD_CMD="pnpm build"
            DETECTED_TEST_CMD="pnpm test"
            DETECTED_RUN_CMD="pnpm start"
        fi
    fi

    # Detect from pyproject.toml or setup.py (Python)
    if [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]]; then
        DETECTED_PROJECT_TYPE="python"

        # Extract project name from pyproject.toml
        if [[ -f "pyproject.toml" ]]; then
            DETECTED_PROJECT_NAME=$(grep -m1 '^name' pyproject.toml | sed 's/.*= *"\([^"]*\)".*/\1/' 2>/dev/null)

            # Detect framework
            if grep -q 'fastapi' pyproject.toml 2>/dev/null; then
                DETECTED_FRAMEWORK="fastapi"
            elif grep -q 'django' pyproject.toml 2>/dev/null; then
                DETECTED_FRAMEWORK="django"
            elif grep -q 'flask' pyproject.toml 2>/dev/null; then
                DETECTED_FRAMEWORK="flask"
            fi
        fi

        # Set build commands (prefer uv if detected)
        if [[ -f "uv.lock" ]] || command -v uv &>/dev/null; then
            DETECTED_BUILD_CMD="uv sync"
            DETECTED_TEST_CMD="uv run pytest"
            DETECTED_RUN_CMD="uv run python -m ${DETECTED_PROJECT_NAME:-main}"
        else
            DETECTED_BUILD_CMD="pip install -e ."
            DETECTED_TEST_CMD="pytest"
            DETECTED_RUN_CMD="python -m ${DETECTED_PROJECT_NAME:-main}"
        fi
    fi

    # Detect from Cargo.toml (Rust)
    if [[ -f "Cargo.toml" ]]; then
        DETECTED_PROJECT_TYPE="rust"
        DETECTED_PROJECT_NAME=$(grep -m1 '^name' Cargo.toml | sed 's/.*= *"\([^"]*\)".*/\1/' 2>/dev/null)
        DETECTED_BUILD_CMD="cargo build"
        DETECTED_TEST_CMD="cargo test"
        DETECTED_RUN_CMD="cargo run"
    fi

    # Detect from go.mod (Go)
    if [[ -f "go.mod" ]]; then
        DETECTED_PROJECT_TYPE="go"
        DETECTED_PROJECT_NAME=$(head -1 go.mod | sed 's/module //' 2>/dev/null)
        DETECTED_BUILD_CMD="go build"
        DETECTED_TEST_CMD="go test ./..."
        DETECTED_RUN_CMD="go run ."
    fi

    # Fallback project name to folder name
    if [[ -z "$DETECTED_PROJECT_NAME" ]]; then
        DETECTED_PROJECT_NAME=$(basename "$(pwd)")
    fi
}

# detect_git_info - Detect git repository information
#
# Sets globals:
#   DETECTED_GIT_REPO - true if in git repo
#   DETECTED_GIT_REMOTE - Remote URL (origin)
#   DETECTED_GIT_GITHUB - true if GitHub remote
#
export DETECTED_GIT_REPO="false"
export DETECTED_GIT_REMOTE=""
export DETECTED_GIT_GITHUB="false"

detect_git_info() {
    DETECTED_GIT_REPO="false"
    DETECTED_GIT_REMOTE=""
    DETECTED_GIT_GITHUB="false"

    # Check if in git repo
    if git rev-parse --git-dir &>/dev/null; then
        DETECTED_GIT_REPO="true"

        # Get remote URL
        DETECTED_GIT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")

        # Check if GitHub
        if [[ "$DETECTED_GIT_REMOTE" == *"github.com"* ]]; then
            DETECTED_GIT_GITHUB="true"
        fi
    fi
}

# detect_task_sources - Detect available task sources
#
# Sets globals:
#   DETECTED_BEADS_AVAILABLE - true if .beads directory exists
#   DETECTED_GITHUB_AVAILABLE - true if GitHub remote detected
#   DETECTED_PRD_FILES - Array of potential PRD files found
#
export DETECTED_BEADS_AVAILABLE="false"
export DETECTED_GITHUB_AVAILABLE="false"
declare -a DETECTED_PRD_FILES=()

detect_task_sources() {
    DETECTED_BEADS_AVAILABLE="false"
    DETECTED_GITHUB_AVAILABLE="false"
    DETECTED_PRD_FILES=()

    # Check for beads
    if [[ -d ".beads" ]]; then
        DETECTED_BEADS_AVAILABLE="true"
    fi

    # Check for GitHub (reuse git detection)
    detect_git_info
    DETECTED_GITHUB_AVAILABLE="$DETECTED_GIT_GITHUB"

    # Search for PRD/spec files
    local search_dirs=("docs" "specs" "." "requirements")
    local prd_patterns=("*prd*.md" "*PRD*.md" "*requirements*.md" "*spec*.md" "*specification*.md")

    for dir in "${search_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            for pattern in "${prd_patterns[@]}"; do
                while IFS= read -r -d '' file; do
                    DETECTED_PRD_FILES+=("$file")
                done < <(find "$dir" -maxdepth 2 -name "$pattern" -print0 2>/dev/null)
            done
        fi
    done
}

# =============================================================================
# TEMPLATE GENERATION
# =============================================================================

# get_templates_dir - Get the templates directory path
#
# Returns:
#   Echoes the path to templates directory
#   Returns 1 if not found
#
get_templates_dir() {
    # Check global installation first
    if [[ -d "$HOME/.korero/templates" ]]; then
        echo "$HOME/.korero/templates"
        return 0
    fi

    # Check local installation (development)
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -d "$script_dir/../templates" ]]; then
        echo "$script_dir/../templates"
        return 0
    fi

    return 1
}

# generate_prompt_md - Generate PROMPT.md with project context
#
# Parameters:
#   $1 (project_name) - Project name
#   $2 (project_type) - Project type (typescript, python, etc.)
#   $3 (framework) - Framework if any (optional)
#   $4 (objectives) - Custom objectives (optional, newline-separated)
#
# Outputs to stdout
#
generate_prompt_md() {
    local project_name="${1:-$(basename "$(pwd)")}"
    local project_type="${2:-unknown}"
    local framework="${3:-}"
    local objectives="${4:-}"

    local framework_line=""
    if [[ -n "$framework" ]]; then
        framework_line="**Framework:** $framework"
    fi

    local objectives_section=""
    if [[ -n "$objectives" ]]; then
        objectives_section="$objectives"
    else
        objectives_section="- Review the codebase and understand the current state
- Follow tasks in fix_plan.md
- Implement one task per loop
- Write tests for new functionality
- Update documentation as needed"
    fi

    cat << PROMPTEOF
# Korero Development Instructions

## Context
You are Korero, an autonomous AI development agent working on the **${project_name}** project.

**Project Type:** ${project_type}
${framework_line}

## Current Objectives
${objectives_section}

## Key Principles
- ONE task per loop - focus on the most important thing
- Search the codebase before assuming something isn't implemented
- Write comprehensive tests with clear documentation
- Update fix_plan.md with your learnings
- Commit working changes with descriptive messages

## Testing Guidelines
- LIMIT testing to ~20% of your total effort per loop
- PRIORITIZE: Implementation > Documentation > Tests
- Only write tests for NEW functionality you implement

## Build & Run
See AGENT.md for build and run instructions.

## Status Reporting (CRITICAL)

At the end of your response, ALWAYS include this status block:

\`\`\`
---KORERO_STATUS---
STATUS: IN_PROGRESS | COMPLETE | BLOCKED
TASKS_COMPLETED_THIS_LOOP: <number>
FILES_MODIFIED: <number>
TESTS_STATUS: PASSING | FAILING | NOT_RUN
WORK_TYPE: IMPLEMENTATION | TESTING | DOCUMENTATION | REFACTORING
EXIT_SIGNAL: false | true
RECOMMENDATION: <one line summary of what to do next>
---END_KORERO_STATUS---
\`\`\`

## Current Task
Follow fix_plan.md and choose the most important item to implement next.
PROMPTEOF
}

# generate_agent_md - Generate AGENT.md with detected build commands
#
# Parameters:
#   $1 (build_cmd) - Build command
#   $2 (test_cmd) - Test command
#   $3 (run_cmd) - Run command
#
# Outputs to stdout
#
generate_agent_md() {
    local build_cmd="${1:-echo 'No build command configured'}"
    local test_cmd="${2:-echo 'No test command configured'}"
    local run_cmd="${3:-echo 'No run command configured'}"

    cat << AGENTEOF
# Korero Agent Configuration

## Build Instructions

\`\`\`bash
# Build the project
${build_cmd}
\`\`\`

## Test Instructions

\`\`\`bash
# Run tests
${test_cmd}
\`\`\`

## Run Instructions

\`\`\`bash
# Start/run the project
${run_cmd}
\`\`\`

## Notes
- Update this file when build process changes
- Add environment setup instructions as needed
- Include any pre-requisites or dependencies
AGENTEOF
}

# generate_fix_plan_md - Generate fix_plan.md with imported tasks
#
# Parameters:
#   $1 (tasks) - Tasks to include (newline-separated, markdown checkbox format)
#
# Outputs to stdout
#
generate_fix_plan_md() {
    local tasks="${1:-}"

    local high_priority=""
    local medium_priority=""
    local low_priority=""

    if [[ -n "$tasks" ]]; then
        high_priority="$tasks"
    else
        high_priority="- [ ] Review codebase and understand architecture
- [ ] Identify and document key components
- [ ] Set up development environment"
        medium_priority="- [ ] Implement core features
- [ ] Add test coverage
- [ ] Update documentation"
        low_priority="- [ ] Performance optimization
- [ ] Code cleanup and refactoring"
    fi

    cat << FIXPLANEOF
# Korero Fix Plan

## High Priority
${high_priority}

## Medium Priority
${medium_priority}

## Low Priority
${low_priority}

## Completed
- [x] Project enabled for Korero

## Notes
- Focus on MVP functionality first
- Ensure each feature is properly tested
- Update this file after each major milestone
FIXPLANEOF
}

# generate_korerorc - Generate .korerorc configuration file
#
# Parameters:
#   $1 (project_name) - Project name
#   $2 (project_type) - Project type
#   $3 (task_sources) - Task sources (local, beads, github)
#
# Outputs to stdout
#
generate_korerorc() {
    local project_name="${1:-$(basename "$(pwd)")}"
    local project_type="${2:-unknown}"
    local task_sources="${3:-local}"
    local korero_mode="${4:-}"
    local project_subject="${5:-}"
    local agent_count="${6:-3}"
    local max_loops="${7:-continuous}"

    local mode_section=""
    if [[ -n "$korero_mode" ]]; then
        mode_section="
# Korero mode: idea (ideation only) or coding (ideation + implementation)
KORERO_MODE=\"${korero_mode}\"

# Project subject (used for agent generation)
PROJECT_SUBJECT=\"${project_subject}\"

# Number of domain expert agents (not including 3 mandatory evaluation agents)
DOMAIN_AGENT_COUNT=${agent_count}

# Maximum loops to run (number or \"continuous\" for unlimited)
MAX_LOOPS=\"${max_loops}\"
"
    fi

    cat << KORERORCEOF
# .korerorc - Korero project configuration
# Generated by: korero enable
# Documentation: https://github.com/pendemic/korero-claude-code

# Project identification
PROJECT_NAME="${project_name}"
PROJECT_TYPE="${project_type}"
${mode_section}
# Loop settings
MAX_CALLS_PER_HOUR=100
CLAUDE_TIMEOUT_MINUTES=15
CLAUDE_OUTPUT_FORMAT="json"

# Tool permissions
# Comma-separated list of allowed tools
ALLOWED_TOOLS="Write,Read,Edit,Bash(git *),Bash(npm *),Bash(pytest)"

# Session management
SESSION_CONTINUITY=true
SESSION_EXPIRY_HOURS=24

# Task sources (for korero enable --sync)
# Options: local, beads, github (comma-separated for multiple)
TASK_SOURCES="${task_sources}"
GITHUB_TASK_LABEL="korero-task"
BEADS_FILTER="status:open"

# Circuit breaker thresholds
CB_NO_PROGRESS_THRESHOLD=3
CB_SAME_ERROR_THRESHOLD=5
CB_OUTPUT_DECLINE_THRESHOLD=70
KORERORCEOF
}

# =============================================================================
# IDEATION MODE - PROJECT CONTEXT GATHERING
# =============================================================================

# gather_project_context - Collect raw project information for context-aware generation
#
# Parameters:
#   $1 (project_dir) - Project directory (default: current directory)
#
# Outputs to stdout: Text block with project context (capped at ~4000 chars)
#
gather_project_context() {
    local project_dir="${1:-.}"
    local context=""
    local max_chars=4000

    # 1. Directory tree (depth-limited, excluding common non-source dirs)
    context+="=== DIRECTORY STRUCTURE ===
"
    local tree_output=""
    if command -v find &>/dev/null; then
        tree_output=$(find "$project_dir" -maxdepth 3 \
            -not -path '*/.git/*' \
            -not -path '*/.git' \
            -not -path '*/node_modules/*' \
            -not -path '*/node_modules' \
            -not -path '*/__pycache__/*' \
            -not -path '*/.korero/*' \
            -not -path '*/.ralph/*' \
            -not -path '*/.venv/*' \
            -not -path '*/venv/*' \
            -not -path '*/.env/*' \
            -not -path '*/dist/*' \
            -not -path '*/build/*' \
            -not -path '*/.next/*' \
            -not -path '*/target/*' \
            -not -path '*/.tox/*' \
            -not -name '*.pyc' \
            -not -name '*.lock' \
            -not -name 'package-lock.json' \
            2>/dev/null | sort | head -200)
    fi
    if [[ -n "$tree_output" ]]; then
        context+="$tree_output
"
    else
        context+="(could not read directory tree)
"
    fi
    context+="
"

    # 2. Package manifest (first found)
    local manifest_file=""
    local manifest_files=("package.json" "requirements.txt" "Cargo.toml" "go.mod" "pyproject.toml" "Gemfile" "setup.py" "pom.xml" "build.gradle")
    for mf in "${manifest_files[@]}"; do
        if [[ -f "$project_dir/$mf" ]]; then
            manifest_file="$project_dir/$mf"
            break
        fi
    done
    if [[ -n "$manifest_file" ]]; then
        context+="=== PACKAGE MANIFEST ($(basename "$manifest_file")) ===
"
        context+="$(head -50 "$manifest_file" 2>/dev/null)
"
        context+="
"
    fi

    # 3. README (first found)
    local readme_file=""
    local readme_files=("README.md" "readme.md" "README.rst" "README.txt" "README" "docs/README.md")
    for rf in "${readme_files[@]}"; do
        if [[ -f "$project_dir/$rf" ]]; then
            readme_file="$project_dir/$rf"
            break
        fi
    done
    if [[ -n "$readme_file" ]]; then
        context+="=== README ($(basename "$readme_file")) ===
"
        context+="$(head -100 "$readme_file" 2>/dev/null)
"
        context+="
"
    fi

    # 4. Key source files inventory (paths only, no content)
    context+="=== SOURCE FILES ===
"
    local source_files=""
    if command -v find &>/dev/null; then
        source_files=$(find "$project_dir" -maxdepth 5 \
            -not -path '*/.git/*' \
            -not -path '*/node_modules/*' \
            -not -path '*/__pycache__/*' \
            -not -path '*/.korero/*' \
            -not -path '*/.ralph/*' \
            -not -path '*/.venv/*' \
            -not -path '*/venv/*' \
            -not -path '*/dist/*' \
            -not -path '*/build/*' \
            -not -path '*/.next/*' \
            -not -path '*/target/*' \
            \( -name '*.py' -o -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
               -o -name '*.rs' -o -name '*.go' -o -name '*.java' -o -name '*.rb' \
               -o -name '*.vue' -o -name '*.svelte' \) \
            2>/dev/null | sort | head -150)
    fi
    if [[ -n "$source_files" ]]; then
        context+="$source_files
"
    else
        context+="(no source files found)
"
    fi
    context+="
"

    # 5. Config files
    local config_files=("docker-compose.yml" "docker-compose.yaml" "Dockerfile" "Makefile" ".env.example" "tsconfig.json" "vite.config.ts" "webpack.config.js" "next.config.js" "tailwind.config.js" "tailwind.config.ts")
    local found_configs=""
    for cf in "${config_files[@]}"; do
        if [[ -f "$project_dir/$cf" ]]; then
            found_configs+="$cf "
        fi
    done
    if [[ -n "$found_configs" ]]; then
        context+="=== CONFIG FILES ===
$found_configs
"
    fi

    # Cap total output at max_chars
    if [[ ${#context} -gt $max_chars ]]; then
        context="${context:0:$max_chars}
...(truncated)"
    fi

    echo "$context"
}

# =============================================================================
# IDEATION MODE - CONTEXT-AWARE CONFIGURATION
# =============================================================================

# generate_context_aware_config - Send project context to Claude CLI for intelligent analysis
#
# Parameters:
#   $1 (subject) - Project subject/description
#   $2 (project_type) - Detected project type
#   $3 (agent_count) - Number of domain agents to generate
#   $4 (max_loops) - Number of loops or "continuous"
#   $5 (mode) - "idea" or "coding"
#   $6 (project_context) - Raw context from gather_project_context()
#
# Sets global variables:
#   CONFIG_AGENTS - Markdown agent descriptions with Lens questions
#   CONFIG_CATEGORIES - Newline-separated category list with descriptions
#   CONFIG_SCORING - Markdown table of weighted scoring criteria
#   CONFIG_KEY_FILES - Grouped key file reference
#   CONFIG_PROJECT_SUMMARY - 2-3 paragraph project description
#   CONFIG_FOCUS_CONSTRAINT - Scope constraint sentence
#   CONFIG_NOTES - Project-specific notes for agents
#
# Returns:
#   0 on success
#   1 on fallback (CONFIG_ vars set to empty)
#
generate_context_aware_config() {
    local subject="$1"
    local project_type="${2:-unknown}"
    local agent_count="${3:-3}"
    local max_loops="${4:-20}"
    local mode="${5:-idea}"
    local project_context="${6:-}"

    # Reset config variables
    CONFIG_AGENTS=""
    CONFIG_CATEGORIES=""
    CONFIG_SCORING=""
    CONFIG_KEY_FILES=""
    CONFIG_PROJECT_SUMMARY=""
    CONFIG_FOCUS_CONSTRAINT=""
    CONFIG_NOTES=""

    if [[ -z "$project_context" && -z "$subject" ]]; then
        enable_log "WARN" "No project context or subject provided, using generic defaults"
        return 1
    fi

    local prompt_file output_file stderr_file
    prompt_file=$(mktemp)
    output_file=$(mktemp)
    stderr_file=$(mktemp)

    local loops_display="$max_loops"
    if [[ "$max_loops" == "continuous" ]]; then
        loops_display="unlimited"
    fi

    cat > "$prompt_file" << 'CONFIGPROMPTEOF'
You are configuring a multi-agent ideation system for a software project. Analyze the project context below and generate a structured configuration.

CONFIGPROMPTEOF

    cat >> "$prompt_file" << CONFIGCONTEXTEOF

PROJECT SUBJECT: ${subject}
PROJECT TYPE: ${project_type}
MODE: ${mode} (${mode} = idea generation only, coding = ideation + implementation)
DOMAIN AGENTS REQUESTED: ${agent_count}
TOTAL LOOPS: ${loops_display}

--- PROJECT CONTEXT ---
${project_context}
--- END PROJECT CONTEXT ---

Based on this project, generate the following configuration sections. Use the EXACT section markers shown. Do NOT include any text outside the markers.

---AGENTS_START---
For each of the ${agent_count} domain agents, output in this exact format:

### Agent: [2-4 word Role Name]
**Expertise:** [specific technical skills relevant to THIS project, 1 sentence]
**Perspective:** [what this agent prioritizes, 1 sentence]
**Focus Areas:** [comma-separated list of specific improvement areas for THIS project]
**Lens:** [a question this agent asks about every idea, starting with "Does this..."]

Separate agents with --- on its own line.
---AGENTS_END---

---CATEGORIES_START---
List 8-12 idea categories specific to this project's domain. Each on its own line in format:
- **Category Name** — Short description of what ideas in this category cover
---CATEGORIES_END---

---SCORING_START---
Create 4-6 weighted scoring criteria as a markdown table. Weights must sum to 100%.
| Criterion | Weight | Description |
|-----------|--------|-------------|
---SCORING_END---

---KEY_FILES_START---
Group the project's key source files by area (e.g., Backend, Frontend, Config). For each file, add a brief description of its purpose. Format:
### Area Name
- \`path/to/file\` — What this file does
---KEY_FILES_END---

---PROJECT_SUMMARY_START---
Write 2-3 paragraphs describing this project for someone who has never seen it. Include: what it does, the tech stack, key features, and target users. Reference actual files and components from the project context.
---PROJECT_SUMMARY_END---

---FOCUS_CONSTRAINT_START---
Write a 1-2 sentence scope constraint for the ideation process. Example: "All ideas MUST be about usability improvements and new feature additions for the end user." Tailor this to the project's domain.
---FOCUS_CONSTRAINT_END---

---NOTES_START---
Write 3-6 bullet points of project-specific guidance for the agents. These should reference actual technologies, patterns, or constraints from the codebase. Format as: - Note text
---NOTES_END---
CONFIGCONTEXTEOF

    local cli_exit_code=0
    local claude_cmd="claude"

    if command -v "$claude_cmd" &>/dev/null; then
        if "$claude_cmd" --print --output-format json < "$prompt_file" > "$output_file" 2> "$stderr_file"; then
            cli_exit_code=0
        else
            cli_exit_code=$?
        fi
    else
        cli_exit_code=1
    fi

    rm -f "$prompt_file" "$stderr_file"

    if [[ $cli_exit_code -eq 0 && -s "$output_file" ]]; then
        # Extract result text from JSON response
        local result_text=""
        if command -v jq &>/dev/null; then
            result_text=$(jq -r '.result // .' "$output_file" 2>/dev/null)
        fi
        if [[ -z "$result_text" || "$result_text" == "null" ]]; then
            result_text=$(cat "$output_file")
        fi
        rm -f "$output_file"

        # Parse sections using markers
        CONFIG_AGENTS=$(echo "$result_text" | sed -n '/---AGENTS_START---/,/---AGENTS_END---/{//d;p}')
        CONFIG_CATEGORIES=$(echo "$result_text" | sed -n '/---CATEGORIES_START---/,/---CATEGORIES_END---/{//d;p}')
        CONFIG_SCORING=$(echo "$result_text" | sed -n '/---SCORING_START---/,/---SCORING_END---/{//d;p}')
        CONFIG_KEY_FILES=$(echo "$result_text" | sed -n '/---KEY_FILES_START---/,/---KEY_FILES_END---/{//d;p}')
        CONFIG_PROJECT_SUMMARY=$(echo "$result_text" | sed -n '/---PROJECT_SUMMARY_START---/,/---PROJECT_SUMMARY_END---/{//d;p}')
        CONFIG_FOCUS_CONSTRAINT=$(echo "$result_text" | sed -n '/---FOCUS_CONSTRAINT_START---/,/---FOCUS_CONSTRAINT_END---/{//d;p}')
        CONFIG_NOTES=$(echo "$result_text" | sed -n '/---NOTES_START---/,/---NOTES_END---/{//d;p}')

        # Trim leading/trailing whitespace from each section
        CONFIG_AGENTS=$(echo "$CONFIG_AGENTS" | sed '/^$/d' | sed '1{/^$/d}')
        CONFIG_CATEGORIES=$(echo "$CONFIG_CATEGORIES" | sed '/^[[:space:]]*$/d')
        CONFIG_SCORING=$(echo "$CONFIG_SCORING" | sed '/^[[:space:]]*$/d')
        CONFIG_KEY_FILES=$(echo "$CONFIG_KEY_FILES" | sed '/^[[:space:]]*$/d')
        CONFIG_PROJECT_SUMMARY=$(echo "$CONFIG_PROJECT_SUMMARY" | sed '/^[[:space:]]*$/d')
        CONFIG_FOCUS_CONSTRAINT=$(echo "$CONFIG_FOCUS_CONSTRAINT" | sed '/^[[:space:]]*$/d')
        CONFIG_NOTES=$(echo "$CONFIG_NOTES" | sed '/^[[:space:]]*$/d')

        # Validate we got at least agents and project summary
        if [[ -n "$CONFIG_AGENTS" ]] && echo "$CONFIG_AGENTS" | grep -q "### Agent:"; then
            enable_log "INFO" "Context-aware configuration generated successfully"
            return 0
        fi
    fi

    rm -f "$output_file"

    enable_log "WARN" "Could not generate context-aware config, using generic defaults"
    return 1
}

# =============================================================================
# IDEATION MODE - AGENT GENERATION
# =============================================================================

# _generate_generic_agents - Generate generic fallback agents
#
# Parameters:
#   $1 (count) - Number of agents to generate (default: 3)
#
# Outputs to stdout: Markdown-formatted agent descriptions
#
_generate_generic_agents() {
    local count="${1:-3}"
    local agents=()

    agents+=("### Agent: Domain Innovation Expert
**Expertise:** Core domain knowledge and best practices
**Perspective:** Prioritizes solving real user problems with proven patterns
**Focus Areas:** Feature improvements, workflow optimization, user pain points")

    agents+=("### Agent: Systems Architecture Expert
**Expertise:** Software architecture, scalability, technical design
**Perspective:** Prioritizes maintainability, performance, and clean abstractions
**Focus Areas:** Architecture improvements, technical debt, system design")

    agents+=("### Agent: User Experience Expert
**Expertise:** UX design, accessibility, user research
**Perspective:** Prioritizes user satisfaction, ease of use, and adoption
**Focus Areas:** Interface improvements, onboarding, discoverability")

    agents+=("### Agent: Business Strategy Expert
**Expertise:** Market analysis, competitive positioning, product strategy
**Perspective:** Prioritizes business value, market fit, and growth potential
**Focus Areas:** Feature prioritization, monetization, competitive advantages")

    agents+=("### Agent: Quality Assurance Expert
**Expertise:** Testing methodologies, reliability engineering, edge cases
**Perspective:** Prioritizes correctness, robustness, and comprehensive coverage
**Focus Areas:** Test coverage, error handling, edge cases, regression prevention")

    agents+=("### Agent: Security & Compliance Expert
**Expertise:** Application security, data protection, compliance standards
**Perspective:** Prioritizes security posture, data privacy, and regulatory compliance
**Focus Areas:** Vulnerability assessment, access control, audit logging")

    agents+=("### Agent: DevOps & Infrastructure Expert
**Expertise:** CI/CD pipelines, cloud infrastructure, deployment automation
**Perspective:** Prioritizes reliability, observability, and deployment velocity
**Focus Areas:** Build optimization, monitoring, infrastructure as code")

    agents+=("### Agent: Data & Analytics Expert
**Expertise:** Data modeling, analytics pipelines, insights generation
**Perspective:** Prioritizes data-driven decisions and measurable outcomes
**Focus Areas:** Metrics, dashboards, data quality, reporting")

    agents+=("### Agent: Performance Engineering Expert
**Expertise:** Performance profiling, optimization, resource efficiency
**Perspective:** Prioritizes speed, efficiency, and resource utilization
**Focus Areas:** Latency reduction, memory optimization, caching strategies")

    agents+=("### Agent: Documentation & Developer Experience Expert
**Expertise:** Technical writing, API design, developer tooling
**Perspective:** Prioritizes clarity, discoverability, and developer productivity
**Focus Areas:** API docs, tutorials, error messages, developer tools")

    # Output only the requested number of agents
    local i=0
    for agent in "${agents[@]}"; do
        if [[ $i -ge $count ]]; then
            break
        fi
        if [[ $i -gt 0 ]]; then
            echo ""
            echo "---"
            echo ""
        fi
        echo "$agent"
        i=$((i + 1))
    done
}

# _generate_agents_from_roles - Generate agent descriptions from user-provided role names
#
# Parameters:
#   $1 (roles) - Comma-separated role names (e.g., "Data Analyst,Data Engineer,Chief Data Officer")
#
# Outputs to stdout: Markdown-formatted agent descriptions
#
_generate_agents_from_roles() {
    local roles_str="$1"
    local first=true

    IFS=',' read -ra roles <<< "$roles_str"
    for role in "${roles[@]}"; do
        # Trim whitespace
        role=$(echo "$role" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ -z "$role" ]]; then
            continue
        fi
        if [[ "$first" != "true" ]]; then
            echo ""
            echo "---"
            echo ""
        fi
        cat << ROLEEOF
### Agent: ${role}
**Expertise:** ${role} domain knowledge and methodologies
**Perspective:** Prioritizes improvements from the ${role} viewpoint
**Focus Areas:** Enhancements, optimizations, and innovations in the ${role} domain
ROLEEOF
        first=false
    done
}

# generate_domain_agents - Use Claude Code CLI to generate domain-specific agent descriptions
#
# Parameters:
#   $1 (subject) - Project subject/domain description
#   $2 (project_type) - Project type (for context)
#   $3 (count) - Number of agents to generate (default: 3)
#
# Outputs to stdout: Markdown-formatted agent descriptions
#
# Returns:
#   0 on success
#   1 on fallback to generic agents
#
generate_domain_agents() {
    local subject="$1"
    local project_type="${2:-unknown}"
    local count="${3:-3}"

    if [[ -z "$subject" ]]; then
        _generate_generic_agents "$count"
        return 1
    fi

    # Try to call Claude Code CLI for intelligent agent generation
    local prompt_file output_file stderr_file
    prompt_file=$(mktemp)
    output_file=$(mktemp)
    stderr_file=$(mktemp)

    cat > "$prompt_file" << AGENTPROMPTEOF
Generate exactly ${count} domain-specific expert agent personas for a multi-agent ideation system.

Project subject: ${subject}
Project type: ${project_type}

For each agent, provide:
1. A short role name (2-4 words, e.g., "Data Analytics Expert")
2. Their domain expertise (1 sentence)
3. Their perspective/bias - what they prioritize (1 sentence)
4. Focus areas - types of improvements they would suggest (comma-separated list)

Output ONLY in this exact markdown format (no additional text before or after):

### Agent: [Role Name]
**Expertise:** [one sentence about their expertise]
**Perspective:** [one sentence about what they prioritize]
**Focus Areas:** [comma-separated list of focus areas]

---

Repeat the above format for each agent. Use --- as separator between agents.
AGENTPROMPTEOF

    local cli_exit_code=0
    local claude_cmd="claude"

    if command -v "$claude_cmd" &>/dev/null; then
        # Modern CLI invocation (same pattern as korero_import.sh)
        if "$claude_cmd" --print --output-format json < "$prompt_file" > "$output_file" 2> "$stderr_file"; then
            cli_exit_code=0
        else
            cli_exit_code=$?
        fi
    else
        cli_exit_code=1
    fi

    rm -f "$prompt_file" "$stderr_file"

    if [[ $cli_exit_code -eq 0 && -s "$output_file" ]]; then
        # Try to extract result from JSON response
        local result_text=""
        if command -v jq &>/dev/null; then
            result_text=$(jq -r '.result // .' "$output_file" 2>/dev/null)
        fi

        # If jq failed or returned null, try raw content
        if [[ -z "$result_text" || "$result_text" == "null" ]]; then
            result_text=$(cat "$output_file")
        fi

        rm -f "$output_file"

        # Verify it looks like agent markdown (contains ### Agent:)
        if echo "$result_text" | grep -q "### Agent:"; then
            echo "$result_text"
            return 0
        fi
    fi

    rm -f "$output_file"

    # Fallback to generic agents
    enable_log "WARN" "Could not auto-generate agents, using generic defaults"
    _generate_generic_agents "$count"
    return 1
}

# =============================================================================
# IDEATION MODE - TEMPLATE GENERATION
# =============================================================================

# generate_ideation_prompt_md - Generate PROMPT.md for multi-agent ideation mode
#
# Parameters:
#   $1 (project_name) - Project name
#   $2 (project_type) - Project type
#   $3 (mode) - "idea" or "coding"
#   $4 (subject) - Project subject/description
#
# Outputs to stdout
#
generate_ideation_prompt_md() {
    local project_name="${1:-$(basename "$(pwd)")}"
    local project_type="${2:-unknown}"
    local mode="${3:-coding}"
    local subject="${4:-}"
    local agent_count="${5:-3}"
    local max_loops="${6:-continuous}"

    # Read CONFIG_* globals set by generate_context_aware_config()
    local project_summary="${CONFIG_PROJECT_SUMMARY:-}"
    local agents_config="${CONFIG_AGENTS:-}"
    local categories_config="${CONFIG_CATEGORIES:-}"
    local scoring_config="${CONFIG_SCORING:-}"
    local key_files_config="${CONFIG_KEY_FILES:-}"
    local focus_constraint="${CONFIG_FOCUS_CONSTRAINT:-}"
    local notes_config="${CONFIG_NOTES:-}"

    # Calculate total agent count (domain + 3 evaluators)
    local total_agents=$(( agent_count + 3 ))

    # Mode-specific sections
    local mode_mission=""
    local mode_constraint=""
    local implementation_section=""
    local idea_mode_no_implementation=""
    local loop_display="${max_loops}"

    if [[ "$mode" == "idea" ]]; then
        mode_mission="Each loop produces exactly ONE best idea through a multi-phase debate process. You do NOT implement anything. You only generate, debate, and document ideas."
        mode_constraint="**IDEA GENERATION ONLY** — No code changes, no file edits, no tests, no implementation."
        idea_mode_no_implementation="Ralph must NOT create, edit, or delete any project source files. Pure ideation only. However, Ralph MUST write to \`.korero/IDEAS.md\` and \`.korero/fix_plan.md\` to persist winning ideas — these are the only files that should be modified."
    else
        mode_mission="Each loop produces exactly ONE best idea through a multi-phase debate process, then implements it with code changes and a git commit."
        mode_constraint="**IDEATION + IMPLEMENTATION** — Generate the best idea through debate, then implement it."
    fi

    # Build context section
    local context_section=""
    if [[ -n "$project_summary" ]]; then
        context_section="${project_summary}"
    else
        context_section="You are Korero, orchestrating a **${total_agents}-person AI agent team** that generates improvement ideas for the **${project_name}** project through structured debate."
    fi

    # Build focus areas section
    local focus_section=""
    if [[ -n "$focus_constraint" ]]; then
        focus_section="
**FOCUS AREAS:**
${focus_constraint}"
    fi

    # Build agent listing for PROMPT.md
    local agent_listing=""
    if [[ -n "$agents_config" ]]; then
        agent_listing="${agents_config}"
    else
        agent_listing="Read AGENT.md for the full list of ${agent_count} domain expert agents and their specializations."
    fi

    # Build categories section
    local categories_section=""
    if [[ -n "$categories_config" ]]; then
        categories_section="## Idea Categories (for classification)

${categories_config}"
    else
        categories_section="## Idea Categories
Classify each idea by the most relevant area of the project it targets."
    fi

    # Build scoring section
    local scoring_section=""
    if [[ -n "$scoring_config" ]]; then
        scoring_section="## Scoring Criteria (used by Idea Orchestrator for final selection)

${scoring_config}"
    else
        scoring_section="## Scoring Criteria (used by Idea Orchestrator for final selection)

| Criterion | Weight | Description |
|-----------|--------|-------------|
| User Impact | 30% | How much does this improve the user experience? |
| Feature Value | 25% | Does this add a genuinely new capability? |
| Technical Feasibility | 20% | Can it be built with the current stack? |
| Adoption Likelihood | 15% | Will users discover and use this? |
| Non-Duplication | 10% | Is it different from prior winning ideas? |"
    fi

    # Build key files section
    local key_files_section=""
    if [[ -n "$key_files_config" ]]; then
        key_files_section="## Key Files Reference (for agents to cite in their proposals)

${key_files_config}"
    fi

    # Build notes section
    local notes_section=""
    if [[ -n "$notes_config" ]]; then
        notes_section="## Project-Specific Notes

${notes_config}"
    fi

    # Build implementation section for coding mode
    if [[ "$mode" == "coding" ]]; then
        implementation_section='
### Phase 3b: Implementation (Coding Mode)

After the winning idea is documented in Phase 4:

1. **Plan** the implementation approach for the winning idea
2. **Implement** the changes following project best practices
3. **Write tests** for the new functionality
4. **Update documentation** as needed
5. **Create a git commit** with a descriptive conventional commit message
6. **Update fix_plan.md** - mark completed items and add new tasks if discovered

### Build & Run
See AGENT.md for build, test, and run instructions.'
    fi

    # Build anti-repetition rules based on max_loops
    local anti_repetition=""
    if [[ "$max_loops" != "continuous" ]] && [[ "$max_loops" -gt 5 ]]; then
        local quarter=$(( max_loops / 4 ))
        local half=$(( max_loops / 2 ))
        local three_quarter=$(( max_loops * 3 / 4 ))
        anti_repetition="## Anti-Repetition Rules

Before proposing or selecting ideas in each loop, review ALL prior winning ideas.
An idea is considered a DUPLICATE if:
- It targets the same file AND the same function as a prior winner
- It solves the same user problem as a prior winner
- It is a minor variation of a prior winner

To ensure diversity:
- Loops 1-${quarter}: No category restrictions (natural exploration)
- Loops $((quarter + 1))-${half}: At least 3 different categories must be represented among winners
- Loops $((half + 1))-${three_quarter}: No category can have more than 3 total winners
- Loops $((three_quarter + 1))-${max_loops}: Prioritize categories with 0-1 winners"
    else
        anti_repetition="## Anti-Repetition Rules

Before proposing or selecting ideas in each loop, review ALL prior winning ideas.
An idea is considered a DUPLICATE if:
- It targets the same file AND the same function as a prior winner
- It solves the same user problem as a prior winner
- It is a minor variation of a prior winner

Ensure category diversity across loops. Avoid repeating the same category more than 3 times."
    fi

    # Output the full PROMPT.md
    cat << IDEATIONEOF
# Korero Multi-Agent Idea Generation System

## Context
${context_section}

${mode_constraint}

**Your mission:** Generate ${loop_display} winning improvement ideas across ${loop_display} loops.
${mode_mission}
${focus_section}

---

## The ${total_agents}-Agent Team

### Idea Generators (${agent_count} agents — participate in Phase 1 and Phase 3)

${agent_listing}

### Evaluators (3 agents — participate in Phase 2 and Phase 3)

$((agent_count + 1)). **Devil's Advocate** — Pokes holes. Finds risks, scope creep, hidden complexity, low adoption risk.
    Asks: "Will users actually use this? How often? Is this solving a real pain point or a hypothetical one?
    Could this confuse existing users? Is the usability gain worth the added complexity?"
    Scores each idea on:
    - User Demand (1-5, higher = more likely to be used daily)
    - Usability Risk (1-5, higher = more likely to confuse existing users)
    - Complexity Creep (1-5, higher = worse)
    - Verdict: STRONG / MODERATE / WEAK

$((agent_count + 2)). **Technical Feasibility Agent** — Assesses implementation against project stack.
    Asks: "How hard is this to build? Does it fit the current architecture? What are the dependencies?
    Can we ship a useful v1 of this feature in a reasonable sprint?"
    Scores each idea on:
    - Implementation Effort (S/M/L/XL)
    - Architecture Fit (1-5, higher = better fit)
    - Breaking Change Risk (Low/Medium/High)
    - Verdict: FEASIBLE / CHALLENGING / IMPRACTICAL

$((agent_count + 3)). **Idea Orchestrator** — Synthesizer and final decision-maker. Weighs all arguments.
    Selects the single best idea based on the scoring criteria below.
    Strongly favors ideas that are immediately noticeable to users over invisible backend improvements.

---

## Per-Loop Workflow (4 Phases)

### Phase 1: Idea Generation (Independent Proposals)
Each of the ${agent_count} idea generator agents independently proposes 1-2 improvement ideas.
Present each as:

\`\`\`
**[Agent Name] proposes:** [Idea Title]
Type: [Usability Improvement | New Feature]
Category: [from categories list below]
Brief: [2-3 sentence description of what the user sees/does differently]
\`\`\`

Total: ${agent_count}-$((agent_count * 2)) raw ideas per loop.

### Phase 2: Evaluation (Evaluator Review)
The 3 evaluators review ALL ideas from Phase 1:

**Devil's Advocate** scores each idea on User Demand, Usability Risk, Complexity Creep.
**Technical Feasibility Agent** scores each idea on Effort, Architecture Fit, Breaking Change Risk.
**Idea Orchestrator** provides initial ranking of top 3-5 ideas with rationale.

### Phase 3: Debate (Back-and-forth)
Structured 2-round debate:

**Round 1 — Defenders respond:**
The agents who proposed the top 3-5 ideas (per Orchestrator's ranking) each defend their idea
against the evaluators' critiques. They can:
- Address specific Devil's Advocate concerns
- Propose scope reductions to address feasibility concerns
- Cite specific files/functions in the codebase that support feasibility
- Strengthen the value proposition

**Round 2 — Evaluators counter:**
Evaluators respond to the defenses. The Idea Orchestrator announces the FINAL WINNER
with clear justification for why this idea beat the alternatives.

### Phase 4: Winning Idea Documentation (CRITICAL — YOU MUST WRITE TO FILES)
The winning idea is documented in full detail using the output format below.
**You MUST perform ALL of these file writes at the end of each loop:**

1. **APPEND the full winning idea to \`.korero/IDEAS.md\`** — This is the permanent record.
   Use the output format below. Append it to the end of the file (do not overwrite existing ideas).

2. **UPDATE the Winning Ideas Tracker table in \`.korero/fix_plan.md\`** — Fill in the row for
   the current loop number with the winner's title, type, category, and proposing agent.
   Change Status from "Pending" to "Complete".

3. **UPDATE the Category Coverage table in \`.korero/fix_plan.md\`** — Increment the count for
   the winning category and add the loop number.

4. **UPDATE the Type Balance table in \`.korero/fix_plan.md\`** — Increment the count for
   the winning type (Usability Improvement or New Feature).

5. **CHECK OFF the phase checkboxes in \`.korero/fix_plan.md\`** — Mark all 5 checkboxes
   for the current loop as \`[x]\`.

If you do not write to these files, the ideas are LOST. This is the most important step.
${implementation_section}

---

## Winning Idea Output Format

For each loop, document the winner as:

\`\`\`
═══════════════════════════════════════════════════════════
LOOP [N] WINNING IDEA
═══════════════════════════════════════════════════════════

**Title:** [Idea Title]
**Type:** [Usability Improvement | New Feature]
**Category:** [from categories list]
**Proposed by:** [Agent Name]
**Loop:** [N] of ${loop_display}

### Description
[3-5 paragraph detailed description of the idea, what it does, and how it works]

### Implementation Instructions
Step-by-step guide for a developer to implement this:
1. [Step with specific file paths, function names, and code patterns from the codebase]
2. [Step...]
3. [Step...]
...

### Value Proposition
**Business Value:**
- [Bullet point with concrete benefit]
- [Bullet point...]

**Technical Value:**
- [Bullet point with concrete benefit]
- [Bullet point...]

**User Impact:**
- [Who benefits and how]

### Evaluator Feedback Summary
**Devil's Advocate:** [2-3 sentence summary of concerns and how they were addressed]
**Technical Feasibility:** [2-3 sentence summary of implementation assessment]
**Idea Orchestrator:** [2-3 sentence summary of why this idea won]

### Files Most Likely Affected
- \`path/to/file\` — [what changes]
- \`path/to/file\` — [what changes]

═══════════════════════════════════════════════════════════
\`\`\`

### Minority Opinions (REQUIRED)

After the winning idea output, document 2-3 runner-up ideas that were NOT selected.
These preserve valuable insights for future iterations and prevent revisiting rejected paths.

For EACH runner-up, output in this format:

\`\`\`
---KORERO_MINORITY_OPINION---
TITLE: [one-line title]
PROPOSED_BY: [agent name]
CATEGORY: [category]
REJECTION_RATIONALE: [1-2 sentences on why it was not selected]
CORE_INSIGHT: [the valuable kernel of the idea worth preserving]
RECONSIDER_WHEN: [conditions under which this idea should be revisited]
---END_KORERO_MINORITY_OPINION---
\`\`\`

**Important:** Before proposing ideas in Phase 1, review any previous minority opinions
in the .korero/ideas/ directory. Do NOT re-propose ideas that were already rejected
unless the conditions in RECONSIDER_WHEN are now met.
${implementation_section}

## Status Reporting (CRITICAL)

At the end of EACH LOOP, include this status block:

\`\`\`
---KORERO_STATUS---
STATUS: IN_PROGRESS | COMPLETE
LOOP: [N] of ${loop_display}
PHASE_COMPLETED: GENERATION | EVALUATION | DEBATE | DOCUMENTATION
WINNING_IDEA: [Title of winning idea]
WINNING_TYPE: [Usability Improvement | New Feature]
WINNING_CATEGORY: [Category]
WINNING_AGENT: [Agent name who proposed it]
CATEGORIES_COVERED: [comma-separated list of unique categories among all winners so far]
IDEAS_GENERATED_THIS_LOOP: [number of raw ideas in Phase 1]
PRIOR_WINNERS: [comma-separated titles of all prior winning ideas]
EXIT_SIGNAL: false | true
RECOMMENDATION: [What the next loop should focus on for diversity]
---END_KORERO_STATUS---
\`\`\`

### EXIT_SIGNAL Guidelines
- **Idea mode:** Set EXIT_SIGNAL to \`true\` only when you genuinely cannot think of any more meaningful improvements. This is rare - there is almost always room for improvement.
- **Coding mode:** Set EXIT_SIGNAL to \`true\` only when all fix_plan.md items are done AND no more meaningful improvements can be found through ideation.
- **Default:** Keep EXIT_SIGNAL \`false\` - the loop should continue running.

---

## Current Task
Execute the next uncompleted loop (check fix_plan.md to see which loop is next).
Follow the 4-phase workflow above. Begin with Phase 1.

**REMINDER:** At the end of Phase 4 you MUST:
- APPEND the winning idea to \`.korero/IDEAS.md\`
- UPDATE the tracker, category, and type tables in \`.korero/fix_plan.md\`
- CHECK OFF the checkboxes for the completed loop in \`.korero/fix_plan.md\`
If IDEAS.md is not updated, the idea is lost and the loop was wasted.
IDEATIONEOF
}

# generate_ideation_agent_md - Generate AGENT.md with agent personas
#
# Parameters:
#   $1 (domain_agents) - Domain agent descriptions (markdown)
#   $2 (build_cmd) - Build command (for coding mode)
#   $3 (test_cmd) - Test command
#   $4 (run_cmd) - Run command
#   $5 (mode) - "idea" or "coding"
#   $6 (agent_count) - Number of domain agents
#   $7 (max_loops) - Maximum loops
#   $8 (project_name) - Project name
#
# Reads CONFIG_* globals set by generate_context_aware_config()
# Outputs to stdout
#
generate_ideation_agent_md() {
    local domain_agents="${1:-}"
    local build_cmd="${2:-echo 'No build command configured'}"
    local test_cmd="${3:-echo 'No test command configured'}"
    local run_cmd="${4:-echo 'No run command configured'}"
    local mode="${5:-coding}"
    local agent_count="${6:-3}"
    local max_loops="${7:-continuous}"
    local project_name="${8:-$(basename "$(pwd)")}"

    # Read CONFIG_* globals
    local focus_constraint="${CONFIG_FOCUS_CONSTRAINT:-}"
    local scoring_config="${CONFIG_SCORING:-}"
    local notes_config="${CONFIG_NOTES:-}"

    local total_agents=$(( agent_count + 3 ))

    # Mode description
    local mode_description=""
    local build_section=""
    if [[ "$mode" == "idea" ]]; then
        mode_description="**IDEA GENERATION ONLY** — No code changes, no file edits, no tests, no implementation.
Korero operates as a ${total_agents}-agent debate team generating improvement ideas for ${project_name}."
        build_section="
## Build Instructions

\`\`\`bash
# No build — this is an idea generation run, not a code change run.
echo 'Idea generation mode — no build required'
\`\`\`

## Test Instructions

\`\`\`bash
# No tests — this is an idea generation run.
echo 'Idea generation mode — no tests required'
\`\`\`

## Run Instructions

\`\`\`bash
# No run — this is an idea generation run.
echo 'Idea generation mode — no run required'
\`\`\`"
    else
        mode_description="**IDEATION + IMPLEMENTATION** — Generate the best idea through ${total_agents}-agent debate, then implement it with code changes and a git commit."
        build_section="
## Build Instructions

\`\`\`bash
# Build the project
${build_cmd}
\`\`\`

## Test Instructions

\`\`\`bash
# Run tests
${test_cmd}
\`\`\`

## Run Instructions

\`\`\`bash
# Start/run the project
${run_cmd}
\`\`\`"
    fi

    # Focus section
    local focus_section=""
    if [[ -n "$focus_constraint" ]]; then
        focus_section="## Focus

${focus_constraint}"
    fi

    # Scoring section
    local scoring_section=""
    if [[ -n "$scoring_config" ]]; then
        scoring_section="## Scoring Criteria (used by Idea Orchestrator for final selection)

${scoring_config}"
    else
        scoring_section="## Scoring Criteria (used by Idea Orchestrator for final selection)

| Criterion | Weight | Description |
|-----------|--------|-------------|
| User Impact | 30% | How much does this improve the user experience? |
| Feature Value | 25% | Does this add a genuinely new capability? |
| Technical Feasibility | 20% | Can it be built with the current stack? |
| Adoption Likelihood | 15% | Will users discover and use this? |
| Non-Duplication | 10% | Is it different from prior winning ideas? |"
    fi

    # Notes section
    local notes_section=""
    if [[ -n "$notes_config" ]]; then
        notes_section="## Notes

${notes_config}"
    else
        notes_section="## Notes
- Korero must read the codebase thoroughly before each loop to ground ideas in reality
- Ideas should reference specific files and functions in their proposals
- Every idea must answer: \"What does the user see or do differently?\"
- Aim for a healthy mix of idea types across all loops
- Domain expert agents are generated based on the project subject
- The 3 mandatory evaluation agents always participate in every debate
- You can edit this file to add, remove, or modify agent descriptions
- To regenerate agents, run \`korero-enable --force\`"
    fi

    # No-implementation rule for idea mode
    local idea_mode_rule=""
    if [[ "$mode" == "idea" ]]; then
        idea_mode_rule="6. **No Implementation:** Korero must NOT create, edit, or delete any project source files. Pure ideation only. However, Korero MUST write to \`.korero/IDEAS.md\` and \`.korero/fix_plan.md\` to persist winning ideas — these are the only files that should be modified."
    else
        idea_mode_rule="6. **Implementation:** After documenting the winning idea, implement it with code changes, tests, and a git commit."
    fi

    cat << AGENTEOF
# Korero Agent Configuration — Multi-Agent Idea Generation

## Mode
${mode_description}

${focus_section}

## Loop Configuration
- **Total Loops:** ${max_loops}
- **Output per Loop:** Exactly 1 winning idea (fully documented)
- **Total Output:** ${max_loops} winning ideas
${build_section}

## Agent Team (${total_agents} members)

### Idea Generators (${agent_count})

${domain_agents}

### Evaluators (3)

| # | Agent | Role | Evaluation Focus |
|---|-------|------|-----------------|
| $((agent_count + 1)) | Devil's Advocate | Critic | User adoption likelihood, usability risk, complexity creep |
| $((agent_count + 2)) | Technical Feasibility Agent | Assessor | Effort sizing, architecture fit, breaking change risk |
| $((agent_count + 3)) | Idea Orchestrator | Decision-maker | Final ranking using weighted scoring criteria |

## Debate Rules

1. **Independence:** In Phase 1, each generator proposes ideas WITHOUT seeing other generators' ideas.
2. **Transparency:** In Phase 2, evaluators must score EVERY idea — no skipping.
3. **Defense:** In Phase 3, only the top 3-5 ideas (per Orchestrator) proceed to debate.
4. **Finality:** The Idea Orchestrator's Phase 3 decision is FINAL. No appeals.
5. **Specificity:** All ideas must reference actual files, functions, or patterns from the codebase.
${idea_mode_rule}
7. **One Winner:** Exactly one idea wins per loop. No ties. No "honorable mentions."
8. **Anti-Repetition:** Ideas materially similar to prior winners are automatically disqualified.

${scoring_section}

## Output Location (CRITICAL — MUST WRITE TO FILES)
Korero MUST write winning ideas to **two files** at the end of every loop:

1. **\`.korero/IDEAS.md\`** — APPEND the full winning idea write-up (description, implementation
   instructions, value proposition, evaluator feedback, affected files). This is the permanent
   record. Never overwrite — always append to the end.

2. **\`.korero/fix_plan.md\`** — UPDATE the tracker table row, category coverage table, type
   balance table, and check off the phase checkboxes for the completed loop.

**If you do not write to these files, the ideas are LOST and the loop counts for nothing.**

${notes_section}
AGENTEOF
}

# generate_ideation_fix_plan_md - Generate fix_plan.md for ideation modes
#
# Parameters:
#   $1 (mode) - "idea" or "coding"
#   $2 (tasks) - Tasks to include (for coding mode)
#   $3 (project_name) - Project name
#   $4 (agent_count) - Number of domain agents
#   $5 (max_loops) - Maximum loops
#
# Reads CONFIG_* globals set by generate_context_aware_config()
# Outputs to stdout
#
generate_ideation_fix_plan_md() {
    local mode="${1:-coding}"
    local tasks="${2:-}"
    local project_name="${3:-$(basename "$(pwd)")}"
    local agent_count="${4:-3}"
    local max_loops="${5:-continuous}"

    # Read CONFIG_* globals
    local categories_config="${CONFIG_CATEGORIES:-}"
    local focus_constraint="${CONFIG_FOCUS_CONSTRAINT:-}"

    local total_agents=$(( agent_count + 3 ))

    # For coding mode without ideation, fall back to standard fix_plan
    if [[ "$mode" != "idea" && "$mode" != "coding" ]]; then
        generate_fix_plan_md "$tasks"
        return
    fi

    # For continuous mode, generate simpler plan
    if [[ "$max_loops" == "continuous" ]]; then
        cat << CONTFIXPLANEOF
# Korero Idea Generation Plan — Continuous

## Mission
Generate winning improvements for ${project_name} through ${total_agents}-agent debate.
Each loop runs 4 phases: Generation → Evaluation → Debate → Documentation.

## Winning Ideas Tracker

| Loop | Winner | Type | Category | Proposed By | Status |
|------|--------|------|----------|-------------|--------|
| (Updated automatically each loop) | — | — | — | — | — |

## Notes
- Each loop produces exactly one winning idea through structured debate
- Winning ideas are appended to .korero/IDEAS.md
- This tracker table is updated at the end of each loop's Phase 4
- Review IDEAS.md periodically to identify themes and priorities
CONTFIXPLANEOF
        return
    fi

    # Generate the full tracker-based fix_plan for numbered loops

    # Build mission description
    local mission=""
    if [[ -n "$focus_constraint" ]]; then
        mission="Generate ${max_loops} winning improvements for ${project_name}
through ${total_agents}-agent debate. Each loop runs 4 phases: Generation → Evaluation → Debate → Documentation.

${focus_constraint}"
    else
        mission="Generate ${max_loops} winning improvements for ${project_name}
through ${total_agents}-agent debate. Each loop runs 4 phases: Generation → Evaluation → Debate → Documentation."
    fi

    # Build Winning Ideas Tracker table rows
    local tracker_rows=""
    local i
    for (( i=1; i<=max_loops; i++ )); do
        tracker_rows="${tracker_rows}| ${i} | — | — | — | — | Pending |
"
    done

    # Build Category Coverage table
    local category_table=""
    if [[ -n "$categories_config" ]]; then
        # Parse categories from CONFIG_CATEGORIES (each line starting with - ** or - )
        # Extract category names and build table rows
        category_table="## Category Coverage

| Category | Count | Loops |
|----------|-------|-------|
"
        while IFS= read -r line; do
            # Extract category name from lines like "- **Category Name** — description"
            # or "- Category Name — description" or "- **Category Name**"
            local cat_name=""
            if [[ "$line" =~ ^-[[:space:]]*\*\*([^*]+)\*\* ]]; then
                cat_name="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^-[[:space:]]*([^—–-]+) ]]; then
                cat_name="${BASH_REMATCH[1]}"
                cat_name="${cat_name%% }"  # trim trailing space
            fi
            if [[ -n "$cat_name" ]]; then
                category_table="${category_table}| ${cat_name} | 0 | — |
"
            fi
        done <<< "$categories_config"
    else
        category_table="## Category Coverage

| Category | Count | Loops |
|----------|-------|-------|
| (Categories will be populated as ideas are generated) | 0 | — |"
    fi

    # Build Type Balance table
    local half_loops=$(( max_loops / 2 ))
    local type_table="## Type Balance

| Type | Count | Target |
|------|-------|--------|
| Usability Improvement | 0 | ~${half_loops} |
| New Feature | 0 | ~${half_loops} |"

    # Build per-loop checklists with checkpoints
    local loop_checklists=""
    local quarter=$(( max_loops / 4 ))
    local half=$(( max_loops / 2 ))
    local three_quarter=$(( max_loops * 3 / 4 ))

    for (( i=1; i<=max_loops; i++ )); do
        local review_note=""
        if [[ $i -eq 1 ]]; then
            review_note=" (read codebase first)"
        elif [[ $i -le 5 ]]; then
            review_note=" (review Loop 1-$((i-1)) winners first)"
        else
            review_note=" (enforce category diversity — review coverage table)"
        fi

        local checkpoint=""
        if [[ $i -eq $quarter ]]; then
            checkpoint="
- [ ] **Checkpoint:** Verify at least 3 different categories represented in winners so far"
        elif [[ $i -eq $half ]]; then
            checkpoint="
- [ ] **Checkpoint:** Verify healthy type balance (roughly 50/50 usability vs new features)"
        elif [[ $i -eq $three_quarter ]]; then
            checkpoint="
- [ ] **Checkpoint:** Review category coverage — prioritize underrepresented categories"
        elif [[ $i -eq $max_loops ]]; then
            checkpoint="
- [ ] **FINAL CHECKPOINT:** Verify all loops complete, generate summary report"
        fi

        loop_checklists="${loop_checklists}
## Loop ${i}

- [ ] Phase 1: All ${agent_count} generators propose ideas${review_note}
- [ ] Phase 2: All 3 evaluators score and rank ideas
- [ ] Phase 3: Top ideas debated (2 rounds)
- [ ] Phase 4: Winning idea documented in full format
- [ ] Update tracker table above${checkpoint}

**Winning Idea:** _(to be filled)_

---
"
    done

    # Build final deliverable section
    local final_section="## Final Deliverable

When all ${max_loops} loops are complete:
1. Review IDEAS.md for the complete list of winning ideas
2. Verify category coverage table shows diversity
3. Verify type balance is roughly 50/50
4. All ${max_loops} rows in the tracker table show \"Complete\"
5. The winning ideas in IDEAS.md serve as the product improvement backlog"

    # Output the full fix_plan.md
    cat << FIXPLANEOF
# Korero Idea Generation Plan — ${max_loops} Loops

## Mission
${mission}

## Winning Ideas Tracker

| Loop | Winner | Type | Category | Proposed By | Status |
|------|--------|------|----------|-------------|--------|
${tracker_rows}
${category_table}

${type_table}

---
${loop_checklists}
${final_section}
FIXPLANEOF
}

# generate_ideation_ideas_md - Generate IDEAS.md header with project context
#
# Parameters:
#   $1 (project_name) - Project name
#   $2 (max_loops) - Maximum loops
#   $3 (total_agents) - Total agent count
#
# Reads CONFIG_FOCUS_CONSTRAINT global
# Outputs to stdout
#
generate_ideation_ideas_md() {
    local project_name="${1:-$(basename "$(pwd)")}"
    local max_loops="${2:-continuous}"
    local total_agents="${3:-6}"

    local focus_constraint="${CONFIG_FOCUS_CONSTRAINT:-}"

    local focus_description=""
    if [[ -n "$focus_constraint" ]]; then
        # Extract a short description from the focus constraint (first line, strip markdown)
        focus_description=$(echo "$focus_constraint" | head -1 | sed 's/\*\*//g; s/^All ideas MUST be about //; s/^All ideas must be about //')
    else
        focus_description="Improvement Ideas"
    fi

    cat << IDEASEOF
# ${project_name} Winning Ideas — ${focus_description}

This file is the persistent record of all winning ideas from the ${total_agents}-agent debate process.
Korero MUST append each winning idea to this file at the end of Phase 4 in every loop.

**Total planned loops:** ${max_loops}
**Format:** Each winning idea uses the ═══ separator format defined in PROMPT.md.

---

IDEASEOF
}

# =============================================================================
# MAIN ENABLE LOGIC
# =============================================================================

# enable_korero_in_directory - Main function to enable Korero in current directory
#
# Parameters:
#   $1 (options) - JSON-like options string or empty
#       force: true/false - Force overwrite existing
#       skip_tasks: true/false - Skip task import
#       project_name: string - Override project name
#       task_content: string - Pre-imported task content
#
# Returns:
#   0 - Success
#   1 - Error
#   2 - Already enabled (and no force flag)
#
enable_korero_in_directory() {
    local force="${ENABLE_FORCE:-false}"
    local skip_tasks="${ENABLE_SKIP_TASKS:-false}"
    local project_name="${ENABLE_PROJECT_NAME:-}"
    local project_type="${ENABLE_PROJECT_TYPE:-}"
    local task_content="${ENABLE_TASK_CONTENT:-}"
    local korero_mode="${ENABLE_KORERO_MODE:-}"
    local project_subject="${ENABLE_PROJECT_SUBJECT:-}"
    local generated_agents="${ENABLE_GENERATED_AGENTS:-}"
    local agent_count="${ENABLE_AGENT_COUNT:-3}"
    local max_loops="${ENABLE_MAX_LOOPS:-continuous}"
    local focus_override="${ENABLE_FOCUS_CONSTRAINT:-}"

    # Check existing state (use || true to prevent set -e from exiting)
    check_existing_korero || true

    if [[ "$KORERO_STATE" == "complete" && "$force" != "true" ]]; then
        enable_log "INFO" "Korero is already enabled in this project"
        enable_log "INFO" "Use --force to overwrite existing configuration"
        return $ENABLE_ALREADY_ENABLED
    fi

    # Detect project context
    detect_project_context

    # Use detected or provided project name
    if [[ -z "$project_name" ]]; then
        project_name="$DETECTED_PROJECT_NAME"
    fi

    # Use detected or provided project type
    if [[ -n "$project_type" ]]; then
        DETECTED_PROJECT_TYPE="$project_type"
    fi

    enable_log "INFO" "Enabling Korero for: $project_name"
    enable_log "INFO" "Project type: $DETECTED_PROJECT_TYPE"
    if [[ -n "$DETECTED_FRAMEWORK" ]]; then
        enable_log "INFO" "Framework: $DETECTED_FRAMEWORK"
    fi
    if [[ -n "$korero_mode" ]]; then
        enable_log "INFO" "Mode: $korero_mode"
    fi

    # Create directory structure
    if ! create_korero_structure; then
        enable_log "ERROR" "Failed to create .korero/ structure"
        return $ENABLE_ERROR
    fi

    # Generate and create files based on mode
    local prompt_content agent_content fix_plan_content

    if [[ "$korero_mode" == "idea" || "$korero_mode" == "coding" ]]; then
        # Gather project context and generate context-aware config
        # (sets CONFIG_* globals: CONFIG_AGENTS, CONFIG_CATEGORIES, CONFIG_SCORING,
        #  CONFIG_KEY_FILES, CONFIG_PROJECT_SUMMARY, CONFIG_FOCUS_CONSTRAINT, CONFIG_NOTES)
        local project_context=""
        project_context=$(gather_project_context "$(pwd)")

        if [[ -n "$project_subject" && -n "$project_context" ]]; then
            enable_log "INFO" "Generating context-aware configuration..."
            if generate_context_aware_config "$project_subject" "$DETECTED_PROJECT_TYPE" "$agent_count" "$max_loops" "$korero_mode" "$project_context"; then
                enable_log "SUCCESS" "Context-aware configuration generated"
            else
                enable_log "WARN" "Context-aware generation failed, using generic templates"
                # CONFIG_* variables remain empty — template functions use fallbacks
            fi
        fi

        # Apply focus constraint override if provided
        if [[ -n "$focus_override" ]]; then
            CONFIG_FOCUS_CONSTRAINT="$focus_override"
        fi

        # Calculate total agents for template functions
        local total_agents=$(( agent_count + 3 ))

        # Ideation mode: use context-aware ideation templates
        prompt_content=$(generate_ideation_prompt_md "$project_name" "$DETECTED_PROJECT_TYPE" "$korero_mode" "$project_subject" "$agent_count" "$max_loops")
        agent_content=$(generate_ideation_agent_md "$generated_agents" "$DETECTED_BUILD_CMD" "$DETECTED_TEST_CMD" "$DETECTED_RUN_CMD" "$korero_mode" "$agent_count" "$max_loops" "$project_name")
        fix_plan_content=$(generate_ideation_fix_plan_md "$korero_mode" "$task_content" "$project_name" "$agent_count" "$max_loops")

        # Generate IDEAS.md header for ideation modes
        local ideas_content
        ideas_content=$(generate_ideation_ideas_md "$project_name" "$max_loops" "$total_agents")
        safe_create_file ".korero/ideas/IDEAS.md" "$ideas_content"
    else
        # Standard mode: use original templates
        prompt_content=$(generate_prompt_md "$project_name" "$DETECTED_PROJECT_TYPE" "$DETECTED_FRAMEWORK")
        agent_content=$(generate_agent_md "$DETECTED_BUILD_CMD" "$DETECTED_TEST_CMD" "$DETECTED_RUN_CMD")
        fix_plan_content=$(generate_fix_plan_md "$task_content")
    fi

    safe_create_file ".korero/PROMPT.md" "$prompt_content"
    safe_create_file ".korero/AGENT.md" "$agent_content"
    safe_create_file ".korero/fix_plan.md" "$fix_plan_content"

    # Detect task sources for .korerorc
    detect_task_sources
    local task_sources="local"
    if [[ "$DETECTED_BEADS_AVAILABLE" == "true" ]]; then
        task_sources="beads,$task_sources"
    fi
    if [[ "$DETECTED_GITHUB_AVAILABLE" == "true" ]]; then
        task_sources="github,$task_sources"
    fi

    # Generate .korerorc
    local korerorc_content
    korerorc_content=$(generate_korerorc "$project_name" "$DETECTED_PROJECT_TYPE" "$task_sources" "$korero_mode" "$project_subject" "$agent_count" "$max_loops")
    safe_create_file ".korerorc" "$korerorc_content"

    enable_log "SUCCESS" "Korero enabled successfully!"

    return $ENABLE_SUCCESS
}

# Export functions for use in other scripts
export -f enable_log
export -f check_existing_korero
export -f is_korero_enabled
export -f safe_create_file
export -f safe_create_dir
export -f create_korero_structure
export -f detect_project_context
export -f detect_git_info
export -f detect_task_sources
export -f get_templates_dir
export -f generate_prompt_md
export -f generate_agent_md
export -f generate_fix_plan_md
export -f generate_korerorc
export -f _generate_generic_agents
export -f _generate_agents_from_roles
export -f generate_domain_agents
export -f gather_project_context
export -f generate_context_aware_config
export -f generate_ideation_prompt_md
export -f generate_ideation_agent_md
export -f generate_ideation_fix_plan_md
export -f generate_ideation_ideas_md
export -f enable_korero_in_directory
