#!/bin/bash

# Korero Enable - Interactive Wizard for Existing Projects
# Adds Korero configuration to an existing codebase
#
# Usage:
#   korero enable              # Interactive wizard
#   korero enable --from beads # With specific task source
#   korero enable --force      # Overwrite existing .korero/
#   korero enable --skip-tasks # Skip task import
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
    echo "Error: Cannot find Korero libraries"
    echo "Please run ./install.sh first or ensure KORERO_HOME is set correctly"
    exit 1
fi

# Source libraries
source "$LIB_DIR/enable_core.sh"
source "$LIB_DIR/wizard_utils.sh"
source "$LIB_DIR/task_sources.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

# Command line options
FORCE_OVERWRITE=false
SKIP_TASKS=false
TASK_SOURCE=""
PRD_FILE=""
GITHUB_LABEL=""
NON_INTERACTIVE=false
SHOW_HELP=false

# Ideation mode options
KORERO_MODE=""           # "coding" or "idea" (empty = ask in wizard)
PROJECT_SUBJECT=""       # Project subject/description
AGENT_COUNT=""           # Number of domain agents (empty = ask in wizard)
AGENT_GEN_METHOD=""      # "auto" or "manual" (empty = ask in wizard)
MANUAL_AGENT_ROLES=""    # Comma-separated roles (for manual agent generation)
MAX_LOOPS=""             # Loop limit (empty = ask in wizard)
GENERATED_AGENTS=""      # Generated agent descriptions (populated during wizard)

# Version
VERSION="0.11.0"

# =============================================================================
# HELP
# =============================================================================

show_help() {
    cat << EOF
Korero Enable - Multi-Agent Ideation & Development System

Usage: korero-enable [OPTIONS]

Options:
    --mode <mode>       Loop mode: coding (ideation + implementation) or idea (ideation only)
    --subject <text>    Project subject/description for agent generation
    --agents <N>        Number of domain agents to generate (default: 3, max: 10)
    --loops <N>         Max loops to run: number or "continuous" (default: continuous)
    --from <source>     Import tasks from: beads, github, prd (coding mode only)
    --prd <file>        PRD file to convert (when --from prd)
    --label <label>     GitHub label filter (when --from github)
    --force             Overwrite existing .korero/ configuration
    --skip-tasks        Skip task import, use default templates
    --non-interactive   Run with defaults (no prompts)
    -h, --help          Show this help message
    -v, --version       Show version

Examples:
    # Interactive wizard (recommended)
    cd my-existing-project
    korero-enable

    # Continuous coding loop for a data analysis tool
    korero-enable --mode coding --subject "data analysis tool" --agents 4

    # Idea-only loop with custom loop limit
    korero-enable --mode idea --subject "web application" --loops 20

    # Force overwrite existing configuration
    korero-enable --force

What this command does:
    1. Detects your project type (TypeScript, Python, etc.)
    2. Asks whether to run a coding loop or idea loop
    3. Generates domain-specific expert agents based on your project
    4. Creates .korero/ configuration with multi-agent debate protocol
    5. Generates PROMPT.md, AGENT.md, fix_plan.md
    6. Creates .korerorc for project-specific settings

This command is:
    - Idempotent: Safe to run multiple times
    - Non-destructive: Never overwrites existing files (unless --force)
    - Project-aware: Detects your language, framework, and build tools

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
                        echo "Error: --mode must be 'coding' or 'idea'" >&2
                        exit $ENABLE_INVALID_ARGS
                    fi
                    shift 2
                else
                    echo "Error: --mode requires a value (coding or idea)" >&2
                    exit $ENABLE_INVALID_ARGS
                fi
                ;;
            --subject)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    PROJECT_SUBJECT="$2"
                    shift 2
                else
                    echo "Error: --subject requires a description" >&2
                    exit $ENABLE_INVALID_ARGS
                fi
                ;;
            --agents)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    AGENT_COUNT="$2"
                    if ! [[ "$AGENT_COUNT" =~ ^[0-9]+$ ]] || [[ "$AGENT_COUNT" -lt 1 ]] || [[ "$AGENT_COUNT" -gt 10 ]]; then
                        echo "Error: --agents must be a number between 1 and 10" >&2
                        exit $ENABLE_INVALID_ARGS
                    fi
                    shift 2
                else
                    echo "Error: --agents requires a number (1-10)" >&2
                    exit $ENABLE_INVALID_ARGS
                fi
                ;;
            --loops)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    MAX_LOOPS="$2"
                    if [[ "$MAX_LOOPS" != "continuous" ]] && ! [[ "$MAX_LOOPS" =~ ^[0-9]+$ ]]; then
                        echo "Error: --loops must be a number or 'continuous'" >&2
                        exit $ENABLE_INVALID_ARGS
                    fi
                    shift 2
                else
                    echo "Error: --loops requires a value (number or 'continuous')" >&2
                    exit $ENABLE_INVALID_ARGS
                fi
                ;;
            --from)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    TASK_SOURCE="$2"
                    shift 2
                else
                    echo "Error: --from requires a source (beads, github, prd)" >&2
                    exit $ENABLE_INVALID_ARGS
                fi
                ;;
            --prd)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    PRD_FILE="$2"
                    shift 2
                else
                    echo "Error: --prd requires a file path" >&2
                    exit $ENABLE_INVALID_ARGS
                fi
                ;;
            --label)
                if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                    GITHUB_LABEL="$2"
                    shift 2
                else
                    echo "Error: --label requires a label name" >&2
                    exit $ENABLE_INVALID_ARGS
                fi
                ;;
            --force)
                FORCE_OVERWRITE=true
                shift
                ;;
            --skip-tasks)
                SKIP_TASKS=true
                shift
                ;;
            --non-interactive)
                NON_INTERACTIVE=true
                shift
                ;;
            -h|--help)
                SHOW_HELP=true
                shift
                ;;
            -v|--version)
                echo "korero enable version $VERSION"
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Use --help for usage information" >&2
                exit $ENABLE_INVALID_ARGS
                ;;
        esac
    done
}

