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

export -f init_debate_transcript
export -f append_transcript_section
export -f finalize_debate_transcript
export -f get_latest_debate_loop
export -f show_debate_transcript
export -f list_debate_transcripts
