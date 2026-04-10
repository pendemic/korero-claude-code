#!/usr/bin/env bash

# cross_ai_debate.sh — Cross-AI debate orchestrator for Korero heavy modes
#
# After Claude and Codex produce parallel proposals, this module orchestrates
# a 3-round debate: mutual critique → defense → final judgment.
#
# Round 1 (parallel): Claude critiques Codex, Codex critiques Claude
# Round 2 (parallel): Claude defends vs Codex's critique, Codex defends vs Claude's
# Round 3 (Claude only): Claude evaluates all artifacts and selects the winner
#
# Depends on: lib/codex_adapter.sh, lib/debate_transcript.sh, lib/timeout_utils.sh

KORERO_DIR="${KORERO_DIR:-.korero}"
DEBATE_RESULT_FILE="$KORERO_DIR/.debate_result"

# ANSI color codes for progress indicators
DEBATE_BLUE='\033[0;34m'
DEBATE_GREEN='\033[0;32m'
DEBATE_YELLOW='\033[1;33m'
DEBATE_CYAN='\033[0;36m'
DEBATE_RED='\033[0;31m'
DEBATE_NC='\033[0m'
DEBATE_BOLD='\033[1m'

# Get icon for a debate phase
# Arguments:
#   $1 (phase) - Phase name: "proposal", "critique", "defense", "judgment", "complete", "error"
# Returns: phase icon character on stdout
get_phase_icon() {
    local phase="$1"
    case "$phase" in
        proposal)  echo "[>]" ;;
        critique)  echo "[*]" ;;
        defense)   echo "[#]" ;;
        judgment)  echo "[=]" ;;
        complete)  echo "[+]" ;;
        error)     echo "[!]" ;;
        waiting)   echo "[.]" ;;
        *)         echo "[-]" ;;
    esac
}

# Show streaming progress indicator for debate phases
# Arguments:
#   $1 (phase)   - Phase name (proposal, critique, defense, judgment)
#   $2 (status)  - Status: "start", "end", "error"
#   $3 (detail)  - Optional detail message
#   $4 (elapsed) - Optional elapsed time in seconds
# Output: Colorized progress line to stderr
show_debate_progress() {
    local phase="$1"
    local status="$2"
    local detail="${3:-}"
    local elapsed="${4:-}"

    local icon
    icon=$(get_phase_icon "$phase")

    local color="$DEBATE_CYAN"
    local status_text=""

    case "$status" in
        start)
            color="$DEBATE_YELLOW"
            status_text="IN PROGRESS"
            ;;
        end)
            color="$DEBATE_GREEN"
            icon=$(get_phase_icon "complete")
            status_text="DONE"
            ;;
        error)
            color="$DEBATE_RED"
            icon=$(get_phase_icon "error")
            status_text="FAILED"
            ;;
    esac

    local time_str=""
    if [[ -n "$elapsed" ]]; then
        time_str=" (${elapsed}s)"
    fi

    local detail_str=""
    if [[ -n "$detail" ]]; then
        detail_str=" — $detail"
    fi

    echo -e "${color}${icon} ${DEBATE_BOLD}${phase^}${DEBATE_NC}${color} [${status_text}]${time_str}${detail_str}${DEBATE_NC}" >&2
}

# Show debate completion summary with winner information
# Arguments:
#   $1 (winner)     - "claude" or "codex"
#   $2 (title)      - Winning idea title
#   $3 (confidence) - Confidence score (0-100)
#   $4 (total_time) - Total debate time in seconds
# Output: Formatted summary to stderr
show_debate_summary() {
    local winner="$1"
    local title="${2:-}"
    local confidence="${3:-}"
    local total_time="${4:-}"

    echo -e "" >&2
    echo -e "${DEBATE_CYAN}╔══════════════════════════════════════════════════╗${DEBATE_NC}" >&2
    echo -e "${DEBATE_CYAN}║  ${DEBATE_BOLD}DEBATE COMPLETE${DEBATE_NC}${DEBATE_CYAN}                                 ║${DEBATE_NC}" >&2
    echo -e "${DEBATE_CYAN}╠══════════════════════════════════════════════════╣${DEBATE_NC}" >&2

    local winner_display
    if [[ "$winner" == "claude" ]]; then
        winner_display="${DEBATE_BLUE}Claude${DEBATE_NC}"
    else
        winner_display="${DEBATE_GREEN}Codex${DEBATE_NC}"
    fi

    echo -e "${DEBATE_CYAN}║${DEBATE_NC}  Winner:     ${winner_display}" >&2
    if [[ -n "$title" ]]; then
        echo -e "${DEBATE_CYAN}║${DEBATE_NC}  Idea:       ${title}" >&2
    fi
    if [[ -n "$confidence" ]]; then
        echo -e "${DEBATE_CYAN}║${DEBATE_NC}  Confidence: ${confidence}%" >&2
    fi
    if [[ -n "$total_time" ]]; then
        echo -e "${DEBATE_CYAN}║${DEBATE_NC}  Duration:   ${total_time}s" >&2
    fi

    echo -e "${DEBATE_CYAN}╚══════════════════════════════════════════════════╝${DEBATE_NC}" >&2
}

# Show round-level progress bar for debate phases
# Arguments:
#   $1 (round)        - Current round number (1-based)
#   $2 (phase)        - Phase name (e.g., "Critique", "Defense", "Judgment")
#   $3 (total_rounds) - Total number of rounds (default: 3)
# Output: Progress bar to stderr with carriage return for in-place update
show_debate_round_progress() {
    local round="$1"
    local phase="$2"
    local total_rounds="${3:-3}"

    # Build progress bar (10 segments)
    local filled=$((round * 10 / total_rounds))
    local empty=$((10 - filled))

    local bar="["
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    bar+="]"

    printf "\r%s Round %d/%d: %s    " "$bar" "$round" "$total_rounds" "$phase" >&2
}

# Show debate completion progress bar
# Output: Full progress bar with "Debate complete!" to stderr
complete_debate_round_progress() {
    printf "\r[██████████] Debate complete!          \n" >&2
}

# Calculate argument length ratio between two proposal files
# Arguments:
#   $1 (claude_file) - Path to Claude's proposal
#   $2 (codex_file)  - Path to Codex's proposal
# Returns: ratio as decimal on stdout (e.g., "0.85"), or "0" on error
calculate_length_ratio() {
    local claude_file="$1"
    local codex_file="$2"

    local claude_words codex_words
    if [[ -f "$claude_file" ]]; then
        claude_words=$(wc -w < "$claude_file" 2>/dev/null | tr -d '[:space:]' || echo "0")
    else
        claude_words="0"
    fi
    if [[ -f "$codex_file" ]]; then
        codex_words=$(wc -w < "$codex_file" 2>/dev/null | tr -d '[:space:]' || echo "0")
    else
        codex_words="0"
    fi

    claude_words="${claude_words:-0}"
    codex_words="${codex_words:-0}"

    if [[ "$codex_words" -eq 0 ]]; then
        echo "0"
        return
    fi

    if command -v bc &>/dev/null; then
        echo "scale=2; $claude_words / $codex_words" | bc -l 2>/dev/null || echo "1.00"
    else
        echo "1.00"
    fi
}