# =============================================================================
# PHASE 1: ENVIRONMENT DETECTION
# =============================================================================

phase_environment_detection() {
    print_header "Environment Detection" "Phase 1 of 7"

    echo "Analyzing your project..."
    echo ""

    # Check for existing Korero setup (use || true to prevent set -e from exiting)
    check_existing_korero || true
    case "$KORERO_STATE" in
        "complete")
            print_detection_result "Korero status" "Already enabled" "true"
            if [[ "$FORCE_OVERWRITE" != "true" ]]; then
                echo ""
                print_warning "Korero is already enabled in this project."
                echo ""
                if [[ "$NON_INTERACTIVE" != "true" ]]; then
                    if ! confirm "Do you want to continue anyway?" "n"; then
                        echo "Exiting. Use --force to overwrite."
                        exit $ENABLE_ALREADY_ENABLED
                    fi
                else
                    echo "Use --force to overwrite existing configuration."
                    exit $ENABLE_ALREADY_ENABLED
                fi
            fi
            ;;
        "partial")
            print_detection_result "Korero status" "Partially configured" "false"
            echo ""
            print_info "Missing files: ${KORERO_MISSING_FILES[*]}"
            echo ""
            ;;
        "none")
            print_detection_result "Korero status" "Not configured" "false"
            ;;
    esac

    # Detect project context
    detect_project_context
    print_detection_result "Project name" "$DETECTED_PROJECT_NAME" "true"
    print_detection_result "Project type" "$DETECTED_PROJECT_TYPE" "true"
    if [[ -n "$DETECTED_FRAMEWORK" ]]; then
        print_detection_result "Framework" "$DETECTED_FRAMEWORK" "true"
    fi

    # Detect git info
    detect_git_info
    if [[ "$DETECTED_GIT_REPO" == "true" ]]; then
        print_detection_result "Git repository" "Yes" "true"
        if [[ "$DETECTED_GIT_GITHUB" == "true" ]]; then
            print_detection_result "GitHub remote" "Yes" "true"
        fi
    else
        print_detection_result "Git repository" "No" "false"
    fi

    # Detect task sources
    detect_task_sources
    echo ""
    echo "Available task sources:"
    if [[ "$DETECTED_BEADS_AVAILABLE" == "true" ]]; then
        local beads_count
        beads_count=$(get_beads_count)
        print_detection_result "beads" "$beads_count open issues" "true"
    fi
    if [[ "$DETECTED_GITHUB_AVAILABLE" == "true" ]]; then
        local gh_count
        gh_count=$(get_github_issue_count)
        print_detection_result "GitHub Issues" "$gh_count open issues" "true"
    fi
    if [[ ${#DETECTED_PRD_FILES[@]} -gt 0 ]]; then
        print_detection_result "PRD files" "${#DETECTED_PRD_FILES[@]} found" "true"
    fi

    echo ""
}

# =============================================================================
# PHASE 2: MODE SELECTION
# =============================================================================

phase_mode_selection() {
    print_header "Mode Selection" "Phase 2 of 7"

    # If mode specified via CLI, use it
    if [[ -n "$KORERO_MODE" ]]; then
        echo "Using mode from command line: $KORERO_MODE"
        echo ""
        return 0
    fi

    # Non-interactive mode: default to coding
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        KORERO_MODE="coding"
        echo "Using default mode: coding"
        return 0
    fi

    echo "Korero supports two modes of operation:"
    echo ""

    local mode_choice
    mode_choice=$(select_with_default "Select Korero mode" 0 \
        "Continuous Coding Loop - ideation + debate + implementation + git commits" \
        "Continuous Idea Loop - ideation + debate only, no code changes")

    case "$mode_choice" in
        *"Coding"*)  KORERO_MODE="coding" ;;
        *"Idea"*)    KORERO_MODE="idea" ;;
    esac

    echo ""
    print_info "Selected mode: $KORERO_MODE"
    echo ""
}

