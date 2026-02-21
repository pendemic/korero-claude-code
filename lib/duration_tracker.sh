#!/usr/bin/env bash

# duration_tracker.sh - Loop duration tracking and display
# Tracks current, last, and rolling average loop execution times.

# Format seconds into human-readable duration
# Usage: format_duration <seconds>
format_duration() {
    local total_seconds="${1:-0}"
    total_seconds="${total_seconds//[^0-9]/}"
    total_seconds="${total_seconds:-0}"

    if [[ $total_seconds -lt 60 ]]; then
        echo "${total_seconds}s"
    elif [[ $total_seconds -lt 3600 ]]; then
        local mins=$((total_seconds / 60))
        local secs=$((total_seconds % 60))
        echo "${mins}m ${secs}s"
    else
        local hours=$((total_seconds / 3600))
        local mins=$(( (total_seconds % 3600) / 60 ))
        echo "${hours}h ${mins}m"
    fi
}

# Record loop start time
# Usage: record_loop_start <korero_dir>
record_loop_start() {
    local korero_dir="${1:-.korero}"
    date +%s > "$korero_dir/.loop_start_time"
}

# Record loop end time and compute duration
# Usage: record_loop_end <korero_dir>
# Appends duration to history file
record_loop_end() {
    local korero_dir="${1:-.korero}"
    local start_file="$korero_dir/.loop_start_time"
    local history_file="$korero_dir/.duration_history"

    if [[ ! -f "$start_file" ]]; then
        return 0
    fi

    local start_time
    start_time=$(cat "$start_file" 2>/dev/null | tr -d '[:space:]')
    start_time="${start_time:-0}"
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Store last duration
    echo "$duration" > "$korero_dir/.last_loop_duration"

    # Append to history (keep last 10)
    echo "$duration" >> "$history_file"
    if [[ -f "$history_file" ]]; then
        local line_count
        line_count=$(wc -l < "$history_file" | tr -d '[:space:]')
        if [[ $line_count -gt 10 ]]; then
            local tail_lines=$((line_count - 10))
            tail -n 10 "$history_file" > "$history_file.tmp"
            mv "$history_file.tmp" "$history_file"
        fi
    fi

    # Clean up start time
    rm -f "$start_file"
}

# Get last loop duration
# Usage: get_last_duration <korero_dir>
get_last_duration() {
    local korero_dir="${1:-.korero}"
    local dur_file="$korero_dir/.last_loop_duration"

    if [[ ! -f "$dur_file" ]]; then
        echo "0"
        return 0
    fi

    local dur
    dur=$(cat "$dur_file" 2>/dev/null | tr -d '[:space:]')
    echo "${dur:-0}"
}

# Get rolling average of last N loop durations
# Usage: get_average_duration <korero_dir> [count]
get_average_duration() {
    local korero_dir="${1:-.korero}"
    local count="${2:-10}"
    local history_file="$korero_dir/.duration_history"

    if [[ ! -f "$history_file" ]]; then
        echo "0"
        return 0
    fi

    local sum=0
    local num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        local val="${line//[^0-9]/}"
        val="${val:-0}"
        sum=$((sum + val))
        num=$((num + 1))
    done < <(tail -n "$count" "$history_file")

    if [[ $num -eq 0 ]]; then
        echo "0"
        return 0
    fi

    echo $((sum / num))
}

# Get current loop elapsed time (if loop is running)
# Usage: get_elapsed_time <korero_dir>
get_elapsed_time() {
    local korero_dir="${1:-.korero}"
    local start_file="$korero_dir/.loop_start_time"

    if [[ ! -f "$start_file" ]]; then
        echo "0"
        return 0
    fi

    local start_time
    start_time=$(cat "$start_file" 2>/dev/null | tr -d '[:space:]')
    start_time="${start_time:-0}"
    local now
    now=$(date +%s)
    echo $((now - start_time))
}

# Render duration display widget for monitor
# Usage: render_duration_widget <korero_dir>
render_duration_widget() {
    local korero_dir="${1:-.korero}"

    local elapsed
    elapsed=$(get_elapsed_time "$korero_dir")
    local last
    last=$(get_last_duration "$korero_dir")
    local avg
    avg=$(get_average_duration "$korero_dir")

    echo "── Loop Timing ──"
    if [[ -f "$korero_dir/.loop_start_time" ]]; then
        printf "  Current:  %s (running)\n" "$(format_duration "$elapsed")"
    else
        printf "  Current:  %s\n" "idle"
    fi
    printf "  Last:     %s\n" "$(format_duration "$last")"
    printf "  Average:  %s\n" "$(format_duration "$avg")"
}

export -f format_duration
export -f record_loop_start
export -f record_loop_end
export -f get_last_duration
export -f get_average_duration
export -f get_elapsed_time
export -f render_duration_widget