# Calculate counter-argument coverage between a proposal and its critique
# Arguments:
#   $1 (proposal_file) - Path to the proposal being critiqued
#   $2 (critique_file) - Path to the critique
# Returns: percentage (0-100) on stdout
calculate_coverage() {
    local proposal_file="$1"
    local critique_file="$2"

    [[ ! -f "$proposal_file" || ! -f "$critique_file" ]] && echo "0" && return

    # Extract significant terms (4+ letters) from proposal
    local key_terms
    key_terms=$(grep -oE '[A-Za-z]{4,}' "$proposal_file" 2>/dev/null | sort -u | head -20)

    local total_terms=0
    local matched_terms=0

    while IFS= read -r term; do
        [[ -z "$term" ]] && continue
        total_terms=$((total_terms + 1))
        if grep -qi "$term" "$critique_file" 2>/dev/null; then
            matched_terms=$((matched_terms + 1))
        fi
    done <<< "$key_terms"

    if [[ "$total_terms" -eq 0 ]]; then
        echo "0"
        return
    fi

    echo $(( (matched_terms * 100) / total_terms ))
}

# Calculate verdict confidence from judgment text
# Arguments:
#   $1 (judgment_file) - Path to the judgment output
# Returns: confidence score (0-100) on stdout
calculate_verdict_confidence() {
    local judgment_file="$1"
    [[ ! -f "$judgment_file" ]] && echo "50" && return

    local content
    content=$(cat "$judgment_file" 2>/dev/null || echo "")

    if echo "$content" | grep -qiE '(clearly superior|definitive|obvious choice|strong winner)'; then
        echo "90"
    elif echo "$content" | grep -qiE '(better overall|solid advantage|preferred|convincingly)'; then
        echo "75"
    elif echo "$content" | grep -qiE '(slight edge|marginal|close call|narrow|minor advantage)'; then
        echo "40"
    elif echo "$content" | grep -qiE '(tie|equal|cannot decide|both strong|neither|draw)'; then
        echo "20"
    else
        echo "50"
    fi
}

# Calculate composite debate quality score (0-100)
# Arguments:
#   $1 (claude_proposal_file)  - Path to Claude's proposal
#   $2 (codex_proposal_file)   - Path to Codex's proposal
#   $3 (claude_critique_file)  - Path to Claude's critique of Codex
#   $4 (codex_critique_file)   - Path to Codex's critique of Claude
#   $5 (judgment_file)         - Path to the final judgment
# Returns: quality score (0-100) on stdout
calculate_debate_quality() {
    local claude_proposal="$1"
    local codex_proposal="$2"
    local claude_critique="$3"
    local codex_critique="$4"
    local judgment="$5"

    local length_ratio coverage_claude coverage_codex verdict_conf

    length_ratio=$(calculate_length_ratio "$claude_proposal" "$codex_proposal")
    coverage_claude=$(calculate_coverage "$codex_proposal" "$claude_critique")
    coverage_codex=$(calculate_coverage "$claude_proposal" "$codex_critique")
    verdict_conf=$(calculate_verdict_confidence "$judgment")

    # Normalize length ratio to score (balanced = 100, extreme deviation = lower)
    local length_score=100
    if command -v bc &>/dev/null; then
        local is_balanced
        is_balanced=$(echo "$length_ratio >= 0.7 && $length_ratio <= 1.3" | bc -l 2>/dev/null || echo "0")
        local is_ok
        is_ok=$(echo "$length_ratio >= 0.5 && $length_ratio <= 1.5" | bc -l 2>/dev/null || echo "0")
        if [[ "$is_balanced" -eq 1 ]]; then
            length_score=100
        elif [[ "$is_ok" -eq 1 ]]; then
            length_score=70
        else
            length_score=40
        fi
    fi

    local avg_coverage=$(( (coverage_claude + coverage_codex) / 2 ))

    # Weighted composite: 30% length, 40% coverage, 30% confidence
    local quality_score
    quality_score=$(( (length_score * 30 + avg_coverage * 40 + verdict_conf * 30) / 100 ))

    echo "$quality_score"
}

# Record debate quality metrics to .korero/.debate_quality.json
# Arguments:
#   $1 (loop_num)      - Loop number
#   $2 (quality_score) - Overall quality score (0-100)
#   $3 (length_ratio)  - Argument length ratio
#   $4 (coverage)      - Average counter-argument coverage
#   $5 (verdict_conf)  - Verdict confidence score
record_debate_quality() {
    local loop_num="$1"
    local quality_score="$2"
    local length_ratio="$3"
    local coverage="$4"
    local verdict_conf="$5"

    local quality_file="${KORERO_DIR:-.korero}/.debate_quality.json"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")

    if ! command -v jq &>/dev/null; then
        return 0
    fi

    if [[ ! -f "$quality_file" ]]; then
        echo '{"debates":[]}' > "$quality_file"
    fi

    local tmp_file
    tmp_file=$(mktemp)
    jq --argjson loop "$loop_num" \
       --argjson quality "$quality_score" \
       --arg ratio "$length_ratio" \
       --argjson coverage "$coverage" \
       --argjson confidence "$verdict_conf" \
       --arg ts "$timestamp" \
       '.debates += [{"loop": $loop, "quality_score": $quality, "length_ratio": $ratio, "coverage": $coverage, "verdict_confidence": $confidence, "timestamp": $ts}]' \
       "$quality_file" > "$tmp_file" 2>/dev/null && mv "$tmp_file" "$quality_file" || rm -f "$tmp_file"
}

# Locate the templates directory (installed or local)
_get_template_dir() {
    local script_dir
    script_dir="$(dirname "${BASH_SOURCE[0]}")/.."

    # Check local repo first, then installed location
    if [[ -d "$script_dir/templates/heavy_debate_prompts" ]]; then
        echo "$script_dir/templates/heavy_debate_prompts"
    elif [[ -d "$HOME/.korero/templates/heavy_debate_prompts" ]]; then
        echo "$HOME/.korero/templates/heavy_debate_prompts"
    else
        echo ""
    fi
}