# =============================================================================
# PHASE 3: SUBJECT & AGENT CONFIGURATION
# =============================================================================

phase_subject_and_agents() {
    print_header "Project Subject & Agents" "Phase 3 of 7"

    # --- Subject ---
    if [[ -z "$PROJECT_SUBJECT" ]]; then
        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            PROJECT_SUBJECT=""
        else
            echo "Describe your project or domain. This will be used to generate"
            echo "domain-specific expert agents for the ideation process."
            echo ""
            PROJECT_SUBJECT=$(prompt_text "Project subject/description" "")
        fi
    else
        echo "Using subject from command line: $PROJECT_SUBJECT"
    fi

    if [[ -z "$PROJECT_SUBJECT" ]]; then
        print_warning "No subject provided. Generic expert agents will be used."
        echo ""
    fi

    # --- Agent Count ---
    if [[ -z "$AGENT_COUNT" ]]; then
        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            AGENT_COUNT=3
        else
            echo ""
            echo "How many domain expert agents should participate in each ideation round?"
            echo "(These are in addition to the 3 mandatory evaluation agents)"
            echo ""
            AGENT_COUNT=$(prompt_number "Number of domain agents" "3" "1" "10")
        fi
    else
        echo "Using agent count from command line: $AGENT_COUNT"
    fi

    # --- Agent Generation Method ---
    if [[ -z "$AGENT_GEN_METHOD" ]]; then
        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            AGENT_GEN_METHOD="auto"
        else
            echo ""
            local gen_choice
            gen_choice=$(select_with_default "How should domain agents be generated?" 0 \
                "Auto-generate with Claude Code - AI creates agents based on your subject" \
                "Enter agent roles manually - you specify agent role names")

            case "$gen_choice" in
                *"Auto"*)  AGENT_GEN_METHOD="auto" ;;
                *"manually"*|*"Enter"*)  AGENT_GEN_METHOD="manual" ;;
            esac
        fi
    fi

    echo ""

    # --- Generate Agents ---
    if [[ "$AGENT_GEN_METHOD" == "manual" ]]; then
        if [[ -z "$MANUAL_AGENT_ROLES" ]]; then
            echo "Enter agent role names separated by commas."
            echo "Example: Data Analyst, Data Engineer, Chief Data Officer"
            echo ""
            MANUAL_AGENT_ROLES=$(prompt_text "Agent roles (comma-separated)" "")
        fi

        if [[ -n "$MANUAL_AGENT_ROLES" ]]; then
            GENERATED_AGENTS=$(_generate_agents_from_roles "$MANUAL_AGENT_ROLES")
            print_success "Created agent descriptions from your roles"
        else
            print_warning "No roles entered. Using generic agents."
            GENERATED_AGENTS=$(_generate_generic_agents "$AGENT_COUNT")
        fi
    else
        # Auto-generate
        echo "Generating domain expert agents..."
        if [[ -n "$PROJECT_SUBJECT" ]]; then
            GENERATED_AGENTS=$(generate_domain_agents "$PROJECT_SUBJECT" "$DETECTED_PROJECT_TYPE" "$AGENT_COUNT")
            if [[ $? -eq 0 ]]; then
                print_success "Auto-generated $AGENT_COUNT domain expert agents"
            else
                print_info "Using generic agents (Claude Code CLI not available)"
            fi
        else
            GENERATED_AGENTS=$(_generate_generic_agents "$AGENT_COUNT")
            print_info "Using $AGENT_COUNT generic expert agents"
        fi
    fi

    echo ""
    echo "Generated agents:"
    # Extract and display agent names
    echo "$GENERATED_AGENTS" | grep "^### Agent:" | while read -r line; do
        local agent_name="${line#*: }"
        print_bullet "$agent_name"
    done
    echo ""
    print_info "Plus 3 mandatory agents: Devil's Advocate, Technical Feasibility Analyst, Idea Orchestrator"
    echo ""
    print_info "You can edit agents later in .korero/AGENT.md"
    echo ""
}

