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
CODEX_LAST_ERROR=""
CODEX_LAST_ERROR_KIND=""

# Global array for Codex command arguments (mirrors CLAUDE_CMD_ARGS pattern)
declare -a CODEX_CMD_ARGS=()

# Resolve the best Codex launcher for the current shell.
# On Windows-like shells, prefer codex.cmd to avoid npm's POSIX shim path issues.
resolve_codex_cli() {
    if [[ -n "${CODEX_CLI:-}" ]]; then
        if [[ -x "$CODEX_CLI" ]] || command -v "$CODEX_CLI" &>/dev/null; then
            printf '%s\n' "$CODEX_CLI"
            return 0
        fi
        return 1
    fi

    local uname_s=""
    uname_s=$(uname -s 2>/dev/null || echo "")

    if [[ "${OS:-}" == "Windows_NT" ]]; then
        if command -v codex.cmd &>/dev/null; then
            printf '%s\n' "codex.cmd"
            return 0
        fi
    fi

    case "$uname_s" in
        CYGWIN*|MINGW*|MSYS*)
            if command -v codex.cmd &>/dev/null; then
                printf '%s\n' "codex.cmd"
                return 0
            fi
            ;;
    esac

    if command -v codex &>/dev/null; then
        printf '%s\n' "codex"
        return 0
    fi

    if command -v codex.cmd &>/dev/null; then
        printf '%s\n' "codex.cmd"
        return 0
    fi

    return 1
}

# Smoke-test the selected Codex launcher.
# Returns: 0 if the launcher starts successfully, 1 otherwise.
check_codex_runtime() {
    local codex_cli="$1"
    local output=""

    CODEX_LAST_ERROR=""
    CODEX_LAST_ERROR_KIND=""

    output=$("$codex_cli" --version 2>&1)
    if [[ $? -eq 0 ]]; then
        return 0
    fi

    CODEX_LAST_ERROR="$output"

    if [[ "$output" == *"MODULE_NOT_FOUND"* ]] || [[ "$output" == *"Cannot find module"* ]] || [[ "$output" == *"Missing optional dependency"* ]]; then
        CODEX_LAST_ERROR_KIND="broken_install"
    elif [[ "$output" == *"running scripts is disabled"* ]]; then
        CODEX_LAST_ERROR_KIND="powershell_policy"
    else
        CODEX_LAST_ERROR_KIND="launch_failed"
    fi

    return 1
}

# Convert the last launcher error into a concise repair hint.
get_codex_error_help() {
    local error_kind="${1:-$CODEX_LAST_ERROR_KIND}"

    case "$error_kind" in
        broken_install)
            echo "Codex CLI is installed but broken. Reinstall with: npm install -g @openai/codex@latest"
            ;;
        powershell_policy)
            echo "PowerShell is blocking codex.ps1. Use codex.cmd, or update execution policy if you run Codex manually."
            ;;
        launch_failed)
            echo "Codex CLI is installed but could not start. Run: codex --version (or codex.cmd --version on Windows) to inspect the launcher."
            ;;
        *)
            echo "Codex CLI is unavailable."
            ;;
    esac
}

# Check if Codex CLI is installed and authenticated
# Returns: 0 (ready), 1 (not installed), 2 (not authenticated), 3 (installed but unusable)
check_codex_ready() {
    local codex_cli=""

    if ! codex_cli=$(resolve_codex_cli); then
        CODEX_LAST_ERROR=""
        CODEX_LAST_ERROR_KIND="not_installed"
        return 1
    fi

    if ! check_codex_runtime "$codex_cli"; then
        return 3
    fi

    if ! check_codex_auth "$codex_cli"; then
        return 2
    fi

    return 0
}

