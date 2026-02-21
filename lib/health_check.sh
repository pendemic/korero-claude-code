#!/usr/bin/env bash

# health_check.sh - Pre-loop health check system
# Validates environment before loop execution to catch predictable failures.
# Checks: session age, rate limit headroom, config syntax, CLI availability,
# ALLOWED_TOOLS patterns.

# Health check status constants
HC_OK="OK"
HC_WARN="WARN"
HC_ERROR="ERROR"

# Check if Claude CLI is available
# Returns: OK, WARN (version mismatch), or ERROR (not found)
check_claude_cli() {
    if command -v claude >/dev/null 2>&1; then
        echo "$HC_OK:claude found"
        return 0
    fi

    if command -v npx >/dev/null 2>&1; then
        echo "$HC_OK:npx available"
        return 0
    fi

    echo "$HC_ERROR:Claude CLI not found (install claude or npx)"
    return 1
}

# Check if required dependencies are present
check_dependencies() {
    local missing=()

    if ! command -v jq >/dev/null 2>&1; then
        missing+=("jq")
    fi

    if ! command -v git >/dev/null 2>&1; then
        missing+=("git")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "$HC_ERROR:Missing dependencies: ${missing[*]}"
        return 1
    fi

    echo "$HC_OK:All dependencies present"
    return 0
}

# Check session age and validity
# Usage: check_session_health <korero_dir>
check_session_health() {
    local korero_dir="${1:-.korero}"
    local session_file="$korero_dir/.claude_session_id"

    if [[ ! -f "$session_file" ]]; then
        echo "$HC_OK:No active session (will start fresh)"
        return 0
    fi

    local session_id
    session_id=$(cat "$session_file" 2>/dev/null)

    if [[ -z "$session_id" ]]; then
        echo "$HC_WARN:Session file exists but is empty"
        return 0
    fi

    # Check session file age (24h expiration)
    local max_age=86400
    local file_age
    if [[ "$(uname)" == "Darwin" ]]; then
        file_age=$(( $(date +%s) - $(stat -f %m "$session_file" 2>/dev/null || echo 0) ))
    else
        file_age=$(( $(date +%s) - $(stat -c %Y "$session_file" 2>/dev/null || echo 0) ))
    fi

    if [[ $file_age -gt $max_age ]]; then
        echo "$HC_WARN:Session expired (${file_age}s old, max ${max_age}s)"
        return 0
    fi

    echo "$HC_OK:Session active (age: ${file_age}s)"
    return 0
}

# Check rate limit headroom
# Usage: check_rate_limit_health <korero_dir> <max_calls>
check_rate_limit_health() {
    local korero_dir="${1:-.korero}"
    local max_calls="${2:-100}"
    local call_count_file="$korero_dir/.call_count"

    if [[ ! -f "$call_count_file" ]]; then
        echo "$HC_OK:Rate limit: 0/$max_calls used"
        return 0
    fi

    local current_count
    current_count=$(cat "$call_count_file" 2>/dev/null || echo "0")
    current_count="${current_count//[^0-9]/}"
    current_count="${current_count:-0}"

    local remaining=$((max_calls - current_count))
    local usage_pct=$((current_count * 100 / max_calls))

    if [[ $remaining -le 0 ]]; then
        echo "$HC_ERROR:Rate limit exhausted ($current_count/$max_calls)"
        return 1
    elif [[ $usage_pct -ge 90 ]]; then
        echo "$HC_WARN:Rate limit near capacity ($current_count/$max_calls, ${remaining} remaining)"
        return 0
    fi

    echo "$HC_OK:Rate limit: $current_count/$max_calls used (${remaining} remaining)"
    return 0
}

