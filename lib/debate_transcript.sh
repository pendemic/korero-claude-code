#!/usr/bin/env bash
# debate_transcript.sh — Debate transcript generation for Korero loops
#
# Generates and manages timestamped debate transcripts in .korero/debates/
# Each loop's multi-agent debate is recorded as a markdown file.

KORERO_DIR="${KORERO_DIR:-.korero}"
DEBATES_DIR="$KORERO_DIR/debates"

# Initialize debate transcript for a loop
# Creates the file with header metadata
# Arguments: loop_number
init_debate_transcript() {
    local loop_num="$1"
    local output_file="$DEBATES_DIR/loop_${loop_num}.md"
    local timestamp

    mkdir -p "$DEBATES_DIR"

    timestamp=$(date "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")

    cat > "$output_file" << EOF
# Debate Transcript: Loop ${loop_num}

**Date:** ${timestamp}
**Status:** In Progress

---

EOF

    echo "$output_file"
}

# Append a named section to a loop's transcript
# Arguments: loop_number, section_name, content
append_transcript_section() {
    local loop_num="$1"
    local section_name="$2"
    local content="$3"
    local output_file="$DEBATES_DIR/loop_${loop_num}.md"

    if [[ ! -f "$output_file" ]]; then
        init_debate_transcript "$loop_num" > /dev/null
    fi

    cat >> "$output_file" << EOF

## ${section_name}

${content}
EOF
}

# Finalize a transcript — mark as complete
# Arguments: loop_number, winner_title (optional)
finalize_debate_transcript() {
    local loop_num="$1"
    local winner="${2:-}"
    local output_file="$DEBATES_DIR/loop_${loop_num}.md"

    if [[ ! -f "$output_file" ]]; then
        return 1
    fi

    # Replace "In Progress" with "Complete"
    sed -i 's/\*\*Status:\*\* In Progress/**Status:** Complete/' "$output_file"

    if [[ -n "$winner" ]]; then
        sed -i "/^\*\*Status:\*\*/a **Winner:** ${winner}" "$output_file"
    fi
}

# Get the latest debate transcript loop number
# Returns: loop number on stdout, or empty if none exist
get_latest_debate_loop() {
    if [[ ! -d "$DEBATES_DIR" ]]; then
        echo ""
        return 0
    fi

    local latest
    latest=$(ls -1 "$DEBATES_DIR"/loop_*.md 2>/dev/null | sort -V | tail -1)

    if [[ -z "$latest" ]]; then
        echo ""
        return 0
    fi

    # Extract loop number from filename
    basename "$latest" | sed 's/loop_//' | sed 's/\.md//'
}

# Show a debate transcript
# Arguments: loop_number (or "latest")
show_debate_transcript() {
    local loop_num="$1"

    if [[ "$loop_num" == "latest" ]]; then
        loop_num=$(get_latest_debate_loop)
        if [[ -z "$loop_num" ]]; then
            echo "No debate transcripts found."
            echo "Run Korero in idea or coding mode to generate debates."
            return 1
        fi
    fi

    local transcript_file="$DEBATES_DIR/loop_${loop_num}.md"

    if [[ ! -f "$transcript_file" ]]; then
        echo "No debate transcript found for loop $loop_num."
        echo ""
        echo "Available transcripts:"
        list_debate_transcripts
        return 1
    fi

    cat "$transcript_file"
}

# List available debate transcripts
list_debate_transcripts() {
    if [[ ! -d "$DEBATES_DIR" ]]; then
        echo "  No debates directory found."
        return 0
    fi

    local count=0
    for f in "$DEBATES_DIR"/loop_*.md; do
        [[ -f "$f" ]] || continue
        local num
        num=$(basename "$f" | sed 's/loop_//' | sed 's/\.md//')
        local status
        status=$(grep -m1 "Status:" "$f" 2>/dev/null | sed 's/.*\*\* //')
        printf "  Loop %-6s %s\n" "$num" "$status"
        ((count++))
    done

    if [[ $count -eq 0 ]]; then
        echo "  No debate transcripts found."
    fi
}