# Check if Codex authentication exists
# Checks ~/.codex/auth.json first, then tries codex login status as smoke test
# Returns: 0 if authenticated, 1 if not
check_codex_auth() {
    local codex_cli="${1:-}"
    local codex_home="${CODEX_HOME:-$HOME/.codex}"

    # Check for auth.json file
    if [[ -f "$codex_home/auth.json" ]]; then
        return 0
    fi

    if [[ -z "$codex_cli" ]]; then
        codex_cli=$(resolve_codex_cli 2>/dev/null || true)
    fi

    # Fallback: try codex login status (exit 0 = logged in)
    if [[ -n "$codex_cli" ]] && "$codex_cli" login status &>/dev/null; then
        return 0
    fi

    return 1
}

# Run Codex OAuth login flow
# Arguments:
#   $1 (method) - "browser" for full OAuth, "device" for device-code flow
# Returns: 0 on success, 1 on failure
run_codex_login() {
    local method="${1:-device}"
    local codex_cli=""

    if ! codex_cli=$(resolve_codex_cli); then
        echo "Error: Codex CLI not found. Install with: npm install -g @openai/codex" >&2
        return 1
    fi

    if ! check_codex_runtime "$codex_cli"; then
        echo "Error: $(get_codex_error_help)" >&2
        return 1
    fi

    case "$method" in
        device)
            echo "Starting Codex device code authentication..."
            echo "Follow the instructions to sign in."
            "$codex_cli" login --device-auth
            ;;
        browser)
            echo "Starting Codex browser OAuth authentication..."
            echo "A browser window will open for sign-in."
            "$codex_cli" login
            ;;
        api-key)
            echo "Enter your OpenAI API key:"
            "$codex_cli" login --with-api-key
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
#   $1 (prompt_content) - The prompt text to send (passed later via stdin)
#   $2 (mode)           - "heavy-coding" or "heavy-idea" (controls sandbox)
#   $3 (output_path)    - Path to write the final message
# Returns: 0 on success
build_codex_command() {
    local prompt_content="$1"
    local mode="${2:-heavy-idea}"
    local output_path="$3"
    local codex_cli="codex"

    if codex_cli=$(resolve_codex_cli 2>/dev/null); then
        :
    else
        codex_cli="codex"
    fi

    # Reset global array
    CODEX_CMD_ARGS=("$codex_cli" "exec")

    # Model selection
    CODEX_CMD_ARGS+=("--model" "$CODEX_MODEL")

    # JSON output for machine parsing
    CODEX_CMD_ARGS+=("--json")

    # Sandbox: always read-only for proposals (Claude implements the winner)
    CODEX_CMD_ARGS+=("--sandbox" "read-only")

    # Korero uses Codex for read-only proposal generation, so bypass the
    # repository trust guard when the working tree itself is otherwise valid.
    CODEX_CMD_ARGS+=("--skip-git-repo-check")

    return 0
}

