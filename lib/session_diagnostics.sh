#!/usr/bin/env bash

# session_diagnostics.sh - Session resume diagnostic information
# Explains why session resumption failed instead of silently starting fresh.

# Diagnose session resume state
# Usage: diagnose_session <session_file> <max_age_seconds>
# Returns a diagnostic message explaining the session state
diagnose_session() {
    local session_file="${1:-.korero/.claude_session_id}"
    local max_age="${2:-86400}"

    # Check if session file exists
    if [[ ! -f "$session_file" ]]; then
        echo "REASON: no_session_file"
        echo "MESSAGE: No previous session found. Starting fresh."
        echo "DETAIL: File '$session_file' does not exist."
        return 0
    fi

    # Check if file is empty
    local content
    content=$(cat "$session_file" 2>/dev/null)
    if [[ -z "$content" ]]; then
        echo "REASON: empty_session_file"
        echo "MESSAGE: Session file exists but is empty. Starting fresh."
        echo "DETAIL: File '$session_file' has no content."
        return 0
    fi

    # Check if it's valid JSON (for JSON format session files)
    if [[ "$content" == "{"* ]]; then
        if ! echo "$content" | jq -e '.' >/dev/null 2>&1; then
            echo "REASON: corrupted_session"
            echo "MESSAGE: Session file is corrupted (invalid JSON). Starting fresh."
            echo "DETAIL: Could not parse '$session_file' as valid JSON."
            return 0
        fi

        # Check for session ID
        local session_id
        session_id=$(echo "$content" | jq -r '.session_id // .sessionId // ""' 2>/dev/null)
        if [[ -z "$session_id" ]]; then
            echo "REASON: missing_session_id"
            echo "MESSAGE: Session file has no session ID. Starting fresh."
            echo "DETAIL: No 'session_id' or 'sessionId' field found."
            return 0
        fi

        # Check session age
        local timestamp
        timestamp=$(echo "$content" | jq -r '.timestamp // ""' 2>/dev/null)
        if [[ -n "$timestamp" ]]; then
            local now
            now=$(date +%s)
            local session_time=""

            # Try to parse timestamp
            if command -v gdate &>/dev/null; then
                local clean_ts="${timestamp}"
                [[ "$timestamp" =~ \.[0-9]+[+-Z] ]] && clean_ts=$(echo "$timestamp" | sed 's/\.[0-9]*\([+-Z]\)/\1/')
                session_time=$(gdate -d "$clean_ts" +%s 2>/dev/null)
            elif date --version 2>&1 | grep -q GNU 2>/dev/null; then
                local clean_ts="${timestamp}"
                [[ "$timestamp" =~ \.[0-9]+[+-Z] ]] && clean_ts=$(echo "$timestamp" | sed 's/\.[0-9]*\([+-Z]\)/\1/')
                session_time=$(date -d "$clean_ts" +%s 2>/dev/null)
            fi

            if [[ -n "$session_time" && "$session_time" =~ ^[0-9]+$ ]]; then
                local age=$((now - session_time))
                if [[ $age -ge $max_age ]]; then
                    local age_hours=$((age / 3600))
                    local max_hours=$((max_age / 3600))
                    echo "REASON: session_expired"
                    echo "MESSAGE: Session expired (${age_hours}h old, max ${max_hours}h). Starting fresh."
                    echo "DETAIL: Session '${session_id}' created $age_hours hours ago exceeds ${max_hours}h limit."
                    return 0
                fi

                # Session is valid
                local age_mins=$((age / 60))
                echo "REASON: session_valid"
                echo "MESSAGE: Session '${session_id}' is valid (${age_mins}m old). Resuming."
                echo "DETAIL: Session within ${max_age}s expiration window."
                return 0
            fi

            echo "REASON: unparseable_timestamp"
            echo "MESSAGE: Could not parse session timestamp. Starting fresh."
            echo "DETAIL: Timestamp '$timestamp' could not be converted to epoch."
            return 0
        fi

        echo "REASON: no_timestamp"
        echo "MESSAGE: Session has no timestamp. Starting fresh."
        echo "DETAIL: No 'timestamp' field in session file."
        return 0
    fi

    # Plain text session ID (old format)
    local session_id="$content"
    # Check file age
    local file_age=0
    if [[ "$(uname)" == "Darwin" ]]; then
        file_age=$(( $(date +%s) - $(stat -f %m "$session_file" 2>/dev/null || echo 0) ))
    else
        file_age=$(( $(date +%s) - $(stat -c %Y "$session_file" 2>/dev/null || echo 0) ))
    fi

    if [[ $file_age -ge $max_age ]]; then
        local age_hours=$((file_age / 3600))
        local max_hours=$((max_age / 3600))
        echo "REASON: session_expired"
        echo "MESSAGE: Session expired (${age_hours}h old, max ${max_hours}h). Starting fresh."
        echo "DETAIL: Session file for '${session_id}' is ${age_hours} hours old."
        return 0
    fi

    local age_mins=$((file_age / 60))
    echo "REASON: session_valid"
    echo "MESSAGE: Session '${session_id}' is valid (${age_mins}m old). Resuming."
    echo "DETAIL: Session within expiration window."
    return 0
}

# Get just the reason code from diagnostics
# Usage: get_session_diagnostic_reason <session_file> [max_age]
get_session_diagnostic_reason() {
    local diag
    diag=$(diagnose_session "$@")
    echo "$diag" | grep "^REASON:" | head -1 | cut -d' ' -f2-
}

# Get just the message from diagnostics
# Usage: get_session_diagnostic_message <session_file> [max_age]
get_session_diagnostic_message() {
    local diag
    diag=$(diagnose_session "$@")
    echo "$diag" | grep "^MESSAGE:" | head -1 | cut -d' ' -f2-
}

# Compute a context hash from key config files
# Usage: compute_context_hash <korero_dir>
# Returns: hash string for detecting config changes
compute_context_hash() {
    local korero_dir="${1:-.korero}"
    local hash_input=""

    # Include PROMPT.md content hash
    if [[ -f "$korero_dir/PROMPT.md" ]]; then
        hash_input+=$(md5sum "$korero_dir/PROMPT.md" 2>/dev/null | cut -d' ' -f1 || echo "no-prompt")
    fi

    # Include .korerorc content hash
    if [[ -f ".korerorc" ]]; then
        hash_input+=$(md5sum ".korerorc" 2>/dev/null | cut -d' ' -f1 || echo "no-rc")
    fi

    # Include AGENT.md content hash
    if [[ -f "$korero_dir/AGENT.md" ]]; then
        hash_input+=$(md5sum "$korero_dir/AGENT.md" 2>/dev/null | cut -d' ' -f1 || echo "no-agent")
    fi

    echo "$hash_input" | md5sum 2>/dev/null | cut -d' ' -f1 || echo "unknown"
}

export -f diagnose_session
export -f get_session_diagnostic_reason
export -f get_session_diagnostic_message
export -f compute_context_hash
