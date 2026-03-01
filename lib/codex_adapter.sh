#!/usr/bin/env bash

# codex_adapter.sh — OpenAI Codex CLI adapter for Korero heavy modes
#
# Encapsulates all interaction with the Codex CLI, mirroring the Claude Code
# patterns in korero_loop.sh. Used by heavy-coding and heavy-idea modes for
# parallel dual-AI execution.
#
# Codex authenticates via OAuth (browser or device-code flow).
# Credentials stored in ~/.codex/auth.json or OS keyring.

KORERO_DIR="${KORERO_DIR:-.korero}"
CODEX_MODEL="${CODEX_MODEL:-gpt-5.3-codex}"

# Global array for Codex command arguments (mirrors CLAUDE_CMD_ARGS pattern)
declare -a CODEX_CMD_ARGS=()

# Check if Codex CLI is installed and authenticated
# Returns: 0 (ready), 1 (not installed), 2 (not authenticated)
check_codex_ready() {
    if ! command -v codex &>/dev/null; then
        return 1
    fi

    if ! check_codex_auth; then
        return 2
    fi

    return 0
}

# Check if Codex authentication exists
# Checks ~/.codex/auth.json first, then tries codex login status as smoke test
# Returns: 0 if authenticated, 1 if not
check_codex_auth() {
    local codex_home="${CODEX_HOME:-$HOME/.codex}"

    # Check for auth.json file
    if [[ -f "$codex_home/auth.json" ]]; then
        return 0
    fi

    # Fallback: try codex login status (exit 0 = logged in)
    if command -v codex &>/dev/null; then
        if codex login status &>/dev/null; then
            return 0
        fi
    fi

    return 1
}

# Run Codex OAuth login flow
# Arguments:
#   $1 (method) - "browser" for full OAuth, "device" for device-code flow
# Returns: 0 on success, 1 on failure
run_codex_login() {
    local method="${1:-device}"

    if ! command -v codex &>/dev/null; then
        echo "Error: Codex CLI not found. Install with: npm install -g @openai/codex" >&2
        return 1
    fi

    case "$method" in
        device)
            echo "Starting Codex device code authentication..."
            echo "Follow the instructions to sign in."
            codex login --device-auth
            ;;
        browser)
            echo "Starting Codex browser OAuth authentication..."
            echo "A browser window will open for sign-in."
            codex login
            ;;
        api-key)
            echo "Enter your OpenAI API key:"
            codex login --with-api-key
            ;;
        *)
            echo "Error: Unknown auth method '$method'. Use 'browser', 'device', or 'api-key'." >&2
            return 1
            ;;
    esac

    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        echo "Codex authentication successful."
    else
        echo "Codex authentication failed (exit code: $exit_code)." >&2
    fi
    return $exit_code
}

# Build Codex CLI command with appropriate flags
# Populates global CODEX_CMD_ARGS array (shell-injection safe)
# Arguments:
#   $1 (prompt_content) - The prompt text to send
#   $2 (mode)           - "heavy-coding" or "heavy-idea" (controls sandbox)
#   $3 (output_path)    - Path to write the final message
# Returns: 0 on success
build_codex_command() {
    local prompt_content="$1"
    local mode="${2:-heavy-idea}"
    local output_path="$3"

    # Reset global array
    CODEX_CMD_ARGS=("codex" "exec")

    # Model selection
    CODEX_CMD_ARGS+=("--model" "$CODEX_MODEL")

    # JSON output for machine parsing
    CODEX_CMD_ARGS+=("--json")

    # Sandbox: always read-only for proposals (Claude implements the winner)
    CODEX_CMD_ARGS+=("--sandbox" "read-only")

    # Prompt as positional argument (must be last)
    CODEX_CMD_ARGS+=("$prompt_content")

    return 0
}

