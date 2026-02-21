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

    local mode_description=""
    local implementation_section=""

    if [[ "$mode" == "idea" ]]; then
        mode_description="You are running a **Continuous Idea Loop**. Your role is to facilitate multi-agent ideation and structured debate. You do NOT implement code, modify files, or make any changes to the project."
    else
        mode_description="You are running a **Continuous Coding Loop**. Your role is to facilitate multi-agent ideation and structured debate, then implement the winning idea with code changes and a git commit."
        implementation_section='
## Phase 3: Implementation (Coding Mode)

After the best idea is selected in Phase 2:

1. **Plan** the implementation approach for the winning idea
2. **Implement** the changes following project best practices
3. **Write tests** for the new functionality
4. **Update documentation** as needed
5. **Create a git commit** with a descriptive conventional commit message
6. **Update fix_plan.md** - mark completed items and add new tasks if discovered

### Build & Run
See AGENT.md for build, test, and run instructions.'
    fi

    cat << IDEATIONEOF
# Korero Multi-Agent Development Instructions

## Context
You are Korero, an autonomous AI agent working on the **${project_name}** project.
${mode_description}

**Project Type:** ${project_type}
**Project Subject:** ${subject}

## Multi-Agent Ideation Protocol

Each loop iteration, you execute a structured multi-agent debate to identify the single best improvement for this project.

### Phase 1: Idea Generation

Read the agent descriptions in AGENT.md. For EACH domain expert agent listed there (do NOT include the mandatory evaluation agents in this phase):

1. **Adopt that agent's persona completely** - think from their expertise and perspective
2. **Review the project's current state** - read key files, understand what exists
3. **Propose ONE specific, actionable improvement** from that agent's perspective
4. **Format each proposal clearly:**

