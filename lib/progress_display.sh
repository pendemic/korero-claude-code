#!/usr/bin/env bash
# lib/progress_display.sh — Loop progress visualization
# Provides functions for rendering progress bars and phase indicators

# Render a text-based progress bar
# Usage: render_progress_bar 75
render_progress_bar() {
    local percent="${1:-0}"
    local width="${2:-30}"

    # Clamp to 0-100
    [[ $percent -lt 0 ]] && percent=0
    [[ $percent -gt 100 ]] && percent=100

    local filled=$((percent * width / 100))
    local empty=$((width - filled))

    printf "["
    if [[ $filled -gt 0 ]]; then
        printf '%*s' "$filled" '' | tr ' ' '#'
    fi
    if [[ $empty -gt 0 ]]; then
        printf '%*s' "$empty" '' | tr ' ' '-'
    fi
    printf "] %d%%" "$percent"
}

# Render phase list with current phase highlighted
# Usage: render_phase_list "DEBATE"
render_phase_list() {
    local current_phase="$1"
    local phases=("GENERATION" "EVALUATION" "DEBATE" "IMPLEMENTATION")
    local passed=true

    for phase in "${phases[@]}"; do
        if [[ "$phase" == "$current_phase" ]]; then
            echo "  > $phase (in progress)"
            passed=false
        elif [[ "$passed" == "true" ]]; then
            echo "  * $phase (done)"
        else
            echo "  - $phase"
        fi
    done

    if [[ "$current_phase" == "COMPLETE" ]]; then
        for phase in "${phases[@]}"; do
            echo "  * $phase (done)"
        done
    fi
}

# Get progress percentage for a phase
get_phase_progress() {
    local phase="$1"
    case "$phase" in
        GENERATION)     echo 25 ;;
        EVALUATION)     echo 50 ;;
        DEBATE)         echo 75 ;;
        IMPLEMENTATION|DOCUMENTATION|COMPLETE) echo 100 ;;
        *)              echo 0 ;;
    esac
}

# Extract current phase from Claude output
extract_loop_phase() {
    local output_file="$1"

    if [[ ! -f "$output_file" ]]; then
        echo "GENERATION"
        return
    fi

    local content
    content=$(cat "$output_file" 2>/dev/null || echo "")

    if echo "$content" | grep -q "PHASE_COMPLETED: IMPLEMENTATION\|PHASE_COMPLETED: DOCUMENTATION" 2>/dev/null; then
        echo "COMPLETE"
    elif echo "$content" | grep -q "PHASE_COMPLETED: DEBATE" 2>/dev/null; then
        echo "IMPLEMENTATION"
    elif echo "$content" | grep -q "PHASE_COMPLETED: EVALUATION" 2>/dev/null; then
        echo "DEBATE"
    elif echo "$content" | grep -q "PHASE_COMPLETED: GENERATION" 2>/dev/null; then
        echo "EVALUATION"
    else
        echo "GENERATION"
    fi
}

# Render the full progress widget from status.json
render_progress_widget() {
    local status_file="${1:-.korero/status.json}"

    if [[ ! -f "$status_file" ]]; then
        echo "No active loop"
        return 1
    fi

    local loop
    loop=$(jq -r '.loop // 0' "$status_file" 2>/dev/null || echo "0")
    local phase
    phase=$(jq -r '.phase // "GENERATION"' "$status_file" 2>/dev/null || echo "GENERATION")
    local progress
    progress=$(jq -r '.phase_progress // 0' "$status_file" 2>/dev/null || echo "0")

    echo "--- Loop $loop Progress ---"
    echo ""
    render_progress_bar "$progress"
    echo ""
    echo ""
    render_phase_list "$phase"
    echo ""
    echo "---------------------------"
}