# Build a critique prompt for one AI to critique the other's proposal
# Arguments:
#   $1 (own_proposal)   - Text of the critiquing AI's own proposal
#   $2 (other_proposal) - Text of the other AI's proposal to critique
#   $3 (ai_name)        - Name of the AI doing the critiquing (e.g., "Claude")
#   $4 (other_name)     - Name of the other AI (e.g., "Codex")
#   $5 (project_name)   - Project name for template substitution
# Returns: critique prompt text on stdout
build_critique_prompt() {
    local own_proposal="$1"
    local other_proposal="$2"
    local ai_name="$3"
    local other_name="$4"
    local project_name="${5:-project}"

    local template_dir
    template_dir=$(_get_template_dir)

    if [[ -n "$template_dir" && -f "$template_dir/critique.md" ]]; then
        local template
        template=$(cat "$template_dir/critique.md")
        # Substitute placeholders
        template="${template//\{AI_NAME\}/$ai_name}"
        template="${template//\{OTHER_NAME\}/$other_name}"
        template="${template//\{PROJECT_NAME\}/$project_name}"
        template="${template//\{OWN_PROPOSAL\}/$own_proposal}"
        template="${template//\{OTHER_PROPOSAL\}/$other_proposal}"
        echo "$template"
    else
        # Inline fallback if templates not found
        cat << CRITIQUE_EOF
You are $ai_name. Critically evaluate $other_name's proposal for the $project_name project.

Your proposal:
$own_proposal

$other_name's proposal:
$other_proposal

Evaluate strengths, weaknesses, feasibility, and give a verdict (STRONG/MODERATE/WEAK).
Keep under 500 words.
CRITIQUE_EOF
    fi
}

# Build a defense prompt for an AI to defend its proposal
# Arguments:
#   $1 (own_proposal) - Text of the defending AI's original proposal
#   $2 (critique)     - Text of the critique received
#   $3 (ai_name)      - Name of the defending AI
#   $4 (other_name)   - Name of the critiquing AI
#   $5 (project_name) - Project name
# Returns: defense prompt text on stdout
build_defense_prompt() {
    local own_proposal="$1"
    local critique="$2"
    local ai_name="$3"
    local other_name="${4:-opponent}"
    local project_name="${5:-project}"

    local template_dir
    template_dir=$(_get_template_dir)

    if [[ -n "$template_dir" && -f "$template_dir/defense.md" ]]; then
        local template
        template=$(cat "$template_dir/defense.md")
        template="${template//\{AI_NAME\}/$ai_name}"
        template="${template//\{OTHER_NAME\}/$other_name}"
        template="${template//\{PROJECT_NAME\}/$project_name}"
        template="${template//\{OWN_PROPOSAL\}/$own_proposal}"
        template="${template//\{CRITIQUE\}/$critique}"
        echo "$template"
    else
        cat << DEFENSE_EOF
You are $ai_name. Defend your proposal against $other_name's critique.

Your proposal:
$own_proposal

Critique from $other_name:
$critique

Address weaknesses, strengthen your case, and explain why your proposal is better.
Keep under 400 words.
DEFENSE_EOF
    fi
}

# Build the final judge prompt with all debate artifacts
# Arguments:
#   $1 (claude_proposal) - Claude's proposal text
#   $2 (codex_proposal)  - Codex's proposal text
#   $3 (claude_critique) - Claude's critique of Codex
#   $4 (codex_critique)  - Codex's critique of Claude
#   $5 (claude_defense)  - Claude's defense
#   $6 (codex_defense)   - Codex's defense
#   $7 (mode)            - "heavy-coding" or "heavy-idea"
#   $8 (project_name)    - Project name
# Returns: judge prompt text on stdout
build_judge_prompt() {
    local claude_proposal="$1"
    local codex_proposal="$2"
    local claude_critique="$3"
    local codex_critique="$4"
    local claude_defense="$5"
    local codex_defense="$6"
    local mode="${7:-heavy-coding}"
    local project_name="${8:-project}"

    # Truncate artifacts to prevent context overflow (2000 chars each)
    local max_len=2000
    claude_proposal="${claude_proposal:0:$max_len}"
    codex_proposal="${codex_proposal:0:$max_len}"
    claude_critique="${claude_critique:0:$max_len}"
    codex_critique="${codex_critique:0:$max_len}"
    claude_defense="${claude_defense:0:$max_len}"
    codex_defense="${codex_defense:0:$max_len}"

    local template_dir
    template_dir=$(_get_template_dir)

    if [[ -n "$template_dir" && -f "$template_dir/judge.md" ]]; then
        local template
        template=$(cat "$template_dir/judge.md")
        template="${template//\{PROJECT_NAME\}/$project_name}"
        template="${template//\{MODE\}/$mode}"
        template="${template//\{CLAUDE_PROPOSAL\}/$claude_proposal}"
        template="${template//\{CODEX_PROPOSAL\}/$codex_proposal}"
        template="${template//\{CLAUDE_CRITIQUE\}/$claude_critique}"
        template="${template//\{CODEX_CRITIQUE\}/$codex_critique}"
        template="${template//\{CLAUDE_DEFENSE\}/$claude_defense}"
        template="${template//\{CODEX_DEFENSE\}/$codex_defense}"
        echo "$template"
    else
        cat << JUDGE_EOF
You are judging a cross-AI debate for $project_name ($mode mode).

Claude's Proposal: $claude_proposal

Codex's Proposal: $codex_proposal

Claude critiques Codex: $claude_critique

Codex critiques Claude: $codex_critique

Claude's Defense: $claude_defense

Codex's Defense: $codex_defense

Select the winner. Output EXACTLY:
---DEBATE_VERDICT---
WINNER: [claude|codex]
TITLE: [Winning idea title]
CONFIDENCE: [0-100]
RATIONALE: [2-3 sentences]
RUNNER_UP_INSIGHT: [1 sentence]
---END_DEBATE_VERDICT---
JUDGE_EOF
    fi
}

# Parse the judge's verdict output and write structured result
# Claude's --output-format json wraps the real text in a top-level "result"
# field. Prefer jq when available, but keep a jq-free fallback so debate
# parsing still works in lighter Windows environments.
unwrap_claude_result_payload() {
    local content="$1"

    if command -v jq &>/dev/null; then
        local json_result
        json_result=$(echo "$content" | jq -r '.result // empty' 2>/dev/null || true)
        if [[ -n "$json_result" ]]; then
            printf '%s' "$json_result"
            return 0
        fi
    fi

    if [[ "$content" == *'"result":"'*
        && "$content" == *'"stop_reason"'* ]]; then
        local escaped_result
        escaped_result=$(printf '%s' "$content" | sed -n 's/.*"result":"\(.*\)","stop_reason".*/\1/p')
        if [[ -n "$escaped_result" ]]; then
            escaped_result=$(printf '%b' "$escaped_result")
            escaped_result=$(printf '%s' "$escaped_result" | sed 's/\\"/"/g')
            printf '%s' "$escaped_result"
            return 0
        fi
    fi

    printf '%s' "$content"
}

