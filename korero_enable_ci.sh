#!/bin/bash

# Korero Enable CI - Non-Interactive Version for Automation
# Adds Korero configuration with sensible defaults
#
# Usage:
#   korero enable-ci                    # Auto-detect and enable
#   korero enable-ci --from beads       # With specific task source
#   korero enable-ci --json             # Output JSON result
#
# Exit codes:
#   0 - Success: Korero enabled
#   1 - Error: General error
#   2 - Already enabled (use --force to override)
#   3 - Invalid arguments
#   4 - File not found (e.g., PRD file)
#   5 - Dependency missing (e.g., jq for --json)
#
# Version: 0.11.0

set -e

# Get script directory for library loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Try to load libraries from global installation first, then local
KORERO_HOME="${KORERO_HOME:-$HOME/.korero}"
if [[ -f "$KORERO_HOME/lib/enable_core.sh" ]]; then
    LIB_DIR="$KORERO_HOME/lib"
elif [[ -f "$SCRIPT_DIR/lib/enable_core.sh" ]]; then
    LIB_DIR="$SCRIPT_DIR/lib"
else
    echo '{"error": "Cannot find Korero libraries", "code": 1}' >&2
    exit 1
fi

# Disable colors for CI
export ENABLE_USE_COLORS="false"

# Source libraries
source "$LIB_DIR/enable_core.sh"
source "$LIB_DIR/task_sources.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Command line options
FORCE_OVERWRITE=false
TASK_SOURCE=""
PRD_FILE=""
GITHUB_LABEL="korero-task"
PROJECT_NAME=""
PROJECT_TYPE=""
OUTPUT_JSON=false
QUIET=false
SHOW_HELP=false

# Ideation mode options
KORERO_MODE="coding"        # Default to coding mode
PROJECT_SUBJECT=""
AGENT_COUNT=3
MAX_LOOPS="continuous"

# Version
VERSION="0.11.0"

# =============================================================================
# HELP
# =============================================================================

show_help() {
    cat << EOF
Korero Enable CI - Non-Interactive Version for Automation

Usage: korero-enable-ci [OPTIONS]

Options:
    --mode <mode>         Loop mode: coding or idea (default: coding)
    --subject <text>      Project subject for agent generation
    --agents <N>          Number of domain agents (default: 3, max: 10)
    --loops <N>           Max loops: number or "continuous" (default: continuous)
    --from <source>       Import tasks from: beads, github, prd, none
    --prd <file>          PRD file to convert (when --from prd)
    --label <label>       GitHub label filter (default: korero-task)
    --project-name <name> Override detected project name
    --project-type <type> Override detected type (typescript, python, etc.)
    --force               Overwrite existing .korero/ configuration
    --json                Output result as JSON
    --quiet               Suppress non-error output
    -h, --help            Show this help message
    -v, --version         Show version

Exit Codes:
    0 - Success: Korero enabled
    1 - Error: General error
    2 - Already enabled: Use --force to override
    3 - Invalid arguments
    4 - File not found (e.g., PRD file)
    5 - Dependency missing (e.g., jq for --json)

Examples:
    # Auto-detect and enable with defaults (coding mode)
    korero-enable-ci

    # Idea loop for a specific domain
    korero-enable-ci --mode idea --subject "data analysis tool" --agents 4

    # Coding loop with limited iterations
    korero-enable-ci --mode coding --subject "web app" --loops 20

    # Force overwrite and output JSON
    korero-enable-ci --force --json

JSON Output Format:
    {
        "success": true,
        "project_name": "my-project",
        "project_type": "typescript",
        "mode": "coding",
        "agent_count": 3,
        "max_loops": "continuous",
        "files_created": [".korero/PROMPT.md", ...],
        "tasks_imported": 15,
        "message": "Korero enabled successfully"
    }

EOF
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    KORERO_MODE="$2"
                    if [[ "$KORERO_MODE" != "coding" && "$KORERO_MODE" != "idea" ]]; then
                        output_error "--mode must be 'coding' or 'idea'"
                        exit $ENABLE_INVALID_ARGS
                    fi
                    shift 2
                else
                    output_error "--mode requires a value (coding or idea)"
                    exit $ENABLE_INVALID_ARGS
                fi
                ;;
            --subject)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    PROJECT_SUBJECT="$2"
                    shift 2
                else
                    output_error "--subject requires a description"
                    exit $ENABLE_INVALID_ARGS
                fi
                ;;
            --agents)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    AGENT_COUNT="$2"
                    if ! [[ "$AGENT_COUNT" =~ ^[0-9]+$ ]] || [[ "$AGENT_COUNT" -lt 1 ]] || [[ "$AGENT_COUNT" -gt 10 ]]; then
                        output_error "--agents must be a number between 1 and 10"
                        exit $ENABLE_INVALID_ARGS
                    fi
                    shift 2
                else
                    output_error "--agents requires a number (1-10)"
                    exit $ENABLE_INVALID_ARGS
                fi
                ;;
            --loops)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    MAX_LOOPS="$2"
                    if [[ "$MAX_LOOPS" != "continuous" ]] && ! [[ "$MAX_LOOPS" =~ ^[0-9]+$ ]]; then
                        output_error "--loops must be a number or 'continuous'"
                        exit $ENABLE_INVALID_ARGS
                    fi
                    shift 2
                else
                    output_error "--loops requires a value (number or 'continuous')"
                    exit $ENABLE_INVALID_ARGS
                fi
                ;;
            --from)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    TASK_SOURCE="$2"
                    shift 2
                else
                    output_error "--from requires a source (beads, github, prd, none)"
                    exit $ENABLE_INVALID_ARGS
                fi
                ;;
            --prd)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    PRD_FILE="$2"
                    shift 2
                else
                    output_error "--prd requires a file path"
                    exit $ENABLE_INVALID_ARGS
                fi
                ;;
            --label)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    GITHUB_LABEL="$2"
                    shift 2
                else
                    output_error "--label requires a label name"
                    exit $ENABLE_INVALID_ARGS
                fi
                ;;
            --project-name)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    PROJECT_NAME="$2"
                    shift 2
                else
                    output_error "--project-name requires a name"
                    exit $ENABLE_INVALID_ARGS
                fi
                ;;
            --project-type)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    PROJECT_TYPE="$2"
                    shift 2
                else
                    output_error "--project-type requires a type"
                    exit $ENABLE_INVALID_ARGS
                fi
                ;;
            --force)
                FORCE_OVERWRITE=true
                shift
                ;;
            --json)
                if ! command -v jq &>/dev/null; then
                    echo "Error: --json requires jq to be installed" >&2
                    exit $ENABLE_DEPENDENCY_MISSING
                fi
                OUTPUT_JSON=true
                shift
                ;;
            --quiet)
                QUIET=true
                shift
                ;;
            -h|--help)
                SHOW_HELP=true
                shift
                ;;
            -v|--version)
                if [[ "$OUTPUT_JSON" == "true" ]]; then
                    echo "{\"version\": \"$VERSION\"}"
                else
                    echo "korero enable-ci version $VERSION"
                fi
                exit 0
                ;;
            *)
                output_error "Unknown option: $1"
                exit $ENABLE_INVALID_ARGS
                ;;
        esac
    done
}