# =============================================================================
# PHASE 4: TASK SOURCE SELECTION
# =============================================================================

phase_task_source_selection() {
    # Skip task source selection in idea mode
    if [[ "$KORERO_MODE" == "idea" ]]; then
        SELECTED_SOURCES=""
        return 0
    fi

    print_header "Task Source Selection" "Phase 4 of 7"

    # If task source specified via CLI, use it
    if [[ -n "$TASK_SOURCE" ]]; then
        echo "Using task source from command line: $TASK_SOURCE"
        SELECTED_SOURCES="$TASK_SOURCE"
        return 0
    fi

    # If skip tasks, use empty
    if [[ "$SKIP_TASKS" == "true" ]]; then
        echo "Skipping task import (--skip-tasks)"
        SELECTED_SOURCES=""
        return 0
    fi

    # Non-interactive mode: auto-select available sources
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        local auto_sources=""
        [[ "$DETECTED_BEADS_AVAILABLE" == "true" ]] && auto_sources="beads"
        [[ "$DETECTED_GITHUB_AVAILABLE" == "true" ]] && auto_sources="${auto_sources:+$auto_sources }github"
        SELECTED_SOURCES="$auto_sources"
        echo "Auto-selected sources: ${SELECTED_SOURCES:-none}"
        return 0
    fi

    # Build options list
    local options=()
    local option_keys=()

    if [[ "$DETECTED_BEADS_AVAILABLE" == "true" ]]; then
        local beads_count
        beads_count=$(get_beads_count)
        options+=("Import from beads ($beads_count issues)")
        option_keys+=("beads")
    fi

    if [[ "$DETECTED_GITHUB_AVAILABLE" == "true" ]]; then
        local gh_count
        gh_count=$(get_github_issue_count)
        options+=("Import from GitHub Issues ($gh_count issues)")
        option_keys+=("github")
    fi

    if [[ ${#DETECTED_PRD_FILES[@]} -gt 0 ]]; then
        options+=("Convert PRD/spec document (${#DETECTED_PRD_FILES[@]} found)")
        option_keys+=("prd")
    fi

    options+=("Start with empty task list")
    option_keys+=("none")

    # Interactive selection
    if [[ ${#options[@]} -gt 1 ]]; then
        echo "Where would you like to import tasks from?"
        echo ""

        local selected_indices
        selected_indices=$(select_multiple "Select task sources" "${options[@]}")

        # Parse selected indices (comma-separated)
        SELECTED_SOURCES=""
        if [[ -n "$selected_indices" ]]; then
            IFS=',' read -ra indices <<< "$selected_indices"
            for idx in "${indices[@]}"; do
                if [[ "${option_keys[$idx]}" != "none" ]]; then
                    SELECTED_SOURCES="${SELECTED_SOURCES:+$SELECTED_SOURCES }${option_keys[$idx]}"
                fi
            done
        fi
    else
        SELECTED_SOURCES=""
    fi

    echo ""
    echo "Selected sources: ${SELECTED_SOURCES:-none}"
}

# =============================================================================
# PHASE 5: CONFIGURATION
# =============================================================================

phase_configuration() {
    print_header "Configuration" "Phase 5 of 7"

    # Project name
    if [[ "$NON_INTERACTIVE" != "true" ]]; then
        CONFIG_PROJECT_NAME=$(prompt_text "Project name" "$DETECTED_PROJECT_NAME")
    else
        CONFIG_PROJECT_NAME="$DETECTED_PROJECT_NAME"
    fi

    # API call limit
    if [[ "$NON_INTERACTIVE" != "true" ]]; then
        CONFIG_MAX_CALLS=$(prompt_number "Max API calls per hour" "100" "10" "500")
    else
        CONFIG_MAX_CALLS=100
    fi

    # GitHub label (if GitHub selected)
    if echo "$SELECTED_SOURCES" | grep -qw "github"; then
        if [[ -n "$GITHUB_LABEL" ]]; then
            CONFIG_GITHUB_LABEL="$GITHUB_LABEL"
        elif [[ "$NON_INTERACTIVE" != "true" ]]; then
            CONFIG_GITHUB_LABEL=$(prompt_text "GitHub issue label filter" "korero-task")
        else
            CONFIG_GITHUB_LABEL="korero-task"
        fi
    fi

    # PRD file selection (if PRD selected)
    if echo "$SELECTED_SOURCES" | grep -qw "prd"; then
        if [[ -n "$PRD_FILE" ]]; then
            CONFIG_PRD_FILE="$PRD_FILE"
        elif [[ "$NON_INTERACTIVE" != "true" && ${#DETECTED_PRD_FILES[@]} -gt 0 ]]; then
            echo ""
            echo "Found PRD files:"
            CONFIG_PRD_FILE=$(select_option "Select PRD file to convert" "${DETECTED_PRD_FILES[@]}")
        else
            CONFIG_PRD_FILE="${DETECTED_PRD_FILES[0]:-}"
        fi
    fi

    # Loop limit
    if [[ -z "$MAX_LOOPS" ]]; then
        if [[ "$NON_INTERACTIVE" != "true" ]]; then
            echo ""
            echo "How many loops should Korero run?"
            echo ""
            local loops_choice
            loops_choice=$(select_with_default "Select loop limit" 0 \
                "Continuous - run until stopped manually" \
                "10 loops" \
                "20 loops" \
                "50 loops")

            case "$loops_choice" in
                *"Continuous"*)  MAX_LOOPS="continuous" ;;
                *"10"*)          MAX_LOOPS="10" ;;
                *"20"*)          MAX_LOOPS="20" ;;
                *"50"*)          MAX_LOOPS="50" ;;
            esac
        else
            MAX_LOOPS="continuous"
        fi
    fi

    # Show configuration summary
    echo ""
    print_summary "Configuration" \
        "Project=$CONFIG_PROJECT_NAME" \
        "Type=$DETECTED_PROJECT_TYPE" \
        "Mode=$KORERO_MODE" \
        "Domain agents=$AGENT_COUNT" \
        "Max loops=$MAX_LOOPS" \
        "Max calls/hour=$CONFIG_MAX_CALLS" \
        "Task sources=${SELECTED_SOURCES:-none}"
}

# =============================================================================
# PHASE 6: FILE GENERATION
# =============================================================================

phase_file_generation() {
    print_header "File Generation" "Phase 6 of 7"

    # Import tasks if sources selected
    local imported_tasks=""
    if [[ -n "$SELECTED_SOURCES" ]]; then
        echo "Importing tasks..."

        if echo "$SELECTED_SOURCES" | grep -qw "beads"; then
            local beads_tasks
            if beads_tasks=$(fetch_beads_tasks); then
                imported_tasks="${imported_tasks}${beads_tasks}
"
                print_success "Imported tasks from beads"
            fi
        fi

        if echo "$SELECTED_SOURCES" | grep -qw "github"; then
            local github_tasks
            if github_tasks=$(fetch_github_tasks "$CONFIG_GITHUB_LABEL"); then
                imported_tasks="${imported_tasks}${github_tasks}
"
                print_success "Imported tasks from GitHub"
            fi
        fi

        if echo "$SELECTED_SOURCES" | grep -qw "prd"; then
            if [[ -n "$CONFIG_PRD_FILE" && -f "$CONFIG_PRD_FILE" ]]; then
                local prd_tasks
                if prd_tasks=$(extract_prd_tasks "$CONFIG_PRD_FILE"); then
                    imported_tasks="${imported_tasks}${prd_tasks}
"
                    print_success "Extracted tasks from PRD: $CONFIG_PRD_FILE"
                fi
            fi
        fi

        echo ""
    fi

    # Set up enable environment
    export ENABLE_FORCE="$FORCE_OVERWRITE"
    export ENABLE_SKIP_TASKS="$SKIP_TASKS"
    export ENABLE_PROJECT_NAME="$CONFIG_PROJECT_NAME"
    export ENABLE_TASK_CONTENT="$imported_tasks"
    export ENABLE_KORERO_MODE="$KORERO_MODE"
    export ENABLE_PROJECT_SUBJECT="$PROJECT_SUBJECT"
    export ENABLE_GENERATED_AGENTS="$GENERATED_AGENTS"
    export ENABLE_AGENT_COUNT="$AGENT_COUNT"
    export ENABLE_MAX_LOOPS="$MAX_LOOPS"
    export ENABLE_FOCUS_CONSTRAINT="${FOCUS_CONSTRAINT:-}"

    # Run core enable logic
    echo "Creating Korero configuration..."
    echo ""

    if ! enable_korero_in_directory; then
        print_error "Failed to enable Korero"
        exit $ENABLE_ERROR
    fi

    # Update .korerorc with specific settings
    # Using awk instead of sed to avoid command injection from user input
    if [[ -f ".korerorc" ]]; then
        # Update max calls (awk safely handles the value without shell interpretation)
        awk -v val="$CONFIG_MAX_CALLS" '/^MAX_CALLS_PER_HOUR=/{$0="MAX_CALLS_PER_HOUR="val}1' .korerorc > .korerorc.tmp && mv .korerorc.tmp .korerorc

        # Update GitHub label if set
        if [[ -n "$CONFIG_GITHUB_LABEL" ]]; then
            awk -v val="$CONFIG_GITHUB_LABEL" '/^GITHUB_TASK_LABEL=/{$0="GITHUB_TASK_LABEL=\""val"\""}1' .korerorc > .korerorc.tmp && mv .korerorc.tmp .korerorc
        fi
    fi

    echo ""
}

# =============================================================================
# PHASE 7: VERIFICATION
# =============================================================================

phase_verification() {
    print_header "Verification" "Phase 7 of 7"

    echo "Checking created files..."
    echo ""

    # Verify required files
    local all_good=true

    if [[ -f ".korero/PROMPT.md" ]]; then
        print_success ".korero/PROMPT.md"
    else
        print_error ".korero/PROMPT.md - MISSING"
        all_good=false
    fi

    if [[ -f ".korero/fix_plan.md" ]]; then
        print_success ".korero/fix_plan.md"
    else
        print_error ".korero/fix_plan.md - MISSING"
        all_good=false
    fi

    if [[ -f ".korero/AGENT.md" ]]; then
        print_success ".korero/AGENT.md"
    else
        print_error ".korero/AGENT.md - MISSING"
        all_good=false
    fi

    if [[ -f ".korerorc" ]]; then
        print_success ".korerorc"
    else
        print_warning ".korerorc - MISSING (optional)"
    fi

    if [[ -d ".korero/specs" ]]; then
        print_success ".korero/specs/"
    fi

    if [[ -d ".korero/logs" ]]; then
        print_success ".korero/logs/"
    fi

    if [[ -d ".korero/ideas" ]]; then
        print_success ".korero/ideas/"
    fi

    if [[ -f ".korero/ideas/IDEAS.md" ]]; then
        print_success ".korero/ideas/IDEAS.md"
    fi

    echo ""

    if [[ "$all_good" == "true" ]]; then
        print_success "Korero enabled successfully!"
        echo ""
        echo "Next steps:"
        echo ""
        print_bullet "Review agent descriptions in .korero/AGENT.md (add, edit, or remove agents)" "1."
        print_bullet "Review the ideation protocol in .korero/PROMPT.md" "2."
        if [[ "$KORERO_MODE" == "coding" ]]; then
            print_bullet "Edit tasks in .korero/fix_plan.md" "3."
            print_bullet "Start Korero: korero --monitor" "4."
        else
            print_bullet "Start Korero: korero --monitor" "3."
            print_bullet "Ideas will be saved to .korero/ideas/IDEAS.md" "4."
        fi
        echo ""

        if [[ "$NON_INTERACTIVE" != "true" ]]; then
            if confirm "Show current status?" "y"; then
                echo ""
                korero --status 2>/dev/null || echo "(korero --status not available)"
            fi
        fi
    else
        print_error "Some files were not created. Please check the errors above."
        exit $ENABLE_ERROR
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    # Parse arguments
    parse_arguments "$@"

    # Show help if requested
    if [[ "$SHOW_HELP" == "true" ]]; then
        show_help
        exit 0
    fi

    # Welcome banner
    echo ""
    echo -e "\033[1m╔════════════════════════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1m║       Korero - Multi-Agent Ideation & Development System       ║\033[0m"
    echo -e "\033[1m╚════════════════════════════════════════════════════════════════╝\033[0m"
    echo ""

    # Run phases (7 total)
    phase_environment_detection      # Phase 1: Detect project type, git, etc.
    phase_mode_selection             # Phase 2: Coding loop or idea loop?
    phase_subject_and_agents         # Phase 3: Project subject + agent generation
    phase_task_source_selection      # Phase 4: Task import (coding mode only)
    phase_configuration              # Phase 5: Project name, API limits, loop limit
    phase_file_generation            # Phase 6: Generate all .korero/ files
    phase_verification               # Phase 7: Verify files and show next steps

    exit $ENABLE_SUCCESS
}

# Run main
main "$@"
