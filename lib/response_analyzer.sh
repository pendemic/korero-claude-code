#!/bin/bash
# Response Analyzer Component for Korero
# Analyzes Claude Code output to detect completion signals, test-only loops, and progress

# Source date utilities for cross-platform compatibility
source "$(dirname "${BASH_SOURCE[0]}")/date_utils.sh"

# Response Analysis Functions
# Based on expert recommendations from Martin Fowler, Michael Nygard, Sam Newman

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Use KORERO_DIR if set by main script, otherwise default to .korero
KORERO_DIR="${KORERO_DIR:-.korero}"

# Analysis configuration
COMPLETION_KEYWORDS=("done" "complete" "finished" "all tasks complete" "project complete" "ready for review")
TEST_ONLY_PATTERNS=("npm test" "bats" "pytest" "jest" "cargo test" "go test" "running tests")
NO_WORK_PATTERNS=("nothing to do" "no changes" "already implemented" "up to date")

# =============================================================================
# JSON OUTPUT FORMAT DETECTION AND PARSING
# =============================================================================

# Detect output format (json or text)
# Returns: "json" if valid JSON, "text" otherwise
detect_output_format() {
    local output_file=$1

    if [[ ! -f "$output_file" ]] || [[ ! -s "$output_file" ]]; then
        echo "text"
        return
    fi

    # Check if file starts with { or [ (JSON indicators)
    local first_char=$(head -c 1 "$output_file" 2>/dev/null | tr -d '[:space:]')

    if [[ "$first_char" != "{" && "$first_char" != "[" ]]; then
        echo "text"
        return
    fi

    # Validate as JSON using jq
    if jq empty "$output_file" 2>/dev/null; then
        echo "json"
    else
        echo "text"
    fi
}

