#!/bin/bash

# Claude Code Korero Loop with Rate Limiting and Documentation
# Adaptation of the Korero technique for Claude Code with usage management

set -e  # Exit on any error

# Note: CLAUDE_CODE_ENABLE_DANGEROUS_PERMISSIONS_IN_SANDBOX and IS_SANDBOX
# environment variables are NOT exported here. Tool restrictions are handled
# via --allowedTools flag in CLAUDE_CMD_ARGS, which is the proper approach.
# Exporting sandbox variables without a verified sandbox would be misleading.

# Source library components
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/lib/date_utils.sh"
source "$SCRIPT_DIR/lib/timeout_utils.sh"
source "$SCRIPT_DIR/lib/response_analyzer.sh"
source "$SCRIPT_DIR/lib/circuit_breaker.sh"
source "$SCRIPT_DIR/lib/permission_presets.sh"
source "$SCRIPT_DIR/lib/health_check.sh"
source "$SCRIPT_DIR/lib/codex_adapter.sh"
source "$SCRIPT_DIR/lib/cross_ai_debate.sh"
source "$SCRIPT_DIR/lib/debate_transcript.sh"
source "$SCRIPT_DIR/lib/cost_estimator.sh"
source "$SCRIPT_DIR/lib/signal_handler.sh"

# Validate bash version before anything else
if ! check_bash_version; then
    exit 3
fi

# Configuration
# Korero-specific files live in .korero/ subfolder
KORERO_DIR="${KORERO_DIR:-.korero}"
PROMPT_FILE="$KORERO_DIR/PROMPT.md"
LOG_DIR="$KORERO_DIR/logs"
DOCS_DIR="$KORERO_DIR/docs/generated"
STATUS_FILE="$KORERO_DIR/status.json"
PROGRESS_FILE="$KORERO_DIR/progress.json"
CLAUDE_CODE_CMD="claude"
SLEEP_DURATION=3600     # 1 hour in seconds
LIVE_OUTPUT=false       # Show Claude Code output in real-time (streaming)
LIVE_LOG_FILE="$KORERO_DIR/live.log"  # Fixed file for live output monitoring
CALL_COUNT_FILE="$KORERO_DIR/.call_count"
TIMESTAMP_FILE="$KORERO_DIR/.last_reset"
USE_TMUX=false
DRY_RUN=false
START_IDEA_LOOP=""

# Duration tracking configuration
DURATION_HISTORY_FILE="$KORERO_DIR/.loop_durations"
MAX_DURATION_ENTRIES=10

# Rate limit warning flags (reset each hour)
RATE_WARNED_80=false
RATE_WARNED_95=false
LOOPS_THIS_HOUR=0

# Save environment variable state BEFORE setting defaults
# These are used by load_korerorc() to determine which values came from environment
_env_MAX_CALLS_PER_HOUR="${MAX_CALLS_PER_HOUR:-}"
_env_CLAUDE_TIMEOUT_MINUTES="${CLAUDE_TIMEOUT_MINUTES:-}"
_env_CLAUDE_OUTPUT_FORMAT="${CLAUDE_OUTPUT_FORMAT:-}"
_env_CLAUDE_ALLOWED_TOOLS="${CLAUDE_ALLOWED_TOOLS:-}"
_env_CLAUDE_USE_CONTINUE="${CLAUDE_USE_CONTINUE:-}"
_env_CLAUDE_SESSION_EXPIRY_HOURS="${CLAUDE_SESSION_EXPIRY_HOURS:-}"
_env_VERBOSE_PROGRESS="${VERBOSE_PROGRESS:-}"

# Now set defaults (only if not already set by environment)
MAX_CALLS_PER_HOUR="${MAX_CALLS_PER_HOUR:-100}"
VERBOSE_PROGRESS="${VERBOSE_PROGRESS:-false}"
CLAUDE_TIMEOUT_MINUTES="${CLAUDE_TIMEOUT_MINUTES:-15}"

# Modern Claude CLI configuration (Phase 1.1)
CLAUDE_OUTPUT_FORMAT="${CLAUDE_OUTPUT_FORMAT:-json}"
CLAUDE_ALLOWED_TOOLS="${CLAUDE_ALLOWED_TOOLS:-Write,Read,Edit,Bash(git *),Bash(npm *),Bash(pytest)}"
CLAUDE_USE_CONTINUE="${CLAUDE_USE_CONTINUE:-true}"
CLAUDE_SESSION_FILE="$KORERO_DIR/.claude_session_id" # Session ID persistence file
CLAUDE_MIN_VERSION="2.0.76"              # Minimum required Claude CLI version

# Session management configuration (Phase 1.2)
# Note: SESSION_EXPIRATION_SECONDS is defined in lib/response_analyzer.sh (86400 = 24 hours)
KORERO_SESSION_FILE="$KORERO_DIR/.korero_session"              # Korero-specific session tracking (lifecycle)
KORERO_SESSION_HISTORY_FILE="$KORERO_DIR/.korero_session_history"  # Session transition history
# Session expiration: 24 hours default balances project continuity with fresh context
# Too short = frequent context loss; Too long = stale context causes unpredictable behavior
CLAUDE_SESSION_EXPIRY_HOURS=${CLAUDE_SESSION_EXPIRY_HOURS:-24}

# Codex CLI configuration (heavy modes: heavy-coding, heavy-idea)
CODEX_TIMEOUT_MINUTES="${CODEX_TIMEOUT_MINUTES:-15}"
CODEX_APPROVAL_MODE="${CODEX_APPROVAL_MODE:-never}"
DEBATE_TIMEOUT_SECONDS="${DEBATE_TIMEOUT_SECONDS:-300}"
DEBATE_ROUNDS="${DEBATE_ROUNDS:-2}"

# Valid tool patterns for --allowed-tools validation
# Tools can be exact matches or pattern matches with wildcards in parentheses
VALID_TOOL_PATTERNS=(
    "Write"
    "Read"
    "Edit"
    "MultiEdit"
    "Glob"
    "Grep"
    "Task"
    "TodoWrite"
    "WebFetch"
    "WebSearch"
    "Bash"
    "Bash(git *)"
    "Bash(npm *)"
    "Bash(bats *)"
    "Bash(python *)"
    "Bash(node *)"
    "NotebookEdit"
)

# Exit detection configuration
EXIT_SIGNALS_FILE="$KORERO_DIR/.exit_signals"
RESPONSE_ANALYSIS_FILE="$KORERO_DIR/.response_analysis"
MAX_CONSECUTIVE_TEST_LOOPS=3
MAX_CONSECUTIVE_DONE_SIGNALS=2
TEST_PERCENTAGE_THRESHOLD=30  # If more than 30% of recent loops are test-only, flag it

# .korerorc configuration file
KORERORC_FILE=".korerorc"
KORERORC_LOADED=false

# load_korerorc - Load project-specific configuration from .korerorc
#
# This function sources .korerorc if it exists, applying project-specific
# settings. Environment variables take precedence over .korerorc values.
#
# Configuration values that can be overridden:
#   - MAX_CALLS_PER_HOUR
#   - CLAUDE_TIMEOUT_MINUTES
#   - CLAUDE_OUTPUT_FORMAT
#   - ALLOWED_TOOLS (mapped to CLAUDE_ALLOWED_TOOLS)
#   - SESSION_CONTINUITY (mapped to CLAUDE_USE_CONTINUE)
#   - SESSION_EXPIRY_HOURS (mapped to CLAUDE_SESSION_EXPIRY_HOURS)
#   - CB_NO_PROGRESS_THRESHOLD
#   - CB_SAME_ERROR_THRESHOLD
#   - CB_OUTPUT_DECLINE_THRESHOLD
#   - KORERO_VERBOSE
#
load_korerorc() {
    if [[ ! -f "$KORERORC_FILE" ]]; then
        return 0
    fi

    # Source .korerorc (this may override default values)
    # shellcheck source=/dev/null
    source "$KORERORC_FILE"

    # Map .korerorc variable names to internal names
    if [[ -n "${ALLOWED_TOOLS:-}" ]]; then
        CLAUDE_ALLOWED_TOOLS="$ALLOWED_TOOLS"
    fi
    if [[ -n "${SESSION_CONTINUITY:-}" ]]; then
        CLAUDE_USE_CONTINUE="$SESSION_CONTINUITY"
    fi
    if [[ -n "${SESSION_EXPIRY_HOURS:-}" ]]; then
        CLAUDE_SESSION_EXPIRY_HOURS="$SESSION_EXPIRY_HOURS"
    fi
    if [[ -n "${KORERO_VERBOSE:-}" ]]; then
        VERBOSE_PROGRESS="$KORERO_VERBOSE"
    fi
    # Map Codex-specific .korerorc variables (heavy modes)
    if [[ -n "${CODEX_TIMEOUT:-}" ]]; then
        CODEX_TIMEOUT_MINUTES="$CODEX_TIMEOUT"
    fi
    if [[ -n "${CODEX_APPROVAL:-}" ]]; then
        CODEX_APPROVAL_MODE="$CODEX_APPROVAL"
    fi
    if [[ -n "${CODEX_MODEL_OVERRIDE:-}" ]]; then
        CODEX_MODEL="$CODEX_MODEL_OVERRIDE"
    fi

    # Restore ONLY values that were explicitly set via environment variables
    # (not script defaults). The _env_* variables were captured BEFORE defaults were set.
    # If _env_* is non-empty, the user explicitly set it in their environment.
    [[ -n "$_env_MAX_CALLS_PER_HOUR" ]] && MAX_CALLS_PER_HOUR="$_env_MAX_CALLS_PER_HOUR"
    [[ -n "$_env_CLAUDE_TIMEOUT_MINUTES" ]] && CLAUDE_TIMEOUT_MINUTES="$_env_CLAUDE_TIMEOUT_MINUTES"
    [[ -n "$_env_CLAUDE_OUTPUT_FORMAT" ]] && CLAUDE_OUTPUT_FORMAT="$_env_CLAUDE_OUTPUT_FORMAT"
    [[ -n "$_env_CLAUDE_ALLOWED_TOOLS" ]] && CLAUDE_ALLOWED_TOOLS="$_env_CLAUDE_ALLOWED_TOOLS"
    [[ -n "$_env_CLAUDE_USE_CONTINUE" ]] && CLAUDE_USE_CONTINUE="$_env_CLAUDE_USE_CONTINUE"
    [[ -n "$_env_CLAUDE_SESSION_EXPIRY_HOURS" ]] && CLAUDE_SESSION_EXPIRY_HOURS="$_env_CLAUDE_SESSION_EXPIRY_HOURS"
    [[ -n "$_env_VERBOSE_PROGRESS" ]] && VERBOSE_PROGRESS="$_env_VERBOSE_PROGRESS"

    # Expand any preset references in ALLOWED_TOOLS (e.g., @standard -> Write,Read,Edit,...)
    if [[ -n "${CLAUDE_ALLOWED_TOOLS:-}" && "${CLAUDE_ALLOWED_TOOLS}" == *"@"* ]]; then
        CLAUDE_ALLOWED_TOOLS=$(expand_allowed_tools "$CLAUDE_ALLOWED_TOOLS")
    fi

    KORERORC_LOADED=true
    return 0
}

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Initialize directories
mkdir -p "$LOG_DIR" "$DOCS_DIR"

# Check if tmux is available
check_tmux_available() {
    if ! command -v tmux &> /dev/null; then
        log_status "ERROR" "tmux is not installed. Please install tmux or run without --monitor flag."
        echo "Install tmux:"
        echo "  Ubuntu/Debian: sudo apt-get install tmux"
        echo "  macOS: brew install tmux"
        echo "  CentOS/RHEL: sudo yum install tmux"
        exit 1
    fi
}

# Get the tmux base-index for windows (handles custom tmux configurations)
# Returns: the base window index (typically 0 or 1)
get_tmux_base_index() {
    local base_index
    base_index=$(tmux show-options -gv base-index 2>/dev/null)
    # Default to 0 if not set or tmux command fails
    echo "${base_index:-0}"
}

# Setup tmux session with monitor
setup_tmux_session() {
    local session_name="korero-$(date +%s)"
    local korero_home="${KORERO_HOME:-$HOME/.korero}"
    local project_dir="$(pwd)"

    # Get the tmux base-index to handle custom configurations (e.g., base-index 1)
    local base_win
    base_win=$(get_tmux_base_index)

    log_status "INFO" "Setting up tmux session: $session_name"

    # Initialize live.log file
    echo "=== Korero Live Output - Waiting for first loop... ===" > "$LIVE_LOG_FILE"

    # Create new tmux session detached (left pane - Korero loop)
    tmux new-session -d -s "$session_name" -c "$project_dir"

    # Split window vertically (right side)
    tmux split-window -h -t "$session_name" -c "$project_dir"

    # Split right pane horizontally (top: Claude output, bottom: status)
    tmux split-window -v -t "$session_name:${base_win}.1" -c "$project_dir"

    # Right-top pane (pane 1): Live Claude Code output
    tmux send-keys -t "$session_name:${base_win}.1" "tail -f '$project_dir/$LIVE_LOG_FILE'" Enter

    # Right-bottom pane (pane 2): Korero status monitor
    if command -v korero-monitor &> /dev/null; then
        tmux send-keys -t "$session_name:${base_win}.2" "korero-monitor" Enter
    else
        tmux send-keys -t "$session_name:${base_win}.2" "'$korero_home/korero_monitor.sh'" Enter
    fi

    # Start korero loop in the left pane (exclude tmux flag to avoid recursion)
    # Forward all CLI parameters that were set by the user
    local korero_cmd
    if command -v korero &> /dev/null; then
        korero_cmd="korero"
    else
        korero_cmd="'$korero_home/korero_loop.sh'"
    fi

    # Always use --live mode in tmux for real-time streaming
    korero_cmd="$korero_cmd --live"

    # Forward --calls if non-default
    if [[ "$MAX_CALLS_PER_HOUR" != "100" ]]; then
        korero_cmd="$korero_cmd --calls $MAX_CALLS_PER_HOUR"
    fi
    # Forward --prompt if non-default
    if [[ "$PROMPT_FILE" != "$KORERO_DIR/PROMPT.md" ]]; then
        korero_cmd="$korero_cmd --prompt '$PROMPT_FILE'"
    fi
    # Forward --output-format if non-default (default is json)
    if [[ "$CLAUDE_OUTPUT_FORMAT" != "json" ]]; then
        korero_cmd="$korero_cmd --output-format $CLAUDE_OUTPUT_FORMAT"
    fi
    # Forward --verbose if enabled
    if [[ "$VERBOSE_PROGRESS" == "true" ]]; then
        korero_cmd="$korero_cmd --verbose"
    fi
    # Forward --timeout if non-default (default is 15)
    if [[ "$CLAUDE_TIMEOUT_MINUTES" != "15" ]]; then
        korero_cmd="$korero_cmd --timeout $CLAUDE_TIMEOUT_MINUTES"
    fi
    # Forward --allowed-tools if non-default
    if [[ "$CLAUDE_ALLOWED_TOOLS" != "Write,Read,Edit,Bash(git *),Bash(npm *),Bash(pytest)" ]]; then
        korero_cmd="$korero_cmd --allowed-tools '$CLAUDE_ALLOWED_TOOLS'"
    fi
    # Forward --no-continue if session continuity disabled
    if [[ "$CLAUDE_USE_CONTINUE" == "false" ]]; then
        korero_cmd="$korero_cmd --no-continue"
    fi
    # Forward --session-expiry if non-default (default is 24)
    if [[ "$CLAUDE_SESSION_EXPIRY_HOURS" != "24" ]]; then
        korero_cmd="$korero_cmd --session-expiry $CLAUDE_SESSION_EXPIRY_HOURS"
    fi

    tmux send-keys -t "$session_name:${base_win}.0" "$korero_cmd" Enter

    # Focus on left pane (main korero loop)
    tmux select-pane -t "$session_name:${base_win}.0"

    # Set pane titles (requires tmux 2.6+)
    tmux select-pane -t "$session_name:${base_win}.0" -T "Korero Loop"
    tmux select-pane -t "$session_name:${base_win}.1" -T "Claude Output"
    tmux select-pane -t "$session_name:${base_win}.2" -T "Status"

    # Set window title
    tmux rename-window -t "$session_name:${base_win}" "Korero: Loop | Output | Status"

    log_status "SUCCESS" "Tmux session created with 3 panes:"
    log_status "INFO" "  Left:         Korero loop"
    log_status "INFO" "  Right-top:    Claude Code live output"
    log_status "INFO" "  Right-bottom: Status monitor"
    log_status "INFO" ""
    log_status "INFO" "Use Ctrl+B then D to detach from session"
    log_status "INFO" "Use 'tmux attach -t $session_name' to reattach"

    # Attach to session (this will block until session ends)
    tmux attach-session -t "$session_name"

    exit 0
}

# Initialize call tracking
init_call_tracking() {
    # Debug logging removed for cleaner output
    local current_hour=$(date +%Y%m%d%H)
    local last_reset_hour=""

    if [[ -f "$TIMESTAMP_FILE" ]]; then
        last_reset_hour=$(cat "$TIMESTAMP_FILE")
    fi

    # Reset counter if it's a new hour
    if [[ "$current_hour" != "$last_reset_hour" ]]; then
        echo "0" > "$CALL_COUNT_FILE"
        echo "$current_hour" > "$TIMESTAMP_FILE"
        RATE_WARNED_80=false
        RATE_WARNED_95=false
        LOOPS_THIS_HOUR=0
        log_status "INFO" "Call counter reset for new hour: $current_hour"
    fi

    # Initialize exit signals tracking if it doesn't exist
    if [[ ! -f "$EXIT_SIGNALS_FILE" ]]; then
        echo '{"test_only_loops": [], "done_signals": [], "completion_indicators": []}' > "$EXIT_SIGNALS_FILE"
    fi

    # Initialize circuit breaker
    init_circuit_breaker

}

# Log function with timestamps and colors
log_status() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local color=""
    
    case $level in
        "INFO")  color=$BLUE ;;
        "WARN")  color=$YELLOW ;;
        "ERROR") color=$RED ;;
        "SUCCESS") color=$GREEN ;;
        "LOOP") color=$PURPLE ;;
    esac
    
    # Write to stderr so log messages don't interfere with function return values
    echo -e "${color}[$timestamp] [$level] $message${NC}" >&2
    echo "[$timestamp] [$level] $message" >> "$LOG_DIR/korero.log"
}

