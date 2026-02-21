#!/usr/bin/env bash

# permission_presets.sh - Named permission template presets for ALLOWED_TOOLS
# Provides @conservative, @standard, @permissive presets that expand to
# specific tool lists. Supports mixing presets with custom tools.

# Preset definitions
PRESET_CONSERVATIVE="Write,Read,Edit"
PRESET_STANDARD="Write,Read,Edit,Bash(git *),Bash(npm *),Bash(pytest)"
PRESET_PERMISSIVE="Write,Read,Edit,Bash(*)"

# Expand a single preset name to its tool list
# Usage: expand_tool_preset <preset_name>
# Returns: expanded tool list or empty string if not a preset
expand_tool_preset() {
    local preset="${1:-}"

    case "$preset" in
        "@conservative")
            echo "$PRESET_CONSERVATIVE"
            ;;
        "@standard")
            echo "$PRESET_STANDARD"
            ;;
        "@permissive")
            echo "$PRESET_PERMISSIVE"
            ;;
        *)
            echo ""
            return 1
            ;;
    esac
    return 0
}

# Expand ALLOWED_TOOLS value, resolving any preset references
# Supports: pure preset ("@standard"), preset + custom ("@standard,Bash(docker *)"),
# or plain tool list ("Write,Read,Edit")
# Usage: expand_allowed_tools <value>
expand_allowed_tools() {
    local value="${1:-}"
    local result=""

    if [[ -z "$value" ]]; then
        echo ""
        return 0
    fi

    # Split by comma
    local IFS=','
    read -ra parts <<< "$value"

    for part in "${parts[@]}"; do
        # Trim whitespace
        part=$(echo "$part" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        if [[ "$part" == "@"* ]]; then
            # It's a preset reference
            local expanded
            expanded=$(expand_tool_preset "$part")
            if [[ -n "$expanded" ]]; then
                if [[ -n "$result" ]]; then
                    result="$result,$expanded"
                else
                    result="$expanded"
                fi
            else
                echo "WARNING: Unknown preset '$part', ignoring" >&2
            fi
        else
            # It's a regular tool
            if [[ -n "$part" ]]; then
                if [[ -n "$result" ]]; then
                    result="$result,$part"
                else
                    result="$part"
                fi
            fi
        fi
    done

    echo "$result"
}

# List all available presets
# Usage: list_presets
list_presets() {
    echo "Available permission presets:"
    echo "  @conservative  $PRESET_CONSERVATIVE"
    echo "  @standard      $PRESET_STANDARD"
    echo "  @permissive    $PRESET_PERMISSIVE"
    echo ""
    echo "Usage in .korerorc:"
    echo '  ALLOWED_TOOLS="@standard"'
    echo '  ALLOWED_TOOLS="@standard,Bash(docker *)"'
}

export -f expand_tool_preset
export -f expand_allowed_tools
export -f list_presets