# Check config file syntax
# Usage: check_config_health <config_file>
check_config_health() {
    local config_file="${1:-.korerorc}"

    if [[ ! -f "$config_file" ]]; then
        echo "$HC_WARN:No .korerorc found (using defaults)"
        return 0
    fi

    # Check for basic syntax errors (unmatched quotes)
    local line_num=0
    local errors=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Check for assignment syntax
        if [[ "$line" == *=* ]]; then
            local value="${line#*=}"
            # Count quotes - should be even
            local dq_count="${value//[^\"]/}"
            local sq_count="${value//[^\']/}"
            if [[ $((${#dq_count} % 2)) -ne 0 ]]; then
                errors+=("Line $line_num: unmatched double quote")
            fi
            if [[ $((${#sq_count} % 2)) -ne 0 ]]; then
                errors+=("Line $line_num: unmatched single quote")
            fi
        fi
    done < "$config_file"

    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "$HC_ERROR:Config syntax errors: ${errors[*]}"
        return 1
    fi

    echo "$HC_OK:Config syntax valid"
    return 0
}

# Check ALLOWED_TOOLS patterns
# Usage: check_tools_health <allowed_tools_value>
check_tools_health() {
    local tools="${1:-}"

    if [[ -z "$tools" ]]; then
        echo "$HC_WARN:No ALLOWED_TOOLS configured (Claude will prompt for each)"
        return 0
    fi

    # Check for preset references
    if [[ "$tools" == "@"* ]]; then
        case "$tools" in
            "@conservative"|"@standard"|"@permissive")
                echo "$HC_OK:Using preset: $tools"
                return 0
                ;;
            *)
                echo "$HC_WARN:Unknown preset '$tools'"
                return 0
                ;;
        esac
    fi

    # Check for common patterns
    if [[ "$tools" != *"Write"* && "$tools" != *"Read"* && "$tools" != *"Edit"* ]]; then
        echo "$HC_WARN:ALLOWED_TOOLS missing basic file operations (Write, Read, Edit)"
        return 0
    fi

    echo "$HC_OK:ALLOWED_TOOLS configured"
    return 0
}

# Check korero project directory
# Usage: check_project_health <korero_dir>
check_project_health() {
    local korero_dir="${1:-.korero}"

    if [[ ! -d "$korero_dir" ]]; then
        echo "$HC_ERROR:No .korero directory found (run korero-enable first)"
        return 1
    fi

    local missing=()

    if [[ ! -f "$korero_dir/PROMPT.md" ]]; then
        missing+=("PROMPT.md")
    fi

    if [[ ! -f "$korero_dir/fix_plan.md" ]]; then
        missing+=("fix_plan.md")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "$HC_WARN:Missing files in .korero/: ${missing[*]}"
        return 0
    fi

    echo "$HC_OK:Project structure valid"
    return 0
}

# Run all health checks
# Usage: run_health_checks [korero_dir] [max_calls] [allowed_tools]
# Returns: 0 if all pass, 1 if any errors
run_health_checks() {
    local korero_dir="${1:-.korero}"
    local max_calls="${2:-100}"
    local allowed_tools="${3:-}"
    local has_errors=0
    local has_warnings=0
    local results=()

    echo "=== Pre-Loop Health Check ==="
    echo ""

    # Run each check
    local checks=(
        "check_claude_cli"
        "check_dependencies"
        "check_project_health $korero_dir"
        "check_session_health $korero_dir"
        "check_rate_limit_health $korero_dir $max_calls"
        "check_config_health .korerorc"
        "check_tools_health $allowed_tools"
    )

    local labels=(
        "Claude CLI"
        "Dependencies"
        "Project Structure"
        "Session State"
        "Rate Limit"
        "Config Syntax"
        "Tool Permissions"
    )

    for i in "${!checks[@]}"; do
        local result
        result=$(eval "${checks[$i]}" 2>&1)
        local status="${result%%:*}"
        local message="${result#*:}"

        case "$status" in
            "$HC_OK")
                printf "  [OK]   %-20s %s\n" "${labels[$i]}" "$message"
                ;;
            "$HC_WARN")
                printf "  [WARN] %-20s %s\n" "${labels[$i]}" "$message"
                has_warnings=1
                ;;
            "$HC_ERROR")
                printf "  [FAIL] %-20s %s\n" "${labels[$i]}" "$message"
                has_errors=1
                ;;
        esac
    done

    echo ""

    if [[ $has_errors -eq 1 ]]; then
        echo "Health check: FAILED — resolve errors before starting loop"
        return 1
    elif [[ $has_warnings -eq 1 ]]; then
        echo "Health check: PASSED with warnings"
        return 0
    else
        echo "Health check: ALL CLEAR"
        return 0
    fi
}

export -f check_claude_cli
export -f check_dependencies
export -f check_session_health
export -f check_rate_limit_health
export -f check_config_health
export -f check_tools_health
export -f check_project_health
export -f run_health_checks