# Parse JSON response and extract structured fields
# Creates .korero/.json_parse_result with normalized analysis data
# Supports THREE JSON formats:
# 1. Flat format: { status, exit_signal, work_type, files_modified, ... }
# 2. Claude CLI object format: { result, sessionId, metadata: { files_changed, has_errors, completion_status, ... } }
# 3. Claude CLI array format: [ {type: "system", ...}, {type: "assistant", ...}, {type: "result", ...} ]
parse_json_response() {
    local output_file=$1
    local result_file="${2:-$KORERO_DIR/.json_parse_result}"
    local normalized_file=""

    if [[ ! -f "$output_file" ]]; then
        echo "ERROR: Output file not found: $output_file" >&2
        return 1
    fi

    # Validate JSON first
    if ! jq empty "$output_file" 2>/dev/null; then
        echo "ERROR: Invalid JSON in output file" >&2
        return 1
    fi

    # Check if JSON is an array (Claude CLI array format)
    # Claude CLI outputs: [{type: "system", ...}, {type: "assistant", ...}, {type: "result", ...}]
    if jq -e 'type == "array"' "$output_file" >/dev/null 2>&1; then
        normalized_file=$(mktemp)

        # Extract the "result" type message from the array (usually the last entry)
        # This contains: result, session_id, is_error, duration_ms, etc.
        local result_obj=$(jq '[.[] | select(.type == "result")] | .[-1] // {}' "$output_file" 2>/dev/null)

        # Guard against empty result_obj if jq fails (review fix: Macroscope)
        [[ -z "$result_obj" ]] && result_obj="{}"

        # Extract session_id from init message as fallback
        local init_session_id=$(jq -r '.[] | select(.type == "system" and .subtype == "init") | .session_id // empty' "$output_file" 2>/dev/null | head -1)

        # Prioritize result object's own session_id, then fall back to init message (review fix: CodeRabbit)
        # This prevents session ID loss when arrays lack an init message with session_id
        local effective_session_id
        effective_session_id=$(echo "$result_obj" | jq -r '.sessionId // .session_id // empty' 2>/dev/null)
        if [[ -z "$effective_session_id" || "$effective_session_id" == "null" ]]; then
            effective_session_id="$init_session_id"
        fi

        # Build normalized object merging result with effective session_id
        if [[ -n "$effective_session_id" && "$effective_session_id" != "null" ]]; then
            echo "$result_obj" | jq --arg sid "$effective_session_id" '. + {sessionId: $sid} | del(.session_id)' > "$normalized_file"
        else
            echo "$result_obj" | jq 'del(.session_id)' > "$normalized_file"
        fi

        # Use normalized file for subsequent parsing
        output_file="$normalized_file"
    fi

    # Detect JSON format by checking for Claude CLI fields
    local has_result_field=$(jq -r 'has("result")' "$output_file" 2>/dev/null)

    # Extract fields - support both flat format and Claude CLI format
    # Priority: Claude CLI fields first, then flat format fields

    # Status: from flat format OR derived from metadata.completion_status
    local status=$(jq -r '.status // "UNKNOWN"' "$output_file" 2>/dev/null)
    local completion_status=$(jq -r '.metadata.completion_status // ""' "$output_file" 2>/dev/null)
    if [[ "$completion_status" == "complete" || "$completion_status" == "COMPLETE" ]]; then
        status="COMPLETE"
    fi

    # Exit signal: from flat format OR derived from completion_status
    # Track whether EXIT_SIGNAL was explicitly provided (vs inferred from STATUS)
    local exit_signal=$(jq -r '.exit_signal // false' "$output_file" 2>/dev/null)
    local explicit_exit_signal_found=$(jq -r 'has("exit_signal")' "$output_file" 2>/dev/null)

    # Bug #1 Fix: If exit_signal is still false, check for KORERO_STATUS block in .result field
    # Claude CLI JSON format embeds the KORERO_STATUS block within the .result text field
    if [[ "$exit_signal" == "false" && "$has_result_field" == "true" ]]; then
        local result_text=$(jq -r '.result // ""' "$output_file" 2>/dev/null)
        if [[ -n "$result_text" ]] && echo "$result_text" | grep -q -- "---KORERO_STATUS---"; then
            # Extract EXIT_SIGNAL value from KORERO_STATUS block within result text
            local embedded_exit_sig
            embedded_exit_sig=$(echo "$result_text" | grep "EXIT_SIGNAL:" | cut -d: -f2 | xargs)
            if [[ -n "$embedded_exit_sig" ]]; then
                # Explicit EXIT_SIGNAL found in KORERO_STATUS block
                explicit_exit_signal_found="true"
                if [[ "$embedded_exit_sig" == "true" ]]; then
                    exit_signal="true"
                    [[ "${VERBOSE_PROGRESS:-}" == "true" ]] && echo "DEBUG: Extracted EXIT_SIGNAL=true from .result KORERO_STATUS block" >&2
                else
                    exit_signal="false"
                    [[ "${VERBOSE_PROGRESS:-}" == "true" ]] && echo "DEBUG: Extracted EXIT_SIGNAL=false from .result KORERO_STATUS block (respecting explicit intent)" >&2
                fi
            fi
            # Also check STATUS field as fallback ONLY when EXIT_SIGNAL was not specified
            # This respects explicit EXIT_SIGNAL: false which means "task complete, continue working"
            local embedded_status
            embedded_status=$(echo "$result_text" | grep "STATUS:" | cut -d: -f2 | xargs)
            if [[ "$embedded_status" == "COMPLETE" && "$explicit_exit_signal_found" != "true" ]]; then
                # STATUS: COMPLETE without any EXIT_SIGNAL field implies completion
                exit_signal="true"
                [[ "${VERBOSE_PROGRESS:-}" == "true" ]] && echo "DEBUG: Inferred EXIT_SIGNAL=true from .result STATUS=COMPLETE (no explicit EXIT_SIGNAL found)" >&2
            fi
        fi
    fi

    # Work type: from flat format
    local work_type=$(jq -r '.work_type // "UNKNOWN"' "$output_file" 2>/dev/null)

    # Files modified: from flat format OR from metadata.files_changed
    local files_modified=$(jq -r '.metadata.files_changed // .files_modified // 0' "$output_file" 2>/dev/null)

    # Error count: from flat format OR derived from metadata.has_errors
    # Note: When only has_errors=true is present (without explicit error_count),
    # we set error_count=1 as a minimum. This is defensive programming since
    # the stuck detection threshold is >5 errors, so 1 error won't trigger it.
    # Actual error count may be higher, but precise count isn't critical for our logic.
    local error_count=$(jq -r '.error_count // 0' "$output_file" 2>/dev/null)
    local has_errors=$(jq -r '.metadata.has_errors // false' "$output_file" 2>/dev/null)
    if [[ "$has_errors" == "true" && "$error_count" == "0" ]]; then
        error_count=1  # At least one error if has_errors is true
    fi

    # Summary: from flat format OR from result field (Claude CLI format)
    local summary=$(jq -r '.result // .summary // ""' "$output_file" 2>/dev/null)

    # Session ID: from Claude CLI format (sessionId) OR from metadata.session_id
    local session_id=$(jq -r '.sessionId // .metadata.session_id // ""' "$output_file" 2>/dev/null)

    # Loop number: from metadata
    local loop_number=$(jq -r '.metadata.loop_number // .loop_number // 0' "$output_file" 2>/dev/null)

    # Confidence: from flat format
    local confidence=$(jq -r '.confidence // 0' "$output_file" 2>/dev/null)

    # Progress indicators: from Claude CLI metadata (optional)
    local progress_count=$(jq -r '.metadata.progress_indicators | if . then length else 0 end' "$output_file" 2>/dev/null)

    # Permission denials: from Claude Code output (Issue #101)
    # When Claude Code is denied permission to run commands, it outputs a permission_denials array
    local permission_denial_count=$(jq -r '.permission_denials | if . then length else 0 end' "$output_file" 2>/dev/null)
    permission_denial_count=$((permission_denial_count + 0))  # Ensure integer

    local has_permission_denials="false"
    if [[ $permission_denial_count -gt 0 ]]; then
        has_permission_denials="true"
    fi

    # Extract denied commands for logging/display
    # Note: Commands are nested under tool_input.command in the permission_denials array
    local denied_commands_json="[]"
    if [[ $permission_denial_count -gt 0 ]]; then
        denied_commands_json=$(jq -r '[.permission_denials[].tool_input.command // empty]' "$output_file" 2>/dev/null || echo "[]")
    fi

    # Normalize values
    # Convert exit_signal to boolean string
    # Only infer from status/completion_status if no explicit EXIT_SIGNAL was provided
    if [[ "$explicit_exit_signal_found" == "true" ]]; then
        # Respect explicit EXIT_SIGNAL value (already set above)
        [[ "$exit_signal" == "true" ]] && exit_signal="true" || exit_signal="false"
    elif [[ "$exit_signal" == "true" || "$status" == "COMPLETE" || "$completion_status" == "complete" || "$completion_status" == "COMPLETE" ]]; then
        exit_signal="true"
    else
        exit_signal="false"
    fi

    # Determine is_test_only from work_type
    local is_test_only="false"
    if [[ "$work_type" == "TEST_ONLY" ]]; then
        is_test_only="true"
    fi

    # Determine is_stuck from error_count (threshold >5)
    local is_stuck="false"
    error_count=$((error_count + 0))  # Ensure integer
    if [[ $error_count -gt 5 ]]; then
        is_stuck="true"
    fi

    # Ensure files_modified is integer
    files_modified=$((files_modified + 0))

    # Ensure progress_count is integer
    progress_count=$((progress_count + 0))

    # Calculate has_completion_signal
    local has_completion_signal="false"
    if [[ "$status" == "COMPLETE" || "$exit_signal" == "true" ]]; then
        has_completion_signal="true"
    fi

    # Boost confidence based on structured data availability
    if [[ "$has_result_field" == "true" ]]; then
        confidence=$((confidence + 20))  # Structured response boost
    fi
    if [[ $progress_count -gt 0 ]]; then
        confidence=$((confidence + progress_count * 5))  # Progress indicators boost
    fi

    # Write normalized result using jq for safe JSON construction
    # String fields use --arg (auto-escapes), numeric/boolean use --argjson
    jq -n \
        --arg status "$status" \
        --argjson exit_signal "$exit_signal" \
        --argjson is_test_only "$is_test_only" \
        --argjson is_stuck "$is_stuck" \
        --argjson has_completion_signal "$has_completion_signal" \
        --argjson files_modified "$files_modified" \
        --argjson error_count "$error_count" \
        --arg summary "$summary" \
        --argjson loop_number "$loop_number" \
        --arg session_id "$session_id" \
        --argjson confidence "$confidence" \
        --argjson has_permission_denials "$has_permission_denials" \
        --argjson permission_denial_count "$permission_denial_count" \
        --argjson denied_commands "$denied_commands_json" \
        '{
            status: $status,
            exit_signal: $exit_signal,
            is_test_only: $is_test_only,
            is_stuck: $is_stuck,
            has_completion_signal: $has_completion_signal,
            files_modified: $files_modified,
            error_count: $error_count,
            summary: $summary,
            loop_number: $loop_number,
            session_id: $session_id,
            confidence: $confidence,
            has_permission_denials: $has_permission_denials,
            permission_denial_count: $permission_denial_count,
            denied_commands: $denied_commands,
            metadata: {
                loop_number: $loop_number,
                session_id: $session_id
            }
        }' > "$result_file"

    # Cleanup temporary normalized file if created (for array format handling)
    if [[ -n "$normalized_file" && -f "$normalized_file" ]]; then
        rm -f "$normalized_file"
    fi

    return 0
}

