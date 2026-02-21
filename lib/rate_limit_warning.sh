#!/usr/bin/env bash

# rate_limit_warning.sh - Rate limit approach warnings
# Warns users at 80% and 95% of API call budget before hitting the limit.

# Warning thresholds (percentages)
RATE_WARN_THRESHOLD=80
RATE_CRITICAL_THRESHOLD=95

# Check rate limit and return warning level
# Usage: check_rate_limit_warning <current_count> <max_calls>
# Returns: "none", "warning", or "critical"
check_rate_limit_warning() {
    local current="${1:-0}"
    local max="${2:-100}"

    current="${current//[^0-9]/}"
    current="${current:-0}"
    max="${max//[^0-9]/}"
    max="${max:-100}"

    if [[ $max -eq 0 ]]; then
        echo "none"
        return 0
    fi

    local pct=$((current * 100 / max))

    if [[ $pct -ge $RATE_CRITICAL_THRESHOLD ]]; then
        echo "critical"
    elif [[ $pct -ge $RATE_WARN_THRESHOLD ]]; then
        echo "warning"
    else
        echo "none"
    fi
}

# Format rate limit warning message
# Usage: format_rate_limit_warning <current_count> <max_calls>
# Returns: warning message or empty string
format_rate_limit_warning() {
    local current="${1:-0}"
    local max="${2:-100}"

    current="${current//[^0-9]/}"
    current="${current:-0}"
    max="${max//[^0-9]/}"
    max="${max:-100}"

    local remaining=$((max - current))
    local level
    level=$(check_rate_limit_warning "$current" "$max")

    case "$level" in
        "critical")
            echo "CRITICAL: Rate limit at ${current}/${max} — only ${remaining} calls remaining!"
            ;;
        "warning")
            echo "WARNING: Rate limit approaching — ${current}/${max} used (${remaining} remaining)"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Get rate limit status for status.json updates
# Usage: get_rate_limit_status <current_count> <max_calls>
# Returns JSON fragment
get_rate_limit_status() {
    local current="${1:-0}"
    local max="${2:-100}"

    current="${current//[^0-9]/}"
    current="${current:-0}"
    max="${max//[^0-9]/}"
    max="${max:-100}"

    local remaining=$((max - current))
    local level
    level=$(check_rate_limit_warning "$current" "$max")
    local pct=$((current * 100 / max))

    echo "{\"current\":${current},\"max\":${max},\"remaining\":${remaining},\"percentage\":${pct},\"warning_level\":\"${level}\"}"
}

# Should we show a warning for the current state?
# Usage: should_warn_rate_limit <current_count> <max_calls> <last_warned_level>
# Returns 0 if warning should be shown, 1 otherwise
# This prevents spamming by only warning once per level transition
should_warn_rate_limit() {
    local current="${1:-0}"
    local max="${2:-100}"
    local last_warned="${3:-none}"

    local level
    level=$(check_rate_limit_warning "$current" "$max")

    # No warning needed
    [[ "$level" == "none" ]] && return 1

    # Already warned at this level or higher
    [[ "$last_warned" == "$level" ]] && return 1
    [[ "$last_warned" == "critical" ]] && return 1

    return 0
}

export -f check_rate_limit_warning
export -f format_rate_limit_warning
export -f get_rate_limit_status
export -f should_warn_rate_limit
