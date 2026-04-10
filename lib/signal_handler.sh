#!/bin/bash
# Signal Handler for Korero — Portable Signal Handling (Loop 31)
# Provides cross-platform SIGINT/SIGTERM handling with shutdown history logging

# Source date utilities for cross-platform compatibility
source "$(dirname "${BASH_SOURCE[0]}")/date_utils.sh"

# Use KORERO_DIR if set by main script, otherwise default to .korero
KORERO_DIR="${KORERO_DIR:-.korero}"
SIGNAL_LOG_FILE="$KORERO_DIR/.signal_log.json"

# Shutdown reason codes
SHUTDOWN_REASON_SIGINT="sigint"
SHUTDOWN_REASON_SIGTERM="sigterm"
SHUTDOWN_REASON_BUDGET="budget_exceeded"
SHUTDOWN_REASON_CIRCUIT="circuit_open"
SHUTDOWN_REASON_COMPLETE="project_complete"
SHUTDOWN_REASON_LIMIT="loop_limit"
SHUTDOWN_REASON_MANUAL="manual"
SHUTDOWN_REASON_ERROR="error"

# Record a shutdown event to the signal log
# Usage: record_shutdown_signal reason loop_count [detail]
record_shutdown_signal() {
    local reason="${1:-unknown}"
    local loop_count="${2:-0}"
    local detail="${3:-}"
    local timestamp
    timestamp=$(get_iso_timestamp)

    mkdir -p "$KORERO_DIR"

    # Build new entry
    local new_entry
    new_entry=$(printf '{"timestamp":"%s","reason":"%s","loop":%d,"detail":"%s"}' \
        "$timestamp" "$reason" "$loop_count" "$detail")

    # Append to log (create if missing)
    if [[ ! -f "$SIGNAL_LOG_FILE" ]]; then
        printf '{"shutdowns":[%s]}\n' "$new_entry" > "$SIGNAL_LOG_FILE"
    elif command -v jq &>/dev/null; then
        local tmp_file
        tmp_file=$(mktemp)
        if jq --argjson entry "$new_entry" '.shutdowns += [$entry]' \
               "$SIGNAL_LOG_FILE" > "$tmp_file" 2>/dev/null; then
            mv "$tmp_file" "$SIGNAL_LOG_FILE"
        else
            rm -f "$tmp_file"
        fi
    else
        # jq not available: overwrite with single entry to avoid corruption
        printf '{"shutdowns":[%s]}\n' "$new_entry" > "$SIGNAL_LOG_FILE"
    fi
}

# Display formatted shutdown history
# Usage: show_shutdown_history [limit]
show_shutdown_history() {
    local limit="${1:-20}"

    if [[ ! -f "$SIGNAL_LOG_FILE" ]]; then
        echo "No shutdown history found."
        echo "History is recorded in $SIGNAL_LOG_FILE after the first graceful exit."
        return 0
    fi

    if ! command -v jq &>/dev/null; then
        echo "jq is required to display shutdown history."
        cat "$SIGNAL_LOG_FILE"
        return 0
    fi

    local count
    count=$(jq '.shutdowns | length' "$SIGNAL_LOG_FILE" 2>/dev/null || echo "0")

    if [[ "$count" -eq 0 ]]; then
        echo "No shutdown events recorded yet."
        return 0
    fi

    echo ""
    echo "══════════════════════════════════════════════════════════"
    echo "SHUTDOWN HISTORY"
    echo "══════════════════════════════════════════════════════════"
    printf "%-26s %-18s %6s  %s\n" "Timestamp" "Reason" "Loop" "Detail"
    echo "──────────────────────────────────────────────────────────"

    # Show last N entries (most recent first)
    jq -r --argjson limit "$limit" \
        '.shutdowns | reverse | .[:$limit] | .[] |
         [.timestamp, .reason, (.loop | tostring), (.detail // "")] | @tsv' \
        "$SIGNAL_LOG_FILE" 2>/dev/null | \
    while IFS=$'\t' read -r ts reason loop detail; do
        printf "%-26s %-18s %6s  %s\n" "$ts" "$reason" "$loop" "$detail"
    done

    echo "──────────────────────────────────────────────────────────"
    echo "Total events: $count (showing last $limit)"
    echo ""
    return 0
}

# Get the count of shutdown events
# Usage: get_shutdown_count
get_shutdown_count() {
    if [[ ! -f "$SIGNAL_LOG_FILE" ]]; then
        echo "0"
        return 0
    fi
    if command -v jq &>/dev/null; then
        jq '.shutdowns | length' "$SIGNAL_LOG_FILE" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Get the most recent shutdown reason
# Usage: get_last_shutdown_reason
get_last_shutdown_reason() {
    if [[ ! -f "$SIGNAL_LOG_FILE" ]]; then
        echo ""
        return 0
    fi
    if command -v jq &>/dev/null; then
        jq -r '.shutdowns[-1].reason // empty' "$SIGNAL_LOG_FILE" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Install a portable signal handler for SIGINT and SIGTERM
# Usage: install_signal_handlers callback_function loop_count_var
# The callback receives: reason loop_count
install_signal_handlers() {
    local callback="${1:-_default_signal_callback}"
    local loop_count_var="${2:-loop_count}"

    # SIGINT (Ctrl+C) handler
    trap "_handle_signal '$callback' '$loop_count_var' '$SHUTDOWN_REASON_SIGINT'" SIGINT

    # SIGTERM (kill, system shutdown) handler
    trap "_handle_signal '$callback' '$loop_count_var' '$SHUTDOWN_REASON_SIGTERM'" SIGTERM
}

# Internal signal dispatch function
_handle_signal() {
    local callback="$1"
    local loop_count_var="$2"
    local reason="$3"
    local current_loop="${!loop_count_var:-0}"

    record_shutdown_signal "$reason" "$current_loop"
    "$callback" "$reason" "$current_loop"
}

# Default signal callback (logs and exits cleanly)
_default_signal_callback() {
    local reason="$1"
    local loop_count="$2"
    echo "" >&2
    echo "Korero: received $reason at loop $loop_count. Exiting." >&2
    exit 0
}

# Export all public functions
export -f record_shutdown_signal
export -f show_shutdown_history
export -f get_shutdown_count
export -f get_last_shutdown_reason
export -f install_signal_handlers
export -f _handle_signal
export -f _default_signal_callback
