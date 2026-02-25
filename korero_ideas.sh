#!/usr/bin/env bash
# korero_ideas.sh — Browse and search winning ideas from ideation loops

set -euo pipefail

KORERO_DIR=".korero"
IDEAS_FILE="$KORERO_DIR/IDEAS.md"

# Colors
if [[ -t 1 ]]; then
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
else
    BOLD='' DIM='' NC=''
fi

show_usage() {
    echo "Usage: korero ideas <command>"
    echo ""
    echo "Commands:"
    echo "  list              List all winning ideas in compact table format"
    echo "  show <N>          Show full details of winning idea from loop N"
    echo "  search <pattern>  Search ideas by title or description"
    echo ""
    echo "Examples:"
    echo "  korero ideas list"
    echo "  korero ideas show 5"
    echo "  korero ideas search 'permission'"
}

list_ideas() {
    if [[ ! -f "$IDEAS_FILE" ]]; then
        echo "No ideas file found. Run ideation loops to generate ideas."
        return 0
    fi

    local idea_count
    idea_count=$(grep -c "^LOOP [0-9]* WINNING IDEA" "$IDEAS_FILE" 2>/dev/null || true)
    idea_count=${idea_count:-0}

    if [[ "$idea_count" -eq 0 ]]; then
        echo "No winning ideas found yet."
        return 0
    fi

    echo ""
    echo -e "${BOLD}==========================================${NC}"
    echo -e "${BOLD}  KORERO WINNING IDEAS ($idea_count total)${NC}"
    echo -e "${BOLD}==========================================${NC}"
    echo ""
    printf "  %-6s %-42s %-20s\n" "Loop" "Title" "Type"
    printf "  %-6s %-42s %-20s\n" "----" "------------------------------------------" "--------------------"

    local current_loop="" current_title="" current_type=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^LOOP\ ([0-9]+)\ WINNING\ IDEA ]]; then
            current_loop="${BASH_REMATCH[1]}"
            current_title=""
            current_type=""
        elif [[ "$line" =~ ^\*\*Title:\*\*\ (.*) ]]; then
            current_title="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^\*\*Type:\*\*\ (.*) ]]; then
            current_type="${BASH_REMATCH[1]}"
            if [[ -n "$current_loop" && -n "$current_title" ]]; then
                local display_title="$current_title"
                if [[ ${#display_title} -gt 40 ]]; then
                    display_title="${display_title:0:37}..."
                fi
                printf "  %-6s %-42s %-20s\n" "$current_loop" "$display_title" "$current_type"
            fi
        fi
    done < "$IDEAS_FILE"

    echo ""
    echo -e "${BOLD}==========================================${NC}"
}

show_idea() {
    local loop_num="$1"

    if [[ ! -f "$IDEAS_FILE" ]]; then
        echo "No ideas file found."
        return 1
    fi

    # Extract the section for the given loop number
    local in_section=false
    local found=false

    while IFS= read -r line; do
        if [[ "$line" =~ ^LOOP\ ${loop_num}\ WINNING\ IDEA ]]; then
            in_section=true
            found=true
            echo ""
            echo "========================================="
            echo "  LOOP $loop_num WINNING IDEA"
            echo "========================================="
            continue
        fi

        # Stop at the next loop header
        if [[ "$in_section" == "true" ]]; then
            if [[ "$line" =~ ^LOOP\ [0-9]+\ WINNING\ IDEA ]]; then
                break
            fi
            # Skip separator lines (═══)
            if [[ "$line" =~ ^═+ ]]; then
                continue
            fi
            echo "$line"
        fi
    done < "$IDEAS_FILE"

    if [[ "$found" == "false" ]]; then
        echo "No winning idea found for loop $loop_num."
        return 1
    fi
}

search_ideas() {
    local pattern="$1"

    if [[ ! -f "$IDEAS_FILE" ]]; then
        echo "No ideas file found."
        return 1
    fi

    echo ""
    echo "Searching for: $pattern"
    echo ""

    local current_loop="" current_title="" current_type=""
    local section_text="" found=false

    while IFS= read -r line; do
        if [[ "$line" =~ ^LOOP\ ([0-9]+)\ WINNING\ IDEA ]]; then
            # Before moving to the next section, check the previous one
            if [[ -n "$current_loop" && -n "$current_title" ]]; then
                _check_and_print_match "$pattern" "$current_loop" "$current_title" "$current_type" "$section_text" && found=true
            fi
            current_loop="${BASH_REMATCH[1]}"
            current_title=""
            current_type=""
            section_text=""
        elif [[ "$line" =~ ^\*\*Title:\*\*\ (.*) ]]; then
            current_title="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^\*\*Type:\*\*\ (.*) ]]; then
            current_type="${BASH_REMATCH[1]}"
        elif [[ -n "$current_loop" ]]; then
            # Accumulate section text for description matching
            section_text+="$line"$'\n'
        fi
    done < "$IDEAS_FILE"

    # Check the last section
    if [[ -n "$current_loop" && -n "$current_title" ]]; then
        _check_and_print_match "$pattern" "$current_loop" "$current_title" "$current_type" "$section_text" && found=true
    fi

    if [[ "$found" == "false" ]]; then
        echo "  No ideas matching '$pattern' found."
    fi
    echo ""
}

# Internal: check if a section matches the pattern and print result
_check_and_print_match() {
    local pattern="$1" loop="$2" title="$3" type="$4" text="$5"
    local matched_in=""

    # Check title match
    if echo "$title" | grep -qi "$pattern" 2>/dev/null; then
        matched_in="title"
    fi

    # Check description/body match
    if echo "$text" | grep -qi "$pattern" 2>/dev/null; then
        if [[ -n "$matched_in" ]]; then
            matched_in="title+description"
        else
            matched_in="description"
        fi
    fi

    if [[ -z "$matched_in" ]]; then
        return 1
    fi

    # Print the match
    printf "  Loop %-4s %s" "$loop" "$title"
    echo -e "  ${DIM}(matched in $matched_in)${NC}"

    # Show a snippet from description if matched there
    if [[ "$matched_in" == *"description"* ]]; then
        local snippet
        snippet=$(echo "$text" | grep -i "$pattern" 2>/dev/null | head -1)
        if [[ -n "$snippet" ]]; then
            # Trim and truncate snippet
            snippet=$(echo "$snippet" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
            if [[ ${#snippet} -gt 80 ]]; then
                snippet="${snippet:0:77}..."
            fi
            echo -e "         ${DIM}> $snippet${NC}"
        fi
    fi

    return 0
}

# Extract idea title for a given loop number
# Returns the title on stdout, or empty string if not found
get_idea_title() {
    local loop_num="$1"

    if [[ ! -f "$IDEAS_FILE" ]]; then
        return 1
    fi

    local in_section=false

    while IFS= read -r line; do
        if [[ "$line" =~ ^LOOP\ ${loop_num}\ WINNING\ IDEA ]]; then
            in_section=true
            continue
        fi
        if [[ "$in_section" == "true" ]]; then
            if [[ "$line" =~ ^\*\*Title:\*\*\ (.*) ]]; then
                echo "${BASH_REMATCH[1]}"
                return 0
            fi
            # Stop at next loop header
            if [[ "$line" =~ ^LOOP\ [0-9]+\ WINNING\ IDEA ]]; then
                break
            fi
        fi
    done < "$IDEAS_FILE"

    return 1
}

# Convert an idea title to a valid git branch name
sanitize_branch_name() {
    local title="$1"
    local sanitized

    # Lowercase, replace spaces/special chars with hyphens, strip leading/trailing hyphens
    sanitized=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')

    # Truncate to 50 chars to keep branch names reasonable
    if [[ ${#sanitized} -gt 50 ]]; then
        sanitized="${sanitized:0:50}"
        sanitized="${sanitized%-}"
    fi

    echo "$sanitized"
}

case "${1:-}" in
    list)
        list_ideas
        ;;
    show)
        if [[ -z "${2:-}" ]]; then
            echo "Usage: korero ideas show <loop_number>"
            exit 1
        fi
        show_idea "$2"
        ;;
    search)
        if [[ -z "${2:-}" ]]; then
            echo "Usage: korero ideas search <pattern>"
            exit 1
        fi
        search_ideas "$2"
        ;;
    --help|-h|help)
        show_usage
        ;;
    *)
        show_usage
        exit 1
        ;;
esac