# Parse the judge's verdict output and write structured result
# Arguments:
#   $1 (judge_output_file) - Path to judge's output
#   $2 (result_file)       - Path to write result (optional, defaults to .debate_result)
# Returns: 0 on success, 1 on parse failure
parse_debate_verdict() {
    local judge_output_file="$1"
    local result_file="${2:-$DEBATE_RESULT_FILE}"

    if [[ ! -f "$judge_output_file" || ! -s "$judge_output_file" ]]; then
        # Default to Claude on parse failure
        cat > "$result_file" << DEFAULT_EOF
{
  "winner": "claude",
  "title": "Default selection (judge output missing)",
  "confidence": 50,
  "rationale": "Judge output was empty or missing. Defaulting to Claude.",
  "runner_up_insight": "N/A"
}
DEFAULT_EOF
        return 1
    fi

    local content
    content=$(cat "$judge_output_file")
    content=$(unwrap_claude_result_payload "$content")

    # Extract verdict block
    local verdict_block
    verdict_block=$(echo "$content" | sed -n '/---DEBATE_VERDICT---/,/---END_DEBATE_VERDICT---/p')

    if [[ -z "$verdict_block" ]]; then
        cat > "$result_file" << NOVERDICT_EOF
{
  "winner": "claude",
  "title": "Default selection (no verdict block found)",
  "confidence": 50,
  "rationale": "Judge did not produce a DEBATE_VERDICT block. Defaulting to Claude.",
  "runner_up_insight": "N/A"
}
NOVERDICT_EOF
        return 1
    fi

    # Parse fields from verdict block
    local winner title confidence rationale runner_up

    winner=$(echo "$verdict_block" | grep -i '^WINNER:' | head -1 | sed 's/^WINNER:[[:space:]]*//' | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]*$//')
    title=$(echo "$verdict_block" | grep -i '^TITLE:' | head -1 | sed 's/^TITLE:[[:space:]]*//' | sed 's/[[:space:]]*$//')
    confidence=$(echo "$verdict_block" | grep -i '^CONFIDENCE:' | head -1 | sed 's/^CONFIDENCE:[[:space:]]*//' | sed 's/[[:space:]]*$//' | grep -oE '^[0-9]+')
    rationale=$(echo "$verdict_block" | grep -i '^RATIONALE:' | head -1 | sed 's/^RATIONALE:[[:space:]]*//' | sed 's/[[:space:]]*$//')
    runner_up=$(echo "$verdict_block" | grep -i '^RUNNER_UP_INSIGHT:' | head -1 | sed 's/^RUNNER_UP_INSIGHT:[[:space:]]*//' | sed 's/[[:space:]]*$//')

    # Validate winner
    if [[ "$winner" != "claude" && "$winner" != "codex" ]]; then
        winner="claude"
    fi

    # Default confidence
    if [[ -z "$confidence" ]]; then
        confidence=50
    fi

    # Escape special chars for JSON
    title=$(echo "$title" | sed 's/"/\\"/g')
    rationale=$(echo "$rationale" | sed 's/"/\\"/g')
    runner_up=$(echo "$runner_up" | sed 's/"/\\"/g')

    cat > "$result_file" << RESULT_EOF
{
  "winner": "$winner",
  "title": "$title",
  "confidence": $confidence,
  "rationale": "$rationale",
  "runner_up_insight": "$runner_up"
}
RESULT_EOF

    return 0
}

# Get the winning proposal's source AI
# Reads from .korero/.debate_result
# Returns: "claude" or "codex" on stdout
get_debate_winner() {
    if [[ ! -f "$DEBATE_RESULT_FILE" ]]; then
        echo "claude"
        return 1
    fi

    local winner
    if command -v jq &>/dev/null; then
        winner=$(jq -r '.winner // "claude"' "$DEBATE_RESULT_FILE" 2>/dev/null)
    else
        winner=$(grep -o '"winner"[[:space:]]*:[[:space:]]*"[^"]*"' "$DEBATE_RESULT_FILE" | head -1 | sed 's/.*"winner"[[:space:]]*:[[:space:]]*"//' | sed 's/"//')
    fi

    echo "${winner:-claude}"
}

# Get the confidence score from the last debate result
# Returns: 0-100 integer on stdout (default 50 if missing)
get_debate_confidence() {
    local result_file="${DEBATE_RESULT_FILE:-${KORERO_DIR:-.korero}/.debate_result}"
    if [[ ! -f "$result_file" ]]; then
        echo "50"
        return 1
    fi

    local confidence
    if command -v jq &>/dev/null; then
        confidence=$(jq -r '.confidence // 50' "$result_file" 2>/dev/null || echo "50")
    else
        confidence=$(grep -o '"confidence"[[:space:]]*:[[:space:]]*[0-9]*' "$result_file" | head -1 | grep -oE '[0-9]+$')
        confidence="${confidence:-50}"
    fi
    echo "$confidence"
}