\`\`\`
**[Agent Name] Proposes:** [Title of improvement]
Rationale: [Why this matters from their perspective]
Description: [Specific, actionable description of the improvement]
Expected Impact: [What benefit this would bring]
\`\`\`

### Phase 2: Structured Debate

After all domain agents have proposed their ideas, the three mandatory evaluation agents analyze each proposal through a structured debate.

#### Round 1: Evaluation

For EACH proposed idea, the evaluation agents provide their analysis:

**Devil's Advocate** critiques each proposal:
- What could go wrong with this idea?
- What are the hidden costs, risks, or unintended consequences?
- What assumptions are being made that might not hold?
- Is this solving a real problem or an imagined one?
- Rate: STRONG CONCERN / MINOR CONCERN / ACCEPTABLE

**Technical Feasibility Analyst** assesses each proposal:
- How complex is the implementation? (Simple / Moderate / Complex)
- What dependencies, constraints, or prerequisites exist?
- What is the estimated effort? (Small: hours / Medium: days / Large: weeks)
- Are there simpler alternatives that achieve the same outcome?
- Rate: HIGHLY FEASIBLE / FEASIBLE / CHALLENGING / IMPRACTICAL

**Idea Orchestrator** evaluates all proposals holistically:
- Which ideas have the highest impact-to-effort ratio?
- Are there synergies between proposals that could be combined?
- Which idea best aligns with the project's current needs?
- What is the strategic priority ordering?

#### Round 2: Rebuttal

Each original proposing agent gets ONE rebuttal opportunity:
- Address the Devil's Advocate's concerns directly
- Respond to feasibility questions with specific technical approaches
- Refine or narrow the proposal based on feedback
- Concede points where the criticism is valid

#### Round 3: Final Selection

The **Idea Orchestrator** makes the final decision:
- Synthesize all feedback from Rounds 1 and 2
- Select the SINGLE best idea (or a synthesized combination of compatible ideas)
- Provide clear justification for why this idea won
- State the expected impact and implementation approach

### Winning Idea Output (REQUIRED)

After the debate concludes, output the winning idea in this EXACT format:

\`\`\`
---KORERO_IDEA---
LOOP: [loop number from context]
SELECTED_IDEA: [one-line title of the winning idea]
PROPOSED_BY: [name of the agent who proposed it]
IMPACT: HIGH | MEDIUM | LOW
EFFORT: SMALL | MEDIUM | LARGE
DESCRIPTION: [2-3 sentence description of what to do and why]
JUSTIFICATION: [1-2 sentences on why this idea won the debate]
---END_KORERO_IDEA---
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

At the END of your response, ALWAYS include this status block:

\`\`\`
---KORERO_STATUS---
STATUS: IN_PROGRESS | COMPLETE | BLOCKED
TASKS_COMPLETED_THIS_LOOP: <number>
FILES_MODIFIED: <number>
TESTS_STATUS: PASSING | FAILING | NOT_RUN
WORK_TYPE: IDEATION | IMPLEMENTATION | TESTING | DOCUMENTATION
EXIT_SIGNAL: false | true
RECOMMENDATION: <one line summary of what to do next>
---END_KORERO_STATUS---
\`\`\`

### EXIT_SIGNAL Guidelines
- **Idea mode:** Set EXIT_SIGNAL to \`true\` only when you genuinely cannot think of any more meaningful improvements. This is rare - there is almost always room for improvement.
- **Coding mode:** Set EXIT_SIGNAL to \`true\` only when all fix_plan.md items are done AND no more meaningful improvements can be found through ideation.
- **Default:** Keep EXIT_SIGNAL \`false\` - the loop should continue running.

## Current Task
Read AGENT.md for the agent descriptions, then execute the Multi-Agent Ideation Protocol above.
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
#
# Outputs to stdout
#
generate_ideation_agent_md() {
    local domain_agents="${1:-}"
    local build_cmd="${2:-echo 'No build command configured'}"
    local test_cmd="${3:-echo 'No test command configured'}"
    local run_cmd="${4:-echo 'No run command configured'}"
    local mode="${5:-coding}"

    local build_section=""
    if [[ "$mode" == "coding" ]]; then
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
\`\`\`
"
    fi

    cat << AGENTEOF
# Korero Agent Configuration

## Domain Expert Agents

These agents participate in each ideation round. Each adopts their persona
to propose improvements from their unique perspective.

${domain_agents}

## Mandatory Evaluation Agents

These three agents ALWAYS participate in the debate phase. They evaluate,
challenge, and ultimately select the best idea from each round.

### Agent: Devil's Advocate
**Role:** Challenge every proposal ruthlessly and expose weaknesses
**Perspective:** Assumes the worst case; looks for flaws, hidden costs, and risks
**Key Questions:** What could go wrong? What are we not considering? Is this really worth the effort? What are the hidden dependencies?

---

### Agent: Technical Feasibility Analyst
**Role:** Assess implementation complexity, constraints, and realistic effort
**Perspective:** Practical engineering reality; focused on what is actually achievable
**Key Questions:** How complex is this really? What will break? What is the simplest viable version? What are the technical prerequisites?

---

### Agent: Idea Orchestrator
**Role:** Synthesize feedback, rank proposals, and make the final selection
**Perspective:** Strategic value; focused on highest impact for lowest effort
**Key Questions:** Which idea matters most right now? Can ideas be combined? What gives us the best return on investment?
${build_section}
## Notes
- Domain expert agents are generated based on the project subject
- The 3 mandatory evaluation agents always participate in every debate
- You can edit this file to add, remove, or modify agent descriptions
- To regenerate agents, run \`korero-enable --force\`
AGENTEOF
}

# generate_ideation_fix_plan_md - Generate fix_plan.md for ideation modes
#
# Parameters:
#   $1 (mode) - "idea" or "coding"
#   $2 (tasks) - Tasks to include (for coding mode)
#
# Outputs to stdout
#
generate_ideation_fix_plan_md() {
    local mode="${1:-coding}"
    local tasks="${2:-}"

    if [[ "$mode" == "idea" ]]; then
        cat << 'IDEAFIXPLANEOF'
# Korero Ideation Plan

## Ideation Goals
- [ ] Run multi-agent ideation loops to generate improvement proposals
- [ ] Build a diverse set of ideas across all domain agent perspectives
- [ ] Refine ideas through structured Devil's Advocate and feasibility debate
- [ ] Capture the best ideas from each loop in .korero/ideas/

## Completed Ideas
(Winning ideas from each loop are automatically saved to .korero/ideas/IDEAS.md)

## Notes
- Each loop produces exactly one winning idea through structured debate
- Ideas accumulate in .korero/ideas/IDEAS.md
- Individual loop results stored in .korero/ideas/loop_N_idea.md
- Review IDEAS.md periodically to identify themes and priorities
IDEAFIXPLANEOF
    else
        # Coding mode: use standard fix_plan with imported tasks
        generate_fix_plan_md "$tasks"
    fi
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
        # Ideation mode: use ideation-specific templates
        prompt_content=$(generate_ideation_prompt_md "$project_name" "$DETECTED_PROJECT_TYPE" "$korero_mode" "$project_subject")
        agent_content=$(generate_ideation_agent_md "$generated_agents" "$DETECTED_BUILD_CMD" "$DETECTED_TEST_CMD" "$DETECTED_RUN_CMD" "$korero_mode")
        fix_plan_content=$(generate_ideation_fix_plan_md "$korero_mode" "$task_content")
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
export -f generate_ideation_prompt_md
export -f generate_ideation_agent_md
export -f generate_ideation_fix_plan_md
export -f enable_korero_in_directory