# Analyze Claude Code response and extract signals
analyze_response() {
    local output_file=$1
    local loop_number=$2
    local analysis_result_file=${3:-"$KORERO_DIR/.response_analysis"}

    # Initialize analysis result
    local has_completion_signal=false
    local is_test_only=false
    local is_stuck=false
    local has_progress=false
    local confidence_score=0
    local exit_signal=false
    local work_summary=""
    local files_modified=0

    # Read output file
    if [[ ! -f "$output_file" ]]; then
        echo "ERROR: Output file not found: $output_file"
        return 1
    fi

    local output_content=$(cat "$output_file")
    local output_length=${#output_content}

    # Detect output format and try JSON parsing first
    local output_format=$(detect_output_format "$output_file")

    if [[ "$output_format" == "json" ]]; then
        # Try JSON parsing
        if parse_json_response "$output_file" "$KORERO_DIR/.json_parse_result" 2>/dev/null; then
            # Extract values from JSON parse result
            has_completion_signal=$(jq -r '.has_completion_signal' $KORERO_DIR/.json_parse_result 2>/dev/null || echo "false")
            exit_signal=$(jq -r '.exit_signal' $KORERO_DIR/.json_parse_result 2>/dev/null || echo "false")
            is_test_only=$(jq -r '.is_test_only' $KORERO_DIR/.json_parse_result 2>/dev/null || echo "false")
            is_stuck=$(jq -r '.is_stuck' $KORERO_DIR/.json_parse_result 2>/dev/null || echo "false")
            work_summary=$(jq -r '.summary' $KORERO_DIR/.json_parse_result 2>/dev/null || echo "")
            files_modified=$(jq -r '.files_modified' $KORERO_DIR/.json_parse_result 2>/dev/null || echo "0")
            local json_confidence=$(jq -r '.confidence' $KORERO_DIR/.json_parse_result 2>/dev/null || echo "0")
            local session_id=$(jq -r '.session_id' $KORERO_DIR/.json_parse_result 2>/dev/null || echo "")

            # Extract permission denial fields (Issue #101)
            local has_permission_denials=$(jq -r '.has_permission_denials' $KORERO_DIR/.json_parse_result 2>/dev/null || echo "false")
            local permission_denial_count=$(jq -r '.permission_denial_count' $KORERO_DIR/.json_parse_result 2>/dev/null || echo "0")
            local denied_commands_json=$(jq -r '.denied_commands' $KORERO_DIR/.json_parse_result 2>/dev/null || echo "[]")

            # Persist session ID if present (for session continuity across loop iterations)
            if [[ -n "$session_id" && "$session_id" != "null" ]]; then
                store_session_id "$session_id"
                [[ "${VERBOSE_PROGRESS:-}" == "true" ]] && echo "DEBUG: Persisted session ID: $session_id" >&2
            fi

            # JSON parsing provides high confidence
            if [[ "$exit_signal" == "true" ]]; then
                confidence_score=100
            else
                confidence_score=$((json_confidence + 50))
            fi

            # Check for file changes via git (supplements JSON data)
            # Fix #141: Detect both uncommitted changes AND committed changes
            if command -v git &>/dev/null && git rev-parse --git-dir >/dev/null 2>&1; then
                local git_files=0
                local loop_start_sha=""
                local current_sha=""

                if [[ -f "$KORERO_DIR/.loop_start_sha" ]]; then
                    loop_start_sha=$(cat "$KORERO_DIR/.loop_start_sha" 2>/dev/null || echo "")
                fi
                current_sha=$(git rev-parse HEAD 2>/dev/null || echo "")

                # Check if commits were made (HEAD changed)
                if [[ -n "$loop_start_sha" && -n "$current_sha" && "$loop_start_sha" != "$current_sha" ]]; then
                    # Commits were made - count union of committed files AND working tree changes
                    git_files=$(
                        {
                            git diff --name-only "$loop_start_sha" "$current_sha" 2>/dev/null
                            git diff --name-only HEAD 2>/dev/null           # unstaged changes
                            git diff --name-only --cached 2>/dev/null       # staged changes
                        } | sort -u | wc -l
                    )
                else
                    # No commits - check for uncommitted changes (staged + unstaged)
                    git_files=$(
                        {
                            git diff --name-only 2>/dev/null                # unstaged changes
                            git diff --name-only --cached 2>/dev/null       # staged changes
                        } | sort -u | wc -l
                    )
                fi

                if [[ $git_files -gt 0 ]]; then
                    has_progress=true
                    files_modified=$git_files
                fi
            fi

            # Write analysis results for JSON path using jq for safe construction
            jq -n \
                --argjson loop_number "$loop_number" \
                --arg timestamp "$(get_iso_timestamp)" \
                --arg output_file "$output_file" \
                --arg output_format "json" \
                --argjson has_completion_signal "$has_completion_signal" \
                --argjson is_test_only "$is_test_only" \
                --argjson is_stuck "$is_stuck" \
                --argjson has_progress "$has_progress" \
                --argjson files_modified "$files_modified" \
                --argjson confidence_score "$confidence_score" \
                --argjson exit_signal "$exit_signal" \
                --arg work_summary "$work_summary" \
                --argjson output_length "$output_length" \
                --argjson has_permission_denials "$has_permission_denials" \
                --argjson permission_denial_count "$permission_denial_count" \
                --argjson denied_commands "$denied_commands_json" \
                '{
                    loop_number: $loop_number,
                    timestamp: $timestamp,
                    output_file: $output_file,
                    output_format: $output_format,
                    analysis: {
                        has_completion_signal: $has_completion_signal,
                        is_test_only: $is_test_only,
                        is_stuck: $is_stuck,
                        has_progress: $has_progress,
                        files_modified: $files_modified,
                        confidence_score: $confidence_score,
                        exit_signal: $exit_signal,
                        work_summary: $work_summary,
                        output_length: $output_length,
                        has_permission_denials: $has_permission_denials,
                        permission_denial_count: $permission_denial_count,
                        denied_commands: $denied_commands
                    }
                }' > "$analysis_result_file"
            rm -f "$KORERO_DIR/.json_parse_result"
            return 0
        fi
        # If JSON parsing failed, fall through to text parsing
    fi

    # Text parsing fallback (original logic)

    # Track whether an explicit EXIT_SIGNAL was found in KORERO_STATUS block
    # If explicit signal found, heuristics should NOT override Claude's intent
    local explicit_exit_signal_found=false

    # 1. Check for explicit structured output (if Claude follows schema)
    if grep -q -- "---KORERO_STATUS---" "$output_file"; then
        # Parse structured output
        local status=$(grep "STATUS:" "$output_file" | cut -d: -f2 | xargs)
        local exit_sig=$(grep "EXIT_SIGNAL:" "$output_file" | cut -d: -f2 | xargs)

        # If EXIT_SIGNAL is explicitly provided, respect it
        if [[ -n "$exit_sig" ]]; then
            explicit_exit_signal_found=true
            if [[ "$exit_sig" == "true" ]]; then
                has_completion_signal=true
                exit_signal=true
                confidence_score=100
            else
                # Explicit EXIT_SIGNAL: false - Claude says to continue
                exit_signal=false
            fi
        elif [[ "$status" == "COMPLETE" ]]; then
            # No explicit EXIT_SIGNAL but STATUS is COMPLETE
            has_completion_signal=true
            exit_signal=true
            confidence_score=100
        fi
    fi

    # 2. Detect completion keywords in natural language output
    for keyword in "${COMPLETION_KEYWORDS[@]}"; do
        if grep -qi "$keyword" "$output_file"; then
            has_completion_signal=true
            ((confidence_score+=10))
            break
        fi
    done

    # 3. Detect test-only loops
    local test_command_count=0
    local implementation_count=0
    local error_count=0

    test_command_count=$(grep -c -i "running tests\|npm test\|bats\|pytest\|jest" "$output_file" 2>/dev/null | head -1 || echo "0")
    implementation_count=$(grep -c -i "implementing\|creating\|writing\|adding\|function\|class" "$output_file" 2>/dev/null | head -1 || echo "0")

    # Strip whitespace and ensure it's a number
    test_command_count=$(echo "$test_command_count" | tr -d '[:space:]')
    implementation_count=$(echo "$implementation_count" | tr -d '[:space:]')

    # Convert to integers with default fallback
    test_command_count=${test_command_count:-0}
    implementation_count=${implementation_count:-0}
    test_command_count=$((test_command_count + 0))
    implementation_count=$((implementation_count + 0))

    if [[ $test_command_count -gt 0 ]] && [[ $implementation_count -eq 0 ]]; then
        is_test_only=true
        work_summary="Test execution only, no implementation"
    fi

    # 4. Detect stuck/error loops
    # Use two-stage filtering to avoid counting JSON field names as errors
    # Stage 1: Filter out JSON field patterns like "is_error": false
    # Stage 2: Count actual error messages in specific contexts
    # Pattern aligned with korero_loop.sh to ensure consistent behavior
    error_count=$(grep -v '"[^"]*error[^"]*":' "$output_file" 2>/dev/null | \
                  grep -cE '(^Error:|^ERROR:|^error:|\]: error|Link: error|Error occurred|failed with error|[Ee]xception|Fatal|FATAL)' \
                  2>/dev/null || echo "0")
    error_count=$(echo "$error_count" | tr -d '[:space:]')
    error_count=${error_count:-0}
    error_count=$((error_count + 0))

    if [[ $error_count -gt 5 ]]; then
        is_stuck=true
    fi

    # 5. Detect "nothing to do" patterns
    for pattern in "${NO_WORK_PATTERNS[@]}"; do
        if grep -qi "$pattern" "$output_file"; then
            has_completion_signal=true
            ((confidence_score+=15))
            work_summary="No work remaining"
            break
        fi
    done

    # 6. Check for file changes (git integration)
    # Fix #141: Detect both uncommitted changes AND committed changes
    if command -v git &>/dev/null && git rev-parse --git-dir >/dev/null 2>&1; then
        local loop_start_sha=""
        local current_sha=""

        if [[ -f "$KORERO_DIR/.loop_start_sha" ]]; then
            loop_start_sha=$(cat "$KORERO_DIR/.loop_start_sha" 2>/dev/null || echo "")
        fi
        current_sha=$(git rev-parse HEAD 2>/dev/null || echo "")

        # Check if commits were made (HEAD changed)
        if [[ -n "$loop_start_sha" && -n "$current_sha" && "$loop_start_sha" != "$current_sha" ]]; then
            # Commits were made - count union of committed files AND working tree changes
            files_modified=$(
                {
                    git diff --name-only "$loop_start_sha" "$current_sha" 2>/dev/null
                    git diff --name-only HEAD 2>/dev/null           # unstaged changes
                    git diff --name-only --cached 2>/dev/null       # staged changes
                } | sort -u | wc -l
            )
        else
            # No commits - check for uncommitted changes (staged + unstaged)
            files_modified=$(
                {
                    git diff --name-only 2>/dev/null                # unstaged changes
                    git diff --name-only --cached 2>/dev/null       # staged changes
                } | sort -u | wc -l
            )
        fi

        if [[ $files_modified -gt 0 ]]; then
            has_progress=true
            ((confidence_score+=20))
        fi
    fi

    # 7. Analyze output length trends (detect declining engagement)
    if [[ -f "$KORERO_DIR/.last_output_length" ]]; then
        local last_length=$(cat "$KORERO_DIR/.last_output_length")
        local length_ratio=$((output_length * 100 / last_length))

        if [[ $length_ratio -lt 50 ]]; then
            # Output is less than 50% of previous - possible completion
            ((confidence_score+=10))
        fi
    fi
    echo "$output_length" > "$KORERO_DIR/.last_output_length"

    # 8. Extract work summary from output
    if [[ -z "$work_summary" ]]; then
        # Try to find summary in output
        work_summary=$(grep -i "summary\|completed\|implemented" "$output_file" | head -1 | cut -c 1-100)
        if [[ -z "$work_summary" ]]; then
            work_summary="Output analyzed, no explicit summary found"
        fi
    fi

    # 9. Determine exit signal based on confidence (heuristic)
    # IMPORTANT: Only apply heuristics if no explicit EXIT_SIGNAL was found in KORERO_STATUS
    # Claude's explicit intent takes precedence over natural language pattern matching
    if [[ "$explicit_exit_signal_found" != "true" ]]; then
        if [[ $confidence_score -ge 40 || "$has_completion_signal" == "true" ]]; then
            exit_signal=true
        fi
    fi

    # Write analysis results to file (text parsing path) using jq for safe construction
    # Note: Permission denial fields default to false/0 since text output doesn't include this data
    jq -n \
        --argjson loop_number "$loop_number" \
        --arg timestamp "$(get_iso_timestamp)" \
        --arg output_file "$output_file" \
        --arg output_format "text" \
        --argjson has_completion_signal "$has_completion_signal" \
        --argjson is_test_only "$is_test_only" \
        --argjson is_stuck "$is_stuck" \
        --argjson has_progress "$has_progress" \
        --argjson files_modified "$files_modified" \
        --argjson confidence_score "$confidence_score" \
        --argjson exit_signal "$exit_signal" \
        --arg work_summary "$work_summary" \
        --argjson output_length "$output_length" \
        '{
            loop_number: $loop_number,
            timestamp: $timestamp,
            output_file: $output_file,
            output_format: $output_format,
            analysis: {
                has_completion_signal: $has_completion_signal,
                is_test_only: $is_test_only,
                is_stuck: $is_stuck,
                has_progress: $has_progress,
                files_modified: $files_modified,
                confidence_score: $confidence_score,
                exit_signal: $exit_signal,
                work_summary: $work_summary,
                output_length: $output_length,
                has_permission_denials: false,
                permission_denial_count: 0,
                denied_commands: []
            }
        }' > "$analysis_result_file"

    # Always return 0 (success) - callers should check the JSON result file
    # Returning non-zero would cause issues with set -e and test frameworks
    return 0
}

