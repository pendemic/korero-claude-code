#!/usr/bin/env bash
# korero_ideas.sh — Browse and search winning ideas from ideation loops

set -euo pipefail

KORERO_DIR=".korero"
IDEAS_FILE="$KORERO_DIR/IDEAS.md"

# Colors
if [[ -t 1 ]]; then
    BOLD='\033[1m'
    NC='\033[0m'
else
    BOLD='' NC=''
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

        # Stop at the next loop header or end separator
        if [[ "$in_section" == "true" ]]; then
            if [[ "$line" =~ ^LOOP\ [0-9]+\ WINNING\ IDEA ]] || [[ "$line" == "======="* && "$line" != *"LOOP"* ]]; then
                # Check if it's just a separator for this section
                if [[ "$line" =~ ^LOOP ]]; then
                    break
                fi
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

    local current_loop="" current_title="" found=false

    while IFS= read -r line; do
        if [[ "$line" =~ ^LOOP\ ([0-9]+)\ WINNING\ IDEA ]]; then
            current_loop="${BASH_REMATCH[1]}"
            current_title=""
        elif [[ "$line" =~ ^\*\*Title:\*\*\ (.*) ]]; then
            current_title="${BASH_REMATCH[1]}"
        fi

        # Check if the line matches the search pattern (case-insensitive)
        if [[ -n "$current_loop" && -n "$current_title" ]]; then
            if echo "$current_title" | grep -qi "$pattern" 2>/dev/null; then
                printf "  Loop %-4s %s\n" "$current_loop" "$current_title"
                found=true
                current_title=""  # Prevent duplicate matches
            fi
        fi
    done < "$IDEAS_FILE"

    if [[ "$found" == "false" ]]; then
        echo "  No ideas matching '$pattern' found."
    fi
    echo ""
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