# Update status JSON for external monitoring
update_status() {
    local loop_count=$1
    local calls_made=$2
    local last_action=$3
    local status=$4
    local exit_reason=${5:-""}
    
    local loop_start=${LOOP_START_TIME:-0}
    local last_dur=${LAST_LOOP_DURATION:-0}
    local avg_dur
    avg_dur=$(get_average_duration)

    # Determine rate limit warning state
    local rate_warning=""
    if [[ "$RATE_WARNED_95" == "true" ]]; then
        rate_warning="rate_limit_imminent"
    elif [[ "$RATE_WARNED_80" == "true" ]]; then
        rate_warning="rate_limit_approaching"
    fi

    cat > "$STATUS_FILE" << STATUSEOF
{
    "timestamp": "$(get_iso_timestamp)",
    "loop_count": $loop_count,
    "calls_made_this_hour": $calls_made,
    "max_calls_per_hour": $MAX_CALLS_PER_HOUR,
    "last_action": "$last_action",
    "status": "$status",
    "exit_reason": "$exit_reason",
    "next_reset": "$(get_next_hour_time)",
    "loop_start_time": $loop_start,
    "last_loop_duration_sec": $last_dur,
    "average_loop_duration_sec": $avg_dur,
    "rate_limit_warning": "$rate_warning"
}
STATUSEOF
}

# Format seconds into human-readable duration
format_duration() {
    local seconds="$1"
    local minutes=$((seconds / 60))
    local remaining=$((seconds % 60))
    if [[ $minutes -gt 0 ]]; then
        echo "${minutes}m ${remaining}s"
    else
        echo "${remaining}s"
    fi
}

# Print visual progress indicator
# Usage: print_progress <loop_number> <phase_name> <phase_percentage>
print_progress() {
    local loop_num=$1
    local phase_name=$2
    local percent=$3

    # Clamp percentage to 0-100
    [[ $percent -lt 0 ]] && percent=0
    [[ $percent -gt 100 ]] && percent=100

    # Calculate filled/empty blocks (10 total)
    local filled=$((percent / 10))
    local empty=$((10 - filled))

    # Build progress bar
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    # Print with colors
    echo -e "${BLUE}[${bar}] ${percent}%${NC} | Loop ${loop_num} | Phase: ${phase_name}"
}

# Record loop duration and compute rolling average
update_loop_duration() {
    local duration="$1"

    # Append to history file
    echo "$duration" >> "$DURATION_HISTORY_FILE"

    # Keep only last N entries
    if [[ -f "$DURATION_HISTORY_FILE" ]]; then
        tail -n "$MAX_DURATION_ENTRIES" "$DURATION_HISTORY_FILE" > "${DURATION_HISTORY_FILE}.tmp"
        mv "${DURATION_HISTORY_FILE}.tmp" "$DURATION_HISTORY_FILE"
    fi
}

# Calculate average duration from history
get_average_duration() {
    if [[ ! -f "$DURATION_HISTORY_FILE" ]]; then
        echo "0"
        return
    fi

    local total=0
    local count=0
    while read -r dur; do
        [[ -z "$dur" ]] && continue
        total=$((total + dur))
        ((count++))
    done < "$DURATION_HISTORY_FILE"

    if [[ $count -gt 0 ]]; then
        echo $((total / count))
    else
        echo "0"
    fi
}

# Display dry run information and exit
show_dry_run_info() {
    echo ""
    echo -e "${BLUE}DRY RUN MODE - No Claude Code calls will be made${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Prompt files
    if [[ -f "$PROMPT_FILE" ]]; then
        echo "Prompt file: $PROMPT_FILE ($(wc -c < "$PROMPT_FILE" 2>/dev/null || echo "?") bytes)"
    else
        echo "Prompt file: $PROMPT_FILE (NOT FOUND)"
    fi
    if [[ -f "$KORERO_DIR/fix_plan.md" ]]; then
        echo "Fix plan:    $KORERO_DIR/fix_plan.md ($(wc -c < "$KORERO_DIR/fix_plan.md" 2>/dev/null || echo "?") bytes)"
    fi
    if [[ -f "$KORERO_DIR/AGENT.md" ]]; then
        echo "Agent config: $KORERO_DIR/AGENT.md ($(wc -c < "$KORERO_DIR/AGENT.md" 2>/dev/null || echo "?") bytes)"
    fi
    echo ""

    # Configuration
    echo "Allowed tools:      $CLAUDE_ALLOWED_TOOLS"
    echo "Output format:      $CLAUDE_OUTPUT_FORMAT"
    echo "Session continuity: $CLAUDE_USE_CONTINUE"
    echo "Max calls/hour:     $MAX_CALLS_PER_HOUR"
    echo "Timeout:            ${CLAUDE_TIMEOUT_MINUTES}m"
    echo ""

    # Session state
    local session_id=""
    if [[ -f "$CLAUDE_SESSION_FILE" ]]; then
        session_id=$(cat "$CLAUDE_SESSION_FILE" 2>/dev/null || echo "")
    fi
    if [[ -n "$session_id" ]]; then
        echo "Session ID: ${session_id:0:20}..."
    else
        echo "Session ID: none (new session will be created)"
    fi

    # Circuit breaker
    local cb_state="UNKNOWN"
    if [[ -f "$KORERO_DIR/.circuit_breaker_state" ]]; then
        cb_state=$(cat "$KORERO_DIR/.circuit_breaker_state" 2>/dev/null || echo "UNKNOWN")
    fi
    echo "Circuit breaker: $cb_state"
    echo ""

    # Loop config
    local max_loops="${MAX_LOOPS:-continuous}"
    echo "Loop limit: $max_loops"
    echo ""

    # Heavy mode info
    local korero_mode="${KORERO_MODE:-coding}"
    if [[ "$korero_mode" == "heavy-coding" || "$korero_mode" == "heavy-idea" ]]; then
        echo -e "${PURPLE}Heavy Mode: $korero_mode${NC}"
        echo "Codex model:        $CODEX_MODEL"
        echo "Codex timeout:      ${CODEX_TIMEOUT_MINUTES}m"
        echo "Codex approval:     $CODEX_APPROVAL_MODE"
        echo "Debate rounds:      $DEBATE_ROUNDS"
        echo ""
        local codex_ready_code=0
        check_codex_ready || codex_ready_code=$?
        case $codex_ready_code in
            0) echo "Codex CLI:          ready" ;;
            1) echo -e "Codex CLI:          ${RED}not installed${NC}" ;;
            2) echo -e "Codex CLI:          ${YELLOW}not authenticated${NC}" ;;
        esac
        echo ""
    fi

    # Command preview
    echo "Command that would run:"
    echo "  claude --print --output-format $CLAUDE_OUTPUT_FORMAT \\"
    if [[ -n "$CLAUDE_ALLOWED_TOOLS" ]]; then
        echo "    --allowedTools \"$CLAUDE_ALLOWED_TOOLS\" \\"
    fi
    echo "    -p <prompt content>"

    if [[ "$korero_mode" == "heavy-coding" || "$korero_mode" == "heavy-idea" ]]; then
        echo ""
        echo "  codex exec --model $CODEX_MODEL --json \\"
        echo "    --sandbox read-only \\"
        echo "    \"<prompt content>\""
    fi
    echo ""
    echo "Run without --dry-run to execute."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Start idea-to-branch workflow