# Update exit signals file based on analysis
update_exit_signals() {
    local analysis_file=${1:-"$KORERO_DIR/.response_analysis"}
    local exit_signals_file=${2:-"$KORERO_DIR/.exit_signals"}

    if [[ ! -f "$analysis_file" ]]; then
        echo "ERROR: Analysis file not found: $analysis_file"
        return 1
    fi

    # Read analysis results
    local is_test_only=$(jq -r '.analysis.is_test_only' "$analysis_file")
    local has_completion_signal=$(jq -r '.analysis.has_completion_signal' "$analysis_file")
    local loop_number=$(jq -r '.loop_number' "$analysis_file")
    local has_progress=$(jq -r '.analysis.has_progress' "$analysis_file")

    # Read current exit signals
    local signals=$(cat "$exit_signals_file" 2>/dev/null || echo '{"test_only_loops": [], "done_signals": [], "completion_indicators": []}')

    # Update test_only_loops array
    if [[ "$is_test_only" == "true" ]]; then
        signals=$(echo "$signals" | jq ".test_only_loops += [$loop_number]")
    else
        # Clear test_only_loops if we had implementation
        if [[ "$has_progress" == "true" ]]; then
            signals=$(echo "$signals" | jq '.test_only_loops = []')
        fi
    fi

    # Update done_signals array
    if [[ "$has_completion_signal" == "true" ]]; then
        signals=$(echo "$signals" | jq ".done_signals += [$loop_number]")
    fi

    # Update completion_indicators array (only when Claude explicitly signals exit)
    # Note: Previously used confidence >= 60, but JSON mode always has confidence >= 70
    # due to deterministic scoring (+50 for JSON format, +20 for result field).
    # This caused premature exits after 5 loops. Now we respect Claude's explicit intent.
    local exit_signal=$(jq -r '.analysis.exit_signal // false' "$analysis_file")
    if [[ "$exit_signal" == "true" ]]; then
        signals=$(echo "$signals" | jq ".completion_indicators += [$loop_number]")
    fi

    # Keep only last 5 signals (rolling window)
    signals=$(echo "$signals" | jq '.test_only_loops = .test_only_loops[-5:]')
    signals=$(echo "$signals" | jq '.done_signals = .done_signals[-5:]')
    signals=$(echo "$signals" | jq '.completion_indicators = .completion_indicators[-5:]')

    # Write updated signals
    echo "$signals" > "$exit_signals_file"

    return 0
}

