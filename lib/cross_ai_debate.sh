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

    # Handle JSON output from Claude (extract .result field if present)
    if command -v jq &>/dev/null; then
        local json_result
        json_result=$(echo "$content" | jq -r '.result // empty' 2>/dev/null || true)
        if [[ -n "$json_result" ]]; then
            content="$json_result"
        fi
    fi

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

    # === ROUND 1: MUTUAL CRITIQUE (parallel) ===
    log_status "INFO" "  Debate Round 1/3: Mutual critique (Claude + Codex in parallel)..."
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
    portable_timeout "${timeout_seconds}s" "${CLAUDE_CRITIQUE_ARGS[@]}" > "$claude_critique_file" 2>&1 &
    local claude_crit_pid=$!

    # Codex critiques Claude (background)
    build_codex_command "$codex_critique_prompt" "$mode"
    portable_timeout "${timeout_seconds}s" "${CODEX_CMD_ARGS[@]}" > "$codex_critique_file" 2>&1 &
    local codex_crit_pid=$!

    # Wait for both critiques
    local claude_crit_exit=0 codex_crit_exit=0
    wait $claude_crit_pid || claude_crit_exit=$?
    wait $codex_crit_pid || codex_crit_exit=$?
    log_status "INFO" "  Round 1 complete — Claude critique: exit $claude_crit_exit, Codex critique: exit $codex_crit_exit"

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
        log_status "INFO" "  Debate Round 2/3: Defense (Claude + Codex in parallel)..."
        local claude_defense_file="$debate_dir/claude_defense_${timestamp}.log"
        local codex_defense_file="$debate_dir/codex_defense_${timestamp}.log"

        # Build defense prompts
        local claude_defense_prompt codex_defense_prompt
        claude_defense_prompt=$(build_defense_prompt "$claude_proposal" "$codex_critique_text" "Claude" "Codex" "$project_name")
        codex_defense_prompt=$(build_defense_prompt "$codex_proposal" "$claude_critique_text" "Codex" "Claude" "$project_name")

        # Claude defends (background)
        declare -a CLAUDE_DEFENSE_ARGS=("${CLAUDE_CODE_CMD:-claude}" "--output-format" "json" "-p" "$claude_defense_prompt")
        portable_timeout "${timeout_seconds}s" "${CLAUDE_DEFENSE_ARGS[@]}" > "$claude_defense_file" 2>&1 &
        local claude_def_pid=$!

        # Codex defends (background)
        build_codex_command "$codex_defense_prompt" "$mode"
        portable_timeout "${timeout_seconds}s" "${CODEX_CMD_ARGS[@]}" > "$codex_defense_file" 2>&1 &
        local codex_def_pid=$!

        # Wait for both defenses
        local claude_def_exit=0 codex_def_exit=0
        wait $claude_def_pid || claude_def_exit=$?
        wait $codex_def_pid || codex_def_exit=$?
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

        # Record defenses in transcript
        append_transcript_section "$loop_num" "Round 2: Claude's Defense" "$claude_defense_text"
        append_transcript_section "$loop_num" "Round 2: Codex's Defense" "$codex_defense_text"
    fi

    # === ROUND 3: FINAL JUDGMENT (Claude only) ===
    log_status "INFO" "  Debate Round 3/3: Final judgment (Claude evaluating all artifacts)..."
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
    portable_timeout "${timeout_seconds}s" "${CLAUDE_JUDGE_ARGS[@]}" > "$judge_file" 2>&1
    local judge_exit=$?
    log_status "INFO" "  Round 3 complete — Judge exit: $judge_exit"

    if [[ $judge_exit -ne 0 ]]; then
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
        return 0
    fi

    # Parse verdict (|| true prevents set -e exit on parse failure — default verdict written)
    parse_debate_verdict "$judge_file" "$DEBATE_RESULT_FILE" || true

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

    return 0
}

export -f build_critique_prompt
export -f build_defense_prompt
export -f build_judge_prompt
export -f parse_debate_verdict
export -f get_debate_winner
export -f run_cross_ai_debate