# Parse Codex NDJSON output into normalized analysis format
# Creates a normalized result file compatible with Korero's analysis pipeline
# Arguments:
#   $1 (ndjson_file)       - Path to raw Codex NDJSON output (stdout from codex exec --json)
#   $2 (last_message_file) - Path to last message file (legacy, may not exist)
#   $3 (result_file)       - Path to write normalized result (optional)
# Returns: 0 on success, 1 on parse error
parse_codex_response() {
    local ndjson_file="$1"
    local last_message_file="${2:-}"
    local result_file="${3:-$KORERO_DIR/.codex_parse_result}"

    local proposal_text=""
    local output_length=0

    # Primary: extract from NDJSON stream (codex exec --json output)
    if [[ -f "$ndjson_file" && -s "$ndjson_file" ]]; then
        if command -v jq &>/dev/null; then
            proposal_text=$(jq -r 'select(.type == "message" or .type == "assistant" or .type == "result") | .content // .message // .result // empty' "$ndjson_file" 2>/dev/null | tail -1)
        fi
        # Fallback: if jq parsing fails, try reading last non-empty line
        if [[ -z "$proposal_text" ]]; then
            proposal_text=$(grep -v '^\s*$' "$ndjson_file" 2>/dev/null | tail -1)
        fi
        output_length=${#proposal_text}
    fi

    # Secondary: check last_message_file if it exists
    if [[ -z "$proposal_text" && -n "$last_message_file" && -f "$last_message_file" && -s "$last_message_file" ]]; then
        proposal_text=$(cat "$last_message_file")
        output_length=${#proposal_text}
    fi

    if [[ -z "$proposal_text" ]]; then
        echo '{"status":"error","error":"no_output","output_length":0}' > "$result_file"
        return 1
    fi

    # Build normalized result JSON
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')

    cat > "$result_file" << PARSEJSON
{
  "source": "codex",
  "timestamp": "$timestamp",
  "status": "success",
  "output_length": $output_length,
  "has_proposal": true
}
PARSEJSON

    return 0
}

# Extract proposal text from Codex output
# Parses NDJSON output from codex exec --json
# Arguments:
#   $1 (ndjson_file)       - Path to Codex NDJSON output (stdout capture)
#   $2 (last_message_file) - Path to last message file (legacy, optional)
# Returns: proposal text on stdout
extract_codex_proposal() {
    local ndjson_file="$1"
    local last_message_file="${2:-}"

    # Primary: parse NDJSON stream from codex exec --json
    if [[ -f "$ndjson_file" && -s "$ndjson_file" ]]; then
        local text=""
        if command -v jq &>/dev/null; then
            text=$(jq -r 'select(.type == "message" or .type == "assistant" or .type == "result") | .content // .message // .result // empty' "$ndjson_file" 2>/dev/null | tail -1)
        fi
        # Fallback: if jq can't parse, read last non-empty line
        if [[ -z "$text" ]]; then
            text=$(grep -v '^\s*$' "$ndjson_file" 2>/dev/null | tail -1)
        fi
        if [[ -n "$text" ]]; then
            echo "$text"
            return 0
        fi
    fi

    # Secondary: check last_message_file if it exists
    if [[ -n "$last_message_file" && -f "$last_message_file" && -s "$last_message_file" ]]; then
        cat "$last_message_file"
        return 0
    fi

    echo ""
    return 1
}

# Determine if heavy mode should fall back to Claude-only
# Checks CODEX_FALLBACK env and Codex readiness
# Returns: 0 if should fallback, 1 if Codex is ready (no fallback needed)
# Side effects: sets CODEX_FALLBACK_REASON on stdout
should_fallback_to_claude() {
    local fallback_mode="${CODEX_FALLBACK:-fail}"

    # If fallback is disabled, never fall back — caller handles errors
    if [[ "$fallback_mode" == "fail" ]]; then
        return 1
    fi

    # Check Codex readiness
    local codex_status=0
    check_codex_ready || codex_status=$?

    case $codex_status in
        0)
            # Codex is ready, no fallback needed
            return 1
            ;;
        1)
            echo "not_installed"
            return 0
            ;;
        2)
            echo "not_authenticated"
            return 0
            ;;
        *)
            echo "unknown_error"
            return 0
            ;;
    esac
}

# Display a warning when falling back to Claude-only mode
# Arguments:
#   $1 (reason) - Fallback reason: "not_installed", "not_authenticated", "unknown_error"
#   $2 (fallback_mode) - Fallback mode: "claude-only" or "silent"
# Output: Warning message to stderr (suppressed in "silent" mode)
display_fallback_warning() {
    local reason="${1:-unknown}"
    local fallback_mode="${2:-${CODEX_FALLBACK:-claude-only}}"

    # Silent mode suppresses all output
    if [[ "$fallback_mode" == "silent" ]]; then
        return 0
    fi

    local reason_text
    case "$reason" in
        not_installed)
            reason_text="Codex CLI is not installed (npm install -g @openai/codex)"
            ;;
        not_authenticated)
            reason_text="Codex is not authenticated (run: codex login --device-auth)"
            ;;
        *)
            reason_text="Codex is unavailable (reason: $reason)"
            ;;
    esac

    cat >&2 << FALLBACK_WARN_EOF
╔════════════════════════════════════════════════════════╗
║  CODEX FALLBACK                                        ║
╠════════════════════════════════════════════════════════╣
║                                                        ║
║  $reason_text
║                                                        ║
║  Falling back to Claude-only mode.                     ║
║  Set CODEX_FALLBACK="fail" in .korerorc to require     ║
║  Codex (default behavior).                             ║
║                                                        ║
╚════════════════════════════════════════════════════════╝
FALLBACK_WARN_EOF
}

export -f check_codex_ready
export -f check_codex_auth
export -f run_codex_login
export -f build_codex_command
export -f parse_codex_response
export -f extract_codex_proposal
export -f should_fallback_to_claude
export -f display_fallback_warning