# Log analysis results in human-readable format
log_analysis_summary() {
    local analysis_file=${1:-"$KORERO_DIR/.response_analysis"}

    if [[ ! -f "$analysis_file" ]]; then
        return 1
    fi

    local loop=$(jq -r '.loop_number' "$analysis_file")
    local exit_sig=$(jq -r '.analysis.exit_signal' "$analysis_file")
    local confidence=$(jq -r '.analysis.confidence_score' "$analysis_file")
    local test_only=$(jq -r '.analysis.is_test_only' "$analysis_file")
    local files_changed=$(jq -r '.analysis.files_modified' "$analysis_file")
    local summary=$(jq -r '.analysis.work_summary' "$analysis_file")

    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           Response Analysis - Loop #$loop                 ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}Exit Signal:${NC}      $exit_sig"
    echo -e "${YELLOW}Confidence:${NC}       $confidence%"
    echo -e "${YELLOW}Test Only:${NC}        $test_only"
    echo -e "${YELLOW}Files Changed:${NC}    $files_changed"
    echo -e "${YELLOW}Summary:${NC}          $summary"
    echo ""
}

# Detect if Claude is stuck (repeating same errors)
detect_stuck_loop() {
    local current_output=$1
    local history_dir=${2:-"$KORERO_DIR/logs"}

    # Get last 3 output files
    local recent_outputs=$(ls -t "$history_dir"/claude_output_*.log 2>/dev/null | head -3)

    if [[ -z "$recent_outputs" ]]; then
        return 1  # Not enough history
    fi

    # Extract key errors from current output using two-stage filtering
    # Stage 1: Filter out JSON field patterns to avoid false positives
    # Stage 2: Extract actual error messages
    local current_errors=$(grep -v '"[^"]*error[^"]*":' "$current_output" 2>/dev/null | \
                          grep -E '(^Error:|^ERROR:|^error:|\]: error|Link: error|Error occurred|failed with error|[Ee]xception|Fatal|FATAL)' 2>/dev/null | \
                          sort | uniq)

    if [[ -z "$current_errors" ]]; then
        return 1  # No errors
    fi

    # Check if same errors appear in all recent outputs
    # For multi-line errors, verify ALL error lines appear in ALL history files
    local all_files_match=true
    while IFS= read -r output_file; do
        local file_matches_all=true
        while IFS= read -r error_line; do
            # Use -F for literal fixed-string matching (not regex)
            if ! grep -qF "$error_line" "$output_file" 2>/dev/null; then
                file_matches_all=false
                break
            fi
        done <<< "$current_errors"

        if [[ "$file_matches_all" != "true" ]]; then
            all_files_match=false
            break
        fi
    done <<< "$recent_outputs"

    if [[ "$all_files_match" == "true" ]]; then
        return 0  # Stuck on same error(s)
    else
        return 1  # Making progress or different errors
    fi
}