# Orchestrate a full cross-AI debate
# Runs all 3 rounds: mutual critique, defense, final judgment
# Arguments:
#   $1 (claude_proposal_file) - Path to Claude's proposal output
#   $2 (codex_proposal_file)  - Path to Codex's proposal output
#   $3 (loop_number)          - Current loop number
#   $4 (mode)                 - "heavy-coding" or "heavy-idea"
#   $5 (project_name)         - Project name for templates
#   $6 (debate_rounds)        - Number of rounds: 1 (critique only), 2 (+ defense), 3 (unused, reserved)
# Returns: 0 on success, writes to .korero/.debate_result
# Side effects: updates debate transcript via debate_transcript.sh
run_cross_ai_debate() {
    local claude_proposal_file="$1"
    local codex_proposal_file="$2"
    local loop_num="$3"
    local mode="${4:-heavy-coding}"
    local project_name="${5:-project}"
    local debate_rounds="${6:-2}"

    local timestamp
    timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
    local debate_dir="$KORERO_DIR/debates"
    mkdir -p "$debate_dir"

    # Check Codex fallback mode before starting debate
    local fallback_reason=""
    fallback_reason=$(should_fallback_to_claude 2>/dev/null) || true
    if [[ -n "$fallback_reason" ]]; then
        local fallback_mode="${CODEX_FALLBACK:-fail}"
        display_fallback_warning "$fallback_reason" "$fallback_mode"
        # In fallback mode, use Claude's proposal directly (skip debate)
        local claude_text
        claude_text=$(cat "$claude_proposal_file" 2>/dev/null || echo "")
        if command -v jq &>/dev/null; then
            local jr
            jr=$(echo "$claude_text" | jq -r '.result // empty' 2>/dev/null || true)
            if [[ -n "$jr" ]]; then claude_text="$jr"; fi
        fi
        cat > "$DEBATE_RESULT_FILE" << FALLBACK_EOF
{
  "winner": "claude",
  "title": "Claude proposal (Codex fallback: $fallback_reason)",
  "confidence": 100,
  "rationale": "Codex unavailable ($fallback_reason). Claude wins by default in fallback mode.",
  "runner_up_insight": "N/A",
  "fallback": true,
  "fallback_reason": "$fallback_reason"
}
FALLBACK_EOF
        append_transcript_section "$loop_num" "Outcome" "Claude wins by default (Codex fallback: $fallback_reason)."
        return 0
    fi

    # Read proposals
    local claude_proposal codex_proposal
    claude_proposal=$(cat "$claude_proposal_file" 2>/dev/null || echo "")
    codex_proposal=$(cat "$codex_proposal_file" 2>/dev/null || echo "")

    # Handle JSON-wrapped Claude output (extract .result field)
    if command -v jq &>/dev/null; then
        local json_result
        json_result=$(echo "$claude_proposal" | jq -r '.result // empty' 2>/dev/null || true)
        if [[ -n "$json_result" ]]; then
            claude_proposal="$json_result"
        fi
    fi

    # Validate we have proposals
    if [[ -z "$claude_proposal" && -z "$codex_proposal" ]]; then
        echo "Error: Both proposals are empty" >&2
        return 1
    fi

    # Single-AI fallback (skip debate if only one proposal)
    if [[ -z "$claude_proposal" ]]; then
        cat > "$DEBATE_RESULT_FILE" << CODEX_WIN_EOF
{
  "winner": "codex",
  "title": "Codex proposal (Claude failed)",
  "confidence": 100,
  "rationale": "Claude did not produce a proposal. Codex wins by default.",
  "runner_up_insight": "N/A"
}
CODEX_WIN_EOF
        append_transcript_section "$loop_num" "Outcome" "Codex wins by default (Claude produced no proposal)."
        return 0
    fi

    if [[ -z "$codex_proposal" ]]; then
        cat > "$DEBATE_RESULT_FILE" << CLAUDE_WIN_EOF
{
  "winner": "claude",
  "title": "Claude proposal (Codex failed)",
  "confidence": 100,
  "rationale": "Codex did not produce a proposal. Claude wins by default.",
  "runner_up_insight": "N/A"
}
CLAUDE_WIN_EOF
        append_transcript_section "$loop_num" "Outcome" "Claude wins by default (Codex produced no proposal)."
        return 0
    fi

    # Track overall debate timing
    local debate_start_time
    debate_start_time=$(date +%s)

    # === ROUND 1: MUTUAL CRITIQUE (parallel) ===
    show_debate_round_progress 1 "Critique" 3
    show_debate_progress "critique" "start" "Claude + Codex critiquing in parallel"
    log_status "INFO" "  Debate Round 1/3: Mutual critique (Claude + Codex in parallel)..."
    local round1_start
    round1_start=$(date +%s)
    local claude_critique_file="$debate_dir/claude_critique_${timestamp}.log"
    local codex_critique_file="$debate_dir/codex_critique_${timestamp}.log"

    # Build critique prompts
    local claude_critique_prompt codex_critique_prompt
    claude_critique_prompt=$(build_critique_prompt "$claude_proposal" "$codex_proposal" "Claude" "Codex" "$project_name")
    codex_critique_prompt=$(build_critique_prompt "$codex_proposal" "$claude_proposal" "Codex" "Claude" "$project_name")

    local timeout_seconds="${DEBATE_TIMEOUT_SECONDS:-300}"

    # Claude critiques Codex (background)
    local claude_critique_cmd
    declare -a CLAUDE_CRITIQUE_ARGS=("${CLAUDE_CODE_CMD:-claude}" "--output-format" "json" "-p" "$claude_critique_prompt")
    portable_timeout "${timeout_seconds}s" "${CLAUDE_CRITIQUE_ARGS[@]}" < /dev/null > "$claude_critique_file" 2>&1 &
    local claude_crit_pid=$!

    # Codex critiques Claude (background)
    build_codex_command "$codex_critique_prompt" "$mode"
    run_codex_with_prompt "${timeout_seconds}s" "$codex_critique_prompt" "${CODEX_CMD_ARGS[@]}" > "$codex_critique_file" 2>&1 &
    local codex_crit_pid=$!

    # Wait for both critiques with per-AI timing display
    run_parallel_critiques_with_timing "Critique" "$claude_crit_pid" "$codex_crit_pid" "$round1_start"
    local claude_crit_exit=$PARALLEL_CLAUDE_EXIT
    local codex_crit_exit=$PARALLEL_CODEX_EXIT
    local round1_elapsed=$PARALLEL_ELAPSED
    log_status "INFO" "  Round 1 complete — Claude critique: exit $claude_crit_exit, Codex critique: exit $codex_crit_exit"

    if [[ $claude_crit_exit -ne 0 || $codex_crit_exit -ne 0 ]]; then
        show_debate_progress "critique" "error" "Claude: exit $claude_crit_exit, Codex: exit $codex_crit_exit" "$round1_elapsed"
    else
        show_debate_progress "critique" "end" "Both critiques received" "$round1_elapsed"
    fi

    # Extract critique text
    local claude_critique_text codex_critique_text
    if [[ $claude_crit_exit -eq 0 ]]; then
        claude_critique_text=$(cat "$claude_critique_file" 2>/dev/null)
        if command -v jq &>/dev/null; then
            local json_crit
            json_crit=$(echo "$claude_critique_text" | jq -r '.result // empty' 2>/dev/null || true)
            if [[ -n "$json_crit" ]]; then
                claude_critique_text="$json_crit"
            fi
        fi
    else
        claude_critique_text="[Claude critique unavailable — execution failed]"
    fi

    if [[ $codex_crit_exit -eq 0 ]]; then
        codex_critique_text=$(extract_codex_proposal "$codex_critique_file")
        if [[ -z "$codex_critique_text" ]]; then
            codex_critique_text="[Codex critique unavailable — no output]"
        fi
    else
        codex_critique_text="[Codex critique unavailable — execution failed]"
    fi

    # Record critiques in transcript
    append_transcript_section "$loop_num" "Round 1: Claude Critiques Codex" "$claude_critique_text"
    append_transcript_section "$loop_num" "Round 1: Codex Critiques Claude" "$codex_critique_text"

    # === ROUND 2: DEFENSE (parallel, if debate_rounds >= 2) ===
    local claude_defense_text="" codex_defense_text=""

    if [[ "$debate_rounds" -ge 2 ]]; then
        show_debate_round_progress 2 "Defense" 3
        show_debate_progress "defense" "start" "Claude + Codex defending in parallel"
        log_status "INFO" "  Debate Round 2/3: Defense (Claude + Codex in parallel)..."
        local round2_start
        round2_start=$(date +%s)
        local claude_defense_file="$debate_dir/claude_defense_${timestamp}.log"
        local codex_defense_file="$debate_dir/codex_defense_${timestamp}.log"

        # Build defense prompts
        local claude_defense_prompt codex_defense_prompt
        claude_defense_prompt=$(build_defense_prompt "$claude_proposal" "$codex_critique_text" "Claude" "Codex" "$project_name")
        codex_defense_prompt=$(build_defense_prompt "$codex_proposal" "$claude_critique_text" "Codex" "Claude" "$project_name")

        # Claude defends (background)
        declare -a CLAUDE_DEFENSE_ARGS=("${CLAUDE_CODE_CMD:-claude}" "--output-format" "json" "-p" "$claude_defense_prompt")
        portable_timeout "${timeout_seconds}s" "${CLAUDE_DEFENSE_ARGS[@]}" < /dev/null > "$claude_defense_file" 2>&1 &
        local claude_def_pid=$!

        # Codex defends (background)
        build_codex_command "$codex_defense_prompt" "$mode"
        run_codex_with_prompt "${timeout_seconds}s" "$codex_defense_prompt" "${CODEX_CMD_ARGS[@]}" > "$codex_defense_file" 2>&1 &
        local codex_def_pid=$!

        # Wait for both defenses with per-AI timing display
        run_parallel_critiques_with_timing "Defense" "$claude_def_pid" "$codex_def_pid" "$round2_start"
        local claude_def_exit=$PARALLEL_CLAUDE_EXIT
        local codex_def_exit=$PARALLEL_CODEX_EXIT
        local round2_elapsed=$PARALLEL_ELAPSED
        log_status "INFO" "  Round 2 complete — Claude defense: exit $claude_def_exit, Codex defense: exit $codex_def_exit"

        # Extract defense text
        if [[ $claude_def_exit -eq 0 ]]; then
            claude_defense_text=$(cat "$claude_defense_file" 2>/dev/null)
            if command -v jq &>/dev/null; then
                local json_def
                json_def=$(echo "$claude_defense_text" | jq -r '.result // empty' 2>/dev/null || true)
                if [[ -n "$json_def" ]]; then
                    claude_defense_text="$json_def"
                fi
            fi
        else
            claude_defense_text="[Claude defense unavailable — execution failed]"
        fi

        if [[ $codex_def_exit -eq 0 ]]; then
            codex_defense_text=$(extract_codex_proposal "$codex_defense_file")
            if [[ -z "$codex_defense_text" ]]; then
                codex_defense_text="[Codex defense unavailable — no output]"
            fi
        else
            codex_defense_text="[Codex defense unavailable — execution failed]"
        fi

        if [[ $claude_def_exit -ne 0 || $codex_def_exit -ne 0 ]]; then
            show_debate_progress "defense" "error" "Claude: exit $claude_def_exit, Codex: exit $codex_def_exit" "$round2_elapsed"
        else
            show_debate_progress "defense" "end" "Both defenses received" "$round2_elapsed"
        fi

        # Record defenses in transcript
        append_transcript_section "$loop_num" "Round 2: Claude's Defense" "$claude_defense_text"
        append_transcript_section "$loop_num" "Round 2: Codex's Defense" "$codex_defense_text"
    fi

    # === ROUND 3: FINAL JUDGMENT (Claude only) ===
    show_debate_round_progress 3 "Judgment" 3
    show_debate_progress "judgment" "start" "Claude evaluating all artifacts"
    log_status "INFO" "  Debate Round 3/3: Final judgment (Claude evaluating all artifacts)..."
    local round3_start
    round3_start=$(date +%s)
    local judge_file="$debate_dir/judge_verdict_${timestamp}.log"

    local judge_prompt
    judge_prompt=$(build_judge_prompt \
        "$claude_proposal" \
        "$codex_proposal" \
        "$claude_critique_text" \
        "$codex_critique_text" \
        "$claude_defense_text" \
        "$codex_defense_text" \
        "$mode" \
        "$project_name")

    declare -a CLAUDE_JUDGE_ARGS=("${CLAUDE_CODE_CMD:-claude}" "--output-format" "json" "-p" "$judge_prompt")
    portable_timeout "${timeout_seconds}s" "${CLAUDE_JUDGE_ARGS[@]}" < /dev/null > "$judge_file" 2>&1
    local judge_exit=$?
    local round3_elapsed=$(( $(date +%s) - round3_start ))
    log_status "INFO" "  Round 3 complete — Judge exit: $judge_exit"

    if [[ $judge_exit -ne 0 ]]; then
        show_debate_progress "judgment" "error" "Judge failed with exit code $judge_exit" "$round3_elapsed"
        # Judge failed — default to Claude
        cat > "$DEBATE_RESULT_FILE" << JUDGE_FAIL_EOF
{
  "winner": "claude",
  "title": "Default selection (judge execution failed)",
  "confidence": 50,
  "rationale": "Judge round failed with exit code $judge_exit. Defaulting to Claude.",
  "runner_up_insight": "N/A"
}
JUDGE_FAIL_EOF
        append_transcript_section "$loop_num" "Final Judgment" "Judge execution failed. Claude wins by default."
        local total_elapsed=$(( $(date +%s) - debate_start_time ))
        show_debate_summary "claude" "Default selection (judge failed)" "50" "$total_elapsed"
        return 0
    fi

    show_debate_progress "judgment" "end" "Verdict received" "$round3_elapsed"

    # Parse verdict (|| true prevents set -e exit on parse failure — default verdict written)
    parse_debate_verdict "$judge_file" "$DEBATE_RESULT_FILE" || true

    # Display verdict explanation (Loop 47)
    display_verdict_explanation "$DEBATE_RESULT_FILE" 2>/dev/null || true

    # Track debate metrics for fatigue detection (Loop 45)
    local debate_confidence
    if command -v jq &>/dev/null; then
        debate_confidence=$(jq -r '.confidence // 50' "$DEBATE_RESULT_FILE" 2>/dev/null || echo 50)
    else
        debate_confidence=50
    fi
    local codex_timed_out="false"
    if command -v jq &>/dev/null; then
        codex_timed_out=$(jq -r '.codex_timed_out // false' "$DEBATE_RESULT_FILE" 2>/dev/null || echo false)
    fi
    track_debate_metrics "$debate_confidence" "$codex_timed_out" "false" 2>/dev/null || true
    # Check for fatigue every 3 loops
    if [[ $(( loop_num % 3 )) -eq 0 ]]; then
        analyze_debate_fatigue 5 2>/dev/null || true
    fi

    # Calculate and record debate quality metrics
    local quality_score length_ratio coverage verdict_conf_score
    quality_score=$(calculate_debate_quality \
        "$claude_proposal_file" \
        "$codex_proposal_file" \
        "${claude_critique_file:-/dev/null}" \
        "${codex_critique_file:-/dev/null}" \
        "$judge_file")
    length_ratio=$(calculate_length_ratio "$claude_proposal_file" "$codex_proposal_file")
    coverage=$(calculate_coverage "$codex_proposal_file" "${claude_critique_file:-/dev/null}")
    verdict_conf_score=$(calculate_verdict_confidence "$judge_file")
    record_debate_quality "$loop_num" "${quality_score:-0}" "${length_ratio:-1.00}" "${coverage:-0}" "${verdict_conf_score:-50}"
    log_status "INFO" "Debate quality score: ${quality_score:-0}/100"

    # Record verdict in transcript
    local winner title confidence rationale
    if command -v jq &>/dev/null; then
        winner=$(jq -r '.winner // "unknown"' "$DEBATE_RESULT_FILE" 2>/dev/null || echo "unknown")
        title=$(jq -r '.title // "unknown"' "$DEBATE_RESULT_FILE" 2>/dev/null || echo "unknown")
        confidence=$(jq -r '.confidence // 0' "$DEBATE_RESULT_FILE" 2>/dev/null || echo "0")
        rationale=$(jq -r '.rationale // ""' "$DEBATE_RESULT_FILE" 2>/dev/null || echo "")
    else
        winner=$(get_debate_winner)
        title="(jq not available)"
        confidence="N/A"
        rationale=""
    fi

    append_transcript_section "$loop_num" "Final Judgment" "**Winner:** $winner
**Title:** $title
**Confidence:** $confidence
**Rationale:** $rationale"

    # Show completion summary
    complete_debate_round_progress
    local total_elapsed=$(( $(date +%s) - debate_start_time ))
    show_debate_summary "$winner" "$title" "$confidence" "$total_elapsed"

    return 0
}