# Execute Codex with prompt content supplied over stdin.
# This avoids Windows command-line length limits when prompts are large.
# Arguments:
#   $1 (timeout_duration) - Timeout duration for portable_timeout (e.g. "300s")
#   $2 (prompt_content)   - Prompt text to pipe into Codex stdin
#   $3+                   - Prepared Codex command and arguments
# Returns: exit code from portable_timeout / Codex
run_codex_with_prompt() {
    local timeout_duration="$1"
    local prompt_content="$2"
    shift 2

    if [[ -z "$timeout_duration" ]]; then
        echo "Error: run_codex_with_prompt requires a timeout duration" >&2
        return 1
    fi

    if [[ $# -eq 0 ]]; then
        echo "Error: run_codex_with_prompt requires a Codex command" >&2
        return 1
    fi

    printf '%s' "$prompt_content" | portable_timeout "$timeout_duration" "$@"
}

# Treat bare protocol/usage objects as telemetry, not substantive Codex output.
codex_text_is_metadata_blob() {
    local text="$1"

    [[ -z "$text" ]] && return 1

    local compact="$text"
    compact="${compact//$'\r'/}"
    compact="${compact//$'\n'/}"

    if [[ "$compact" != \{*\"type\"* ]]; then
        return 1
    fi

    if command -v jq &>/dev/null; then
        printf '%s' "$compact" | jq -e '
            type == "object"
            and (.type? != null)
            and (
                (.text? // .content? // .message? // .result? // .output_text?
                 // .item?.text? // .item?.content? // .item?.message? // .item?.result? // .item?.output_text?) == null
            )
        ' >/dev/null 2>&1
        return $?
    fi

    [[ "$compact" == *'"type":'* ]] \
        && [[ "$compact" != *'"text":'* ]] \
        && [[ "$compact" != *'"content":'* ]] \
        && [[ "$compact" != *'"message":'* ]] \
        && [[ "$compact" != *'"result":'* ]] \
        && [[ "$compact" != *'"output_text":'* ]]
}

# PowerShell provides a reliable Windows fallback for large NDJSON lines when
# jq/grep extraction misses the final agent_message.
extract_codex_text_with_powershell() {
    local ndjson_file="$1"

    command -v powershell.exe &>/dev/null || return 1
    [[ ! -f "$ndjson_file" || ! -s "$ndjson_file" ]] && return 1

    local text=""
    local ps_script=""
    ps_script=$(cat <<'POWERSHELL'
$Path = $args[0]

if (-not (Test-Path -LiteralPath $Path)) {
    exit 1
}

$candidates = New-Object System.Collections.Generic.List[string]

Get-Content -LiteralPath $Path | ForEach-Object {
    if ($_ -eq 'Reading prompt from stdin...') {
        return
    }

    try {
        $obj = $_ | ConvertFrom-Json -Depth 100
    } catch {
        return
    }

    $text = $null

    if ($obj.type -in @('item.completed', 'item.started')) {
        $item = $obj.item
        if ($null -ne $item -and $item.type -in @('agent_message', 'assistant_message', 'message')) {
            $text = $item.text
            if (-not $text) { $text = $item.content }
            if (-not $text) { $text = $item.message }
            if (-not $text) { $text = $item.result }
            if (-not $text) { $text = $item.output_text }
        }
    }

    if (-not $text -and $obj.type -in @('message', 'assistant', 'result')) {
        $text = $obj.text
        if (-not $text) { $text = $obj.content }
        if (-not $text) { $text = $obj.message }
        if (-not $text) { $text = $obj.result }
        if (-not $text) { $text = $obj.output_text }
    }

    if (-not $text -and $obj.output_text) {
        $text = $obj.output_text
    }

    if (-not $text -and $obj.response -and $obj.response.output_text) {
        $text = $obj.response.output_text
    }

    if ($text) {
        $candidates.Add([string]$text)
    }
}

if ($candidates.Count -eq 0) {
    exit 1
}

[Console]::Out.Write($candidates[$candidates.Count - 1])
POWERSHELL
)
    text=$(powershell.exe -NoProfile -NonInteractive -Command "$ps_script" -- "$ndjson_file" 2>/dev/null)

    if [[ -n "$text" ]]; then
        printf '%s' "$text"
        return 0
    fi

    return 1
}

# Extract the final assistant text from Codex NDJSON output.
# Handles both older top-level message/result records and newer
# item.completed -> item.type=agent_message records.
# Arguments:
#   $1 (ndjson_file) - Path to Codex NDJSON output
# Returns: extracted text on stdout, 0 if non-empty text found, 1 otherwise
extract_codex_text_from_ndjson() {
    local ndjson_file="$1"

    if [[ ! -f "$ndjson_file" || ! -s "$ndjson_file" ]]; then
        return 1
    fi

    local text=""

    if command -v jq &>/dev/null; then
        text=$(jq -rs '
            def flatten_text:
                if . == null then empty
                elif type == "string" then .
                elif type == "array" then [ .[]? | flatten_text ] | map(select(length > 0)) | join("\n")
                elif type == "object" then (.text? // .content? // .message? // .result? // .output_text? // empty) | flatten_text
                else empty
                end;

            def candidate_texts:
                [
                    (.item? | select(.type == "agent_message" or .type == "assistant_message" or .type == "message") | flatten_text),
                    (select(.type == "message" or .type == "assistant" or .type == "result") | flatten_text),
                    (.output_text? | flatten_text),
                    (.response?.output_text? | flatten_text)
                ]
                | map(select(type == "string" and length > 0));

            [ .[] | candidate_texts[] ]
            | last // empty
        ' "$ndjson_file" 2>/dev/null)

        if codex_text_is_metadata_blob "$text"; then
            text=""
        fi
    fi

    if [[ -z "$text" ]]; then
        text=$(extract_codex_text_with_powershell "$ndjson_file" 2>/dev/null || echo "")
        if codex_text_is_metadata_blob "$text"; then
            text=""
        fi
    fi

    if [[ -z "$text" ]]; then
        local result_line=""
        result_line=$(grep -a '"type":"result"' "$ndjson_file" 2>/dev/null | tail -1)
        if [[ -n "$result_line" && "$result_line" == *'"result":"'* ]]; then
            text=$(printf '%s\n' "$result_line" | sed -n 's/.*"result":"\(.*\)","stop_reason".*/\1/p')
            text=$(printf '%b' "$(printf '%s' "$text" | sed 's/\\"/"/g; s/\\\\/\x5c/g; s/\\r//g; s/\\n/\\n/g; s/\\t/\\t/g')")
        fi

        if codex_text_is_metadata_blob "$text"; then
            text=""
        fi
    fi

    if [[ -z "$text" ]]; then
        local agent_line=""
        agent_line=$(grep -a '"type":"agent_message"' "$ndjson_file" 2>/dev/null | tail -1)
        if [[ -n "$agent_line" ]]; then
            text=$(printf '%s\n' "$agent_line" | sed -E 's/^.*"text":"(.*)".*$/\1/')
            text=$(printf '%b' "$(printf '%s' "$text" | sed 's/\\"/"/g; s/\\\\/\x5c/g; s/\\r//g; s/\\n/\\n/g; s/\\t/\\t/g')")
        fi

        if codex_text_is_metadata_blob "$text"; then
            text=""
        fi
    fi

    if [[ -z "$text" ]]; then
        text=$(grep -a -v '^\s*$' "$ndjson_file" 2>/dev/null | grep -a -v '^Reading prompt from stdin\.\.\.$' | grep -a -v '"type":"turn.completed"' | tail -1)
    fi

    if codex_text_is_metadata_blob "$text"; then
        text=""
    fi

    if [[ -n "$text" ]]; then
        printf '%s\n' "$text"
        return 0
    fi

    return 1
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
        proposal_text=$(extract_codex_text_from_ndjson "$ndjson_file" 2>/dev/null || echo "")
        output_length=${#proposal_text}
    fi

    # Secondary: check last_message_file if it exists
    if [[ -z "$proposal_text" && -n "$last_message_file" && -f "$last_message_file" && -s "$last_message_file" ]]; then
        proposal_text=$(cat "$last_message_file")
        output_length=${#proposal_text}
    fi

    if codex_text_is_metadata_blob "$proposal_text"; then
        proposal_text=""
        output_length=0
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
        text=$(extract_codex_text_from_ndjson "$ndjson_file" 2>/dev/null || echo "")
        if [[ -n "$text" ]] && ! codex_text_is_metadata_blob "$text"; then
            echo "$text"
            return 0
        fi
    fi

    # Secondary: check last_message_file if it exists
    if [[ -n "$last_message_file" && -f "$last_message_file" && -s "$last_message_file" ]]; then
        local text=""
        text=$(cat "$last_message_file")
        if [[ -n "$text" ]] && ! codex_text_is_metadata_blob "$text"; then
            printf '%s\n' "$text"
            return 0
        fi
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
        3)
            echo "broken_install"
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
        broken_install)
            reason_text="Codex CLI is installed but broken (reinstall with: npm install -g @openai/codex@latest)"
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
export -f resolve_codex_cli
export -f check_codex_runtime
export -f get_codex_error_help
export -f run_codex_login
export -f build_codex_command
export -f run_codex_with_prompt
export -f codex_text_is_metadata_blob
export -f extract_codex_text_with_powershell
export -f extract_codex_text_from_ndjson
export -f parse_codex_response
export -f extract_codex_proposal
export -f should_fallback_to_claude
export -f display_fallback_warning