# =============================================================================
# SESSION MANAGEMENT FUNCTIONS
# =============================================================================

# Session file location - standardized across korero_loop.sh and response_analyzer.sh
SESSION_FILE="$KORERO_DIR/.claude_session_id"
# Session expiration time in seconds (24 hours)
SESSION_EXPIRATION_SECONDS=86400

# Store session ID to file with timestamp
# Usage: store_session_id "session-uuid-123"
store_session_id() {
    local session_id=$1

    if [[ -z "$session_id" ]]; then
        return 1
    fi

    # Write session with timestamp using jq for safe JSON construction
    jq -n \
        --arg session_id "$session_id" \
        --arg timestamp "$(get_iso_timestamp)" \
        '{
            session_id: $session_id,
            timestamp: $timestamp
        }' > "$SESSION_FILE"

    return 0
}

# Get the last stored session ID
# Returns: session ID string or empty if not found
get_last_session_id() {
    if [[ ! -f "$SESSION_FILE" ]]; then
        echo ""
        return 0
    fi

    # Extract session_id from JSON file
    local session_id=$(jq -r '.session_id // ""' "$SESSION_FILE" 2>/dev/null)
    echo "$session_id"
    return 0
}

# Check if the stored session should be resumed
# Returns: 0 (true) if session is valid and recent, 1 (false) otherwise
should_resume_session() {
    if [[ ! -f "$SESSION_FILE" ]]; then
        echo "false"
        return 1
    fi

    # Get session timestamp
    local timestamp=$(jq -r '.timestamp // ""' "$SESSION_FILE" 2>/dev/null)

    if [[ -z "$timestamp" ]]; then
        echo "false"
        return 1
    fi

    # Calculate session age using date utilities
    local now=$(get_epoch_seconds)
    local session_time

    # Parse ISO timestamp to epoch - try multiple formats for cross-platform compatibility
    # Strip milliseconds if present (e.g., 2026-01-09T10:30:00.123+00:00 → 2026-01-09T10:30:00+00:00)
    local clean_timestamp="${timestamp}"
    if [[ "$timestamp" =~ \.[0-9]+[+-Z] ]]; then
        clean_timestamp=$(echo "$timestamp" | sed 's/\.[0-9]*\([+-Z]\)/\1/')
    fi

    if command -v gdate &>/dev/null; then
        # macOS with coreutils
        session_time=$(gdate -d "$clean_timestamp" +%s 2>/dev/null)
    elif date --version 2>&1 | grep -q GNU; then
        # GNU date (Linux)
        session_time=$(date -d "$clean_timestamp" +%s 2>/dev/null)
    else
        # BSD date (macOS without coreutils) - try parsing ISO format
        # Format: 2026-01-09T10:30:00+00:00 or 2026-01-09T10:30:00Z
        # Strip timezone suffix for BSD date parsing
        local date_only="${clean_timestamp%[+-Z]*}"
        session_time=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$date_only" +%s 2>/dev/null)
    fi

    # If we couldn't parse the timestamp, consider session expired
    if [[ -z "$session_time" || ! "$session_time" =~ ^[0-9]+$ ]]; then
        echo "false"
        return 1
    fi

    # Calculate age in seconds
    local age=$((now - session_time))

    # Check if session is still valid (less than expiration time)
    if [[ $age -lt $SESSION_EXPIRATION_SECONDS ]]; then
        echo "true"
        return 0
    else
        echo "false"
        return 1
    fi
}

# =============================================================================
# SESSION AGE WARNING
# =============================================================================

# Check session file age and warn if older than threshold
# Arguments: none (uses KORERO_DIR and SESSION_AGE_WARNING_HOURS env vars)
# Output: Warning message to stdout if session exceeds threshold, empty otherwise
# Returns: 0 always
check_session_age() {
    local session_file="${KORERO_DIR:-.korero}/.claude_session_id"
    local max_age_hours="${SESSION_AGE_WARNING_HOURS:-12}"

    if [[ ! -f "$session_file" ]]; then
        return 0
    fi

    # Cross-platform file modification time
    local session_time=""
    if [[ "$(uname)" == "Darwin" ]]; then
        session_time=$(stat -f %m "$session_file" 2>/dev/null)
    else
        session_time=$(stat -c %Y "$session_file" 2>/dev/null)
    fi

    if [[ -z "$session_time" ]]; then
        return 0
    fi

    local current_time
    current_time=$(date +%s)
    local age_seconds=$((current_time - session_time))
    local age_hours=$((age_seconds / 3600))

    if [[ $age_hours -ge $max_age_hours ]]; then
        echo "Warning: Session is ${age_hours} hours old. Consider: korero --reset-session"
    fi

    return 0
}

# =============================================================================
# PERMISSION DENIAL SUGGESTION FUNCTIONS
# =============================================================================