# ===== Parallel Critique Timing Display (Loop 32) =====

# Display elapsed time for each parallel AI process as it finishes
# Arguments:
#   $1 (ai_name)    - "claude" or "codex"
#   $2 (elapsed_sec) - Elapsed seconds as an integer
#   $3 (exit_code)  - Exit code of the process (0=success, other=fail)
# Output: Colorized per-AI timing line to stderr (suppressed if KORERO_QUIET=1)
display_parallel_timing() {
    local ai_name="$1"
    local elapsed_sec="${2:-0}"
    local exit_code="${3:-0}"

    # Suppress if quiet mode is set
    [[ "${KORERO_QUIET:-0}" == "1" ]] && return 0

    local color="$DEBATE_GREEN"
    local status_icon="✓"
    if [[ "$exit_code" -ne 0 ]]; then
        color="$DEBATE_RED"
        status_icon="✗"
    fi

    local ai_label
    case "$ai_name" in
        claude) ai_label="Claude" ;;
        codex)  ai_label="Codex " ;;
        *)      ai_label="$ai_name" ;;
    esac

    printf "${color}  %s %s finished in %ds${DEBATE_NC}\n" \
        "$status_icon" "$ai_label" "$elapsed_sec" >&2
}

# Run two background processes in parallel and show per-AI timing as each completes
# Uses a polling loop so timing is shown immediately when an AI finishes.
# Arguments:
#   $1 (phase)           - Phase label shown in output (e.g., "Critique", "Defense")
#   $2 (claude_pid)      - PID of the Claude background process
#   $3 (codex_pid)       - PID of the Codex background process
#   $4 (start_time)      - Unix epoch when parallel execution started
# Sets globals:
#   PARALLEL_CLAUDE_EXIT - Exit code of the Claude process
#   PARALLEL_CODEX_EXIT  - Exit code of the Codex process
#   PARALLEL_ELAPSED     - Total elapsed seconds (time of last finish)
run_parallel_critiques_with_timing() {
    local phase="$1"
    local claude_pid="$2"
    local codex_pid="$3"
    local start_time="$4"

    PARALLEL_CLAUDE_EXIT=-1
    PARALLEL_CODEX_EXIT=-1
    PARALLEL_ELAPSED=0

    local claude_done=0
    local codex_done=0
    local claude_finish_time=0
    local codex_finish_time=0

    # Poll until both processes finish
    while [[ $claude_done -eq 0 || $codex_done -eq 0 ]]; do
        local now
        now=$(date +%s)

        if [[ $claude_done -eq 0 ]] && ! kill -0 "$claude_pid" 2>/dev/null; then
            wait "$claude_pid" || PARALLEL_CLAUDE_EXIT=$?
            [[ $PARALLEL_CLAUDE_EXIT -eq -1 ]] && PARALLEL_CLAUDE_EXIT=0
            claude_finish_time=$now
            claude_done=1
            local claude_elapsed=$(( now - start_time ))
            display_parallel_timing "claude" "$claude_elapsed" "$PARALLEL_CLAUDE_EXIT"
        fi

        if [[ $codex_done -eq 0 ]] && ! kill -0 "$codex_pid" 2>/dev/null; then
            wait "$codex_pid" || PARALLEL_CODEX_EXIT=$?
            [[ $PARALLEL_CODEX_EXIT -eq -1 ]] && PARALLEL_CODEX_EXIT=0
            codex_finish_time=$now
            codex_done=1
            local codex_elapsed=$(( now - start_time ))
            display_parallel_timing "codex" "$codex_elapsed" "$PARALLEL_CODEX_EXIT"
        fi

        [[ $claude_done -eq 0 || $codex_done -eq 0 ]] && sleep 0.5
    done

    local last_finish
    if [[ $claude_finish_time -ge $codex_finish_time ]]; then
        last_finish=$claude_finish_time
    else
        last_finish=$codex_finish_time
    fi
    PARALLEL_ELAPSED=$(( last_finish - start_time ))
}

