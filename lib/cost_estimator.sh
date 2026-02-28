#!/usr/bin/env bash

# cost_estimator.sh — API cost estimation from Korero loop logs
#
# Estimates API costs by analyzing log file sizes as a proxy for token usage.
# Uses approximate token-to-character ratios and published pricing.
#
# Depends on: lib/date_utils.sh (optional, for timestamps)

KORERO_DIR="${KORERO_DIR:-.korero}"
COST_LOG_DIR="${COST_LOG_DIR:-$KORERO_DIR/logs}"

# ANSI color codes
COST_BLUE='\033[0;34m'
COST_GREEN='\033[0;32m'
COST_YELLOW='\033[1;33m'
COST_CYAN='\033[0;36m'
COST_RED='\033[0;31m'
COST_NC='\033[0m'
COST_BOLD='\033[1m'

# Approximate characters per token (industry average for English text)
CHARS_PER_TOKEN=4

# Pricing per 1M tokens (USD) — Claude Sonnet 4 defaults
COST_INPUT_PER_1M="${COST_INPUT_PER_1M:-3.00}"
COST_OUTPUT_PER_1M="${COST_OUTPUT_PER_1M:-15.00}"

# Estimate token count from a file based on character count
# Arguments:
#   $1 (file_path) - Path to file
# Returns: estimated token count on stdout
estimate_tokens_from_file() {
    local file_path="$1"

    if [[ ! -f "$file_path" ]]; then
        echo "0"
        return 0
    fi

    local char_count
    char_count=$(wc -c < "$file_path" 2>/dev/null || echo "0")
    char_count=$(echo "$char_count" | tr -d '[:space:]')

    if [[ "$char_count" -eq 0 ]]; then
        echo "0"
        return 0
    fi

    local tokens=$(( char_count / CHARS_PER_TOKEN ))
    echo "$tokens"
}

# Calculate cost in USD for a given token count
# Arguments:
#   $1 (tokens)   - Number of tokens
#   $2 (rate)     - Cost per 1M tokens in USD
# Returns: cost as decimal string on stdout
calculate_cost() {
    local tokens="$1"
    local rate="$2"

    if [[ "$tokens" -eq 0 ]]; then
        echo "0.000000"
        return 0
    fi

    # Use awk for floating-point arithmetic
    awk "BEGIN { printf \"%.6f\", ($tokens / 1000000) * $rate }"
}

# Scan log directory and estimate total API costs
# Arguments:
#   $1 (log_dir) - Path to logs directory (optional, defaults to COST_LOG_DIR)
# Returns: JSON object on stdout with cost breakdown
estimate_api_costs() {
    local log_dir="${1:-$COST_LOG_DIR}"

    if [[ ! -d "$log_dir" ]]; then
        cat << NOLOGS_EOF
{
  "error": "Log directory not found: $log_dir",
  "total_cost": 0,
  "input_tokens": 0,
  "output_tokens": 0
}
NOLOGS_EOF
        return 1
    fi

    local total_input_tokens=0
    local total_output_tokens=0
    local file_count=0

    # Claude output logs are responses (output tokens)
    for f in "$log_dir"/claude_output_*.log "$log_dir"/claude_proposal_*.log "$log_dir"/claude_impl_*.log "$log_dir"/idea_output_*.log; do
        if [[ -f "$f" ]]; then
            local tokens
            tokens=$(estimate_tokens_from_file "$f")
            total_output_tokens=$(( total_output_tokens + tokens ))
            file_count=$(( file_count + 1 ))
        fi
    done

    # Codex output logs
    for f in "$log_dir"/codex_proposal_*.log "$log_dir"/codex_lastmsg_*.log; do
        if [[ -f "$f" ]]; then
            local tokens
            tokens=$(estimate_tokens_from_file "$f")
            total_output_tokens=$(( total_output_tokens + tokens ))
            file_count=$(( file_count + 1 ))
        fi
    done

    # Debate logs (critique, defense, verdict) — both input and output
    local debate_dir="$KORERO_DIR/debates"
    if [[ -d "$debate_dir" ]]; then
        for f in "$debate_dir"/claude_critique_*.log "$debate_dir"/codex_critique_*.log \
                 "$debate_dir"/claude_defense_*.log "$debate_dir"/codex_defense_*.log \
                 "$debate_dir"/judge_verdict_*.log; do
            if [[ -f "$f" ]]; then
                local tokens
                tokens=$(estimate_tokens_from_file "$f")
                total_output_tokens=$(( total_output_tokens + tokens ))
                file_count=$(( file_count + 1 ))
            fi
        done
    fi

    # Estimate input tokens as ~2x output (prompts are typically larger than responses)
    total_input_tokens=$(( total_output_tokens * 2 ))

    local input_cost output_cost total_cost
    input_cost=$(calculate_cost "$total_input_tokens" "$COST_INPUT_PER_1M")
    output_cost=$(calculate_cost "$total_output_tokens" "$COST_OUTPUT_PER_1M")
    total_cost=$(awk "BEGIN { printf \"%.6f\", $input_cost + $output_cost }")

    cat << COST_EOF
{
  "total_cost": $total_cost,
  "input_tokens": $total_input_tokens,
  "output_tokens": $total_output_tokens,
  "input_cost": $input_cost,
  "output_cost": $output_cost,
  "files_analyzed": $file_count,
  "input_rate_per_1m": $COST_INPUT_PER_1M,
  "output_rate_per_1m": $COST_OUTPUT_PER_1M,
  "log_dir": "$log_dir"
}
COST_EOF
}

