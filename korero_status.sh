#!/usr/bin/env bash
# korero_status.sh — Display comprehensive Korero project status
# Aggregates runtime state from all Korero state files into a single view

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/date_utils.sh"

KORERO_DIR=".korero"

# Colors (only if terminal supports them)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''
fi

show_status() {
    local project_name
    project_name=$(basename "$(pwd)")

    # Check if this is a Korero project
    if [[ ! -d "$KORERO_DIR" ]] && [[ ! -f ".korerorc" ]]; then
        echo "Not a Korero project directory (no .korero/ or .korerorc found)."
        echo "Run 'korero-enable' to set up Korero in this project."
        return 1
    fi

    # Load configuration from .korerorc
    local mode="coding"
    local max_loops="continuous"
    local subject=""
    local agent_count=3
    if [[ -f ".korerorc" ]]; then
        # shellcheck disable=SC1091
        source ".korerorc" 2>/dev/null || true
        mode="${KORERO_MODE:-coding}"
        max_loops="${MAX_LOOPS:-continuous}"
        subject="${PROJECT_SUBJECT:-}"
        agent_count="${DOMAIN_AGENT_COUNT:-3}"
    fi

    # Read session info
    local session_id="none"
    local session_age="N/A"
    if [[ -f "$KORERO_DIR/.claude_session_id" ]]; then
        session_id=$(cat "$KORERO_DIR/.claude_session_id" 2>/dev/null || echo "none")
        if [[ "$session_id" != "none" && -n "$session_id" ]]; then
            # Cross-platform stat for modification time
            local session_file_time
            session_file_time=$(stat -c %Y "$KORERO_DIR/.claude_session_id" 2>/dev/null || stat -f %m "$KORERO_DIR/.claude_session_id" 2>/dev/null || echo "0")
            if [[ "$session_file_time" != "0" ]]; then
                local now
                now=$(date +%s)
                local age_seconds=$((now - session_file_time))
                local age_hours=$((age_seconds / 3600))
                local age_minutes=$(((age_seconds % 3600) / 60))
                session_age="${age_hours}h ${age_minutes}m"
            fi
        fi
    fi

    # Read rate limit info
    local calls_used=0
    local calls_max="${MAX_CALLS_PER_HOUR:-100}"
    if [[ -f "$KORERO_DIR/.call_count" ]]; then
        calls_used=$(cat "$KORERO_DIR/.call_count" 2>/dev/null || echo "0")
        calls_used=$((calls_used + 0))
    fi
    local calls_remaining=$((calls_max - calls_used))
    if [[ $calls_remaining -lt 0 ]]; then calls_remaining=0; fi

    # Read circuit breaker state
    local cb_state="CLOSED"
    local cb_no_progress=0
    local cb_same_error=0
    local cb_total_opens=0
    local cb_reason=""
    if [[ -f "$KORERO_DIR/.circuit_breaker_state" ]]; then
        cb_state=$(jq -r '.state // "CLOSED"' "$KORERO_DIR/.circuit_breaker_state" 2>/dev/null || echo "CLOSED")
        cb_no_progress=$(jq -r '.consecutive_no_progress // 0' "$KORERO_DIR/.circuit_breaker_state" 2>/dev/null || echo "0")
        cb_same_error=$(jq -r '.consecutive_same_error // 0' "$KORERO_DIR/.circuit_breaker_state" 2>/dev/null || echo "0")
        cb_total_opens=$(jq -r '.total_opens // 0' "$KORERO_DIR/.circuit_breaker_state" 2>/dev/null || echo "0")
        cb_reason=$(jq -r '.reason // ""' "$KORERO_DIR/.circuit_breaker_state" 2>/dev/null || echo "")
    fi

    # Read loop info from status.json
    local current_loop=0
    local loop_status="idle"
    local last_exit="none"
    if [[ -f "$KORERO_DIR/status.json" ]]; then
        current_loop=$(jq -r '.loop // 0' "$KORERO_DIR/status.json" 2>/dev/null || echo "0")
        loop_status=$(jq -r '.status // "idle"' "$KORERO_DIR/status.json" 2>/dev/null || echo "idle")
        last_exit=$(jq -r '.last_exit_reason // "none"' "$KORERO_DIR/status.json" 2>/dev/null || echo "none")
    fi

    # Count ideas if in idea mode
    local idea_count=0
    if [[ -d "$KORERO_DIR/ideas" ]]; then
        idea_count=$(find "$KORERO_DIR/ideas" -name "loop_*_idea.md" 2>/dev/null | wc -l | tr -d '[:space:]')
        idea_count=${idea_count:-0}
    fi

    # Count fix_plan items
    local total_tasks=0
    local completed_tasks=0
    if [[ -f "$KORERO_DIR/fix_plan.md" ]]; then
        total_tasks=$(grep -c '^\s*-\s*\[' "$KORERO_DIR/fix_plan.md" 2>/dev/null || true)
        total_tasks=${total_tasks:-0}
        completed_tasks=$(grep -c '^\s*-\s*\[x\]' "$KORERO_DIR/fix_plan.md" 2>/dev/null || true)
        completed_tasks=${completed_tasks:-0}
    fi

    # Output formatted status
    echo ""
    echo -e "${BOLD}==========================================${NC}"
    echo -e "${BOLD}  KORERO STATUS${NC}"
    echo -e "${BOLD}==========================================${NC}"
    echo ""
    echo -e "${BLUE}Project:${NC}    $project_name"
    echo -e "${BLUE}Mode:${NC}       $mode"
    [[ -n "$subject" ]] && echo -e "${BLUE}Subject:${NC}    $subject"
    echo -e "${BLUE}Agents:${NC}     $agent_count domain + 3 evaluation"
    echo ""

    # Session
    echo -e "${BOLD}Session${NC}"
    if [[ "$session_id" != "none" && -n "$session_id" ]]; then
        echo -e "  ID:  ${session_id:0:16}..."
        echo -e "  Age: $session_age"
    else
        echo -e "  No active session"
    fi
    echo ""

    # Loop Progress
    echo -e "${BOLD}Loop Progress${NC}"
    echo -e "  Current: $current_loop of $max_loops"
    echo -e "  Status:  $loop_status"
    [[ "$last_exit" != "none" ]] && echo -e "  Last Exit: $last_exit"
    echo ""

    # Tasks
    if [[ $total_tasks -gt 0 ]]; then
        echo -e "${BOLD}Tasks${NC}"
        echo -e "  Completed: $completed_tasks/$total_tasks"
        echo ""
    fi

    # Ideas (if applicable)
    if [[ $idea_count -gt 0 ]]; then
        echo -e "${BOLD}Ideas${NC}"
        echo -e "  Generated: $idea_count"
        echo ""
    fi

    # Rate Limit
    echo -e "${BOLD}Rate Limit${NC}"
    if [[ $calls_remaining -le 10 ]]; then
        echo -e "  Remaining: ${RED}$calls_remaining${NC}/$calls_max calls"
    elif [[ $calls_remaining -le 25 ]]; then
        echo -e "  Remaining: ${YELLOW}$calls_remaining${NC}/$calls_max calls"
    else
        echo -e "  Remaining: ${GREEN}$calls_remaining${NC}/$calls_max calls"
    fi
    echo ""

    # Circuit Breaker
    echo -e "${BOLD}Circuit Breaker${NC}"
    case "$cb_state" in
        "CLOSED")  echo -e "  State: ${GREEN}$cb_state${NC}" ;;
        "HALF_OPEN") echo -e "  State: ${YELLOW}$cb_state${NC}" ;;
        "OPEN")    echo -e "  State: ${RED}$cb_state${NC}" ;;
        *)         echo -e "  State: $cb_state" ;;
    esac
    echo -e "  No-progress: $cb_no_progress/${CB_NO_PROGRESS_THRESHOLD:-3}"
    echo -e "  Same-error:  $cb_same_error/${CB_SAME_ERROR_THRESHOLD:-5}"
    [[ "$cb_total_opens" -gt 0 ]] && echo -e "  Total opens: $cb_total_opens"
    [[ -n "$cb_reason" && "$cb_reason" != "" ]] && echo -e "  Reason: $cb_reason"
    echo ""
    echo -e "${BOLD}==========================================${NC}"
}

show_status "$@"