# =============================================================================
# OUTPUT FUNCTIONS
# =============================================================================

# Track created files for JSON output
declare -a CREATED_FILES=()
TASKS_IMPORTED=0

output_message() {
    if [[ "$QUIET" != "true" && "$OUTPUT_JSON" != "true" ]]; then
        echo "$1"
    fi
}

output_error() {
    if [[ "$OUTPUT_JSON" == "true" ]]; then
        echo "{\"error\": \"$1\", \"code\": 1}" >&2
    else
        echo "Error: $1" >&2
    fi
}

output_success() {
    local project_name="$1"
    local project_type="$2"

    if [[ "$OUTPUT_JSON" == "true" ]]; then
        local files_json
        files_json=$(printf '%s\n' "${CREATED_FILES[@]}" | jq -R . | jq -s .)

        cat << EOF
{
    "success": true,
    "project_name": "$project_name",
    "project_type": "$project_type",
    "mode": "$KORERO_MODE",
    "agent_count": $AGENT_COUNT,
    "max_loops": "$MAX_LOOPS",
    "files_created": $files_json,
    "tasks_imported": $TASKS_IMPORTED,
    "message": "Korero enabled successfully"
}
EOF
    else
        echo "Korero enabled successfully for: $project_name ($project_type)"
        echo "Mode: $KORERO_MODE"
        echo "Domain agents: $AGENT_COUNT"
        echo "Max loops: $MAX_LOOPS"
        echo "Files created: ${#CREATED_FILES[@]}"
        echo "Tasks imported: $TASKS_IMPORTED"
    fi
}

output_already_enabled() {
    if [[ "$OUTPUT_JSON" == "true" ]]; then
        echo '{"success": false, "code": 2, "message": "Korero already enabled. Use --force to override."}'
    else
        echo "Korero is already enabled in this project. Use --force to override."
    fi
}

# =============================================================================
# MAIN LOGIC
# =============================================================================