# Display a formatted cost report to the terminal
# Arguments:
#   $1 (log_dir) - Path to logs directory (optional)
# Output: Formatted report to stdout
display_cost_report() {
    local log_dir="${1:-$COST_LOG_DIR}"

    local cost_json
    cost_json=$(estimate_api_costs "$log_dir")

    # Check for error
    local error
    error=$(echo "$cost_json" | grep -o '"error"' || true)
    if [[ -n "$error" ]]; then
        echo -e "${COST_RED}Error: No log directory found at $log_dir${COST_NC}"
        echo "Run some Korero loops first to generate logs."
        return 1
    fi

    # Parse fields using grep/sed (avoid jq dependency for portability)
    local total_cost input_tokens output_tokens input_cost output_cost files_analyzed
    total_cost=$(echo "$cost_json" | grep '"total_cost"' | head -1 | sed 's/.*: *//' | sed 's/,$//')
    input_tokens=$(echo "$cost_json" | grep '"input_tokens"' | head -1 | sed 's/.*: *//' | sed 's/,$//')
    output_tokens=$(echo "$cost_json" | grep '"output_tokens"' | head -1 | sed 's/.*: *//' | sed 's/,$//')
    input_cost=$(echo "$cost_json" | grep '"input_cost"' | head -1 | sed 's/.*: *//' | sed 's/,$//')
    output_cost=$(echo "$cost_json" | grep '"output_cost"' | head -1 | sed 's/.*: *//' | sed 's/,$//')
    files_analyzed=$(echo "$cost_json" | grep '"files_analyzed"' | head -1 | sed 's/.*: *//' | sed 's/,$//')

    # Format token counts with commas using printf
    local fmt_input fmt_output
    fmt_input=$(printf "%'d" "$input_tokens" 2>/dev/null || echo "$input_tokens")
    fmt_output=$(printf "%'d" "$output_tokens" 2>/dev/null || echo "$output_tokens")

    echo ""
    echo -e "${COST_CYAN}╔══════════════════════════════════════════════════╗${COST_NC}"
    echo -e "${COST_CYAN}║  ${COST_BOLD}API COST ESTIMATE${COST_NC}${COST_CYAN}                               ║${COST_NC}"
    echo -e "${COST_CYAN}╠══════════════════════════════════════════════════╣${COST_NC}"
    echo -e "${COST_CYAN}║${COST_NC}"
    echo -e "${COST_CYAN}║${COST_NC}  ${COST_BOLD}Token Usage${COST_NC}"
    echo -e "${COST_CYAN}║${COST_NC}    Input tokens:    ${COST_BLUE}${fmt_input}${COST_NC} (estimated)"
    echo -e "${COST_CYAN}║${COST_NC}    Output tokens:   ${COST_BLUE}${fmt_output}${COST_NC}"
    echo -e "${COST_CYAN}║${COST_NC}"
    echo -e "${COST_CYAN}║${COST_NC}  ${COST_BOLD}Cost Breakdown${COST_NC}"
    echo -e "${COST_CYAN}║${COST_NC}    Input cost:      ${COST_GREEN}\$${input_cost}${COST_NC}"
    echo -e "${COST_CYAN}║${COST_NC}    Output cost:     ${COST_GREEN}\$${output_cost}${COST_NC}"
    echo -e "${COST_CYAN}║${COST_NC}    ─────────────────────────"
    echo -e "${COST_CYAN}║${COST_NC}    ${COST_BOLD}Total estimate:  ${COST_YELLOW}\$${total_cost}${COST_NC}"
    echo -e "${COST_CYAN}║${COST_NC}"
    echo -e "${COST_CYAN}║${COST_NC}  ${COST_BOLD}Details${COST_NC}"
    echo -e "${COST_CYAN}║${COST_NC}    Files analyzed:  ${files_analyzed}"
    echo -e "${COST_CYAN}║${COST_NC}    Pricing:        \$${COST_INPUT_PER_1M}/1M input, \$${COST_OUTPUT_PER_1M}/1M output"
    echo -e "${COST_CYAN}║${COST_NC}    Log directory:   ${log_dir}"
    echo -e "${COST_CYAN}║${COST_NC}"
    echo -e "${COST_CYAN}║${COST_NC}  ${COST_YELLOW}Note: Estimates based on log file sizes.${COST_NC}"
    echo -e "${COST_CYAN}║${COST_NC}  ${COST_YELLOW}Actual costs may vary. Input tokens estimated at 2x output.${COST_NC}"
    echo -e "${COST_CYAN}╚══════════════════════════════════════════════════╝${COST_NC}"
    echo ""
}

export -f estimate_tokens_from_file
export -f calculate_cost
export -f estimate_api_costs
export -f display_cost_report