# ===== Debate Fatigue Indicator (Loop 45) =====

# Append one debate's metrics to the rolling metrics log
# Arguments: confidence (0-100), timed_out (true|false), agreed (true|false)
track_debate_metrics() {
    local confidence="${1:-50}"
    local timed_out="${2:-false}"
    local agreed="${3:-false}"
    local metrics_file="${KORERO_DIR:-.korero}/.debate_metrics"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")

    mkdir -p "$(dirname "$metrics_file")"
    echo "{\"timestamp\":\"$timestamp\",\"confidence\":$confidence,\"timed_out\":$timed_out,\"agreed\":$agreed}" >> "$metrics_file"

    # Keep only last 20 entries
    local line_count
    line_count=$(wc -l < "$metrics_file" 2>/dev/null || echo 0)
    if [[ "$line_count" -gt 20 ]]; then
        tail -20 "$metrics_file" > "${metrics_file}.tmp" && mv "${metrics_file}.tmp" "$metrics_file"
    fi
}

# Display fatigue warning box with per-metric status and recommendations
# Arguments: avg_conf, timeout_rate, consensus_rate, rec1 [rec2 ...]
display_fatigue_warning() {
    local avg_conf="$1"
    local timeout_rate="$2"
    local consensus_rate="$3"
    shift 3
    local recommendations=("$@")

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  DEBATE FATIGUE DETECTED                                   ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    printf "Recent debate metrics (last 5 loops):\n"

    if [[ "$avg_conf" -lt 60 ]]; then
        printf "  Average confidence: %d%% ⚠ (threshold: 60%%)\n" "$avg_conf"
    else
        printf "  Average confidence: %d%% ✓\n" "$avg_conf"
    fi

    if [[ "$timeout_rate" -gt 20 ]]; then
        printf "  Timeout rate: %d%% ⚠ (threshold: 20%%)\n" "$timeout_rate"
    else
        printf "  Timeout rate: %d%% ✓\n" "$timeout_rate"
    fi

    printf "  Consensus rate: %d%%\n" "$consensus_rate"
    echo ""

    if [[ ${#recommendations[@]} -gt 0 ]]; then
        echo "Recommendations:"
        local i=1
        for rec in "${recommendations[@]}"; do
            printf "  %d. %s\n" "$i" "$rec"
            i=$(( i + 1 ))
        done
        echo ""
    fi
}

# Analyze rolling debate metrics and display fatigue warning if thresholds exceeded
# Arguments: window (default 5) — number of recent debates to analyze
# Returns: 0 always (non-blocking)
analyze_debate_fatigue() {
    local window="${1:-5}"
    local metrics_file="${KORERO_DIR:-.korero}/.debate_metrics"

    if [[ ! -f "$metrics_file" ]]; then
        return 0
    fi

    local line_count
    line_count=$(wc -l < "$metrics_file" 2>/dev/null || echo 0)
    if [[ "$line_count" -lt 3 ]]; then
        return 0  # Not enough data for meaningful analysis
    fi

    local total=0 timeout_count=0 agree_count=0 conf_sum=0

    while IFS= read -r line; do
        local conf timed agreed
        if command -v jq &>/dev/null; then
            conf=$(echo "$line" | jq -r '.confidence // 0' 2>/dev/null || echo 0)
            timed=$(echo "$line" | jq -r '.timed_out // false' 2>/dev/null || echo false)
            agreed=$(echo "$line" | jq -r '.agreed // false' 2>/dev/null || echo false)
        else
            conf=$(echo "$line" | sed 's/.*"confidence":\([0-9]*\).*/\1/' | grep -E '^[0-9]+$' || echo 0)
            timed=$(echo "$line" | grep -o '"timed_out":true' && echo true || echo false)
            agreed=$(echo "$line" | grep -o '"agreed":true' && echo true || echo false)
        fi
        conf="${conf:-0}"
        conf_sum=$(( conf_sum + conf ))
        [[ "$timed" == "true" ]] && timeout_count=$(( timeout_count + 1 ))
        [[ "$agreed" == "true" ]] && agree_count=$(( agree_count + 1 ))
        total=$(( total + 1 ))
    done < <(tail -"$window" "$metrics_file" 2>/dev/null)

    [[ $total -eq 0 ]] && return 0

    local avg_confidence timeout_rate consensus_rate
    avg_confidence=$(( conf_sum / total ))
    timeout_rate=$(( timeout_count * 100 / total ))
    consensus_rate=$(( agree_count * 100 / total ))

    local fatigue_detected=false
    local recommendations=()

    if [[ $avg_confidence -lt 60 ]]; then
        fatigue_detected=true
        recommendations+=("Low confidence (${avg_confidence}%): debates aren't decisive — try reducing DEBATE_ROUNDS or switching modes")
    fi

    if [[ $timeout_rate -gt 20 ]]; then
        fatigue_detected=true
        recommendations+=("High timeout rate (${timeout_rate}%): increase CODEX_TIMEOUT from ${CODEX_TIMEOUT:-15} to $(( ${CODEX_TIMEOUT:-15} + 10 )) minutes")
    fi

    if [[ $consensus_rate -gt 80 ]]; then
        fatigue_detected=true
        recommendations+=("High consensus rate (${consensus_rate}%): reduce DEBATE_ROUNDS — extra rounds add little value when AIs agree")
    fi

    if [[ "$fatigue_detected" == "true" ]]; then
        display_fatigue_warning "$avg_confidence" "$timeout_rate" "$consensus_rate" "${recommendations[@]}"
    fi

    return 0
}

# ===== Cross-AI Verdict Explanation (Loop 47) =====

# Display a formatted verdict explanation from the debate result file
# Reads .korero/.debate_result and shows winner, confidence, summary
# Arguments: result_file (optional, defaults to $DEBATE_RESULT_FILE)
display_verdict_explanation() {
    local result_file="${1:-${DEBATE_RESULT_FILE:-${KORERO_DIR:-.korero}/.debate_result}}"

    if [[ ! -f "$result_file" ]]; then
        echo "No debate result found." >&2
        return 1
    fi

    local winner confidence title summary rationale
    if command -v jq &>/dev/null; then
        winner=$(jq -r '.winner // "unknown"' "$result_file" 2>/dev/null || echo "unknown")
        confidence=$(jq -r '.confidence // 0' "$result_file" 2>/dev/null || echo 0)
        title=$(jq -r '.title // ""' "$result_file" 2>/dev/null || echo "")
        summary=$(jq -r '.summary // .rationale // ""' "$result_file" 2>/dev/null || echo "")
        rationale=$(jq -r '.rationale // ""' "$result_file" 2>/dev/null || echo "")
    else
        winner=$(sed 's/.*"winner":[[:space:]]*"\([^"]*\)".*/\1/' "$result_file" | head -1)
        confidence=$(sed 's/.*"confidence":[[:space:]]*\([0-9]*\).*/\1/' "$result_file" | head -1)
        title=$(sed 's/.*"title":[[:space:]]*"\([^"]*\)".*/\1/' "$result_file" | head -1)
        summary=$(sed 's/.*"summary":[[:space:]]*"\([^"]*\)".*/\1/' "$result_file" | head -1)
        rationale=$(sed 's/.*"rationale":[[:space:]]*"\([^"]*\)".*/\1/' "$result_file" | head -1)
    fi

    # Use rationale as fallback for summary
    [[ -z "$summary" ]] && summary="$rationale"
    local winner_display
    winner_display=$(echo "$winner" | tr '[:lower:]' '[:upper:]')

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  DEBATE VERDICT EXPLANATION                                ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    printf "Winner: %s (%s%% confidence)\n" "$winner_display" "$confidence"
    if [[ -n "$title" ]]; then
        printf "Title:  \"%s\"\n" "$title"
    fi
    echo ""

    if [[ -n "$summary" ]]; then
        echo "RATIONALE:"
        # Word-wrap at ~60 chars
        echo "$summary" | fold -s -w 60 | sed 's/^/  /'
        echo ""
    fi

    # Show runner-up insight if present
    local runner_up
    if command -v jq &>/dev/null; then
        runner_up=$(jq -r '.runner_up_insight // ""' "$result_file" 2>/dev/null || echo "")
    else
        runner_up=$(sed 's/.*"runner_up_insight":[[:space:]]*"\([^"]*\)".*/\1/' "$result_file" | head -1)
    fi
    if [[ -n "$runner_up" && "$runner_up" != "N/A" ]]; then
        echo "RUNNER-UP INSIGHT:"
        echo "$runner_up" | fold -s -w 60 | sed 's/^/  /'
        echo ""
    fi

    # Low confidence warning (Loop 60)
    local conf_num="${confidence:-0}"
    if [[ "$conf_num" =~ ^[0-9]+$ ]] && [[ "$conf_num" -le 50 ]]; then
        echo "WARNING: Low confidence (${conf_num}%) — This was a close debate."
        echo "  Consider reviewing both proposals manually."
        echo ""
    fi

    echo "════════════════════════════════════════════════════════════"
    echo ""
    return 0
}

export -f get_phase_icon
export -f show_debate_progress
export -f show_debate_round_progress
export -f complete_debate_round_progress
export -f show_debate_summary
export -f build_critique_prompt
export -f build_defense_prompt
export -f build_judge_prompt
export -f parse_debate_verdict
export -f get_debate_winner
export -f get_debate_confidence
export -f run_cross_ai_debate
export -f calculate_length_ratio
export -f calculate_coverage
export -f calculate_verdict_confidence
export -f calculate_debate_quality
export -f record_debate_quality
export -f display_parallel_timing
export -f run_parallel_critiques_with_timing
export -f track_debate_metrics
export -f display_fatigue_warning
export -f analyze_debate_fatigue
export -f display_verdict_explanation