main() {
    # Parse arguments
    parse_arguments "$@"

    # Show help if requested
    if [[ "$SHOW_HELP" == "true" ]]; then
        show_help
        exit 0
    fi

    output_message "Korero Enable CI - Non-Interactive Mode"
    output_message ""

    # Check existing state (use || true to prevent set -e from exiting)
    check_existing_korero || true
    if [[ "$KORERO_STATE" == "complete" && "$FORCE_OVERWRITE" != "true" ]]; then
        output_already_enabled
        exit $ENABLE_ALREADY_ENABLED
    fi

    # Detect project context
    detect_project_context
    output_message "Detected: $DETECTED_PROJECT_NAME ($DETECTED_PROJECT_TYPE)"

    # Override with CLI options if provided
    if [[ -n "$PROJECT_NAME" ]]; then
        DETECTED_PROJECT_NAME="$PROJECT_NAME"
    fi
    if [[ -n "$PROJECT_TYPE" ]]; then
        DETECTED_PROJECT_TYPE="$PROJECT_TYPE"
    fi

    # Auto-detect task source if not specified
    if [[ -z "$TASK_SOURCE" ]]; then
        detect_task_sources

        if [[ "$DETECTED_BEADS_AVAILABLE" == "true" ]]; then
            TASK_SOURCE="beads"
            output_message "Auto-detected task source: beads"
        elif [[ "$DETECTED_GITHUB_AVAILABLE" == "true" ]]; then
            TASK_SOURCE="github"
            output_message "Auto-detected task source: github"
        elif [[ ${#DETECTED_PRD_FILES[@]} -gt 0 ]]; then
            TASK_SOURCE="prd"
            PRD_FILE="${DETECTED_PRD_FILES[0]}"
            output_message "Auto-detected task source: prd ($PRD_FILE)"
        else
            TASK_SOURCE="none"
            output_message "No task sources detected, using defaults"
        fi
    fi

    # Import tasks
    local imported_tasks=""
    case "$TASK_SOURCE" in
        beads)
            if beads_tasks=$(fetch_beads_tasks 2>/dev/null); then
                imported_tasks="$beads_tasks"
                TASKS_IMPORTED=$(echo "$imported_tasks" | grep -c '^\- \[' || echo "0")
                output_message "Imported $TASKS_IMPORTED tasks from beads"
            fi
            ;;
        github)
            if github_tasks=$(fetch_github_tasks "$GITHUB_LABEL" 2>/dev/null); then
                imported_tasks="$github_tasks"
                TASKS_IMPORTED=$(echo "$imported_tasks" | grep -c '^\- \[' || echo "0")
                output_message "Imported $TASKS_IMPORTED tasks from GitHub"
            fi
            ;;
        prd)
            if [[ -n "$PRD_FILE" && -f "$PRD_FILE" ]]; then
                if prd_tasks=$(extract_prd_tasks "$PRD_FILE" 2>/dev/null); then
                    imported_tasks="$prd_tasks"
                    TASKS_IMPORTED=$(echo "$imported_tasks" | grep -c '^\- \[' || echo "0")
                    output_message "Extracted $TASKS_IMPORTED tasks from PRD"
                fi
            else
                output_error "PRD file not found: $PRD_FILE"
                exit $ENABLE_FILE_NOT_FOUND
            fi
            ;;
        none|"")
            output_message "Skipping task import"
            ;;
        *)
            output_error "Unknown task source: $TASK_SOURCE"
            exit $ENABLE_ERROR
            ;;
    esac

    # Generate domain agents for ideation modes
    local generated_agents=""
    if [[ -n "$PROJECT_SUBJECT" ]]; then
        output_message "Generating domain agents..."
        generated_agents=$(generate_domain_agents "$PROJECT_SUBJECT" "$DETECTED_PROJECT_TYPE" "$AGENT_COUNT" 2>/dev/null)
    else
        generated_agents=$(_generate_generic_agents "$AGENT_COUNT")
    fi

    # Set up enable environment
    export ENABLE_FORCE="$FORCE_OVERWRITE"
    export ENABLE_SKIP_TASKS="false"
    export ENABLE_PROJECT_NAME="$DETECTED_PROJECT_NAME"
    export ENABLE_PROJECT_TYPE="$DETECTED_PROJECT_TYPE"
    export ENABLE_TASK_CONTENT="$imported_tasks"
    export ENABLE_KORERO_MODE="$KORERO_MODE"
    export ENABLE_PROJECT_SUBJECT="$PROJECT_SUBJECT"
    export ENABLE_GENERATED_AGENTS="$generated_agents"
    export ENABLE_AGENT_COUNT="$AGENT_COUNT"
    export ENABLE_MAX_LOOPS="$MAX_LOOPS"

    # Run core enable logic
    output_message ""
    output_message "Creating Korero configuration..."

    # Suppress enable_korero_in_directory output when in JSON mode
    if [[ "$OUTPUT_JSON" == "true" ]]; then
        if ! enable_korero_in_directory >/dev/null 2>&1; then
            output_error "Failed to enable Korero"
            exit $ENABLE_ERROR
        fi
    else
        if ! enable_korero_in_directory; then
            output_error "Failed to enable Korero"
            exit $ENABLE_ERROR
        fi
    fi

    # Track created files
    [[ -f ".korero/PROMPT.md" ]] && CREATED_FILES+=(".korero/PROMPT.md")
    [[ -f ".korero/fix_plan.md" ]] && CREATED_FILES+=(".korero/fix_plan.md")
    [[ -f ".korero/AGENT.md" ]] && CREATED_FILES+=(".korero/AGENT.md")
    [[ -f ".korerorc" ]] && CREATED_FILES+=(".korerorc")

    # Verify required files exist
    if [[ ! -f ".korero/PROMPT.md" ]] || [[ ! -f ".korero/fix_plan.md" ]]; then
        output_error "Required files were not created"
        exit $ENABLE_ERROR
    fi

    # Output success
    output_message ""
    output_success "$DETECTED_PROJECT_NAME" "$DETECTED_PROJECT_TYPE"

    exit $ENABLE_SUCCESS
}

# Run main
main "$@"