# Extracts a winning idea from IDEAS.md, creates a feature branch, and starts coding loop
start_idea_workflow() {
    local loop_num="$1"
    local ideas_script="$SCRIPT_DIR/korero_ideas.sh"

    if [[ ! -f "$ideas_script" ]]; then
        echo "Error: korero_ideas.sh not found at $ideas_script" >&2
        return 1
    fi

    # Source helper functions from korero_ideas.sh (only the functions, not the case block)
    local ideas_file="${KORERO_DIR}/IDEAS.md"
    if [[ ! -f "$ideas_file" ]]; then
        echo "Error: No IDEAS.md found. Run ideation loops first." >&2
        return 1
    fi

    # Extract title using inline parsing (avoids sourcing the entire script)
    local title=""
    local in_section=false
    local idea_body=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^LOOP\ ${loop_num}\ WINNING\ IDEA ]]; then
            in_section=true
            continue
        fi
        if [[ "$in_section" == "true" ]]; then
            if [[ "$line" =~ ^LOOP\ [0-9]+\ WINNING\ IDEA ]]; then
                break
            fi
            if [[ "$line" =~ ^\*\*Title:\*\*\ (.*) ]]; then
                title="${BASH_REMATCH[1]}"
            fi
            # Skip separator lines
            if [[ ! "$line" =~ ^═+ ]]; then
                idea_body+="$line"$'\n'
            fi
        fi
    done < "$ideas_file"

    if [[ -z "$title" ]]; then
        echo "Error: No winning idea found for loop $loop_num." >&2
        return 1
    fi

    # Sanitize title for branch name
    local sanitized
    sanitized=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')
    if [[ ${#sanitized} -gt 50 ]]; then
        sanitized="${sanitized:0:50}"
        sanitized="${sanitized%-}"
    fi

    local branch_name="feature/loop-${loop_num}-${sanitized}"

    echo ""
    echo -e "${GREEN}Starting idea-to-branch workflow${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Idea:   $title"
    echo "  Branch: $branch_name"
    echo ""

    # Create and switch to the feature branch
    if ! git checkout -b "$branch_name" 2>/dev/null; then
        echo "Error: Failed to create branch '$branch_name'." >&2
        echo "  Branch may already exist. Use: git checkout $branch_name" >&2
        return 1
    fi

    echo -e "  ${GREEN}Branch created and checked out.${NC}"

    # Save idea context for build_loop_context() to pick up
    local idea_context_file="$KORERO_DIR/.idea_context"
    cat > "$idea_context_file" << IDEAEOF
IDEA_LOOP=$loop_num
IDEA_TITLE=$title
IDEA_BRANCH=$branch_name
IDEAEOF
    echo "$idea_body" >> "$idea_context_file"

    echo "  Idea context saved to $idea_context_file"
    echo ""
    echo "  Mode set to: coding"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Override mode to coding for implementation
    export KORERO_MODE="coding"
}

# Check if we can make another call
can_make_call() {
    local calls_made=0
    if [[ -f "$CALL_COUNT_FILE" ]]; then
        calls_made=$(cat "$CALL_COUNT_FILE")
    fi
    
    if [[ $calls_made -ge $MAX_CALLS_PER_HOUR ]]; then
        return 1  # Cannot make call
    else
        return 0  # Can make call
    fi
}

# Increment call counter
increment_call_counter() {
    local calls_made=0
    if [[ -f "$CALL_COUNT_FILE" ]]; then
        calls_made=$(cat "$CALL_COUNT_FILE")
    fi
    
    ((calls_made++))
    echo "$calls_made" > "$CALL_COUNT_FILE"
    echo "$calls_made"
}

# Check if rate limit warnings should be emitted
check_rate_limit_warnings() {
    local calls_made="$1"
    local threshold_80=$((MAX_CALLS_PER_HOUR * 80 / 100))
    local threshold_95=$((MAX_CALLS_PER_HOUR * 95 / 100))

    if [[ $calls_made -ge $threshold_80 ]] && [[ "$RATE_WARNED_80" == "false" ]]; then
        local remaining=$((MAX_CALLS_PER_HOUR - calls_made))
        log_status "WARN" "API budget: 80% used ($remaining calls remaining)"
        RATE_WARNED_80=true
    fi

    if [[ $calls_made -ge $threshold_95 ]] && [[ "$RATE_WARNED_95" == "false" ]]; then
        local remaining=$((MAX_CALLS_PER_HOUR - calls_made))
        log_status "WARN" "API budget: 95% used ($remaining calls remaining) — consider saving work"
        RATE_WARNED_95=true
    fi
}

# Predict remaining loops before hitting rate limit
# Uses current call count, loop count, and max calls to project remaining loops
# Returns: projected remaining loops on stdout (0 if at/over limit)
predict_remaining_loops() {
    local max_calls="${MAX_CALLS_PER_HOUR:-100}"
    local current_calls
    current_calls=$(cat "$CALL_COUNT_FILE" 2>/dev/null || echo "0")
    local loops_this_hour="${LOOPS_THIS_HOUR:-1}"

    # Avoid division by zero
    if [[ $loops_this_hour -eq 0 ]]; then
        loops_this_hour=1
    fi

    local avg_calls_per_loop=$((current_calls / loops_this_hour))

    # Avoid division by zero for avg
    if [[ $avg_calls_per_loop -eq 0 ]]; then
        avg_calls_per_loop=1
    fi

    local remaining_calls=$((max_calls - current_calls))
    if [[ $remaining_calls -le 0 ]]; then
        echo "0"
        return
    fi

    local projected_loops=$((remaining_calls / avg_calls_per_loop))
    echo "$projected_loops"
}

# Show rate limit prediction warning if approaching limit
# Warns when projected remaining loops drops below threshold (default: 5)
show_rate_limit_prediction() {
    local threshold="${RATE_LIMIT_WARNING_THRESHOLD:-5}"
    local max_calls="${MAX_CALLS_PER_HOUR:-100}"
    local current_calls
    current_calls=$(cat "$CALL_COUNT_FILE" 2>/dev/null || echo "0")
    local loops_this_hour="${LOOPS_THIS_HOUR:-1}"

    # Skip if threshold is 0 (disabled)
    if [[ "$threshold" -eq 0 ]]; then
        return
    fi

    local projected
    projected=$(predict_remaining_loops)
    local usage_percent=$((current_calls * 100 / max_calls))
    local effective_loops=$((loops_this_hour > 0 ? loops_this_hour : 1))
    local avg_calls=$((current_calls / effective_loops))

    if [[ $projected -lt $threshold && $projected -ge 0 ]]; then
        echo ""
        echo "═══════════════════════════════════════════════════════════"
        echo "RATE LIMIT PROJECTION"
        echo "═══════════════════════════════════════════════════════════"
        echo "Current usage: ${current_calls}/${max_calls} calls (${usage_percent}%)"
        echo "Average consumption: ${avg_calls} calls/loop"
        echo "Projected remaining: ~${projected} loops before limit"
        echo ""
        echo "Suggestions:"
        echo "  - Pause after this loop to let the hourly limit reset"
        echo "  - Increase limit: korero --calls $((max_calls + 50))"
        echo "  - Check status anytime: korero --status"
        echo "═══════════════════════════════════════════════════════════"
        echo ""
    fi
}

# Wait for rate limit reset with countdown
wait_for_reset() {
    local calls_made=$(cat "$CALL_COUNT_FILE" 2>/dev/null || echo "0")
    log_status "WARN" "Rate limit reached ($calls_made/$MAX_CALLS_PER_HOUR). Waiting for reset..."
    
    # Calculate time until next hour
    local current_minute=$(date +%M)
    local current_second=$(date +%S)
    local wait_time=$(((60 - current_minute - 1) * 60 + (60 - current_second)))
    
    log_status "INFO" "Sleeping for $wait_time seconds until next hour..."
    
    # Countdown display
    while [[ $wait_time -gt 0 ]]; do
        local hours=$((wait_time / 3600))
        local minutes=$(((wait_time % 3600) / 60))
        local seconds=$((wait_time % 60))
        
        printf "\r${YELLOW}Time until reset: %02d:%02d:%02d${NC}" $hours $minutes $seconds
        sleep 1
        ((wait_time--))
    done
    printf "\n"
    
    # Reset counter and warning flags
    echo "0" > "$CALL_COUNT_FILE"
    echo "$(date +%Y%m%d%H)" > "$TIMESTAMP_FILE"
    RATE_WARNED_80=false
    RATE_WARNED_95=false
    LOOPS_THIS_HOUR=0
    log_status "SUCCESS" "Rate limit reset! Ready for new calls."
}

# =============================================================================
# RATE LIMIT VISUALIZATION (Loop 33)
# =============================================================================

# Return seconds until the current hourly window resets
# The window resets on the clock hour (e.g., at :00 minutes)
# Usage: get_time_until_reset
# Returns: integer seconds on stdout
get_time_until_reset() {
    local current_minute
    local current_second
    current_minute=$(date +%M | sed 's/^0*//' || echo "0")
    current_second=$(date +%S | sed 's/^0*//' || echo "0")
    current_minute="${current_minute:-0}"
    current_second="${current_second:-0}"
    local seconds_until_reset=$(( (60 - current_minute - 1) * 60 + (60 - current_second) ))
    # Guard against negative values (edge case at :00:00)
    [[ $seconds_until_reset -lt 0 ]] && seconds_until_reset=0
    echo "$seconds_until_reset"
}

# Display a visual rate limit status dashboard
# Shows current call count, bar fill, time until reset, and suggestions
# Usage: show_rate_status
show_rate_status() {
    local calls_made
    calls_made=$(cat "$CALL_COUNT_FILE" 2>/dev/null | tr -d '[:space:]' || echo "0")
    calls_made="${calls_made:-0}"
    local max_calls="${MAX_CALLS_PER_HOUR:-100}"

    local remaining=$(( max_calls - calls_made ))
    [[ $remaining -lt 0 ]] && remaining=0

    local usage_pct=$(( calls_made * 100 / max_calls ))
    [[ $usage_pct -gt 100 ]] && usage_pct=100

    # Build ASCII bar (20 chars wide)
    local bar_width=20
    local filled=$(( usage_pct * bar_width / 100 ))
    local empty=$(( bar_width - filled ))
    local bar=""
    local i
    for (( i=0; i<filled; i++ )); do bar="${bar}█"; done
    for (( i=0; i<empty; i++ ));  do bar="${bar}░"; done

    # Choose color based on usage
    local color="$GREEN"
    if [[ $usage_pct -ge 95 ]]; then
        color="$RED"
    elif [[ $usage_pct -ge 80 ]]; then
        color="$YELLOW"
    fi

    local seconds_left
    seconds_left=$(get_time_until_reset)
    local mins_left=$(( seconds_left / 60 ))
    local secs_left=$(( seconds_left % 60 ))

    echo ""
    echo "══════════════════════════════════════════════════════════"
    echo "RATE LIMIT STATUS"
    echo "══════════════════════════════════════════════════════════"
    printf "  Calls used:   %d / %d  (%d%%)\n" "$calls_made" "$max_calls" "$usage_pct"
    printf "  Progress:     ${color}[%s]${NC}\n" "$bar"
    printf "  Remaining:    %d calls\n" "$remaining"
    printf "  Resets in:    %02d:%02d (mm:ss)\n" "$mins_left" "$secs_left"
    echo "──────────────────────────────────────────────────────────"

    if [[ $usage_pct -ge 95 ]]; then
        echo "  Status:  ⛔ Rate limit nearly exhausted"
        echo "  Tip:     Wait for reset or reduce loop frequency"
    elif [[ $usage_pct -ge 80 ]]; then
        echo "  Status:  ⚠️  Approaching rate limit"
        echo "  Tip:     korero --calls $((max_calls + 50)) to increase limit"
    else
        echo "  Status:  ✅ Healthy"
    fi
    echo "══════════════════════════════════════════════════════════"
    echo ""
}

# =============================================================================
# IDEA EXTRACTION (Ideation Mode)
# =============================================================================

# store_loop_idea - Extract and save the winning idea from a loop iteration
#
# Parameters:
#   $1 (output_file) - Path to Claude's output file
#   $2 (loop_number) - Current loop iteration number
#
# Extracts the KORERO_IDEA block and saves it to .korero/ideas/
#
store_loop_idea() {
    local output_file="$1"
    local loop_number="$2"
    local ideas_dir="$KORERO_DIR/ideas"

    mkdir -p "$ideas_dir"

    if [[ ! -f "$output_file" ]]; then
        return 0
    fi

    # Get the content (handle JSON output format)
    local content=""
    if command -v jq &>/dev/null; then
        content=$(jq -r '.result // .' "$output_file" 2>/dev/null || true)
        if [[ -z "$content" || "$content" == "null" ]]; then
            content=$(cat "$output_file")
        fi
    else
        content=$(cat "$output_file")
    fi

    # Extract the KORERO_IDEA block
    local idea_block=""
    idea_block=$(echo "$content" | sed -n '/---KORERO_IDEA---/,/---END_KORERO_IDEA---/p')

    if [[ -n "$idea_block" ]]; then
        # Save individual loop idea
        echo "$idea_block" > "$ideas_dir/loop_${loop_number}_idea.md"

        # Append to cumulative IDEAS.md
        {
            echo ""
            echo "## Loop $loop_number - $(date '+%Y-%m-%d %H:%M:%S')"
            echo ""
            echo "$idea_block"
            echo ""
            echo "---"
        } >> "$ideas_dir/IDEAS.md"

        log_status "SUCCESS" "Saved winning idea from loop #$loop_number to .korero/ideas/"
    else
        log_status "WARN" "No KORERO_IDEA block found in loop #$loop_number output"
    fi
}

# Check if we should gracefully exit
should_exit_gracefully() {
    
    if [[ ! -f "$EXIT_SIGNALS_FILE" ]]; then
        return 1  # Don't exit, file doesn't exist
    fi
    
    local signals=$(cat "$EXIT_SIGNALS_FILE")
    
    # Count recent signals (last 5 loops) - with error handling
    local recent_test_loops
    local recent_done_signals  
    local recent_completion_indicators
    
    recent_test_loops=$(echo "$signals" | jq '.test_only_loops | length' 2>/dev/null || echo "0")
    recent_done_signals=$(echo "$signals" | jq '.done_signals | length' 2>/dev/null || echo "0")
    recent_completion_indicators=$(echo "$signals" | jq '.completion_indicators | length' 2>/dev/null || echo "0")
    

    # Check for exit conditions

    # 0. Permission denials (highest priority - Issue #101)
    # When Claude Code is denied permission to run commands, halt immediately
    # to allow user to update .korerorc ALLOWED_TOOLS configuration
    if [[ -f "$RESPONSE_ANALYSIS_FILE" ]]; then
        local has_permission_denials=$(jq -r '.analysis.has_permission_denials // false' "$RESPONSE_ANALYSIS_FILE" 2>/dev/null || echo "false")
        if [[ "$has_permission_denials" == "true" ]]; then
            local denied_count=$(jq -r '.analysis.permission_denial_count // 0' "$RESPONSE_ANALYSIS_FILE" 2>/dev/null || echo "0")
            local denied_cmds=$(jq -r '.analysis.denied_commands | join(", ")' "$RESPONSE_ANALYSIS_FILE" 2>/dev/null || echo "unknown")
            log_status "WARN" "🚫 Permission denied for $denied_count command(s): $denied_cmds"
            log_status "WARN" "Update ALLOWED_TOOLS in .korerorc to include the required tools"
            echo "permission_denied"
            return 0
        fi
    fi

    # 1. Too many consecutive test-only loops
    if [[ $recent_test_loops -ge $MAX_CONSECUTIVE_TEST_LOOPS ]]; then
        log_status "WARN" "Exit condition: Too many test-focused loops ($recent_test_loops >= $MAX_CONSECUTIVE_TEST_LOOPS)"
        echo "test_saturation"
        return 0
    fi
    
    # 2. Multiple "done" signals
    if [[ $recent_done_signals -ge $MAX_CONSECUTIVE_DONE_SIGNALS ]]; then
        log_status "WARN" "Exit condition: Multiple completion signals ($recent_done_signals >= $MAX_CONSECUTIVE_DONE_SIGNALS)"
        echo "completion_signals"
        return 0
    fi
    
    # 3. Safety circuit breaker - force exit after 5 consecutive EXIT_SIGNAL=true responses
    # Note: completion_indicators only accumulates when Claude explicitly sets EXIT_SIGNAL=true
    # (not based on confidence score). This safety breaker catches cases where Claude signals
    # completion 5+ times but the normal exit path (completion_indicators >= 2 + EXIT_SIGNAL=true)
    # didn't trigger for some reason. Threshold of 5 prevents API waste while being higher than
    # the normal threshold (2) to avoid false positives.
    if [[ $recent_completion_indicators -ge 5 ]]; then
        log_status "WARN" "🚨 SAFETY CIRCUIT BREAKER: Force exit after 5 consecutive EXIT_SIGNAL=true responses ($recent_completion_indicators)" >&2
        echo "safety_circuit_breaker"
        return 0
    fi

    # 4. Strong completion indicators (only if Claude's EXIT_SIGNAL is true)
    # This prevents premature exits when heuristics detect completion patterns
    # but Claude explicitly indicates work is still in progress via KORERO_STATUS block.
    # The exit_signal in .response_analysis represents Claude's explicit intent.
    local claude_exit_signal="false"
    if [[ -f "$RESPONSE_ANALYSIS_FILE" ]]; then
        claude_exit_signal=$(jq -r '.analysis.exit_signal // false' "$RESPONSE_ANALYSIS_FILE" 2>/dev/null || echo "false")
    fi

    if [[ $recent_completion_indicators -ge 2 ]] && [[ "$claude_exit_signal" == "true" ]]; then
        log_status "WARN" "Exit condition: Strong completion indicators ($recent_completion_indicators) with EXIT_SIGNAL=true" >&2
        echo "project_complete"
        return 0
    fi
    
    # 5. fix_plan.md completion check removed
    # Loop termination is controlled solely by MAX_LOOPS in .korerorc.
    # Users set "continuous" or a specific number — that should be the authority.

    echo ""  # Return empty string instead of using return code
}

# =============================================================================
# MODERN CLI HELPER FUNCTIONS (Phase 1.1)
# =============================================================================

# Check Claude CLI version for compatibility with modern flags
check_claude_version() {
    local version=$($CLAUDE_CODE_CMD --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

    if [[ -z "$version" ]]; then
        log_status "WARN" "Cannot detect Claude CLI version, assuming compatible"
        return 0
    fi

    # Compare versions (simplified semver comparison)
    local required="$CLAUDE_MIN_VERSION"

    # Convert to comparable integers (major * 10000 + minor * 100 + patch)
    local ver_parts=(${version//./ })
    local req_parts=(${required//./ })

    local ver_num=$((${ver_parts[0]:-0} * 10000 + ${ver_parts[1]:-0} * 100 + ${ver_parts[2]:-0}))
    local req_num=$((${req_parts[0]:-0} * 10000 + ${req_parts[1]:-0} * 100 + ${req_parts[2]:-0}))

    if [[ $ver_num -lt $req_num ]]; then
        log_status "WARN" "Claude CLI version $version < $required. Some modern features may not work."
        log_status "WARN" "Consider upgrading: npm update -g @anthropic-ai/claude-code"
        return 1
    fi

    log_status "INFO" "Claude CLI version $version (>= $required) - modern features enabled"
    return 0
}

# Validate allowed tools against whitelist
# Returns 0 if valid, 1 if invalid with error message
validate_allowed_tools() {
    local tools_input=$1

    if [[ -z "$tools_input" ]]; then
        return 0  # Empty is valid (uses defaults)
    fi

    # Split by comma
    local IFS=','
    read -ra tools <<< "$tools_input"

    for tool in "${tools[@]}"; do
        # Trim whitespace
        tool=$(echo "$tool" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        if [[ -z "$tool" ]]; then
            continue
        fi

        local valid=false

        # Check against valid patterns
        for pattern in "${VALID_TOOL_PATTERNS[@]}"; do
            if [[ "$tool" == "$pattern" ]]; then
                valid=true
                break
            fi

            # Check for Bash(*) pattern - any Bash with parentheses is allowed
            if [[ "$tool" =~ ^Bash\(.+\)$ ]]; then
                valid=true
                break
            fi
        done

        if [[ "$valid" == "false" ]]; then
            echo "Error: Invalid tool in --allowed-tools: '$tool'"
            echo "Valid tools: ${VALID_TOOL_PATTERNS[*]}"
            echo "Note: Bash(...) patterns with any content are allowed (e.g., 'Bash(git *)')"
            return 1
        fi
    done

    return 0
}

# Build loop context for Claude Code session
# Provides loop-specific context via --append-system-prompt
build_loop_context() {
    local loop_count=$1
    local context=""

    # Add loop number
    context="Loop #${loop_count}. "

    # Extract incomplete tasks from fix_plan.md
    # Bug #3 Fix: Support indented markdown checkboxes with [[:space:]]* pattern
    if [[ -f "$KORERO_DIR/fix_plan.md" ]]; then
        local incomplete_tasks=$(grep -cE "^[[:space:]]*- \[ \]" "$KORERO_DIR/fix_plan.md" 2>/dev/null | tr -d '\r' || echo "0")
        context+="Remaining tasks: ${incomplete_tasks}. "
    fi

    # Add circuit breaker state
    if [[ -f "$KORERO_DIR/.circuit_breaker_state" ]]; then
        local cb_state=$(jq -r '.state // "UNKNOWN"' "$KORERO_DIR/.circuit_breaker_state" 2>/dev/null)
        if [[ "$cb_state" != "CLOSED" && "$cb_state" != "null" && -n "$cb_state" ]]; then
            context+="Circuit breaker: ${cb_state}. "
        fi
    fi

    # Add previous loop summary (truncated)
    if [[ -f "$RESPONSE_ANALYSIS_FILE" ]]; then
        local prev_summary=$(jq -r '.analysis.work_summary // ""' "$RESPONSE_ANALYSIS_FILE" 2>/dev/null | head -c 200)
        if [[ -n "$prev_summary" && "$prev_summary" != "null" ]]; then
            context+="Previous: ${prev_summary}. "
        fi
    fi

    # Add previous debate winner context (heavy modes)
    if [[ -f "$KORERO_DIR/.debate_result" ]]; then
        local prev_winner prev_title
        prev_winner=$(jq -r '.winner // ""' "$KORERO_DIR/.debate_result" 2>/dev/null)
        prev_title=$(jq -r '.title // ""' "$KORERO_DIR/.debate_result" 2>/dev/null)
        if [[ -n "$prev_title" && "$prev_title" != "null" ]]; then
            context+="Previous debate winner ($prev_winner): ${prev_title}. "
        fi
    fi

    # Add diversity stats for ideation modes
    local current_mode="${KORERO_MODE:-coding}"
    if [[ "$current_mode" == "idea" || "$current_mode" == "heavy-idea" || "$current_mode" == "coding" || "$current_mode" == "heavy-coding" ]]; then
        local diversity_stats=""
        diversity_stats=$(generate_diversity_stats "$KORERO_DIR/ideas" 2>/dev/null || echo "")
        if [[ -n "$diversity_stats" ]]; then
            context+="$diversity_stats "
        fi
    fi

    # Add idea context if implementing a specific idea
    if [[ -f "$KORERO_DIR/.idea_context" ]]; then
        local idea_title=""
        local idea_loop=""
        idea_title=$(grep "^IDEA_TITLE=" "$KORERO_DIR/.idea_context" 2>/dev/null | cut -d= -f2-)
        idea_loop=$(grep "^IDEA_LOOP=" "$KORERO_DIR/.idea_context" 2>/dev/null | cut -d= -f2-)
        if [[ -n "$idea_title" ]]; then
            context+="Implementing idea from loop ${idea_loop}: ${idea_title}. "
        fi
    fi

    # Limit total length to ~500 chars
    echo "${context:0:500}"
}

# Get session file age in hours (cross-platform)
# Returns: age in hours on stdout, or -1 if stat fails
# Note: Returns 0 for files less than 1 hour old
get_session_file_age_hours() {
    local file=$1

    if [[ ! -f "$file" ]]; then
        echo "0"
        return
    fi

    # Get file modification time using capability detection
    # Handles macOS with Homebrew coreutils where stat flags differ
    local file_mtime

    # Try GNU stat first (Linux, macOS with Homebrew coreutils)
    if file_mtime=$(stat -c %Y "$file" 2>/dev/null) && [[ -n "$file_mtime" && "$file_mtime" =~ ^[0-9]+$ ]]; then
        : # success
    # Try BSD stat (native macOS)
    elif file_mtime=$(stat -f %m "$file" 2>/dev/null) && [[ -n "$file_mtime" && "$file_mtime" =~ ^[0-9]+$ ]]; then
        : # success
    # Fallback to date -r (most portable)
    elif file_mtime=$(date -r "$file" +%s 2>/dev/null) && [[ -n "$file_mtime" && "$file_mtime" =~ ^[0-9]+$ ]]; then
        : # success
    else
        file_mtime=""
    fi

    # Handle stat failure - return -1 to indicate error
    # This prevents false expiration when stat fails
    if [[ -z "$file_mtime" || "$file_mtime" == "0" ]]; then
        echo "-1"
        return
    fi

    local current_time
    current_time=$(date +%s)

    local age_seconds=$((current_time - file_mtime))
    local age_hours=$((age_seconds / 3600))

    echo "$age_hours"
}

# Initialize or resume Claude session (with expiration check)
#
# Session Expiration Strategy:
# - Default expiration: 24 hours (configurable via CLAUDE_SESSION_EXPIRY_HOURS)
# - 24 hours chosen because: long enough for multi-day projects, short enough
#   to prevent stale context from causing unpredictable behavior
# - Sessions auto-expire to ensure Claude starts fresh periodically
#
# Returns (stdout):
#   - Session ID string: when resuming a valid, non-expired session
#   - Empty string: when starting new session (no file, expired, or stat error)
#
# Return codes:
#   - 0: Always returns success (caller should check stdout for session ID)
#
init_claude_session() {
    if [[ -f "$CLAUDE_SESSION_FILE" ]]; then
        # Check session age
        local age_hours
        age_hours=$(get_session_file_age_hours "$CLAUDE_SESSION_FILE")

        # Handle stat failure (-1) - treat as needing new session
        # Don't expire sessions when we can't determine age
        if [[ $age_hours -eq -1 ]]; then
            log_status "WARN" "Could not determine session age, starting new session"
            rm -f "$CLAUDE_SESSION_FILE"
            echo ""
            return 0
        fi

        # Check if session has expired
        if [[ $age_hours -ge $CLAUDE_SESSION_EXPIRY_HOURS ]]; then
            log_status "INFO" "Session expired (${age_hours}h old, max ${CLAUDE_SESSION_EXPIRY_HOURS}h), starting new session"
            rm -f "$CLAUDE_SESSION_FILE"
            echo ""
            return 0
        fi

        # Session is valid, try to read it
        local session_id=$(cat "$CLAUDE_SESSION_FILE" 2>/dev/null)
        if [[ -n "$session_id" ]]; then
            log_status "INFO" "Resuming Claude session: ${session_id:0:20}... (${age_hours}h old)"
            echo "$session_id"
            return 0
        fi
    fi

    log_status "INFO" "Starting new Claude session"
    echo ""
}

# Save session ID after successful execution
save_claude_session() {
    local output_file=$1

    # Try to extract session ID from JSON output
    if [[ -f "$output_file" ]]; then
        local session_id=$(jq -r '.metadata.session_id // .session_id // empty' "$output_file" 2>/dev/null)
        if [[ -n "$session_id" && "$session_id" != "null" ]]; then
            echo "$session_id" > "$CLAUDE_SESSION_FILE"
            log_status "INFO" "Saved Claude session: ${session_id:0:20}..."
        fi
    fi
}

# =============================================================================
# SESSION LIFECYCLE MANAGEMENT FUNCTIONS (Phase 1.2)
# =============================================================================

# Get current session ID from Korero session file
# Returns: session ID string or empty if not found
get_session_id() {
    if [[ ! -f "$KORERO_SESSION_FILE" ]]; then
        echo ""
        return 0
    fi

    # Extract session_id from JSON file (SC2155: separate declare from assign)
    local session_id
    session_id=$(jq -r '.session_id // ""' "$KORERO_SESSION_FILE" 2>/dev/null)
    local jq_status=$?

    # Handle jq failure or null/empty results
    if [[ $jq_status -ne 0 || -z "$session_id" || "$session_id" == "null" ]]; then
        session_id=""
    fi
    echo "$session_id"
    return 0
}

# Reset session with reason logging
# Usage: reset_session "reason_for_reset"
reset_session() {
    local reason=${1:-"manual_reset"}

    # Get current timestamp
    local reset_timestamp
    reset_timestamp=$(get_iso_timestamp)

    # Always create/overwrite the session file using jq for safe JSON escaping
    jq -n \
        --arg session_id "" \
        --arg created_at "" \
        --arg last_used "" \
        --arg reset_at "$reset_timestamp" \
        --arg reset_reason "$reason" \
        '{
            session_id: $session_id,
            created_at: $created_at,
            last_used: $last_used,
            reset_at: $reset_at,
            reset_reason: $reset_reason
        }' > "$KORERO_SESSION_FILE"

    # Also clear the Claude session file for consistency
    rm -f "$CLAUDE_SESSION_FILE" 2>/dev/null

    # Clear exit signals to prevent stale completion indicators from causing premature exit (issue #91)
    # This ensures a fresh start without leftover state from previous sessions
    if [[ -f "$EXIT_SIGNALS_FILE" ]]; then
        echo '{"test_only_loops": [], "done_signals": [], "completion_indicators": []}' > "$EXIT_SIGNALS_FILE"
        [[ "${VERBOSE_PROGRESS:-}" == "true" ]] && log_status "INFO" "Cleared exit signals file"
    fi

    # Clear response analysis to prevent stale EXIT_SIGNAL from previous session
    rm -f "$RESPONSE_ANALYSIS_FILE" 2>/dev/null

    # Log the session transition (non-fatal to prevent script exit under set -e)
    log_session_transition "active" "reset" "$reason" "${loop_count:-0}" || true

    log_status "INFO" "Session reset: $reason"
}

# Log session state transitions to history file
# Usage: log_session_transition from_state to_state reason loop_number
log_session_transition() {
    local from_state=$1
    local to_state=$2
    local reason=$3
    local loop_number=${4:-0}

    # Get timestamp once (SC2155: separate declare from assign)
    local ts
    ts=$(get_iso_timestamp)

    # Create transition entry using jq for safe JSON (SC2155: separate declare from assign)
    local transition
    transition=$(jq -n -c \
        --arg timestamp "$ts" \
        --arg from_state "$from_state" \
        --arg to_state "$to_state" \
        --arg reason "$reason" \
        --argjson loop_number "$loop_number" \
        '{
            timestamp: $timestamp,
            from_state: $from_state,
            to_state: $to_state,
            reason: $reason,
            loop_number: $loop_number
        }')

    # Read history file defensively - fallback to empty array on any failure
    local history
    if [[ -f "$KORERO_SESSION_HISTORY_FILE" ]]; then
        history=$(cat "$KORERO_SESSION_HISTORY_FILE" 2>/dev/null)
        # Validate JSON, fallback to empty array if corrupted
        if ! echo "$history" | jq empty 2>/dev/null; then
            history='[]'
        fi
    else
        history='[]'
    fi

    # Append transition and keep only last 50 entries
    local updated_history
    updated_history=$(echo "$history" | jq ". += [$transition] | .[-50:]" 2>/dev/null)
    local jq_status=$?

    # Only write if jq succeeded
    if [[ $jq_status -eq 0 && -n "$updated_history" ]]; then
        echo "$updated_history" > "$KORERO_SESSION_HISTORY_FILE"
    else
        # Fallback: start fresh with just this transition
        echo "[$transition]" > "$KORERO_SESSION_HISTORY_FILE"
    fi
}

# Generate a unique session ID using timestamp and random component
generate_session_id() {
    local ts
    ts=$(date +%s)
    local rand
    rand=$RANDOM
    echo "korero-${ts}-${rand}"
}

# Initialize session tracking (called at loop start)
init_session_tracking() {
    local ts
    ts=$(get_iso_timestamp)

    # Create session file if it doesn't exist
    if [[ ! -f "$KORERO_SESSION_FILE" ]]; then
        local new_session_id
        new_session_id=$(generate_session_id)

        jq -n \
            --arg session_id "$new_session_id" \
            --arg created_at "$ts" \
            --arg last_used "$ts" \
            --arg reset_at "" \
            --arg reset_reason "" \
            '{
                session_id: $session_id,
                created_at: $created_at,
                last_used: $last_used,
                reset_at: $reset_at,
                reset_reason: $reset_reason
            }' > "$KORERO_SESSION_FILE"

        log_status "INFO" "Initialized session tracking (session: $new_session_id)"
        return 0
    fi

    # Validate existing session file
    if ! jq empty "$KORERO_SESSION_FILE" 2>/dev/null; then
        log_status "WARN" "Corrupted session file detected, recreating..."
        local new_session_id
        new_session_id=$(generate_session_id)

        jq -n \
            --arg session_id "$new_session_id" \
            --arg created_at "$ts" \
            --arg last_used "$ts" \
            --arg reset_at "$ts" \
            --arg reset_reason "corrupted_file_recovery" \
            '{
                session_id: $session_id,
                created_at: $created_at,
                last_used: $last_used,
                reset_at: $reset_at,
                reset_reason: $reset_reason
            }' > "$KORERO_SESSION_FILE"
    fi
}

# Update last_used timestamp in session file (called on each loop iteration)
update_session_last_used() {
    if [[ ! -f "$KORERO_SESSION_FILE" ]]; then
        return 0
    fi

    local ts
    ts=$(get_iso_timestamp)

    # Update last_used in existing session file
    local updated
    updated=$(jq --arg last_used "$ts" '.last_used = $last_used' "$KORERO_SESSION_FILE" 2>/dev/null)
    local jq_status=$?

    if [[ $jq_status -eq 0 && -n "$updated" ]]; then
        echo "$updated" > "$KORERO_SESSION_FILE"
    fi
}

# Global array for Claude command arguments (avoids shell injection)
declare -a CLAUDE_CMD_ARGS=()

# Build Claude CLI command with modern flags using array (shell-injection safe)
# Populates global CLAUDE_CMD_ARGS array for direct execution
# Uses -p flag with prompt content (Claude CLI does not have --prompt-file)
build_claude_command() {
    local prompt_file=$1
    local loop_context=$2
    local session_id=$3

    # Reset global array
    # Note: We do NOT use --dangerously-skip-permissions here. Tool permissions
    # are controlled via --allowedTools from CLAUDE_ALLOWED_TOOLS in .korerorc.
    # This preserves the permission denial circuit breaker (Issue #101).
    CLAUDE_CMD_ARGS=("$CLAUDE_CODE_CMD")

    # Check if prompt file exists
    if [[ ! -f "$prompt_file" ]]; then
        log_status "ERROR" "Prompt file not found: $prompt_file"
        return 1
    fi

    # Add output format flag
    if [[ "$CLAUDE_OUTPUT_FORMAT" == "json" ]]; then
        CLAUDE_CMD_ARGS+=("--output-format" "json")
    fi

    # Add allowed tools (each tool as separate array element)
    if [[ -n "$CLAUDE_ALLOWED_TOOLS" ]]; then
        CLAUDE_CMD_ARGS+=("--allowedTools")
        # Split by comma and add each tool
        local IFS=','
        read -ra tools_array <<< "$CLAUDE_ALLOWED_TOOLS"
        for tool in "${tools_array[@]}"; do
            # Trim whitespace
            tool=$(echo "$tool" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [[ -n "$tool" ]]; then
                CLAUDE_CMD_ARGS+=("$tool")
            fi
        done
    fi

    # Add session continuity flag
    # IMPORTANT: Use --resume with explicit session ID instead of --continue
    # --continue resumes the "most recent session in current directory" which
    # can hijack active Claude Code sessions. --resume with a specific session ID
    # ensures we only resume Korero's own sessions. (Issue #151)
    if [[ "$CLAUDE_USE_CONTINUE" == "true" && -n "$session_id" ]]; then
        CLAUDE_CMD_ARGS+=("--resume" "$session_id")
    fi
    # If no session_id, start fresh - Claude will generate a new session ID
    # which we'll capture via save_claude_session() for future loops

    # Add loop context as system prompt (no escaping needed - array handles it)
    if [[ -n "$loop_context" ]]; then
        CLAUDE_CMD_ARGS+=("--append-system-prompt" "$loop_context")
    fi

    # Read prompt file content and use -p flag
    # Note: Claude CLI uses -p for prompts, not --prompt-file (which doesn't exist)
    # Array-based approach maintains shell injection safety
    local prompt_content
    prompt_content=$(cat "$prompt_file")
    CLAUDE_CMD_ARGS+=("-p" "$prompt_content")
}

# Main execution function
execute_claude_code() {
    local timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
    local output_file="$LOG_DIR/claude_output_${timestamp}.log"
    local loop_count=$1
    local calls_made=$(cat "$CALL_COUNT_FILE" 2>/dev/null || echo "0")
    calls_made=$((calls_made + 1))

    # Rate limit approach warnings
    check_rate_limit_warnings "$calls_made"

    # Fix #141: Capture git HEAD SHA at loop start to detect commits as progress
    # Store in file for access by progress detection after Claude execution
    local loop_start_sha=""
    if command -v git &>/dev/null && git rev-parse --git-dir &>/dev/null 2>&1; then
        loop_start_sha=$(git rev-parse HEAD 2>/dev/null || echo "")
    fi
    echo "$loop_start_sha" > "$KORERO_DIR/.loop_start_sha"

    log_status "LOOP" "Executing Claude Code (Call $calls_made/$MAX_CALLS_PER_HOUR)"
    local timeout_seconds=$((CLAUDE_TIMEOUT_MINUTES * 60))
    log_status "INFO" "⏳ Starting Claude Code execution... (timeout: ${CLAUDE_TIMEOUT_MINUTES}m)"

    # Build loop context for session continuity
    local loop_context=""
    if [[ "$CLAUDE_USE_CONTINUE" == "true" ]]; then
        loop_context=$(build_loop_context "$loop_count")
        if [[ -n "$loop_context" && "$VERBOSE_PROGRESS" == "true" ]]; then
            log_status "INFO" "Loop context: $loop_context"
        fi
    fi

    # Initialize or resume session
    local session_id=""
    if [[ "$CLAUDE_USE_CONTINUE" == "true" ]]; then
        session_id=$(init_claude_session)
    fi

    # Build the Claude CLI command with modern flags
    # Note: We use the modern CLI with -p flag when CLAUDE_OUTPUT_FORMAT is "json"
    # For backward compatibility, fall back to stdin piping for text mode
    local use_modern_cli=false

    if [[ "$CLAUDE_OUTPUT_FORMAT" == "json" ]]; then
        # Modern approach: use CLI flags (builds CLAUDE_CMD_ARGS array)
        if build_claude_command "$PROMPT_FILE" "$loop_context" "$session_id"; then
            use_modern_cli=true
            log_status "INFO" "Using modern CLI mode (JSON output)"
        else
            log_status "WARN" "Failed to build modern CLI command, falling back to legacy mode"
        fi
    else
        log_status "INFO" "Using legacy CLI mode (text output)"
    fi

    # Execute Claude Code
    local exit_code=0

    # Initialize live.log for this execution
    echo -e "\n\n=== Loop #$loop_count - $(date '+%Y-%m-%d %H:%M:%S') ===" > "$LIVE_LOG_FILE"

    if [[ "$LIVE_OUTPUT" == "true" ]]; then
        # LIVE MODE: Show streaming output in real-time using stream-json + jq
        # Based on: https://www.ytyng.com/en/blog/claude-stream-json-jq/
        #
        # Uses CLAUDE_CMD_ARGS from build_claude_command() to preserve:
        # - --allowedTools (tool permissions)
        # - --append-system-prompt (loop context)
        # - --continue (session continuity)
        # - -p (prompt content)

        # Check dependencies for live mode
        if ! command -v jq &> /dev/null; then
            log_status "ERROR" "Live mode requires 'jq' but it's not installed. Falling back to background mode."
            LIVE_OUTPUT=false
        elif ! command -v stdbuf &> /dev/null; then
            log_status "ERROR" "Live mode requires 'stdbuf' (from coreutils) but it's not installed. Falling back to background mode."
            LIVE_OUTPUT=false
        fi
    fi

    if [[ "$LIVE_OUTPUT" == "true" ]]; then
        log_status "INFO" "📺 Live output mode enabled - showing Claude Code streaming..."
        echo -e "${PURPLE}━━━━━━━━━━━━━━━━ Claude Code Output ━━━━━━━━━━━━━━━━${NC}"

        # Modify CLAUDE_CMD_ARGS: replace --output-format value with stream-json
        # and add streaming-specific flags
        local -a LIVE_CMD_ARGS=()
        local skip_next=false
        for arg in "${CLAUDE_CMD_ARGS[@]}"; do
            if [[ "$skip_next" == "true" ]]; then
                # Replace "json" with "stream-json" for output format
                LIVE_CMD_ARGS+=("stream-json")
                skip_next=false
            elif [[ "$arg" == "--output-format" ]]; then
                LIVE_CMD_ARGS+=("$arg")
                skip_next=true
            else
                LIVE_CMD_ARGS+=("$arg")
            fi
        done

        # Add streaming-specific flags (--verbose and --include-partial-messages)
        # These are required for stream-json to work properly
        LIVE_CMD_ARGS+=("--verbose" "--include-partial-messages")

        # jq filter: show text + tool names + newlines for readability
        local jq_filter='
            if .type == "stream_event" then
                if .event.type == "content_block_delta" and .event.delta.type == "text_delta" then
                    .event.delta.text
                elif .event.type == "content_block_start" and .event.content_block.type == "tool_use" then
                    "\n\n⚡ [" + .event.content_block.name + "]\n"
                elif .event.type == "content_block_stop" then
                    "\n"
                else
                    empty
                end
            else
                empty
            end'

        # Execute with streaming, preserving all flags from build_claude_command()
        # Use stdbuf to disable buffering for real-time output
        # Use portable_timeout for consistent timeout protection (Issue: missing timeout)
        # Capture all pipeline exit codes for proper error handling
        set -o pipefail
        portable_timeout ${timeout_seconds}s stdbuf -oL "${LIVE_CMD_ARGS[@]}" \
            2>&1 | stdbuf -oL tee "$output_file" | stdbuf -oL jq --unbuffered -j "$jq_filter" 2>/dev/null | tee "$LIVE_LOG_FILE"

        # Capture exit codes from pipeline
        local -a pipe_status=("${PIPESTATUS[@]}")
        set +o pipefail

        # Primary exit code is from Claude/timeout (first command in pipeline)
        exit_code=${pipe_status[0]}

        # Check for tee failures (second command) - could break logging/session
        if [[ ${pipe_status[1]} -ne 0 ]]; then
            log_status "WARN" "Failed to write stream output to log file (exit code ${pipe_status[1]})"
        fi

        # Check for jq failures (third command) - warn but don't fail
        if [[ ${pipe_status[2]} -ne 0 ]]; then
            log_status "WARN" "jq filter had issues parsing some stream events (exit code ${pipe_status[2]})"
        fi

        echo ""
        echo -e "${PURPLE}━━━━━━━━━━━━━━━━ End of Output ━━━━━━━━━━━━━━━━━━━${NC}"

        # Extract session ID from stream-json output for session continuity
        # Stream-json format has session_id in the final "result" type message
        # Keep full stream output in _stream.log, extract session data separately
        if [[ "$CLAUDE_USE_CONTINUE" == "true" && -f "$output_file" ]]; then
            # Preserve full stream output for analysis (don't overwrite output_file)
            local stream_output_file="${output_file%.log}_stream.log"
            cp "$output_file" "$stream_output_file"

            # Extract the result message and convert to standard JSON format
            # Use flexible regex to match various JSON formatting styles
            # Matches: "type":"result", "type": "result", "type" : "result"
            local result_line=$(grep -E '"type"[[:space:]]*:[[:space:]]*"result"' "$output_file" 2>/dev/null | tail -1)

            if [[ -n "$result_line" ]]; then
                # Validate that extracted line is valid JSON before using it
                if echo "$result_line" | jq -e . >/dev/null 2>&1; then
                    # Write validated result as the output_file for downstream processing
                    # (save_claude_session and analyze_response expect JSON format)
                    echo "$result_line" > "$output_file"
                    log_status "INFO" "Extracted and validated session data from stream output"
                else
                    log_status "WARN" "Extracted result line is not valid JSON, keeping stream output"
                    # Restore original stream output
                    cp "$stream_output_file" "$output_file"
                fi
            else
                log_status "WARN" "Could not find result message in stream output"
                # Keep stream output as-is for debugging
            fi
        fi
    else
        # BACKGROUND MODE: Original behavior with progress monitoring
        if [[ "$use_modern_cli" == "true" ]]; then
            # Modern execution with command array (shell-injection safe)
            # Execute array directly without bash -c to prevent shell metacharacter interpretation
            if portable_timeout ${timeout_seconds}s "${CLAUDE_CMD_ARGS[@]}" > "$output_file" 2>&1 &
            then
                :  # Continue to wait loop
            else
                log_status "ERROR" "❌ Failed to start Claude Code process (modern mode)"
                # Fall back to legacy mode
                log_status "INFO" "Falling back to legacy mode..."
                use_modern_cli=false
            fi
        fi

        # Fall back to legacy stdin piping if modern mode failed or not enabled
        # Note: Legacy mode doesn't use --allowedTools, so tool permissions
        # will be handled by Claude Code's default permission system
        if [[ "$use_modern_cli" == "false" ]]; then
            if portable_timeout ${timeout_seconds}s $CLAUDE_CODE_CMD < "$PROMPT_FILE" > "$output_file" 2>&1 &
            then
                :  # Continue to wait loop
            else
                log_status "ERROR" "❌ Failed to start Claude Code process"
                return 1
            fi
        fi

        # Get PID and monitor progress
        local claude_pid=$!
        local progress_counter=0

        # Show progress while Claude Code is running
        while kill -0 $claude_pid 2>/dev/null; do
            progress_counter=$((progress_counter + 1))
            case $((progress_counter % 4)) in
                1) progress_indicator="⠋" ;;
                2) progress_indicator="⠙" ;;
                3) progress_indicator="⠹" ;;
                0) progress_indicator="⠸" ;;
            esac

            # Get last line from output if available
            local last_line=""
            if [[ -f "$output_file" && -s "$output_file" ]]; then
                last_line=$(tail -1 "$output_file" 2>/dev/null | head -c 80)
                # Copy to live.log for tmux monitoring
                cp "$output_file" "$LIVE_LOG_FILE" 2>/dev/null
            fi

            # Update progress file for monitor
            cat > "$PROGRESS_FILE" << EOF
{
    "status": "executing",
    "indicator": "$progress_indicator",
    "elapsed_seconds": $((progress_counter * 10)),
    "last_output": "$last_line",
    "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOF

            # Only log if verbose mode is enabled
            if [[ "$VERBOSE_PROGRESS" == "true" ]]; then
                if [[ -n "$last_line" ]]; then
                    log_status "INFO" "$progress_indicator Claude Code: $last_line... (${progress_counter}0s)"
                else
                    log_status "INFO" "$progress_indicator Claude Code working... (${progress_counter}0s elapsed)"
                fi
            fi

            sleep 10
        done

        # Wait for the process to finish and get exit code
        wait $claude_pid
        exit_code=$?
    fi

    if [ $exit_code -eq 0 ]; then
        # Only increment counter on successful execution
        echo "$calls_made" > "$CALL_COUNT_FILE"

        # Clear progress file
        echo '{"status": "completed", "timestamp": "'$(date '+%Y-%m-%d %H:%M:%S')'"}' > "$PROGRESS_FILE"

        log_status "SUCCESS" "✅ Claude Code execution completed successfully"

        # Save session ID from JSON output (Phase 1.1)
        if [[ "$CLAUDE_USE_CONTINUE" == "true" ]]; then
            save_claude_session "$output_file"
        fi

        # Analyze the response
        log_status "INFO" "🔍 Analyzing Claude Code response..."
        analyze_response "$output_file" "$loop_count"
        local analysis_exit_code=$?

        # Update exit signals based on analysis
        update_exit_signals

        # Extract and save idea (ideation modes only)
        local korero_mode="${KORERO_MODE:-}"
        if [[ "$korero_mode" == "idea" || "$korero_mode" == "coding" ]]; then
            store_loop_idea "$output_file" "$loop_count"
        fi

        # Log analysis summary
        log_analysis_summary

        # Get file change count for circuit breaker
        # Fix #141: Detect both uncommitted changes AND committed changes
        local files_changed=0
        local loop_start_sha=""
        local current_sha=""

        if [[ -f "$KORERO_DIR/.loop_start_sha" ]]; then
            loop_start_sha=$(cat "$KORERO_DIR/.loop_start_sha" 2>/dev/null || echo "")
        fi

        if command -v git &>/dev/null && git rev-parse --git-dir &>/dev/null 2>&1; then
            current_sha=$(git rev-parse HEAD 2>/dev/null || echo "")

            # Check if commits were made (HEAD changed)
            if [[ -n "$loop_start_sha" && -n "$current_sha" && "$loop_start_sha" != "$current_sha" ]]; then
                # Commits were made - count union of committed files AND working tree changes
                # This catches cases where Claude commits some files but still has other modified files
                files_changed=$(
                    {
                        git diff --name-only "$loop_start_sha" "$current_sha" 2>/dev/null
                        git diff --name-only HEAD 2>/dev/null           # unstaged changes
                        git diff --name-only --cached 2>/dev/null       # staged changes
                    } | sort -u | wc -l
                )
                [[ "$VERBOSE_PROGRESS" == "true" ]] && log_status "DEBUG" "Detected $files_changed unique files changed (commits + working tree) since loop start"
            else
                # No commits - check for uncommitted changes (staged + unstaged)
                files_changed=$(
                    {
                        git diff --name-only 2>/dev/null                # unstaged changes
                        git diff --name-only --cached 2>/dev/null       # staged changes
                    } | sort -u | wc -l
                )
            fi
        fi

        local has_errors="false"

        # Two-stage error detection to avoid JSON field false positives
        # Stage 1: Filter out JSON field patterns like "is_error": false
        # Stage 2: Look for actual error messages in specific contexts
        # Avoid type annotations like "error: Error" by requiring lowercase after ": error"
        if grep -v '"[^"]*error[^"]*":' "$output_file" 2>/dev/null | \
           grep -qE '(^Error:|^ERROR:|^error:|\]: error|Link: error|Error occurred|failed with error|[Ee]xception|Fatal|FATAL)'; then
            has_errors="true"

            # Debug logging: show what triggered error detection
            if [[ "$VERBOSE_PROGRESS" == "true" ]]; then
                log_status "DEBUG" "Error patterns found:"
                grep -v '"[^"]*error[^"]*":' "$output_file" 2>/dev/null | \
                    grep -nE '(^Error:|^ERROR:|^error:|\]: error|Link: error|Error occurred|failed with error|[Ee]xception|Fatal|FATAL)' | \
                    head -3 | while IFS= read -r line; do
                    log_status "DEBUG" "  $line"
                done
            fi

            log_status "WARN" "Errors detected in output, check: $output_file"
        fi
        local output_length=$(wc -c < "$output_file" 2>/dev/null || echo 0)

        # Record result in circuit breaker
        record_loop_result "$loop_count" "$files_changed" "$has_errors" "$output_length"
        local circuit_result=$?

        if [[ $circuit_result -ne 0 ]]; then
            log_status "WARN" "Circuit breaker opened - halting execution"
            return 3  # Special code for circuit breaker trip
        fi

        return 0
    else
        # Clear progress file on failure
        echo '{"status": "failed", "timestamp": "'$(date '+%Y-%m-%d %H:%M:%S')'"}' > "$PROGRESS_FILE"

        # Check if the failure is due to API 5-hour limit
        if grep -qi "5.*hour.*limit\|limit.*reached.*try.*back\|usage.*limit.*reached" "$output_file"; then
            log_status "ERROR" "🚫 Claude API 5-hour usage limit reached"
            return 2  # Special return code for API limit
        else
            log_status "ERROR" "❌ Claude Code execution failed, check: $output_file"
            return 1
        fi
    fi
}

# =============================================================================
# HEAVY MODE EXECUTION (Dual-AI: Claude + Codex)
# =============================================================================

# execute_heavy_loop - Run Claude and Codex in parallel, then cross-AI debate
#
# Parameters:
#   $1 (loop_count) - Current loop number
#
# Returns: 0 (success), 1 (failure), 2 (API limit), 3 (circuit breaker)
execute_heavy_loop() {
    local loop_count=$1
    local timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
    local claude_output="$LOG_DIR/claude_proposal_${timestamp}.log"
    local codex_output="$LOG_DIR/codex_proposal_${timestamp}.log"
    local codex_last_msg="$LOG_DIR/codex_lastmsg_${timestamp}.log"
    local korero_mode="${KORERO_MODE:-heavy-coding}"
    local calls_made=$(cat "$CALL_COUNT_FILE" 2>/dev/null || echo "0")
    calls_made=$((calls_made + 1))

    check_rate_limit_warnings "$calls_made"

    # Capture git HEAD SHA for progress detection
    local loop_start_sha=""
    if command -v git &>/dev/null && git rev-parse --git-dir &>/dev/null 2>&1; then
        loop_start_sha=$(git rev-parse HEAD 2>/dev/null || echo "")
    fi
    echo "$loop_start_sha" > "$KORERO_DIR/.loop_start_sha"

    log_status "LOOP" "Heavy mode: Dual-AI parallel execution (Claude + Codex)"
    local timeout_seconds=$((CLAUDE_TIMEOUT_MINUTES * 60))
    local codex_timeout=$((CODEX_TIMEOUT_MINUTES * 60))

    # Build loop context
    local loop_context=""
    if [[ "$CLAUDE_USE_CONTINUE" == "true" ]]; then
        loop_context=$(build_loop_context "$loop_count")
    fi

    # Add cross-AI competition context
    local heavy_context="You are in a DUAL-AI competition. Another AI (Codex) also receives this prompt. Your proposals will be debated head-to-head. Focus on producing your single BEST idea."

    # Initialize session
    local session_id=""
    if [[ "$CLAUDE_USE_CONTINUE" == "true" ]]; then
        session_id=$(init_claude_session)
    fi

    # === PHASE 1: PARALLEL PROPOSAL GENERATION ===
    log_status "LOOP" "Phase 1: Parallel proposal generation (Claude + Codex)"
    init_debate_transcript "$loop_count" > /dev/null

    # Read prompt content
    local prompt_content
    prompt_content=$(cat "$PROMPT_FILE")

    # Build and execute Claude in background
    local combined_context="$loop_context $heavy_context"
    build_claude_command "$PROMPT_FILE" "$combined_context" "$session_id"
    portable_timeout "${timeout_seconds}s" "${CLAUDE_CMD_ARGS[@]}" > "$claude_output" 2>&1 &
    local claude_pid=$!

    # Build and execute Codex in background
    local codex_prompt="$prompt_content

$heavy_context"
    build_codex_command "$codex_prompt" "$korero_mode"
    portable_timeout "${codex_timeout}s" "${CODEX_CMD_ARGS[@]}" > "$codex_output" 2>&1 &
    local codex_pid=$!

    # Wait for both to complete
    local claude_exit=0 codex_exit=0
    wait $claude_pid || claude_exit=$?
    wait $codex_pid || codex_exit=$?

    log_status "INFO" "Claude exit: $claude_exit, Codex exit: $codex_exit"

    # Log Codex error details when it fails
    if [[ $codex_exit -ne 0 && -f "$codex_output" ]]; then
        local codex_err
        codex_err=$(tail -5 "$codex_output" 2>/dev/null || echo "(no output)")
        log_status "WARN" "Codex stderr/output: $codex_err"
    fi

    # Handle failures — fallback to surviving AI
    if [[ $claude_exit -ne 0 && $codex_exit -ne 0 ]]; then
        log_status "ERROR" "Both AIs failed. Claude=$claude_exit, Codex=$codex_exit"
        echo '{"status": "failed", "timestamp": "'$(date '+%Y-%m-%d %H:%M:%S')'"}' > "$PROGRESS_FILE"
        return 1
    fi

    # Update call counter
    echo "$calls_made" > "$CALL_COUNT_FILE"

    # Save Claude session if available
    if [[ $claude_exit -eq 0 && -f "$claude_output" ]]; then
        save_claude_session "$claude_output"
    fi

    # Record proposals in transcript
    local claude_proposal_text="" codex_proposal_text=""
    if [[ $claude_exit -eq 0 && -f "$claude_output" ]]; then
        claude_proposal_text=$(cat "$claude_output" 2>/dev/null)
        # Extract .result from JSON if present
        if command -v jq &>/dev/null; then
            local json_result
            json_result=$(echo "$claude_proposal_text" | jq -r '.result // empty' 2>/dev/null || true)
            if [[ -n "$json_result" ]]; then
                claude_proposal_text="$json_result"
            fi
        fi
    fi

    if [[ $codex_exit -eq 0 ]]; then
        codex_proposal_text=$(extract_codex_proposal "$codex_output" "$codex_last_msg")
    fi

    append_transcript_section "$loop_count" "Claude Proposal" "${claude_proposal_text:0:5000}"
    append_transcript_section "$loop_count" "Codex Proposal" "${codex_proposal_text:0:5000}"

    # === PHASE 2: CROSS-AI DEBATE ===
    # If only one AI produced output, skip debate and use its proposal
    if [[ $claude_exit -ne 0 || -z "$claude_proposal_text" ]]; then
        log_status "WARN" "Claude failed — using Codex proposal directly"
        # Write codex proposal to a temp file for store_loop_idea
        echo "$codex_proposal_text" > "$KORERO_DIR/.winning_proposal"
        cat > "$DEBATE_RESULT_FILE" << CODEX_FALLBACK
{
  "winner": "codex",
  "title": "Codex proposal (Claude unavailable)",
  "confidence": 100,
  "rationale": "Claude execution failed. Using Codex proposal directly."
}
CODEX_FALLBACK
        append_transcript_section "$loop_count" "Outcome" "Codex wins by default (Claude failed)."
    elif [[ $codex_exit -ne 0 || -z "$codex_proposal_text" ]]; then
        log_status "WARN" "Codex failed — using Claude proposal directly"
        echo "$claude_proposal_text" > "$KORERO_DIR/.winning_proposal"
        cat > "$DEBATE_RESULT_FILE" << CLAUDE_FALLBACK
{
  "winner": "claude",
  "title": "Claude proposal (Codex unavailable)",
  "confidence": 100,
  "rationale": "Codex execution failed. Using Claude proposal directly."
}
CLAUDE_FALLBACK
        append_transcript_section "$loop_count" "Outcome" "Claude wins by default (Codex failed)."
    else
        # Both AIs produced proposals — run the debate
        log_status "LOOP" "Phase 2: Cross-AI debate ($DEBATE_ROUNDS rounds)"

        # Write proposals to temp files for the debate orchestrator
        local claude_prop_file="$KORERO_DIR/.claude_proposal"
        local codex_prop_file="$KORERO_DIR/.codex_proposal"
        echo "$claude_proposal_text" > "$claude_prop_file"
        echo "$codex_proposal_text" > "$codex_prop_file"

        # Determine project name from .korerorc or directory
        local project_name="${PROJECT_SUBJECT:-$(basename "$(pwd)")}"

        run_cross_ai_debate "$claude_prop_file" "$codex_prop_file" "$loop_count" "$korero_mode" "$project_name" "$DEBATE_ROUNDS" || true

        # Copy winning proposal for downstream processing
        local winner
        winner=$(get_debate_winner || echo "claude")
        if [[ "$winner" == "codex" ]]; then
            cp "$codex_prop_file" "$KORERO_DIR/.winning_proposal"
        else
            cp "$claude_prop_file" "$KORERO_DIR/.winning_proposal"
        fi
    fi

    # === PHASE 3: WINNER PROCESSING ===
    local winner_title
    if command -v jq &>/dev/null && [[ -f "$DEBATE_RESULT_FILE" ]]; then
        winner_title=$(jq -r '.title // "unknown"' "$DEBATE_RESULT_FILE" 2>/dev/null || echo "unknown")
    else
        winner_title="(unknown)"
    fi
    local winner
    winner=$(get_debate_winner || echo "claude")

    finalize_debate_transcript "$loop_count" "$winner_title (by $winner)" || true
    log_status "SUCCESS" "Debate winner: $winner — $winner_title"

    if [[ "$korero_mode" == "heavy-coding" ]]; then
        # Implementation phase: Claude implements the winning idea
        log_status "LOOP" "Phase 3: Claude implementing winning idea"

        local winning_proposal
        winning_proposal=$(cat "$KORERO_DIR/.winning_proposal" 2>/dev/null || echo "")

        local impl_prompt="Implement the following winning idea from a cross-AI debate. This idea was selected as the best proposal after structured evaluation.

## Winning Idea
$winner_title

## Full Proposal
$winning_proposal

## Instructions
1. Plan the implementation approach
2. Implement the changes
3. Write tests for the new code
4. Create a git commit with a descriptive message
5. Update .korero/fix_plan.md to reflect completed work"

        local impl_output="$LOG_DIR/claude_impl_${timestamp}.log"
        declare -a IMPL_CMD_ARGS=("$CLAUDE_CODE_CMD" "--output-format" "$CLAUDE_OUTPUT_FORMAT")

        if [[ -n "$CLAUDE_ALLOWED_TOOLS" ]]; then
            IMPL_CMD_ARGS+=("--allowedTools")
            local IFS=','
            read -ra tools_array <<< "$CLAUDE_ALLOWED_TOOLS"
            for tool in "${tools_array[@]}"; do
                tool=$(echo "$tool" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                if [[ -n "$tool" ]]; then
                    IMPL_CMD_ARGS+=("$tool")
                fi
            done
        fi

        if [[ "$CLAUDE_USE_CONTINUE" == "true" && -n "$session_id" ]]; then
            IMPL_CMD_ARGS+=("--resume" "$session_id")
        fi
        IMPL_CMD_ARGS+=("-p" "$impl_prompt")

        portable_timeout "${timeout_seconds}s" "${IMPL_CMD_ARGS[@]}" > "$impl_output" 2>&1
        local impl_exit=$?

        if [[ $impl_exit -eq 0 ]]; then
            log_status "SUCCESS" "Implementation completed"
            save_claude_session "$impl_output"
            analyze_response "$impl_output" "$loop_count"
            update_exit_signals "$impl_output" "$loop_count"
        else
            log_status "WARN" "Implementation phase failed (exit: $impl_exit)"
        fi

        # Also store idea for tracking
        store_loop_idea "$impl_output" "$loop_count"
    else
        # heavy-idea: save winning idea to disk
        log_status "LOOP" "Phase 3: Saving winning idea to disk"

        # Create a synthetic output file with KORERO_IDEA block for store_loop_idea
        local idea_output="$LOG_DIR/idea_output_${timestamp}.log"
        local winning_text
        winning_text=$(cat "$KORERO_DIR/.winning_proposal" 2>/dev/null || echo "")

        cat > "$idea_output" << IDEA_EOF
---KORERO_IDEA---
## $winner_title

Source: Cross-AI Debate (Winner: $winner)

$winning_text
---END_KORERO_IDEA---
IDEA_EOF

        store_loop_idea "$idea_output" "$loop_count"
    fi

    # Detect file changes for circuit breaker
    local files_changed=0
    if [[ -n "$loop_start_sha" ]] && command -v git &>/dev/null; then
        local current_sha
        current_sha=$(git rev-parse HEAD 2>/dev/null || echo "")
        if [[ -n "$current_sha" && "$current_sha" != "$loop_start_sha" ]]; then
            files_changed=$(git diff --name-only "$loop_start_sha" "$current_sha" 2>/dev/null | wc -l | tr -d ' ')
        fi
        # Also check uncommitted changes
        local uncommitted
        uncommitted=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
        files_changed=$((files_changed + uncommitted))
    fi

    # Record loop result for circuit breaker
    local has_errors=false
    record_loop_result "$loop_count" "$files_changed" "$has_errors" "0"
    local cb_result=$?

    if [[ $cb_result -ne 0 ]]; then
        log_status "WARN" "Circuit breaker opened — halting execution"
        return 3
    fi

    return 0
}

# Cleanup function (invoked by portable signal handler)
cleanup() {
    local reason="${1:-manual}"
    local lc="${2:-$loop_count}"
    log_status "INFO" "Korero loop interrupted ($reason). Cleaning up..."
    reset_session "manual_interrupt"
    update_status "$lc" "$(cat "$CALL_COUNT_FILE" 2>/dev/null || echo "0")" "interrupted" "stopped"
    exit 0
}

# Set up portable signal handlers (records each signal to .korero/.signal_log.json)
install_signal_handlers "cleanup" "loop_count"

# Global variable for loop count (needed by cleanup function)
loop_count=0

# Main loop
main() {
    # Load project-specific configuration from .korerorc
    if load_korerorc; then
        if [[ "$KORERORC_LOADED" == "true" ]]; then
            log_status "INFO" "Loaded configuration from .korerorc"
        fi
    fi

    local korero_mode_startup="${KORERO_MODE:-coding}"
    if [[ "$korero_mode_startup" == "heavy-coding" || "$korero_mode_startup" == "heavy-idea" ]]; then
        log_status "SUCCESS" "🚀 Korero loop starting in HEAVY MODE ($korero_mode_startup): Claude + Codex"
        # Verify Codex is ready
        local codex_status=0
        check_codex_ready || codex_status=$?
        if [[ $codex_status -eq 1 ]]; then
            log_status "ERROR" "Codex CLI not installed. Install with: npm install -g @openai/codex"
            exit 1
        elif [[ $codex_status -eq 2 ]]; then
            log_status "ERROR" "Codex CLI not authenticated. Run: codex login"
            exit 1
        fi
    else
        log_status "SUCCESS" "🚀 Korero loop starting with Claude Code"
    fi
    log_status "INFO" "Max calls per hour: $MAX_CALLS_PER_HOUR"
    log_status "INFO" "Logs: $LOG_DIR/ | Docs: $DOCS_DIR/ | Status: $STATUS_FILE"

    # Check if project uses old flat structure and needs migration
    if [[ -f "PROMPT.md" ]] && [[ ! -d ".korero" ]]; then
        log_status "ERROR" "This project uses the old flat structure."
        echo ""
        echo "Korero v0.10.0+ uses a .korero/ subfolder to keep your project root clean."
        echo ""
        echo "To upgrade your project, run:"
        echo "  korero-migrate"
        echo ""
        echo "This will move Korero-specific files to .korero/ while preserving src/ at root."
        echo "A backup will be created before migration."
        exit 1
    fi

    # Check if this is a Korero project directory
    if [[ ! -f "$PROMPT_FILE" ]]; then
        log_status "ERROR" "Prompt file '$PROMPT_FILE' not found!"
        echo ""
        
        # Check if this looks like a partial Korero project
        if [[ -f "$KORERO_DIR/fix_plan.md" ]] || [[ -d "$KORERO_DIR/specs" ]] || [[ -f "$KORERO_DIR/AGENT.md" ]]; then
            echo "This appears to be a Korero project but is missing .korero/PROMPT.md."
            echo "You may need to create or restore the PROMPT.md file."
        else
            echo "This directory is not a Korero project."
        fi

        echo ""
        echo "To fix this:"
        echo "  1. Enable Korero in existing project: korero-enable"
        echo "  2. Create a new project: korero-setup my-project"
        echo "  3. Import existing requirements: korero-import requirements.md"
        echo "  4. Navigate to an existing Korero project directory"
        echo "  5. Or create .korero/PROMPT.md manually in this directory"
        echo ""
        echo "Korero projects should contain: .korero/PROMPT.md, .korero/fix_plan.md, .korero/specs/, src/, etc."
        exit 1
    fi

    # Initialize session tracking before entering the loop
    init_session_tracking

    # Check session age and warn if stale
    local session_warning
    session_warning=$(check_session_age 2>/dev/null)
    if [[ -n "$session_warning" ]]; then
        log_status "WARN" "$session_warning"
    fi

    log_status "INFO" "Starting main loop..."

    while true; do
        loop_count=$((loop_count + 1))

        # Capture loop start time for duration tracking
        LOOP_START_TIME=$(date +%s)

        # Check loop limit (from .korerorc MAX_LOOPS setting)
        local max_loops="${MAX_LOOPS:-continuous}"
        if [[ "$max_loops" != "continuous" && "$max_loops" =~ ^[0-9]+$ ]]; then
            if [[ $loop_count -gt $max_loops ]]; then
                log_status "INFO" "Reached configured loop limit ($max_loops loops)"
                record_shutdown_signal "$SHUTDOWN_REASON_LIMIT" "$loop_count" "max_loops=$max_loops"
                update_status "$loop_count" "$(cat "$CALL_COUNT_FILE" 2>/dev/null || echo 0)" "loop_limit_reached" "completed" "loop_limit"
                break
            fi
        fi

        # Update session last_used timestamp
        update_session_last_used

        log_status "INFO" "Loop #$loop_count - calling init_call_tracking..."
        init_call_tracking

        # Track loops this hour and show rate limit prediction
        LOOPS_THIS_HOUR=$((LOOPS_THIS_HOUR + 1))
        show_rate_limit_prediction

        log_status "LOOP" "=== Starting Loop #$loop_count ==="

        # Display visual progress indicator
        local progress_percent=0
        local progress_phase="Executing"
        if [[ "$max_loops" != "continuous" && "$max_loops" =~ ^[0-9]+$ && $max_loops -gt 0 ]]; then
            progress_percent=$(( (loop_count - 1) * 100 / max_loops ))
            progress_phase="Executing ($loop_count/$max_loops)"
        fi
        print_progress "$loop_count" "$progress_phase" "$progress_percent"

        # Check circuit breaker before attempting execution
        if should_halt_execution; then
            reset_session "circuit_breaker_open"
            record_shutdown_signal "$SHUTDOWN_REASON_CIRCUIT" "$loop_count" "circuit_breaker_open"
            update_status "$loop_count" "$(cat "$CALL_COUNT_FILE")" "circuit_breaker_open" "halted" "stagnation_detected"
            log_status "ERROR" "🛑 Circuit breaker has opened - execution halted"
            break
        fi

        # Check budget threshold (if KORERO_BUDGET_USD is set)
        if [[ -n "${KORERO_BUDGET_USD:-}" ]]; then
            # Warn at 80%
            local budget_pct
            budget_pct=$(get_budget_percentage)
            if [[ "${budget_pct:-0}" -ge 80 && "${budget_pct:-0}" -lt 100 ]] 2>/dev/null; then
                log_status "WARN" "Budget warning: ${budget_pct}% of \$${KORERO_BUDGET_USD} spent (estimated)"
            fi

            # Pause when threshold exceeded
            if ! check_budget_threshold; then
                local current_cost
                current_cost=$(jq -r '.session_total_usd // 0' "$KORERO_DIR/cost_history.json" 2>/dev/null || echo "0")
                if ! prompt_budget_exceeded "$current_cost" "$KORERO_BUDGET_USD"; then
                    log_status "INFO" "Exiting due to budget limit."
                    record_shutdown_signal "$SHUTDOWN_REASON_BUDGET" "$loop_count" "spent=${current_cost}_limit=${KORERO_BUDGET_USD}"
                    break
                fi
            fi
        fi

        # Check rate limits
        if ! can_make_call; then
            wait_for_reset
            continue
        fi

        # Check for graceful exit conditions
        local exit_reason=$(should_exit_gracefully)
        if [[ "$exit_reason" != "" ]]; then
            # Handle permission_denied specially (Issue #101)
            if [[ "$exit_reason" == "permission_denied" ]]; then
                log_status "WARN" "🚫 Permission denied - offering interactive fix"

                # Extract denied commands from response analysis
                local denied_cmds=()
                if [[ -f "$RESPONSE_ANALYSIS_FILE" ]]; then
                    local denied_json
                    denied_json=$(jq -r '.analysis.denied_commands // [] | .[]' "$RESPONSE_ANALYSIS_FILE" 2>/dev/null)
                    if [[ -n "$denied_json" ]]; then
                        while IFS= read -r cmd; do
                            [[ -n "$cmd" ]] && denied_cmds+=("$cmd")
                        done <<< "$denied_json"
                    fi
                fi

                echo ""
                echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
                echo -e "${RED}║  PERMISSION DENIED                                         ║${NC}"
                echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
                echo ""
                echo -e "${YELLOW}Claude Code was denied permission to execute commands.${NC}"
                echo ""

                # Try interactive fix first
                if [[ ${#denied_cmds[@]} -gt 0 ]]; then
                    # Export project root for apply_permission_fix
                    export KORERO_PROJECT_ROOT="$PROJECT_ROOT"

                    if prompt_permission_fix "${denied_cmds[@]}"; then
                        # User accepted fix - continue the loop instead of breaking
                        log_status "SUCCESS" "Permission fix applied - continuing loop"
                        update_status "$loop_count" "$(cat "$CALL_COUNT_FILE")" "permission_fixed" "running"

                        # Reload ALLOWED_TOOLS from updated .korerorc
                        if [[ -f "$PROJECT_ROOT/.korerorc" ]]; then
                            source "$PROJECT_ROOT/.korerorc"
                            # Rebuild Claude command with new permissions
                            CLAUDE_ALLOWED_TOOLS="${ALLOWED_TOOLS:-}"
                        fi

                        # Continue to next iteration instead of breaking
                        continue
                    fi
                    # User declined - fall through to halt
                else
                    # No specific commands available - show generic guidance and halt
                    echo "  Update ALLOWED_TOOLS in .korerorc to include the required tools."
                    echo ""
                    echo "  Or use a preset for broader permissions:"
                    echo "    ALLOWED_TOOLS=\"@standard\"    # Read, Write, Edit, git, npm, pytest"
                    echo "    ALLOWED_TOOLS=\"@permissive\"   # All Bash commands"
                    echo ""
                    echo "  Then restart: korero --reset-session && korero --monitor"
                fi

                # If we get here, user declined or fix failed - halt the loop
                log_status "ERROR" "🚫 Permission denied - halting loop"
                reset_session "permission_denied"
                update_status "$loop_count" "$(cat "$CALL_COUNT_FILE")" "permission_denied" "halted" "permission_denied"
                echo ""
                break
            fi

            log_status "SUCCESS" "🏁 Graceful exit triggered: $exit_reason"
            reset_session "project_complete"
            record_shutdown_signal "$SHUTDOWN_REASON_COMPLETE" "$loop_count" "$exit_reason"
            update_status "$loop_count" "$(cat "$CALL_COUNT_FILE")" "graceful_exit" "completed" "$exit_reason"

            log_status "SUCCESS" "🎉 Korero has completed the project! Final stats:"
            log_status "INFO" "  - Total loops: $loop_count"
            log_status "INFO" "  - API calls used: $(cat "$CALL_COUNT_FILE")"
            log_status "INFO" "  - Exit reason: $exit_reason"

            break
        fi
        
        # Update status
        local calls_made=$(cat "$CALL_COUNT_FILE" 2>/dev/null || echo "0")
        update_status "$loop_count" "$calls_made" "executing" "running"
        
        # Execute appropriate loop based on mode
        local korero_mode="${KORERO_MODE:-coding}"
        if [[ "$korero_mode" == "heavy-coding" || "$korero_mode" == "heavy-idea" ]]; then
            execute_heavy_loop "$loop_count"
        else
            execute_claude_code "$loop_count"
        fi
        local exec_result=$?

        # Record loop duration
        local loop_end_time
        loop_end_time=$(date +%s)
        LAST_LOOP_DURATION=$((loop_end_time - LOOP_START_TIME))
        update_loop_duration "$LAST_LOOP_DURATION"
        log_status "INFO" "Loop #$loop_count duration: $(format_duration $LAST_LOOP_DURATION)"

        # Record per-loop cost estimate
        local latest_output_file
        latest_output_file=$(ls -t "$LOG_DIR"/claude_output_*.log "$LOG_DIR"/claude_proposal_*.log 2>/dev/null | head -1)
        record_loop_cost "$loop_count" "$latest_output_file" "$LAST_LOOP_DURATION"

        if [ $exec_result -eq 0 ]; then
            update_status "$loop_count" "$(cat "$CALL_COUNT_FILE")" "completed" "success"

            # Brief pause between successful executions
            sleep 5
        elif [ $exec_result -eq 3 ]; then
            # Circuit breaker opened
            reset_session "circuit_breaker_trip"
            update_status "$loop_count" "$(cat "$CALL_COUNT_FILE")" "circuit_breaker_open" "halted" "stagnation_detected"
            log_status "ERROR" "🛑 Circuit breaker has opened - halting loop"
            log_status "INFO" "Run 'korero --reset-circuit' to reset the circuit breaker after addressing issues"
            break
        elif [ $exec_result -eq 2 ]; then
            # API 5-hour limit reached - handle specially
            update_status "$loop_count" "$(cat "$CALL_COUNT_FILE")" "api_limit" "paused"
            log_status "WARN" "🛑 Claude API 5-hour limit reached!"
            
            # Ask user whether to wait or exit
            echo -e "\n${YELLOW}The Claude API 5-hour usage limit has been reached.${NC}"
            echo -e "${YELLOW}You can either:${NC}"
            echo -e "  ${GREEN}1)${NC} Wait for the limit to reset (usually within an hour)"
            echo -e "  ${GREEN}2)${NC} Exit the loop and try again later"
            echo -e "\n${BLUE}Choose an option (1 or 2):${NC} "
            
            # Read user input with timeout
            read -t 30 -n 1 user_choice
            echo  # New line after input
            
            if [[ "$user_choice" == "2" ]] || [[ -z "$user_choice" ]]; then
                log_status "INFO" "User chose to exit (or timed out). Exiting loop..."
                update_status "$loop_count" "$(cat "$CALL_COUNT_FILE")" "api_limit_exit" "stopped" "api_5hour_limit"
                break
            else
                log_status "INFO" "User chose to wait. Waiting for API limit reset..."
                # Wait for longer period when API limit is hit
                local wait_minutes=60
                log_status "INFO" "Waiting $wait_minutes minutes before retrying..."
                
                # Countdown display
                local wait_seconds=$((wait_minutes * 60))
                while [[ $wait_seconds -gt 0 ]]; do
                    local minutes=$((wait_seconds / 60))
                    local seconds=$((wait_seconds % 60))
                    printf "\r${YELLOW}Time until retry: %02d:%02d${NC}" $minutes $seconds
                    sleep 1
                    ((wait_seconds--))
                done
                printf "\n"
            fi
        else
            update_status "$loop_count" "$(cat "$CALL_COUNT_FILE")" "failed" "error"
            log_status "WARN" "Execution failed, waiting 30 seconds before retry..."
            sleep 30
        fi
        
        log_status "LOOP" "=== Completed Loop #$loop_count ==="
    done
}

# Help function
show_help() {
    cat << HELPEOF
Korero Loop for Claude Code

Usage: $0 [OPTIONS]

IMPORTANT: This command must be run from a Korero project directory.
           Use 'korero-setup project-name' to create a new project first.

Options:
    -h, --help              Show this help message
    -c, --calls NUM         Set max calls per hour (default: $MAX_CALLS_PER_HOUR)
    -p, --prompt FILE       Set prompt file (default: $PROMPT_FILE)
    -s, --status            Show current status and exit
    ideas <cmd>             Browse and search winning ideas (list, show, search)
    -m, --monitor           Start with tmux session and live monitor (requires tmux)
    -v, --verbose           Show detailed progress updates during execution
    -l, --live              Show Claude Code output in real-time (streaming mode)
    -t, --timeout MIN       Set Claude Code execution timeout in minutes (default: $CLAUDE_TIMEOUT_MINUTES)
    --dry-run               Show what would happen without executing
    --validate              Validate .korerorc configuration and exit
    --validate-config       Verbose config validation with per-field checkmarks
    --fix-config            Apply default fixes for missing/invalid .korerorc fields
    --quickstart            Quick 3-question setup for new users
    --examples              Interactive gallery of curated workflow examples
    --show-debate [N]       Show debate transcript (latest, or loop N)
    --health-check          Validate environment prerequisites (Claude CLI, jq, git, network)
    --cost-estimate         Estimate API costs from loop logs and display report
    --cost-history          Show per-loop cost breakdown with session totals
    --debate-stats          Show debate quality statistics + win distribution (heavy modes)
    --debate-health         Analyze debate fatigue metrics (last 10 debates) for heavy modes
    --implementation-status / --impl-status  Show winning idea implementation progress
    --search-ideas KEYWORD  Search past ideas by keyword (case-insensitive)
    --shutdown-history      Show history of past shutdowns (signals, budget, circuit)
    --rate-status / --rate / -r  Show visual rate limit status dashboard
    --troubleshoot          Show troubleshooting quick reference for common issues
    --diagnose              Interactive troubleshooting wizard (guided diagnosis)
    --start-idea N          Create branch from winning idea N and start coding loop
    --reset-circuit         Reset circuit breaker to CLOSED state
    --circuit-status        Show circuit breaker status and exit
    --reset-session         Reset session state and exit (clears session continuity)

Modern CLI Options (Phase 1.1):
    --output-format FORMAT  Set Claude output format: json or text (default: $CLAUDE_OUTPUT_FORMAT)
    --allowed-tools TOOLS   Comma-separated list of allowed tools (default: $CLAUDE_ALLOWED_TOOLS)
    --no-continue           Disable session continuity across loops
    --session-expiry HOURS  Set session expiration time in hours (default: $CLAUDE_SESSION_EXPIRY_HOURS)

Files created:
    - $LOG_DIR/: All execution logs
    - $DOCS_DIR/: Generated documentation
    - $STATUS_FILE: Current status (JSON)
    - .korero/.korero_session: Session lifecycle tracking
    - .korero/.korero_session_history: Session transition history (last 50)
    - .korero/.call_count: API call counter for rate limiting
    - .korero/.last_reset: Timestamp of last rate limit reset

Example workflow:
    korero-setup my-project     # Create project
    cd my-project             # Enter project directory
    $0 --monitor             # Start Korero with monitoring

Examples:
    $0 --calls 50 --prompt my_prompt.md
    $0 --monitor             # Start with integrated tmux monitoring
    $0 --live                # Show Claude Code output in real-time (streaming)
    $0 --live --verbose      # Live streaming + verbose logging
    $0 --monitor --timeout 30   # 30-minute timeout for complex tasks
    $0 --verbose --timeout 5    # 5-minute timeout with detailed progress
    $0 --output-format text     # Use legacy text output format
    $0 --no-continue            # Disable session continuity
    $0 --session-expiry 48      # 48-hour session expiration

Help Topics:
    korero --help <topic>       Show detailed help on a specific topic

    Available topics:
      presets          Permission preset details (@conservative, @standard, @permissive)
      circuit-breaker  Circuit breaker states, thresholds, and recovery
      session          Session continuity and lifecycle management
      tools            Allowed tools syntax and patterns
      modes            Korero modes (coding vs idea)
      exit-detection   Exit signal detection and completion indicators
      rate-limiting    Rate limiting configuration and behavior
      config           .korerorc configuration reference

HELPEOF
}

# Troubleshooting Quick Reference — common issues and fixes
show_troubleshoot_reference() {
    cat << 'TROUBLESHOOT_EOF'

═══════════════════════════════════════════════════════════
           KORERO TROUBLESHOOTING QUICK REFERENCE
═══════════════════════════════════════════════════════════

PERMISSION ISSUES
  "Permission denied" during loop execution
    → Check ALLOWED_TOOLS in .korerorc
    → Quick fix: korero --help presets
    → Auto-fix: Interactive recovery prompts you on denial

  "Bash(npm *) not allowed"
    → Add to ALLOWED_TOOLS or use @standard preset
    → See: korero --help tools

RATE LIMITING
  "Rate limit approaching" warnings
    → Check current usage: korero --status
    → Adjust limit: korero --calls 50
    → See: korero --help rate-limiting

  "Rate limit exceeded"
    → Wait for hourly reset (shown in --status)
    → Or increase limit in .korerorc: MAX_CALLS_PER_HOUR=150

SESSION ISSUES
  "Session context seems stale"
    → Reset session: korero --reset-session
    → See: korero --help session

  "Session won't continue across loops"
    → Check .korero/.claude_session_id exists
    → Verify CLAUDE_USE_CONTINUE=true in .korerorc

CIRCUIT BREAKER
  "Circuit breaker OPEN" message
    → Check state: korero --circuit-status
    → Reset after fixing issue: korero --reset-circuit
    → See: korero --help circuit-breaker

  "No progress detected" warnings
    → Check if loops are making file changes
    → Review .korero/logs/ for recent loop output

HEAVY MODE (Claude + Codex)
  "Codex authentication failed"
    → Run: codex login
    → Or check ~/.codex/auth.json
    → See: korero --help modes

  "Debate timeout"
    → Increase CODEX_TIMEOUT in .korerorc (default: 15 min)
    → Or use --codex-timeout flag

CONFIGURATION
  "Invalid .korerorc" errors
    → Validate: korero --validate
    → Verbose check: korero --validate-config
    → See: korero --help config

  "Unknown preset" errors
    → Valid presets: @conservative, @standard, @permissive
    → See: korero --help presets

STARTUP
  "Bash syntax errors" on macOS
    → Korero requires Bash 4.0+. macOS ships with 3.2
    → Upgrade: brew install bash
    → Check: korero --health-check

  "Command not found: korero"
    → Run install.sh first: ./install.sh
    → Ensure ~/.local/bin is in PATH

═══════════════════════════════════════════════════════════
Tip: Run 'korero --help <topic>' for detailed documentation
     on any topic mentioned above.
═══════════════════════════════════════════════════════════

TROUBLESHOOT_EOF
}

# Interactive Troubleshooter — guided diagnosis with yes/no questions
run_interactive_troubleshooter() {
    # Simple confirm helper (reads y/n from stdin)
    _ts_confirm() {
        local prompt="$1"
        local answer
        read -rp "$prompt [Y/n] " answer
        case "$answer" in
            [Nn]*) return 1 ;;
            *) return 0 ;;
        esac
    }

    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "           KORERO INTERACTIVE TROUBLESHOOTER"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "Let me help diagnose your issue."
    echo ""

    # Branch 1: Permission issues
    if _ts_confirm "Are you seeing 'permission denied' errors?"; then
        if _ts_confirm "Is the error for a Bash command (npm, git, docker, etc.)?"; then
            cat << 'EOF'

═══════════════════════════════════════════════════════════
DIAGNOSIS: Missing Bash tool permission

FIX: Add the command pattern to ALLOWED_TOOLS in .korerorc

Examples:
  ALLOWED_TOOLS="@standard"                    # Includes git, npm, pytest
  ALLOWED_TOOLS="@standard,Bash(docker *)"     # Add docker
  ALLOWED_TOOLS="@permissive"                  # Allow all Bash commands

Quick reference: korero --help presets
═══════════════════════════════════════════════════════════
EOF
            return 0
        else
            cat << 'EOF'

═══════════════════════════════════════════════════════════
DIAGNOSIS: Missing file operation permission

FIX: Ensure Read, Write, and Edit are in ALLOWED_TOOLS

Example:
  ALLOWED_TOOLS="Write,Read,Edit,Bash(git *)"

Or use any preset (all include Read/Write/Edit):
  ALLOWED_TOOLS="@conservative"

Quick reference: korero --help tools
═══════════════════════════════════════════════════════════
EOF
            return 0
        fi
    fi

    # Branch 2: Rate limiting
    if _ts_confirm "Are you hitting rate limit warnings or errors?"; then
        if _ts_confirm "Is the loop stopping due to 'rate limit exceeded'?"; then
            cat << 'EOF'

═══════════════════════════════════════════════════════════
DIAGNOSIS: Rate limit exceeded

FIX: Wait for hourly reset or increase the limit

Check current status:
  korero --status

Increase limit temporarily:
  korero --calls 150

Increase limit permanently in .korerorc:
  MAX_CALLS_PER_HOUR=150

Quick reference: korero --help rate-limiting
═══════════════════════════════════════════════════════════
EOF
            return 0
        else
            cat << 'EOF'

═══════════════════════════════════════════════════════════
DIAGNOSIS: Rate limit warning (approaching limit)

This is informational — no action required yet.

To reduce API usage:
  - Use --calls flag to set a lower limit
  - Pause between intensive sessions

Monitor usage:
  korero --status

Quick reference: korero --help rate-limiting
═══════════════════════════════════════════════════════════
EOF
            return 0
        fi
    fi

    # Branch 3: Circuit breaker
    if _ts_confirm "Is the loop showing 'circuit breaker OPEN' or stopping unexpectedly?"; then
        cat << 'EOF'

═══════════════════════════════════════════════════════════
DIAGNOSIS: Circuit breaker triggered

The circuit breaker opens when it detects problems like:
- No file changes for 3+ consecutive loops
- Same error repeated 5+ times
- Permission denials without recovery

Check current state:
  korero --circuit-status

Reset after fixing the underlying issue:
  korero --reset-circuit

Quick reference: korero --help circuit-breaker
═══════════════════════════════════════════════════════════
EOF
        return 0
    fi

    # Branch 4: Session issues
    if _ts_confirm "Are you having session continuity problems?"; then
        if _ts_confirm "Is the session context seeming stale or outdated?"; then
            cat << 'EOF'

═══════════════════════════════════════════════════════════
DIAGNOSIS: Stale session context

Sessions older than 12 hours may have degraded context.

Reset the session:
  korero --reset-session

Check session age in status output:
  korero --status

Quick reference: korero --help session
═══════════════════════════════════════════════════════════
EOF
            return 0
        else
            cat << 'EOF'

═══════════════════════════════════════════════════════════
DIAGNOSIS: Session continuity failure

Check these settings in .korerorc:
  CLAUDE_USE_CONTINUE=true    # Required for session continuity

Verify session file exists:
  ls -la .korero/.claude_session_id

Manual session reset:
  korero --reset-session

Quick reference: korero --help session
═══════════════════════════════════════════════════════════
EOF
            return 0
        fi
    fi

    # Branch 5: Heavy mode (Codex)
    if _ts_confirm "Are you using heavy mode (Claude + Codex)?"; then
        if _ts_confirm "Is Codex authentication failing?"; then
            cat << 'EOF'

═══════════════════════════════════════════════════════════
DIAGNOSIS: Codex authentication failure

Run Codex login:
  codex login

Or check auth file:
  cat ~/.codex/auth.json

Verify Codex is working:
  codex --version

Quick reference: korero --help modes
═══════════════════════════════════════════════════════════
EOF
            return 0
        else
            cat << 'EOF'

═══════════════════════════════════════════════════════════
DIAGNOSIS: Heavy mode debate issue

For timeout issues, increase in .korerorc:
  CODEX_TIMEOUT=30    # Default is 15 minutes

For debate round issues:
  DEBATE_ROUNDS=2     # 1-3 rounds

View latest debate:
  korero --show-debate

Quick reference: korero --help modes
═══════════════════════════════════════════════════════════
EOF
            return 0
        fi
    fi

    # Branch 6: Configuration
    if _ts_confirm "Are you seeing .korerorc or configuration errors?"; then
        cat << 'EOF'

═══════════════════════════════════════════════════════════
DIAGNOSIS: Configuration issue

Validate your configuration:
  korero --validate           # Quick check
  korero --validate-config    # Verbose with per-field status
  korero --fix-config         # Auto-fix missing fields

Common issues:
- Missing quotes around values with spaces
- Unknown preset names (valid: @conservative, @standard, @permissive)
- Typos in variable names

Quick reference: korero --help config
═══════════════════════════════════════════════════════════
EOF
        return 0
    fi

    # Fallback: No diagnosis matched
    cat << 'EOF'

═══════════════════════════════════════════════════════════
No specific diagnosis matched your issue.

General troubleshooting steps:
1. Check status: korero --status
2. Validate config: korero --validate
3. View recent logs: ls -la .korero/logs/
4. Check circuit breaker: korero --circuit-status
5. Run health check: korero --health-check

For help topics:
  korero --help presets
  korero --help config
  korero --help session
  korero --help circuit-breaker

Still stuck? Open an issue:
  https://github.com/pendemic/korero-claude-code/issues
═══════════════════════════════════════════════════════════
EOF
}

# Search IDEAS.md for keyword matches
# Usage: search_ideas <keyword>
search_ideas() {
    local keyword="$1"
    local ideas_dir="${KORERO_DIR:-.korero}/ideas"
    local ideas_file="$ideas_dir/IDEAS.md"

    if [[ -z "$keyword" ]]; then
        echo "Usage: korero --search-ideas <keyword>" >&2
        return 1
    fi

    if [[ ! -f "$ideas_file" ]]; then
        echo "No IDEAS.md found. Run ideation loops first." >&2
        return 1
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "           IDEA SEARCH: \"$keyword\""
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    local matches=0

    # Search individual idea files for richer context
    for idea_file in "$ideas_dir"/loop_*_idea.md; do
        [[ -f "$idea_file" ]] || continue

        if grep -qi "$keyword" "$idea_file" 2>/dev/null; then
            local loop_num
            loop_num=$(echo "$idea_file" | grep -o 'loop_[0-9]*' | grep -o '[0-9]*')

            local title=""
            local type=""
            local category=""
            local agent=""

            title=$(grep '^\*\*Title:\*\*' "$idea_file" 2>/dev/null | head -1 | sed 's/\*\*Title:\*\*[[:space:]]*//')
            type=$(grep '^\*\*Type:\*\*' "$idea_file" 2>/dev/null | head -1 | sed 's/\*\*Type:\*\*[[:space:]]*//')
            category=$(grep '^\*\*Category:\*\*' "$idea_file" 2>/dev/null | head -1 | sed 's/\*\*Category:\*\*[[:space:]]*//')
            agent=$(grep '^\*\*Proposed by:\*\*' "$idea_file" 2>/dev/null | head -1 | sed 's/\*\*Proposed by:\*\*[[:space:]]*//')

            # Get first matching line for context
            local context
            context=$(grep -i "$keyword" "$idea_file" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//' | cut -c1-80)

            matches=$((matches + 1))
            echo "LOOP $loop_num (Winner): ${title:-Unknown}"
            [[ -n "$type" || -n "$category" ]] && echo "  Type: ${type:-N/A} | Category: ${category:-N/A}"
            [[ -n "$agent" ]] && echo "  Agent: $agent"
            echo "  Match: \"$context\""
            echo ""
        fi
    done

    # Also search the main IDEAS.md for runner-ups or other mentions
    local index_matches
    index_matches=$(grep -c -i "$keyword" "$ideas_file" 2>/dev/null || true)
    index_matches=$(echo "$index_matches" | tr -d '[:space:]')
    index_matches="${index_matches:-0}"

    if [[ $matches -eq 0 && "$index_matches" -eq 0 ]]; then
        echo "No matches found for \"$keyword\""
    else
        echo "═══════════════════════════════════════════════════════════"
        echo "Found $matches idea files matching, $index_matches lines in IDEAS.md"
    fi
    echo ""
}

# Show per-loop cost history from cost_history.json
# Reads from .korero/cost_history.json written by record_loop_cost()
show_cost_history() {
    local korero_dir="${KORERO_DIR:-.korero}"
    local cost_file="$korero_dir/cost_history.json"

    if [[ ! -f "$cost_file" ]]; then
        echo "No cost history found. Run some loops first."
        return 1
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "              LOOP COST HISTORY"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    printf "%-6s| %-10s| %-8s| %-9s| %s\n" "Loop" "Est. Cost" "Tokens" "Duration" "Timestamp"
    echo "──────|───────────|─────────|──────────|──────────────────"

    # Display each loop entry
    jq -r '.loops[] | "\(.loop)|\(.cost_usd)|\(.tokens)|\(.duration_sec)|\(.timestamp)"' "$cost_file" 2>/dev/null | \
    while IFS='|' read -r loop cost tokens duration ts; do
        local ts_short
        ts_short=$(echo "$ts" | cut -d'T' -f1,2 | tr 'T' ' ' | cut -c1-16)
        printf "  %-4s|   \$%-6s |  %6s |   %3ss   | %s\n" "$loop" "$cost" "$tokens" "$duration" "$ts_short"
    done

    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "SESSION SUMMARY"
    echo "═══════════════════════════════════════════════════════════"

    local total_cost total_tokens loop_count avg_cost
    total_cost=$(jq -r '.session_total_usd' "$cost_file" 2>/dev/null || echo "0")
    total_tokens=$(jq -r '.session_total_tokens' "$cost_file" 2>/dev/null || echo "0")
    loop_count=$(jq -r '.loops | length' "$cost_file" 2>/dev/null || echo "0")

    if [[ "$loop_count" -gt 0 ]]; then
        avg_cost=$(awk "BEGIN { printf \"%.2f\", $total_cost / $loop_count }" 2>/dev/null || echo "0.00")
    else
        avg_cost="0.00"
    fi

    echo "Total estimated cost:  \$${total_cost}"
    echo "Total tokens:          ${total_tokens}"
    echo "Average per loop:      \$${avg_cost}"
    echo "Loops recorded:        ${loop_count}"
    echo "═══════════════════════════════════════════════════════════"
}

# Show debate quality statistics from .korero/.debate_quality.json
# Also displays aggregate win distribution via display_debate_stats() (Loop 35)
show_debate_stats() {
    local korero_dir="${KORERO_DIR:-.korero}"
    local quality_file="$korero_dir/.debate_quality.json"

    # Show transcript-based aggregate stats first (Loop 35)
    source "$SCRIPT_DIR/lib/debate_transcript.sh" 2>/dev/null || true
    display_debate_stats

    if [[ ! -f "$quality_file" ]]; then
        echo "No debate quality data found. Run heavy mode loops first."
        return 1
    fi

    if ! command -v jq &>/dev/null; then
        echo "jq is required to display quality metrics."
        return 1
    fi

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              DEBATE QUALITY STATISTICS                     ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    local total_debates avg_quality
    total_debates=$(jq '.debates | length' "$quality_file" 2>/dev/null || echo "0")
    avg_quality=$(jq 'if (.debates | length) > 0 then ([.debates[].quality_score] | add / length | floor) else 0 end' "$quality_file" 2>/dev/null || echo "0")

    echo "  Total debates analyzed: $total_debates"
    echo "  Average quality score:  $avg_quality/100"
    echo ""

    if [[ "$avg_quality" -ge 70 ]]; then
        echo "  Assessment: HIGH QUALITY — AIs are engaging substantively"
    elif [[ "$avg_quality" -ge 50 ]]; then
        echo "  Assessment: MODERATE — Some improvement possible"
    else
        echo "  Assessment: LOW — Consider reviewing debate prompts"
    fi
    echo ""

    if [[ "$total_debates" -gt 0 ]]; then
        echo "  Recent Debates (up to 5):"
        echo "  ────────────────────────────────────────────────────────"
        printf "  %-6s| %-9s| %-13s| %-10s| %s\n" "Loop" "Quality" "Length Ratio" "Coverage" "Confidence"
        echo "  ──────|───────────|─────────────|──────────|───────────"

        jq -r '
          .debates |
          sort_by(.loop) |
          reverse |
          .[:5][] |
          "\(.loop)|\(.quality_score)|\(.length_ratio)|\(.coverage)|\(.verdict_confidence)"
        ' "$quality_file" 2>/dev/null | \
        while IFS='|' read -r loop quality ratio coverage conf; do
            printf "  %-6s|   %3s/100 |  %-11s|  %4s%%    |  %3s%%\n" \
                "$loop" "$quality" "$ratio" "$coverage" "$conf"
        done
    fi

    echo ""
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
}

# =============================================================================
# IDEA IMPLEMENTATION STATUS (Loop 37)
# =============================================================================

# Display idea implementation status dashboard
# Parses fix_plan.md's Loop Checkpoints section and Winning Ideas Tracker table
# Usage: show_implementation_status
show_implementation_status() {
    local fix_plan="${KORERO_DIR:-.korero}/fix_plan.md"

    if [[ ! -f "$fix_plan" ]]; then
        echo "No fix_plan.md found. Run korero-enable first."
        return 1
    fi

    # Parse winning ideas tracker: rows like | NN | Title | Type | Category | Agent | Status |
    declare -A idea_titles
    declare -A idea_categories
    while IFS='|' read -r _ loop title _ category _; do
        loop=$(echo "$loop" | tr -d '[:space:]')
        title=$(echo "$title" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        category=$(echo "$category" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
        [[ "$loop" =~ ^[0-9]+$ ]] || continue
        idea_titles["$loop"]="$title"
        idea_categories["$loop"]="$category"
    done < <(grep -E '^\| *[0-9]+ *\|' "$fix_plan" 2>/dev/null)

    # Parse Loop Checkpoint checkboxes
    # Format:
    #   ### Loop N
    #   - [x] Implementation   (completed)
    #   - [ ] Implementation   (pending)
    local implemented=()
    local pending=()
    local current_loop=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^###[[:space:]]Loop[[:space:]]([0-9]+) ]]; then
            current_loop="${BASH_REMATCH[1]}"
        elif [[ -n "$current_loop" && "$line" =~ [Ii]mplementation ]]; then
            if [[ "$line" =~ \[x\] ]]; then
                implemented+=("$current_loop")
            else
                pending+=("$current_loop")
            fi
            current_loop=""
        fi
    done < "$fix_plan"

    local total=$(( ${#implemented[@]} + ${#pending[@]} ))
    local impl_count=${#implemented[@]}
    local pct=0
    [[ $total -gt 0 ]] && pct=$(( impl_count * 100 / total ))

    # Build progress bar (20 chars wide)
    local filled=$(( pct / 5 ))
    local empty=$(( 20 - filled ))
    local bar=""
    local i
    for (( i=0; i<filled; i++ )); do bar="${bar}█"; done
    for (( i=0; i<empty; i++ ));  do bar="${bar}░"; done

    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "           IDEA IMPLEMENTATION STATUS"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    printf "SUMMARY: %d/%d implemented (%d%%)\n" "$impl_count" "$total" "$pct"
    echo ""
    printf "PROGRESS BAR: [%s] %d%%\n" "$bar" "$pct"
    echo ""

    # Implemented ideas
    if [[ ${#implemented[@]} -gt 0 ]]; then
        printf "IMPLEMENTED (%d):\n" "${#implemented[@]}"
        for loop in "${implemented[@]}"; do
            printf "  ✓ Loop %s: %s\n" "$loop" "${idea_titles[$loop]:-Unknown}"
        done
        echo ""
    fi

    # Pending ideas (show first 5, summarise rest)
    if [[ ${#pending[@]} -gt 0 ]]; then
        printf "PENDING (%d):\n" "${#pending[@]}"
        local count=0
        for loop in "${pending[@]}"; do
            printf "  ○ Loop %s: %s\n" "$loop" "${idea_titles[$loop]:-Unknown}"
            count=$(( count + 1 ))
            [[ $count -ge 5 ]] && break
        done
        if [[ ${#pending[@]} -gt 5 ]]; then
            printf "  ... (%d more)\n" "$(( ${#pending[@]} - 5 ))"
        fi
        echo ""
    fi

    # Next up
    if [[ ${#pending[@]} -gt 0 ]]; then
        local next_loop="${pending[0]}"
        echo "NEXT UP (oldest pending):"
        printf "  → Loop %s: %s\n" "$next_loop" "${idea_titles[$next_loop]:-Unknown}"
        printf "    Category: %s\n" "${idea_categories[$next_loop]:-Unknown}"
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    return 0
}

# Example Gallery — curated workflow examples for new users
show_examples_gallery() {
    local choice
    while true; do
        echo ""
        echo "╔══════════════════════════════════════════════════════╗"
        echo "║          KORERO EXAMPLE WORKFLOWS                    ║"
        echo "╚══════════════════════════════════════════════════════╝"
        echo ""
        echo "Select an example to view:"
        echo ""
        echo "  [1] TypeScript Project Setup"
        echo "  [2] Python Project Setup"
        echo "  [3] Idea-Only Mode (no code changes)"
        echo "  [4] CI/CD Integration"
        echo "  [5] Custom Agent Configuration"
        echo "  [6] Permission Presets Guide"
        echo "  [7] Monitoring & Debugging"
        echo ""
        read -rp "Enter number (1-7) or 'q' to quit: " choice
        case "$choice" in
            1) _show_example_typescript ;;
            2) _show_example_python ;;
            3) _show_example_idea_mode ;;
            4) _show_example_cicd ;;
            5) _show_example_custom_agents ;;
            6) _show_example_presets ;;
            7) _show_example_monitoring ;;
            q|Q) break ;;
            *) echo "Invalid choice." ;;
        esac
    done
}

_show_example_typescript() {
    cat << 'EOF'

═══════════════════════════════════════════════════════════
EXAMPLE: TypeScript Project Setup
═══════════════════════════════════════════════════════════

Description:
  Set up Korero for a TypeScript project with standard
  permissions for npm, git, and testing.

Quick Start:
  cd your-project
  korero --quickstart           # or full wizard: korero-enable
  korero --monitor              # start with live monitoring

Configuration (.korerorc):
  KORERO_MODE="coding"
  ALLOWED_TOOLS="@standard"
  PROJECT_SUBJECT="TypeScript web application"
  MAX_LOOPS="continuous"

Tips:
  - @standard preset includes npm, git, and pytest access
  - Add custom tools: ALLOWED_TOOLS="@standard,Bash(npx *)"
  - Run 'korero --validate-config' before first loop
EOF
}

_show_example_python() {
    cat << 'EOF'

═══════════════════════════════════════════════════════════
EXAMPLE: Python Project Setup
═══════════════════════════════════════════════════════════

Description:
  Set up Korero for a Python project with pytest and pip.

Quick Start:
  cd your-project
  korero-enable --mode coding --subject "Python application"
  korero --monitor

Configuration (.korerorc):
  KORERO_MODE="coding"
  ALLOWED_TOOLS="@standard,Bash(pip *),Bash(python *)"
  PROJECT_SUBJECT="Python data pipeline"
  MAX_LOOPS="continuous"

Tips:
  - Add Bash(pip *) and Bash(python *) for Python workflows
  - Use 'korero --validate' to verify config syntax
  - pytest is included in @standard preset
EOF
}

_show_example_idea_mode() {
    cat << 'EOF'

═══════════════════════════════════════════════════════════
EXAMPLE: Idea-Only Mode (no code changes)
═══════════════════════════════════════════════════════════

Description:
  Run Korero's multi-agent debate without modifying code.
  Winning ideas are saved to .korero/ideas/.

Quick Start:
  korero-enable --mode idea --subject "e-commerce platform" --loops 10
  korero

Configuration (.korerorc):
  KORERO_MODE="idea"
  PROJECT_SUBJECT="e-commerce platform improvements"
  DOMAIN_AGENT_COUNT=5
  MAX_LOOPS=10
  ALLOWED_TOOLS="@conservative"

Tips:
  - Use @conservative (Read/Write/Edit only) for safety
  - Browse results: korero ideas list
  - View details: korero ideas show 3
  - Convert to code: korero --start-idea 3
EOF
}

_show_example_cicd() {
    cat << 'EOF'

═══════════════════════════════════════════════════════════
EXAMPLE: CI/CD Integration
═══════════════════════════════════════════════════════════

Description:
  Enable Korero non-interactively in CI pipelines.

Quick Start:
  # In your CI script:
  korero-enable-ci --mode coding --subject "web app" --loops 5
  korero --validate
  korero

Configuration (.korerorc):
  KORERO_MODE="coding"
  MAX_LOOPS=5
  ALLOWED_TOOLS="@standard"

Tips:
  - Use korero-enable-ci for non-interactive setup
  - Add --json flag for machine-readable output
  - Set MAX_LOOPS to limit API usage in CI
  - Use 'korero --validate' as a CI gate
EOF
}

_show_example_custom_agents() {
    cat << 'EOF'

═══════════════════════════════════════════════════════════
EXAMPLE: Custom Agent Configuration
═══════════════════════════════════════════════════════════

Description:
  Configure domain-specific expert agents for better ideas.

Quick Start:
  korero-enable --mode idea --subject "ML pipeline" --agents 5
  # Or manually edit .korero/AGENT.md after setup

Configuration (.korerorc):
  KORERO_MODE="idea"
  PROJECT_SUBJECT="machine learning pipeline"
  DOMAIN_AGENT_COUNT=5
  MAX_LOOPS="continuous"

Agent Structure:
  - 1-10 domain agents (auto-generated from subject)
  - 3 mandatory evaluators (always present):
    * Devil's Advocate
    * Technical Feasibility Analyst
    * Idea Orchestrator

Tips:
  - More agents = more diverse ideas (but longer loops)
  - Edit .korero/AGENT.md to customize agent roles
  - Use korero-enable for guided agent setup
EOF
}

_show_example_presets() {
    cat << 'EOF'

═══════════════════════════════════════════════════════════
EXAMPLE: Permission Presets Guide
═══════════════════════════════════════════════════════════

Description:
  Choose the right permission level for your workflow.

Presets:
  @conservative    Write, Read, Edit
                   Best for: idea mode, untrusted projects

  @standard        Write, Read, Edit, Bash(git *),
                   Bash(npm *), Bash(pytest)
                   Best for: most projects (recommended)

  @permissive      Write, Read, Edit, Bash(*)
                   Best for: complex builds, Docker, custom tools

Mixing presets with custom tools:
  ALLOWED_TOOLS="@standard,Bash(docker *),Bash(cargo *)"

Examples:
  # See current preset details
  korero --help presets

  # Validate your tools config
  korero --validate-config
EOF
}

_show_example_monitoring() {
    cat << 'EOF'

═══════════════════════════════════════════════════════════
EXAMPLE: Monitoring & Debugging
═══════════════════════════════════════════════════════════

Description:
  Monitor Korero's progress and debug issues.

Monitoring:
  korero --monitor              # Integrated tmux dashboard
  korero --status               # Quick status check
  korero --circuit-status       # Circuit breaker state

Debugging:
  korero --dry-run              # Preview without executing
  korero --validate-config      # Check config for errors
  korero --live --verbose       # Real-time output + logging

Recovery:
  korero --reset-circuit        # Reset stuck circuit breaker
  korero --reset-session        # Clear session state

Tips:
  - Check .korero/logs/ for execution history
  - Use --verbose for detailed progress updates
  - Circuit breaker halts after 3 stagnant loops
EOF
}

# Show detailed help on a specific topic
show_help_topic() {
    local topic="$1"
    case "$topic" in
        presets)
            cat << 'TOPICEOF'
PERMISSION PRESETS
==================

Korero provides three built-in permission presets for ALLOWED_TOOLS:

  @conservative    Write, Read, Edit
                   Safest option — no shell access. Claude can only modify files.

  @standard        Write, Read, Edit, Bash(git *), Bash(npm *), Bash(pytest)
                   Recommended for most projects. Covers common dev workflows.

  @permissive      Write, Read, Edit, Bash(*)
                   Full shell access. Use when Claude needs arbitrary commands.

Mixing presets with custom tools:
  ALLOWED_TOOLS="@standard,Bash(docker *)"
  ALLOWED_TOOLS="@conservative,Bash(git commit)"

Set in .korerorc:
  ALLOWED_TOOLS="@standard"

Or via CLI:
  korero --allowed-tools "@standard,Bash(cargo *)"
TOPICEOF
            ;;
        circuit-breaker|circuit_breaker|cb)
            cat << 'TOPICEOF'
CIRCUIT BREAKER
================

Prevents runaway loops by detecting stagnation patterns.

States:
  CLOSED     Normal operation. Loop runs freely.
  HALF_OPEN  Monitoring mode. Loop continues with extra scrutiny.
  OPEN       Halted. Loop stops until manually reset.

Thresholds:
  No progress:        3 loops with no file changes → OPEN
  Same error:         5 loops with repeated errors → OPEN
  Output decline:     70% drop in output volume    → OPEN
  Permission denials: 2 loops with denied commands  → OPEN

Commands:
  korero --circuit-status    Show current state and counters
  korero --reset-circuit     Reset to CLOSED state
TOPICEOF
            ;;
        session|sessions)
            cat << 'TOPICEOF'
SESSION CONTINUITY
===================

Korero preserves Claude Code sessions across loop iterations for context.

How it works:
  - Session ID stored in .korero/.claude_session_id
  - Passed via --continue flag to maintain conversation context
  - Expires after 24 hours (configurable with --session-expiry)

Auto-reset triggers:
  - Circuit breaker opens
  - Manual interrupt (Ctrl+C)
  - Project completion detected

Commands:
  korero --reset-session         Clear session state
  korero --session-expiry 48     Set 48-hour expiration
  korero --no-continue           Disable session continuity entirely
TOPICEOF
            ;;
        tools)
            cat << 'TOPICEOF'
ALLOWED TOOLS SYNTAX
=====================

Tools control what Claude Code can do during loop execution.

Basic tools:
  Write    Create new files
  Read     Read file contents
  Edit     Modify existing files

Bash patterns (wildcard matching):
  Bash(git *)       Any git command
  Bash(npm *)       Any npm command
  Bash(pytest)      Exactly pytest
  Bash(*)           Any bash command

Combining tools (comma-separated):
  ALLOWED_TOOLS="Write,Read,Edit,Bash(git *),Bash(npm *)"

Using presets (see: korero --help presets):
  ALLOWED_TOOLS="@standard"
  ALLOWED_TOOLS="@standard,Bash(docker *)"

Set via .korerorc or CLI --allowed-tools flag.
TOPICEOF
            ;;
        modes|mode)
            cat << 'TOPICEOF'
KORERO MODES
==============

Korero supports four loop modes:

  coding        Ideation → Debate → Implementation → Git Commit
                Full development cycle. Claude writes and commits code.
                Set: KORERO_MODE="coding" in .korerorc

  idea          Ideation → Debate → Save Best Idea
                No code changes. Winning ideas saved to .korero/ideas/.
                Set: KORERO_MODE="idea" in .korerorc

  heavy-coding  Claude + Codex parallel → Cross-AI Debate → Implement
                Both AIs propose ideas simultaneously. Mutual critique
                and defense rounds, then Claude judges and implements
                the winning idea with a git commit.
                Set: KORERO_MODE="heavy-coding" in .korerorc

  heavy-idea    Claude + Codex parallel → Cross-AI Debate → Save Idea
                Same dual-AI competition but no code changes.
                Winning idea saved to .korero/ideas/.
                Set: KORERO_MODE="heavy-idea" in .korerorc

Heavy modes require the Codex CLI (npm install -g @openai/codex)
and OAuth authentication (codex login).

Configure via korero-enable wizard or .korerorc directly.
Browse saved ideas: korero ideas list
TOPICEOF
            ;;
        exit-detection|exit|exits)
            cat << 'TOPICEOF'
EXIT DETECTION
===============

Korero uses dual-condition checking to prevent premature exits:

Conditions (BOTH required):
  1. completion_indicators >= 2  (heuristic from natural language patterns)
  2. EXIT_SIGNAL: true           (Claude's explicit signal in KORERO_STATUS)

Other exit triggers:
  - 2+ consecutive "done" signals
  - 3+ test-only loops (no feature work)
  - All fix_plan.md items checked off

Why dual-condition?
  Phrases like "feature done, moving to tests" contain completion keywords
  but don't mean the project is finished. EXIT_SIGNAL prevents false exits.
TOPICEOF
            ;;
        rate-limiting|rate|ratelimit)
            cat << 'TOPICEOF'
RATE LIMITING
==============

Prevents excessive API usage by limiting calls per hour.

Defaults:
  Max calls per hour: 100
  Reset: Automatic hourly countdown

Configuration:
  korero --calls 50              Set to 50 calls/hour
  .korerorc: MAX_CALLS_PER_HOUR=200

When limit is reached:
  - Loop pauses with countdown timer
  - Resumes automatically when the hour resets
  - Call count persists across script restarts

Files:
  .korero/.call_count    Current call counter
  .korero/.last_reset    Last reset timestamp
TOPICEOF
            ;;
        config|configuration|korerorc)
            cat << 'TOPICEOF'
.KORERORC CONFIGURATION
========================

Project-level configuration file. Loaded automatically on loop start.

Key variables:
  KORERO_MODE="coding"           Loop mode: coding, idea, heavy-coding, heavy-idea
  PROJECT_SUBJECT="my project"   Subject for agent generation
  DOMAIN_AGENT_COUNT=3           Number of domain expert agents (1-10)
  MAX_LOOPS="continuous"         Loop limit: number or "continuous"
  ALLOWED_TOOLS="@standard"      Permission preset or explicit tools
  MAX_CALLS_PER_HOUR=100         API call rate limit

Heavy mode variables (heavy-coding / heavy-idea only):
  CODEX_TIMEOUT=15               Codex CLI timeout in minutes (1-120)
  CODEX_APPROVAL="never"         Codex approval mode: never or on-request
  DEBATE_ROUNDS=2                Cross-AI debate rounds (1-3)

Validation:
  korero --validate              Check .korerorc for errors

Create via:
  korero-enable                  Interactive wizard
  korero-enable-ci               Non-interactive (CI/scripts)
TOPICEOF
            ;;
        *)
            echo "Unknown help topic: $topic"
            echo ""
            echo "Available topics:"
            echo "  presets, circuit-breaker, session, tools,"
            echo "  modes, exit-detection, rate-limiting, config"
            echo ""
            echo "Usage: korero --help <topic>"
            return 1
            ;;
    esac
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
                show_help_topic "$2"
                exit $?
            fi
            show_help
            exit 0
            ;;
        -c|--calls)
            MAX_CALLS_PER_HOUR="$2"
            shift 2
            ;;
        -p|--prompt)
            PROMPT_FILE="$2"
            shift 2
            ;;
        -s|--status)
            bash "$SCRIPT_DIR/korero_status.sh"
            exit $?
            ;;
        --config)
            shift
            bash "$SCRIPT_DIR/korero_config.sh" "$@"
            exit $?
            ;;
        ideas)
            shift
            bash "$SCRIPT_DIR/korero_ideas.sh" "$@"
            exit $?
            ;;
        -m|--monitor)
            USE_TMUX=true
            shift
            ;;
        -v|--verbose)
            VERBOSE_PROGRESS=true
            shift
            ;;
        -l|--live)
            LIVE_OUTPUT=true
            shift
            ;;
        -t|--timeout)
            if [[ "$2" =~ ^[1-9][0-9]*$ ]] && [[ "$2" -le 120 ]]; then
                CLAUDE_TIMEOUT_MINUTES="$2"
            else
                echo "Error: Timeout must be a positive integer between 1 and 120 minutes"
                exit 1
            fi
            shift 2
            ;;
        --reset-circuit)
            # Source the circuit breaker library
            SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
            source "$SCRIPT_DIR/lib/circuit_breaker.sh"
            source "$SCRIPT_DIR/lib/date_utils.sh"
            reset_circuit_breaker "Manual reset via command line"
            reset_session "manual_circuit_reset"
            exit 0
            ;;
        --reset-session)
            # Reset session state only
            SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
            source "$SCRIPT_DIR/lib/date_utils.sh"
            reset_session "manual_reset_flag"
            echo -e "\033[0;32m✅ Session state reset successfully\033[0m"
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --validate)
            SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
            source "$SCRIPT_DIR/lib/enable_core.sh"
            if validate_korerorc ".korerorc"; then
                echo -e "\033[0;32m✅ Configuration valid: .korerorc\033[0m"
                exit 0
            else
                exit 1
            fi
            ;;
        --validate-config)
            SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
            source "$SCRIPT_DIR/lib/enable_core.sh"
            validate_korerorc_verbose ".korerorc"
            exit $?
            ;;
        --fix-config)
            SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
            source "$SCRIPT_DIR/lib/enable_core.sh"
            local korerorc=".korerorc"
            if [[ ! -f "$korerorc" ]]; then
                echo "No .korerorc found. Run: korero --quickstart"
                exit 1
            fi
            echo "Applying default fixes to $korerorc..."
            local fix_count=0
            for field in ALLOWED_TOOLS KORERO_MODE MAX_LOOPS; do
                if ! grep -q "^${field}=" "$korerorc" 2>/dev/null; then
                    eval "$(get_config_fix "$field" "$korerorc")"
                    echo "  Added: $field"
                    fix_count=$((fix_count + 1))
                fi
            done
            if [[ $fix_count -eq 0 ]]; then
                echo "  No missing fields found."
            else
                echo "$fix_count field(s) added."
            fi
            echo "Run 'korero --validate-config' to verify."
            exit 0
            ;;
        --quickstart)
            SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
            source "$SCRIPT_DIR/lib/enable_core.sh"
            source "$SCRIPT_DIR/lib/wizard_utils.sh" 2>/dev/null || true
            run_quickstart_wizard
            exit $?
            ;;
        --examples)
            show_examples_gallery
            exit 0
            ;;
        --health-check)
            run_health_check
            exit $?
            ;;
        --cost-estimate)
            display_cost_report
            exit $?
            ;;
        --cost-history|--costs)
            show_cost_history
            exit $?
            ;;
        --debate-stats|--quality)
            show_debate_stats
            exit $?
            ;;
        --debate-health)
            source "$SCRIPT_DIR/lib/cross_ai_debate.sh" 2>/dev/null || true
            echo "Analyzing debate health (last 10 debates)..."
            analyze_debate_fatigue 10
            local _dh_rc=$?
            if [[ $_dh_rc -eq 0 ]]; then
                local _metrics_file="${KORERO_DIR:-.korero}/.debate_metrics"
                if [[ ! -f "$_metrics_file" ]] || [[ $(wc -l < "$_metrics_file" 2>/dev/null || echo 0) -lt 3 ]]; then
                    echo "No debate metrics found. Run heavy mode loops to collect data."
                fi
            fi
            exit 0
            ;;
        --implementation-status|--impl-status)
            show_implementation_status
            exit $?
            ;;
        --shutdown-history)
            show_shutdown_history "${2:-20}"
            exit $?
            ;;
        --rate-status|--rate|-r)
            show_rate_status
            exit $?
            ;;
        --search-ideas|--find-ideas)
            shift
            search_ideas "$1"
            exit $?
            ;;
        --troubleshoot|--troubleshooting)
            show_troubleshoot_reference
            exit 0
            ;;
        --diagnose)
            run_interactive_troubleshooter
            exit 0
            ;;
        --show-debate)
            SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
            source "$SCRIPT_DIR/lib/debate_transcript.sh"
            if [[ -n "${2:-}" && "$2" =~ ^[0-9]+$ ]]; then
                show_debate_transcript "$2"
            else
                show_debate_transcript "latest"
            fi
            exit $?
            ;;
        --circuit-status)
            # Source the circuit breaker library
            SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
            source "$SCRIPT_DIR/lib/circuit_breaker.sh"
            show_circuit_status
            exit 0
            ;;
        --output-format)
            if [[ "$2" == "json" || "$2" == "text" ]]; then
                CLAUDE_OUTPUT_FORMAT="$2"
            else
                echo "Error: --output-format must be 'json' or 'text'"
                exit 1
            fi
            shift 2
            ;;
        --allowed-tools)
            if ! validate_allowed_tools "$2"; then
                exit 1
            fi
            CLAUDE_ALLOWED_TOOLS="$2"
            shift 2
            ;;
        --no-continue)
            CLAUDE_USE_CONTINUE=false
            shift
            ;;
        --session-expiry)
            if [[ -z "$2" || ! "$2" =~ ^[1-9][0-9]*$ ]]; then
                echo "Error: --session-expiry requires a positive integer (hours)"
                exit 1
            fi
            CLAUDE_SESSION_EXPIRY_HOURS="$2"
            shift 2
            ;;
        --codex-timeout)
            if [[ "$2" =~ ^[1-9][0-9]*$ ]] && [[ "$2" -le 120 ]]; then
                CODEX_TIMEOUT_MINUTES="$2"
            else
                echo "Error: --codex-timeout must be a positive integer between 1 and 120 minutes"
                exit 1
            fi
            shift 2
            ;;
        --debate-rounds)
            if [[ "$2" =~ ^[1-3]$ ]]; then
                DEBATE_ROUNDS="$2"
            else
                echo "Error: --debate-rounds must be 1, 2, or 3"
                exit 1
            fi
            shift 2
            ;;
        --start-idea)
            if [[ -z "${2:-}" || ! "$2" =~ ^[1-9][0-9]*$ ]]; then
                echo "Error: --start-idea requires a positive loop number"
                echo "Usage: korero --start-idea <loop_number>"
                echo ""
                echo "List available ideas: korero ideas list"
                exit 1
            fi
            START_IDEA_LOOP="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Only execute when run directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Dry run mode: show config and exit without executing
    if [[ "$DRY_RUN" == "true" ]]; then
        load_korerorc 2>/dev/null || true
        show_dry_run_info
        exit 0
    fi

    # Start idea-to-branch workflow if requested
    if [[ -n "${START_IDEA_LOOP:-}" ]]; then
        load_korerorc 2>/dev/null || true
        start_idea_workflow "$START_IDEA_LOOP"
    fi

    # If tmux mode requested, set it up
    if [[ "$USE_TMUX" == "true" ]]; then
        check_tmux_available
        setup_tmux_session
    fi

    # Start the main loop
    main
fi
