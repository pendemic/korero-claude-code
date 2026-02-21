#!/usr/bin/env bash
# korero_config.sh — Display and manage Korero configuration
# Shows all configuration options with current values, defaults, and sources

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors (only if terminal supports them)
if [[ -t 1 ]]; then
    BOLD='\033[1m'
    BLUE='\033[0;34m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    BOLD='' BLUE='' GREEN='' YELLOW='' NC=''
fi

# Define all known config options with defaults
declare -A CONFIG_DEFAULTS=(
    ["KORERO_MODE"]="coding"
    ["DOMAIN_AGENT_COUNT"]="3"
    ["MAX_LOOPS"]="continuous"
    ["MAX_CALLS_PER_HOUR"]="100"
    ["CLAUDE_TIMEOUT_MINUTES"]="15"
    ["CB_NO_PROGRESS_THRESHOLD"]="3"
    ["CB_SAME_ERROR_THRESHOLD"]="5"
    ["CB_OUTPUT_DECLINE_THRESHOLD"]="70"
    ["CB_PERMISSION_DENIAL_THRESHOLD"]="2"
    ["CLAUDE_OUTPUT_FORMAT"]="json"
    ["CLAUDE_USE_CONTINUE"]="true"
    ["CLAUDE_SESSION_EXPIRY_HOURS"]="24"
    ["CLAUDE_ALLOWED_TOOLS"]=""
    ["PROJECT_SUBJECT"]=""
    ["VERBOSE_PROGRESS"]="false"
)

# Descriptions for each option
declare -A CONFIG_DESCRIPTIONS=(
    ["KORERO_MODE"]="Loop mode: coding or idea"
    ["DOMAIN_AGENT_COUNT"]="Domain expert agents (1-10)"
    ["MAX_LOOPS"]="Max loops: number or continuous"
    ["MAX_CALLS_PER_HOUR"]="API call rate limit per hour"
    ["CLAUDE_TIMEOUT_MINUTES"]="Claude execution timeout (min)"
    ["CB_NO_PROGRESS_THRESHOLD"]="No-progress loops before halt"
    ["CB_SAME_ERROR_THRESHOLD"]="Same-error loops before halt"
    ["CB_OUTPUT_DECLINE_THRESHOLD"]="Output decline % before halt"
    ["CB_PERMISSION_DENIAL_THRESHOLD"]="Permission denials before halt"
    ["CLAUDE_OUTPUT_FORMAT"]="Claude CLI output: json or text"
    ["CLAUDE_USE_CONTINUE"]="Session continuity: true/false"
    ["CLAUDE_SESSION_EXPIRY_HOURS"]="Session expiry (hours)"
    ["CLAUDE_ALLOWED_TOOLS"]="Permitted tool patterns"
    ["PROJECT_SUBJECT"]="Project subject for agents"
    ["VERBOSE_PROGRESS"]="Detailed progress updates"
)

# Determine where a config value comes from
get_config_source() {
    local var_name="$1"
    local default_value="${CONFIG_DEFAULTS[$var_name]:-}"

    # Check .korerorc first
    if [[ -f ".korerorc" ]] && grep -q "^${var_name}=" ".korerorc" 2>/dev/null; then
        echo ".korerorc"
        return
    fi

    # Check if environment variable differs from default
    local current="${!var_name:-}"
    if [[ -n "$current" && "$current" != "$default_value" ]]; then
        echo "env"
        return
    fi

    echo "default"
}

show_config() {
    # Source .korerorc if it exists
    if [[ -f ".korerorc" ]]; then
        # shellcheck disable=SC1091
        source ".korerorc" 2>/dev/null || true
    fi

    echo ""
    echo -e "${BOLD}==========================================${NC}"
    echo -e "${BOLD}  KORERO CONFIGURATION${NC}"
    echo -e "${BOLD}==========================================${NC}"
    echo ""
    printf "  %-32s %-20s %-10s\n" "Option" "Value" "Source"
    printf "  %-32s %-20s %-10s\n" "--------------------------------" "--------------------" "----------"

    # Sort keys and display
    local sorted_keys
    sorted_keys=$(echo "${!CONFIG_DEFAULTS[@]}" | tr ' ' '\n' | sort)

    while IFS= read -r var_name; do
        [[ -z "$var_name" ]] && continue
        local default_value="${CONFIG_DEFAULTS[$var_name]}"
        local current_value="${!var_name:-$default_value}"
        local source
        source=$(get_config_source "$var_name")

        # Truncate long values
        if [[ ${#current_value} -gt 18 ]]; then
            current_value="${current_value:0:15}..."
        fi

        # Empty values display as (not set)
        if [[ -z "$current_value" ]]; then
            current_value="(not set)"
        fi

        # Color the source
        local source_display="$source"
        case "$source" in
            ".korerorc") source_display="${GREEN}${source}${NC}" ;;
            "env")       source_display="${YELLOW}${source}${NC}" ;;
        esac

        printf "  %-32s %-20s " "$var_name" "$current_value"
        echo -e "$source_display"
    done <<< "$sorted_keys"

    echo ""
    echo "  Legend: default = built-in | .korerorc = project config | env = environment"
    echo ""
    echo -e "${BOLD}==========================================${NC}"
}

show_config_help() {
    echo ""
    echo -e "${BOLD}KORERO CONFIGURATION OPTIONS${NC}"
    echo ""

    local sorted_keys
    sorted_keys=$(echo "${!CONFIG_DEFAULTS[@]}" | tr ' ' '\n' | sort)

    while IFS= read -r var_name; do
        [[ -z "$var_name" ]] && continue
        local desc="${CONFIG_DESCRIPTIONS[$var_name]:-No description}"
        local default="${CONFIG_DEFAULTS[$var_name]:-}"
        [[ -z "$default" ]] && default="(none)"
        echo -e "  ${BLUE}$var_name${NC}"
        echo "    $desc"
        echo "    Default: $default"
        echo ""
    done <<< "$sorted_keys"
}

case "${1:-show}" in
    show)
        show_config
        ;;
    help)
        show_config_help
        ;;
    *)
        echo "Usage: korero config [show|help]"
        echo "  show  - Display current configuration (default)"
        echo "  help  - Show description of each option"
        exit 1
        ;;
esac