# ===== Debate Statistics (Loop 35) =====

# Aggregate statistics from all debate transcripts in .korero/debates/
# Returns: JSON object on stdout, or message + return 1 if no debates
# Fields: total, completed, timed_out, claude_wins, codex_wins,
#         claude_pct, codex_pct, avg_confidence, high_conf_count, low_conf_count
get_debate_stats() {
    local debates_dir="${KORERO_DIR:-.korero}/debates"

    if [[ ! -d "$debates_dir" ]]; then
        echo "No debates found."
        return 1
    fi

    local total=0 claude_wins=0 codex_wins=0
    local confidence_sum=0 completed=0 timed_out=0
    local high_conf_count=0 low_conf_count=0

    for transcript in "$debates_dir"/loop_*.md; do
        [[ -f "$transcript" ]] || continue
        ((total++))

        # Extract winner — format: **Winner:** claude  (in Final Judgment section)
        local winner=""
        winner=$(grep -i '^\*\*Winner:\*\*' "$transcript" 2>/dev/null | head -1 | sed 's/\*\*Winner:\*\*[[:space:]]*//' | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

        if [[ "$winner" == "claude" ]]; then
            ((claude_wins++))
            ((completed++))
        elif [[ "$winner" == "codex" ]]; then
            ((codex_wins++))
            ((completed++))
        else
            ((timed_out++))
        fi

        # Extract confidence — format: **Confidence:** 85  (in Final Judgment section)
        local confidence=0
        confidence=$(grep -i '^\*\*Confidence:\*\*' "$transcript" 2>/dev/null | head -1 | sed 's/\*\*Confidence:\*\*[[:space:]]*//' | tr -d '[:space:]%' | grep -E '^[0-9]+$' || echo "0")
        confidence="${confidence:-0}"
        confidence_sum=$((confidence_sum + confidence))

        if [[ $confidence -ge 80 ]]; then
            ((high_conf_count++))
        elif [[ $confidence -gt 0 && $confidence -lt 60 ]]; then
            ((low_conf_count++))
        fi
    done

    if [[ $total -eq 0 ]]; then
        printf '{"total":0,"completed":0,"timed_out":0,"claude_wins":0,"codex_wins":0,"claude_pct":0,"codex_pct":0,"avg_confidence":0,"high_conf_count":0,"low_conf_count":0}\n'
        return 0
    fi

    local claude_pct=0 codex_pct=0 avg_confidence=0
    if [[ $completed -gt 0 ]]; then
        claude_pct=$((claude_wins * 100 / completed))
        codex_pct=$((codex_wins * 100 / completed))
    fi
    avg_confidence=$((confidence_sum / total))

    printf '{"total":%d,"completed":%d,"timed_out":%d,"claude_wins":%d,"codex_wins":%d,"claude_pct":%d,"codex_pct":%d,"avg_confidence":%d,"high_conf_count":%d,"low_conf_count":%d}\n' \
        "$total" "$completed" "$timed_out" \
        "$claude_wins" "$codex_wins" \
        "$claude_pct" "$codex_pct" \
        "$avg_confidence" "$high_conf_count" "$low_conf_count"
}

# Display formatted debate statistics dashboard
# Reads debate transcripts from .korero/debates/ and displays aggregate metrics
display_debate_stats() {
    local stats
    stats=$(get_debate_stats)
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "$stats"
        return 1
    fi

    # Parse JSON fields (without requiring jq)
    local total completed timed_out claude_wins codex_wins
    local claude_pct codex_pct avg_confidence high_conf_count low_conf_count

    if command -v jq &>/dev/null; then
        total=$(echo "$stats"         | jq -r '.total')
        completed=$(echo "$stats"     | jq -r '.completed')
        timed_out=$(echo "$stats"     | jq -r '.timed_out')
        claude_wins=$(echo "$stats"   | jq -r '.claude_wins')
        codex_wins=$(echo "$stats"    | jq -r '.codex_wins')
        claude_pct=$(echo "$stats"    | jq -r '.claude_pct')
        codex_pct=$(echo "$stats"     | jq -r '.codex_pct')
        avg_confidence=$(echo "$stats"| jq -r '.avg_confidence')
        high_conf_count=$(echo "$stats"| jq -r '.high_conf_count')
        low_conf_count=$(echo "$stats" | jq -r '.low_conf_count')
    else
        # Portable fallback: parse compact JSON with sed
        total=$(echo "$stats"         | sed 's/.*"total":\([0-9]*\).*/\1/')
        completed=$(echo "$stats"     | sed 's/.*"completed":\([0-9]*\).*/\1/')
        timed_out=$(echo "$stats"     | sed 's/.*"timed_out":\([0-9]*\).*/\1/')
        claude_wins=$(echo "$stats"   | sed 's/.*"claude_wins":\([0-9]*\).*/\1/')
        codex_wins=$(echo "$stats"    | sed 's/.*"codex_wins":\([0-9]*\).*/\1/')
        claude_pct=$(echo "$stats"    | sed 's/.*"claude_pct":\([0-9]*\).*/\1/')
        codex_pct=$(echo "$stats"     | sed 's/.*"codex_pct":\([0-9]*\).*/\1/')
        avg_confidence=$(echo "$stats"| sed 's/.*"avg_confidence":\([0-9]*\).*/\1/')
        high_conf_count=$(echo "$stats"| sed 's/.*"high_conf_count":\([0-9]*\).*/\1/')
        low_conf_count=$(echo "$stats" | sed 's/.*"low_conf_count":\([0-9]*\).*/\1/')
    fi

    if [[ "${total:-0}" -eq 0 ]]; then
        echo ""
        echo "No debate transcripts found. Run Korero in heavy mode to generate debates."
        return 0
    fi

    # Build win distribution bars (20 chars wide)
    local claude_bar_len=$(( ${claude_pct:-0} / 5 ))
    local codex_bar_len=$(( ${codex_pct:-0} / 5 ))
    local claude_bar="" codex_bar=""
    local i
    for (( i=0; i<claude_bar_len; i++ )); do claude_bar="${claude_bar}█"; done
    for (( i=claude_bar_len; i<20; i++ )); do claude_bar="${claude_bar}░"; done
    for (( i=0; i<codex_bar_len; i++ )); do codex_bar="${codex_bar}█"; done
    for (( i=codex_bar_len; i<20; i++ )); do codex_bar="${codex_bar}░"; done

    local completed_pct=0 timed_out_pct=0
    [[ $total -gt 0 ]] && completed_pct=$(( completed * 100 / total ))
    [[ $total -gt 0 ]] && timed_out_pct=$(( timed_out * 100 / total ))

    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "              CROSS-AI DEBATE STATISTICS"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    printf "Total Debates: %d\n" "$total"
    printf "Completed: %d (%d%%)  |  Timed Out: %d (%d%%)\n" \
        "$completed" "$completed_pct" "$timed_out" "$timed_out_pct"
    echo ""
    echo "WIN DISTRIBUTION"
    printf "  Claude: %3d (%2d%%)  %s\n" "$claude_wins" "$claude_pct" "$claude_bar"
    printf "  Codex:  %3d (%2d%%)  %s\n" "$codex_wins"  "$codex_pct"  "$codex_bar"
    echo ""
    echo "CONFIDENCE ANALYSIS"
    printf "  Average Confidence:     %d%%\n" "$avg_confidence"
    printf "  High Confidence (≥80%%): %d debates\n" "$high_conf_count"
    printf "  Low Confidence  (<60%%): %d debates\n" "$low_conf_count"
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo ""
}

export -f init_debate_transcript
export -f append_transcript_section
export -f finalize_debate_transcript
export -f get_latest_debate_loop
export -f show_debate_transcript
export -f list_debate_transcripts
export -f get_debate_stats
export -f display_debate_stats