# Merge new tool permissions with existing ones, avoiding duplicates
# Usage: merge_tool_permissions "Write,Read,Edit" "Bash(npm *)"
# Returns: "Write,Read,Edit,Bash(npm *)"
merge_tool_permissions() {
    local current="$1"
    local new="$2"

    # Handle empty current
    if [[ -z "$current" ]]; then
        echo "$new"
        return
    fi

    # Handle preset - presets can be mixed with custom tools
    # e.g., "@standard" + "Bash(docker *)" = "@standard,Bash(docker *)"
    if [[ "$current" == @* && ! "$current" == *","* ]]; then
        echo "$current,$new"
        return
    fi

    # Split current into array and check for duplicates
    local -a current_arr
    IFS=',' read -ra current_arr <<< "$current"

    # Check each new tool
    local -a new_arr
    IFS=',' read -ra new_arr <<< "$new"

    local merged="$current"
    for tool in "${new_arr[@]}"; do
        local found=false
        for existing in "${current_arr[@]}"; do
            if [[ "$tool" == "$existing" ]]; then
                found=true
                break
            fi
        done
        if [[ "$found" == false ]]; then
            merged="$merged,$tool"
        fi
    done

    echo "$merged"
}

# Apply permission fix by updating .korerorc ALLOWED_TOOLS
# Usage: apply_permission_fix "Bash(npm *),Bash(git *)"
# Returns: 0 on success, 1 on failure
apply_permission_fix() {
    local new_tools="$1"
    local korerorc="${KORERO_PROJECT_ROOT:-.}/.korerorc"

    if [[ ! -f "$korerorc" ]]; then
        echo "Error: .korerorc not found at $korerorc" >&2
        return 1
    fi

    # Get current ALLOWED_TOOLS value
    local current_tools
    current_tools=$(grep -E '^ALLOWED_TOOLS=' "$korerorc" 2>/dev/null | head -1 | sed 's/^ALLOWED_TOOLS="\(.*\)"$/\1/' | sed "s/^ALLOWED_TOOLS='\(.*\)'$/\1/")

    # If no ALLOWED_TOOLS line exists, use the default
    if [[ -z "$current_tools" ]]; then
        current_tools="Write,Read,Edit"
    fi

    # Merge new tools with existing
    local merged_tools
    merged_tools=$(merge_tool_permissions "$current_tools" "$new_tools")

    # Display diff preview before applying
    show_config_diff "ALLOWED_TOOLS" "$current_tools" "$merged_tools"
    echo ""

    # Create backup
    cp "$korerorc" "${korerorc}.bak"

    # Update .korerorc using sed
    # Handle both quoted and unquoted ALLOWED_TOOLS
    if grep -qE '^ALLOWED_TOOLS=' "$korerorc"; then
        # Replace existing line
        sed -i.tmp "s|^ALLOWED_TOOLS=.*|ALLOWED_TOOLS=\"$merged_tools\"|" "$korerorc"
        rm -f "${korerorc}.tmp"
    else
        # Append new line
        echo "ALLOWED_TOOLS=\"$merged_tools\"" >> "$korerorc"
    fi

    echo -e "${GREEN}Updated ALLOWED_TOOLS in $korerorc${NC}"

    return 0
}

# =============================================================================
# VISUAL CONFIGURATION DIFF FUNCTIONS
# =============================================================================

# Display colorized before/after diff of a configuration field change
# Pure display function — no side effects, no confirmation prompt
# Usage: show_config_diff "field_name" "old_value" "new_value"
# Output: Colorized diff to stdout (RED for removed, GREEN for added)
# Returns: 0 always
show_config_diff() {
    local field_name="$1"
    local old_value="$2"
    local new_value="$3"

    echo -e "  ${BLUE}${field_name}:${NC}"

    if [[ "$old_value" == "$new_value" ]]; then
        echo -e "    ${YELLOW}(no change)${NC}"
        return 0
    fi

    # Show old value (red, with - prefix)
    if [[ -n "$old_value" ]]; then
        echo -e "    ${RED}- ${old_value}${NC}"
    else
        echo -e "    ${RED}- (not set)${NC}"
    fi

    # Show new value (green, with + prefix)
    if [[ -n "$new_value" ]]; then
        echo -e "    ${GREEN}+ ${new_value}${NC}"
    else
        echo -e "    ${GREEN}+ (not set)${NC}"
    fi

    # If new value is a preset, show what it expands to
    if [[ "$new_value" == @* ]]; then
        if ! type expand_allowed_tools &>/dev/null; then
            local lib_dir
            lib_dir="$(dirname "${BASH_SOURCE[0]}")"
            if [[ -f "$lib_dir/permission_presets.sh" ]]; then
                source "$lib_dir/permission_presets.sh"
            fi
        fi
        if type expand_allowed_tools &>/dev/null; then
            local expanded
            expanded=$(expand_allowed_tools "$new_value" 2>/dev/null)
            if [[ -n "$expanded" ]]; then
                echo -e "    ${YELLOW}(expands to: ${expanded})${NC}"
            fi
        fi
    fi

    return 0
}

# Show config diff and prompt for user confirmation before applying
# Used in contexts where there is NO prior menu selection (e.g., korero-enable --force)
# NOT used by prompt_permission_fix (which has its own 1/2/3/n menu)
# Usage: confirm_config_change "field_name" "old_value" "new_value"
# Returns: 0 if user confirms or values identical, 1 if user declines
confirm_config_change() {
    local field_name="$1"
    local old_value="$2"
    local new_value="$3"

    # No change needed — return success without prompting
    if [[ "$old_value" == "$new_value" ]]; then
        return 0
    fi

    show_config_diff "$field_name" "$old_value" "$new_value"

    echo ""
    echo -en "  Apply this change? [y/N]: "
    read -r response

    case "${response,,}" in
        y|yes)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Interactive prompt for permission fix
# Displays suggestions and offers to auto-apply them
# Usage: prompt_permission_fix "npm install" "git status"
# Returns: 0 if fixed (continue loop), 1 if declined (exit)
prompt_permission_fix() {
    local denied_commands=("$@")

    # Source wizard_utils.sh for confirm() if not already available
    if ! type confirm &>/dev/null; then
        local lib_dir
        lib_dir="$(dirname "${BASH_SOURCE[0]}")"
        if [[ -f "$lib_dir/wizard_utils.sh" ]]; then
            source "$lib_dir/wizard_utils.sh"
        elif [[ -f "${KORERO_LIB_DIR:-$HOME/.korero/lib}/wizard_utils.sh" ]]; then
            source "${KORERO_LIB_DIR:-$HOME/.korero/lib}/wizard_utils.sh"
        fi
    fi

    # Build new tools string from denied commands
    local new_tools=""
    for cmd in "${denied_commands[@]}"; do
        local suggestion
        suggestion=$(suggest_permission_fix "$cmd")
        if [[ -z "$new_tools" ]]; then
            new_tools="$suggestion"
        elif [[ "$new_tools" != *"$suggestion"* ]]; then
            new_tools="$new_tools,$suggestion"
        fi
    done

    # Display the fix options (using existing format_permission_denial_message)
    format_permission_denial_message "${denied_commands[@]}"

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Offer interactive fix options
    echo -e "${YELLOW}Quick Actions:${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} Apply quick fix (add only needed tools): ${GREEN}${new_tools}${NC}"
    echo -e "  ${CYAN}2)${NC} Apply @standard preset (recommended for most projects)"
    echo -e "  ${CYAN}3)${NC} Apply @permissive preset (all Bash commands)"
    echo -e "  ${CYAN}n)${NC} Exit and fix manually"
    echo ""
    echo -en "Select option [1/2/3/n] (default: n): "
    read -r response

    case "${response,,}" in
        1)
            if apply_permission_fix "$new_tools"; then
                echo ""
                echo -e "${GREEN}Permission fix applied. Resuming loop...${NC}"
                echo ""
                # Re-source .korerorc to load new permissions
                local korerorc="${KORERO_PROJECT_ROOT:-.}/.korerorc"
                if [[ -f "$korerorc" ]]; then
                    source "$korerorc"
                fi
                return 0
            else
                echo -e "${RED}Failed to apply fix. Please fix manually.${NC}"
                return 1
            fi
            ;;
        2)
            if apply_permission_fix "@standard"; then
                echo ""
                echo -e "${GREEN}@standard preset applied. Resuming loop...${NC}"
                echo ""
                local korerorc="${KORERO_PROJECT_ROOT:-.}/.korerorc"
                if [[ -f "$korerorc" ]]; then
                    source "$korerorc"
                fi
                return 0
            else
                echo -e "${RED}Failed to apply fix. Please fix manually.${NC}"
                return 1
            fi
            ;;
        3)
            if apply_permission_fix "@permissive"; then
                echo ""
                echo -e "${GREEN}@permissive preset applied. Resuming loop...${NC}"
                echo ""
                local korerorc="${KORERO_PROJECT_ROOT:-.}/.korerorc"
                if [[ -f "$korerorc" ]]; then
                    source "$korerorc"
                fi
                return 0
            else
                echo -e "${RED}Failed to apply fix. Please fix manually.${NC}"
                return 1
            fi
            ;;
        *)
            echo ""
            echo -e "${YELLOW}Manual fix required. Edit .korerorc and restart: korero${NC}"
            return 1
            ;;
    esac
}

# Suggest ALLOWED_TOOLS pattern for a denied command
# Maps common commands to wildcard patterns, unknown commands to exact match
# Usage: suggest_permission_fix "npm install lodash"
# Returns: "Bash(npm *)"
suggest_permission_fix() {
    local denied_cmd="$1"
    local base_cmd="${denied_cmd%% *}"

    case "$base_cmd" in
        npm)     echo "Bash(npm *)" ;;
        git)     echo "Bash(git *)" ;;
        pytest)  echo "Bash(pytest)" ;;
        make)    echo "Bash(make *)" ;;
        cargo)   echo "Bash(cargo *)" ;;
        yarn)    echo "Bash(yarn *)" ;;
        pnpm)    echo "Bash(pnpm *)" ;;
        go)      echo "Bash(go *)" ;;
        python)  echo "Bash(python *)" ;;
        pip)     echo "Bash(pip *)" ;;
        docker)  echo "Bash(docker *)" ;;
        *)       echo "Bash($denied_cmd)" ;;
    esac
}

# Format permission denial message with progressive disclosure fix suggestions
# Presents three numbered options: quick fix, standard preset, permissive preset
# Usage: format_permission_denial_message "npm install" "git push"
# Outputs actionable fix with per-command suggestions and composite ALLOWED_TOOLS
format_permission_denial_message() {
    local denied_commands=("$@")
    local current_tools="${CLAUDE_ALLOWED_TOOLS:-Write,Read,Edit}"

    echo "========================================="
    echo "PERMISSION DENIED - Choose a fix:"
    echo "========================================="
    echo ""
    echo "Commands denied:"

    local new_tools="$current_tools"
    for cmd in "${denied_commands[@]}"; do
        local suggestion
        suggestion=$(suggest_permission_fix "$cmd")
        echo "  - $cmd"
        # Build composite tools string
        if [[ "$new_tools" != *"$suggestion"* ]]; then
            new_tools="$new_tools,$suggestion"
        fi
    done

    echo ""
    echo "-----------------------------------------"
    echo "Option 1: Quick fix (minimal permissions)"
    echo "  Add only what's needed for these commands:"
    echo "  ALLOWED_TOOLS=\"$new_tools\""
    echo ""
    echo "Option 2: Use @standard preset (recommended)"
    echo "  Covers git, npm, pytest - good for most projects:"
    echo "  ALLOWED_TOOLS=\"@standard\""
    echo ""
    echo "Option 3: Go permissive (all Bash commands)"
    echo "  Maximum flexibility, less restrictive:"
    echo "  ALLOWED_TOOLS=\"@permissive\""
    echo "-----------------------------------------"
    echo ""
    echo "Edit .korerorc with your choice, then restart: korero"
    echo "========================================="
}

# Export functions for use in korero_loop.sh
export -f detect_output_format
export -f parse_json_response
export -f analyze_response
export -f update_exit_signals
export -f log_analysis_summary
export -f detect_stuck_loop
export -f store_session_id
export -f get_last_session_id
export -f should_resume_session
export -f check_session_age
export -f suggest_permission_fix
export -f format_permission_denial_message
export -f merge_tool_permissions
export -f apply_permission_fix
export -f show_config_diff
export -f confirm_config_change
export -f prompt_permission_fix
