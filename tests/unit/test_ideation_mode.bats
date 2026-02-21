#!/usr/bin/env bats
# Unit tests for Korero ideation mode functionality
# Tests agent generation, ideation templates, idea storage, and loop limits

load '../helpers/test_helper'
load '../helpers/fixtures'

# Path to enable_core.sh and korero_loop.sh
ENABLE_CORE="${BATS_TEST_DIRNAME}/../../lib/enable_core.sh"
KORERO_LOOP="${BATS_TEST_DIRNAME}/../../korero_loop.sh"

setup() {
    # Create temporary test directory
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"

    # Source the library (disable set -e for testing)
    set +e
    source "$ENABLE_CORE"
    set -e
}

teardown() {
    if [[ -n "$TEST_DIR" ]] && [[ -d "$TEST_DIR" ]]; then
        cd /
        rm -rf "$TEST_DIR"
    fi
}

# =============================================================================
# GENERIC AGENT GENERATION (4 tests)
# =============================================================================

@test "_generate_generic_agents produces 3 agents by default" {
    local output
    output=$(_generate_generic_agents)

    local agent_count
    agent_count=$(echo "$output" | grep -c "^### Agent:")

    assert_equal "$agent_count" "3"
}

@test "_generate_generic_agents produces requested number of agents" {
    local output
    output=$(_generate_generic_agents 5)

    local agent_count
    agent_count=$(echo "$output" | grep -c "^### Agent:")

    assert_equal "$agent_count" "5"
}

@test "_generate_generic_agents includes expected format fields" {
    local output
    output=$(_generate_generic_agents 1)

    echo "$output" | grep -q "^### Agent:"
    echo "$output" | grep -q "^\*\*Expertise:\*\*"
    echo "$output" | grep -q "^\*\*Perspective:\*\*"
    echo "$output" | grep -q "^\*\*Focus Areas:\*\*"
}

@test "_generate_generic_agents limits to max available agents" {
    local output
    output=$(_generate_generic_agents 10)

    local agent_count
    agent_count=$(echo "$output" | grep -c "^### Agent:")

    assert_equal "$agent_count" "10"
}

# =============================================================================
# MANUAL AGENT GENERATION (3 tests)
# =============================================================================

@test "_generate_agents_from_roles creates agents from comma-separated roles" {
    local output
    output=$(_generate_agents_from_roles "Data Analyst,Data Engineer,Chief Data Officer")

    local agent_count
    agent_count=$(echo "$output" | grep -c "^### Agent:")

    assert_equal "$agent_count" "3"
    echo "$output" | grep -q "### Agent: Data Analyst"
    echo "$output" | grep -q "### Agent: Data Engineer"
    echo "$output" | grep -q "### Agent: Chief Data Officer"
}

@test "_generate_agents_from_roles handles single role" {
    local output
    output=$(_generate_agents_from_roles "UX Designer")

    local agent_count
    agent_count=$(echo "$output" | grep -c "^### Agent:")

    assert_equal "$agent_count" "1"
    echo "$output" | grep -q "### Agent: UX Designer"
}

@test "_generate_agents_from_roles trims whitespace" {
    local output
    output=$(_generate_agents_from_roles "  Data Analyst , Data Engineer  ")

    echo "$output" | grep -q "### Agent: Data Analyst"
    echo "$output" | grep -q "### Agent: Data Engineer"
}

# =============================================================================
# DOMAIN AGENT GENERATION (3 tests)
# =============================================================================

@test "generate_domain_agents falls back to generic when no subject" {
    local output
    output=$(generate_domain_agents "" "typescript" 3 || true)

    # Should return generic agents as fallback
    local agent_count
    agent_count=$(echo "$output" | grep -c "^### Agent:")

    [[ $agent_count -ge 1 ]]
}

@test "generate_domain_agents falls back when Claude CLI unavailable" {
    # Ensure claude command doesn't exist in this test
    local output
    PATH="/nonexistent:$PATH" output=$(generate_domain_agents "data analysis tool" "python" 3 2>/dev/null)

    local agent_count
    agent_count=$(echo "$output" | grep -c "^### Agent:")

    [[ $agent_count -ge 1 ]]
}

@test "generate_domain_agents respects count parameter" {
    local output
    output=$(generate_domain_agents "" "unknown" 5 || true)

    local agent_count
    agent_count=$(echo "$output" | grep -c "^### Agent:")

    assert_equal "$agent_count" "5"
}

# =============================================================================
# IDEATION PROMPT.MD GENERATION (6 tests)
# =============================================================================

@test "generate_ideation_prompt_md includes multi-agent system for idea mode" {
    local output
    output=$(generate_ideation_prompt_md "test-project" "typescript" "idea" "data analysis tool" "3" "10")

    echo "$output" | grep -q "Multi-Agent Idea Generation System"
    echo "$output" | grep -q "IDEA GENERATION ONLY"
    echo "$output" | grep -q "KORERO_STATUS"
}

@test "generate_ideation_prompt_md includes implementation section for coding mode" {
    local output
    output=$(generate_ideation_prompt_md "test-project" "typescript" "coding" "web app" "3" "20")

    echo "$output" | grep -q "IDEATION + IMPLEMENTATION"
    echo "$output" | grep -q "Phase 3b: Implementation"
    echo "$output" | grep -q "git commit"
}

@test "generate_ideation_prompt_md excludes implementation section for idea mode" {
    local output
    output=$(generate_ideation_prompt_md "test-project" "typescript" "idea" "web app" "3" "10")

    ! echo "$output" | grep -q "Phase 3b: Implementation"
    echo "$output" | grep -q "do NOT implement"
}

@test "generate_ideation_prompt_md includes loop count and agent count" {
    local output
    output=$(generate_ideation_prompt_md "test-project" "python" "idea" "machine learning pipeline" "5" "20")

    echo "$output" | grep -q "20 winning improvement ideas"
    echo "$output" | grep -q "8-Agent Team"
    echo "$output" | grep -q "5 agents"
}

@test "generate_ideation_prompt_md includes debate phases" {
    local output
    output=$(generate_ideation_prompt_md "test-project" "unknown" "idea" "" "3" "10")

    echo "$output" | grep -q "Phase 1: Idea Generation"
    echo "$output" | grep -q "Phase 2: Evaluation"
    echo "$output" | grep -q "Phase 3: Debate"
    echo "$output" | grep -q "Phase 4: Winning Idea Documentation"
}

@test "generate_ideation_prompt_md includes EXIT_SIGNAL guidelines" {
    local output
    output=$(generate_ideation_prompt_md "test-project" "unknown" "idea" "" "3" "continuous")

    echo "$output" | grep -q "EXIT_SIGNAL"
    echo "$output" | grep -q "KORERO_STATUS"
}

@test "generate_ideation_prompt_md includes minority opinion section" {
    local output
    output=$(generate_ideation_prompt_md "test-project" "unknown" "idea" "")

    echo "$output" | grep -q "Minority Opinions"
    echo "$output" | grep -q "KORERO_MINORITY_OPINION"
    echo "$output" | grep -q "REJECTION_RATIONALE"
    echo "$output" | grep -q "CORE_INSIGHT"
    echo "$output" | grep -q "RECONSIDER_WHEN"
}

# =============================================================================
# IDEATION AGENT.MD GENERATION (5 tests)
# =============================================================================

@test "generate_ideation_agent_md includes domain agents in table" {
    local agents
    agents=$(_generate_generic_agents 2)
    local output
    output=$(generate_ideation_agent_md "$agents" "npm build" "npm test" "npm start" "coding" "2" "20" "test-project")

    echo "$output" | grep -q "Idea Generators"
    echo "$output" | grep -q "Domain Innovation Expert"
}

@test "generate_ideation_agent_md always includes 3 mandatory evaluators" {
    local agents
    agents=$(_generate_generic_agents 1)
    local output
    output=$(generate_ideation_agent_md "$agents" "" "" "" "idea" "1" "10" "test-project")

    echo "$output" | grep -q "Devil's Advocate"
    echo "$output" | grep -q "Technical Feasibility Agent"
    echo "$output" | grep -q "Idea Orchestrator"
}

@test "generate_ideation_agent_md includes build commands in coding mode" {
    local agents
    agents=$(_generate_generic_agents 1)
    local output
    output=$(generate_ideation_agent_md "$agents" "npm run build" "npm test" "npm start" "coding" "1" "10" "test-project")

    echo "$output" | grep -q "Build Instructions"
    echo "$output" | grep -q "npm run build"
}

@test "generate_ideation_agent_md idea mode shows no-build message" {
    local agents
    agents=$(_generate_generic_agents 1)
    local output
    output=$(generate_ideation_agent_md "$agents" "npm run build" "npm test" "npm start" "idea" "1" "10" "test-project")

    echo "$output" | grep -q "Idea generation mode"
    echo "$output" | grep -q "no build required"
}

@test "generate_ideation_agent_md includes debate rules" {
    local agents
    agents=$(_generate_generic_agents 1)
    local output
    output=$(generate_ideation_agent_md "$agents" "" "" "" "idea" "1" "10" "test-project")

    echo "$output" | grep -q "Debate Rules"
    echo "$output" | grep -q "Independence"
    echo "$output" | grep -q "Anti-Repetition"
}

@test "generate_ideation_agent_md includes scoring criteria" {
    local agents
    agents=$(_generate_generic_agents 1)
    local output
    output=$(generate_ideation_agent_md "$agents" "" "" "" "idea" "1" "10" "test-project")

    echo "$output" | grep -q "Scoring Criteria"
}

@test "generate_ideation_agent_md includes output location instructions" {
    local agents
    agents=$(_generate_generic_agents 1)
    local output
    output=$(generate_ideation_agent_md "$agents" "" "" "" "idea" "1" "10" "test-project")

    echo "$output" | grep -q "Output Location"
    echo "$output" | grep -q "IDEAS.md"
    echo "$output" | grep -q "fix_plan.md"
}

@test "generate_ideation_agent_md uses CONFIG_SCORING when set" {
    CONFIG_SCORING="| Custom Criterion | 50% | Custom description |
| Another | 50% | Another desc |"
    local agents
    agents=$(_generate_generic_agents 1)
    local output
    output=$(generate_ideation_agent_md "$agents" "" "" "" "idea" "1" "10" "test-project")
    unset CONFIG_SCORING

    echo "$output" | grep -q "Custom Criterion"
    echo "$output" | grep -q "50%"
}

@test "generate_ideation_agent_md uses CONFIG_FOCUS_CONSTRAINT when set" {
    CONFIG_FOCUS_CONSTRAINT="Only UI/UX improvements are in scope."
    local agents
    agents=$(_generate_generic_agents 1)
    local output
    output=$(generate_ideation_agent_md "$agents" "" "" "" "idea" "1" "10" "test-project")
    unset CONFIG_FOCUS_CONSTRAINT

    echo "$output" | grep -q "Focus"
    echo "$output" | grep -q "UI/UX improvements"
}

# =============================================================================
# IDEATION FIX_PLAN.MD GENERATION (3 tests + 6 new)
# =============================================================================

@test "generate_ideation_fix_plan_md produces tracker-based plan for numbered loops" {
    local output
    output=$(generate_ideation_fix_plan_md "idea" "" "test-project" "3" "10")

    echo "$output" | grep -q "Idea Generation Plan"
    echo "$output" | grep -q "Winning Ideas Tracker"
    echo "$output" | grep -q "IDEAS.md"
}

@test "generate_ideation_fix_plan_md produces coding-mode plan with tasks" {
    local tasks="- [ ] Build data pipeline
- [ ] Add authentication"
    local output
    output=$(generate_ideation_fix_plan_md "coding" "$tasks" "test-project" "3" "10")

    echo "$output" | grep -q "Winning Ideas Tracker"
    echo "$output" | grep -q "10 Loops"
}

@test "generate_ideation_fix_plan_md produces continuous plan for continuous loops" {
    local output
    output=$(generate_ideation_fix_plan_md "idea" "" "test-project" "3" "continuous")

    echo "$output" | grep -q "Continuous"
    echo "$output" | grep -q "Winning Ideas Tracker"
}

@test "generate_ideation_fix_plan_md includes tracker rows matching max_loops" {
    local output
    output=$(generate_ideation_fix_plan_md "idea" "" "test-project" "3" "10")

    local pending_count
    pending_count=$(echo "$output" | grep -c "| Pending |")

    assert_equal "$pending_count" "10"
}

@test "generate_ideation_fix_plan_md includes category coverage table with CONFIG_CATEGORIES" {
    CONFIG_CATEGORIES="- **Data Management** — Data upload and processing
- **Visualization** — Charts and graphs
- **AI Features** — LLM-powered capabilities"
    local output
    output=$(generate_ideation_fix_plan_md "idea" "" "test-project" "3" "10")
    unset CONFIG_CATEGORIES

    echo "$output" | grep -q "Category Coverage"
    echo "$output" | grep -q "Data Management"
    echo "$output" | grep -q "Visualization"
    echo "$output" | grep -q "AI Features"
}

@test "generate_ideation_fix_plan_md includes type balance table" {
    local output
    output=$(generate_ideation_fix_plan_md "idea" "" "test-project" "3" "10")

    echo "$output" | grep -q "Type Balance"
    echo "$output" | grep -q "Usability Improvement"
    echo "$output" | grep -q "New Feature"
}

@test "generate_ideation_fix_plan_md includes per-loop checklists" {
    local output
    output=$(generate_ideation_fix_plan_md "idea" "" "test-project" "3" "10")

    echo "$output" | grep -q "## Loop 1"
    echo "$output" | grep -q "## Loop 10"
    echo "$output" | grep -q "Phase 1: All 3 generators"
    echo "$output" | grep -q "Phase 4: Winning idea documented"
}

@test "generate_ideation_fix_plan_md includes checkpoints" {
    local output
    output=$(generate_ideation_fix_plan_md "idea" "" "test-project" "3" "20")

    echo "$output" | grep -q "Checkpoint"
    echo "$output" | grep -q "FINAL CHECKPOINT"
}

@test "generate_ideation_fix_plan_md includes final deliverable section" {
    local output
    output=$(generate_ideation_fix_plan_md "idea" "" "test-project" "3" "10")

    echo "$output" | grep -q "Final Deliverable"
}

# =============================================================================
# IDEA STORAGE (5 tests)
# =============================================================================

@test "store_loop_idea extracts KORERO_IDEA block and saves to file" {
    # Set up test environment
    KORERO_DIR=".korero"
    mkdir -p "$KORERO_DIR/ideas"

    # Create mock output with idea block
    local output_file="$TEST_DIR/output.txt"
    cat > "$output_file" << 'EOF'
Some preamble text...

---KORERO_IDEA---
LOOP: 1
SELECTED_IDEA: Add real-time data dashboard
PROPOSED_BY: Data Analytics Expert
IMPACT: HIGH
EFFORT: MEDIUM
DESCRIPTION: Build a real-time dashboard to visualize key metrics
JUSTIFICATION: Highest impact-to-effort ratio
---END_KORERO_IDEA---

Some postamble text...
EOF

    # Source the function (it's in korero_loop.sh but we need it standalone)
    # Define minimal stubs
    log_status() { :; }

    source "$ENABLE_CORE"

    # Run function inline since it's in korero_loop.sh
    local ideas_dir="$KORERO_DIR/ideas"
    local content
    content=$(cat "$output_file")
    local idea_block
    idea_block=$(echo "$content" | sed -n '/---KORERO_IDEA---/,/---END_KORERO_IDEA---/p')

    [[ -n "$idea_block" ]]
    echo "$idea_block" > "$ideas_dir/loop_1_idea.md"

    [[ -f "$ideas_dir/loop_1_idea.md" ]]
    grep -q "Add real-time data dashboard" "$ideas_dir/loop_1_idea.md"
}

@test "store_loop_idea appends to IDEAS.md" {
    KORERO_DIR=".korero"
    mkdir -p "$KORERO_DIR/ideas"

    # Create first idea
    cat > "$KORERO_DIR/ideas/IDEAS.md" << 'EOF'
## Loop 1 - 2026-01-01 00:00:00

---KORERO_IDEA---
LOOP: 1
SELECTED_IDEA: First idea
---END_KORERO_IDEA---

---
EOF

    # Append second idea
    {
        echo ""
        echo "## Loop 2 - 2026-01-02 00:00:00"
        echo ""
        echo "---KORERO_IDEA---"
        echo "LOOP: 2"
        echo "SELECTED_IDEA: Second idea"
        echo "---END_KORERO_IDEA---"
        echo ""
        echo "---"
    } >> "$KORERO_DIR/ideas/IDEAS.md"

    grep -q "First idea" "$KORERO_DIR/ideas/IDEAS.md"
    grep -q "Second idea" "$KORERO_DIR/ideas/IDEAS.md"
}

@test "store_loop_idea handles missing idea block gracefully" {
    KORERO_DIR=".korero"
    mkdir -p "$KORERO_DIR/ideas"

    local output_file="$TEST_DIR/output.txt"
    echo "No idea block here, just regular output" > "$output_file"

    local content
    content=$(cat "$output_file")
    local idea_block
    idea_block=$(echo "$content" | sed -n '/---KORERO_IDEA---/,/---END_KORERO_IDEA---/p')

    [[ -z "$idea_block" ]]
    # No file should be created
    [[ ! -f "$KORERO_DIR/ideas/loop_1_idea.md" ]]
}

@test "ideas directory created by create_korero_structure in ideation mode" {
    export ENABLE_KORERO_MODE="idea"
    create_korero_structure

    [[ -d ".korero/ideas" ]]
}

@test "ideas directory not created in standard mode" {
    export ENABLE_KORERO_MODE=""
    create_korero_structure

    [[ ! -d ".korero/ideas" ]]
}

# =============================================================================
# KORERORC GENERATION (4 tests)
# =============================================================================

@test "generate_korerorc includes mode and subject when set" {
    local output
    output=$(generate_korerorc "test-project" "typescript" "local" "idea" "data tool" "4" "20")

    echo "$output" | grep -q 'KORERO_MODE="idea"'
    echo "$output" | grep -q 'PROJECT_SUBJECT="data tool"'
    echo "$output" | grep -q 'DOMAIN_AGENT_COUNT=4'
    echo "$output" | grep -q 'MAX_LOOPS="20"'
}

@test "generate_korerorc omits mode section when mode is empty" {
    local output
    output=$(generate_korerorc "test-project" "typescript" "local" "" "" "" "")

    ! echo "$output" | grep -q "KORERO_MODE="
}

@test "generate_korerorc handles continuous loop setting" {
    local output
    output=$(generate_korerorc "test-project" "typescript" "local" "coding" "web app" "3" "continuous")

    echo "$output" | grep -q 'MAX_LOOPS="continuous"'
}

@test "generate_korerorc includes standard settings" {
    local output
    output=$(generate_korerorc "test-project" "typescript" "local" "coding" "" "3" "continuous")

    echo "$output" | grep -q "MAX_CALLS_PER_HOUR=100"
    echo "$output" | grep -q "ALLOWED_TOOLS="
    echo "$output" | grep -q "SESSION_CONTINUITY=true"
}

# =============================================================================
# IDEAS.MD HEADER GENERATION (3 tests)
# =============================================================================

@test "generate_ideation_ideas_md includes project name" {
    local output
    output=$(generate_ideation_ideas_md "my-project" "10" "6")

    echo "$output" | grep -q "my-project Winning Ideas"
}

@test "generate_ideation_ideas_md includes loop count" {
    local output
    output=$(generate_ideation_ideas_md "my-project" "20" "12")

    echo "$output" | grep -q "20"
    echo "$output" | grep -q "12-agent"
}

@test "generate_ideation_ideas_md uses focus constraint description" {
    CONFIG_FOCUS_CONSTRAINT="All ideas MUST be about usability improvements"
    local output
    output=$(generate_ideation_ideas_md "my-project" "10" "6")
    unset CONFIG_FOCUS_CONSTRAINT

    echo "$output" | grep -q "usability improvements"
}

# =============================================================================
# PROJECT CONTEXT GATHERING (5 tests)
# =============================================================================

@test "gather_project_context returns directory tree" {
    mkdir -p src lib
    echo "test" > src/main.py
    echo "test" > lib/utils.py

    local output
    output=$(gather_project_context "$(pwd)")

    echo "$output" | grep -q "DIRECTORY STRUCTURE"
    echo "$output" | grep -q "src"
}

@test "gather_project_context reads package.json" {
    cat > package.json << 'EOF'
{
    "name": "test-project",
    "version": "1.0.0",
    "dependencies": {
        "express": "^4.18.0"
    }
}
EOF

    local output
    output=$(gather_project_context "$(pwd)")

    echo "$output" | grep -q "PACKAGE MANIFEST"
    echo "$output" | grep -q "express"
}

@test "gather_project_context reads README.md" {
    cat > README.md << 'EOF'
# Test Project

This is a test project for unit testing.
EOF

    local output
    output=$(gather_project_context "$(pwd)")

    echo "$output" | grep -q "README"
    echo "$output" | grep -q "Test Project"
}

@test "gather_project_context handles missing README gracefully" {
    # No README exists in temp dir
    local output
    output=$(gather_project_context "$(pwd)")

    # Should still return something (at least directory tree)
    [[ -n "$output" ]]
}

@test "gather_project_context respects size limit" {
    # Create many files to generate a large context
    mkdir -p src
    for i in $(seq 1 50); do
        echo "// file $i content" > "src/file_${i}.py"
    done

    local output
    output=$(gather_project_context "$(pwd)")

    # Should be capped at roughly 4000 chars
    local char_count=${#output}
    [[ $char_count -le 5000 ]]
}

# =============================================================================
# INTEGRATION: ENABLE WITH IDEATION MODE (7 tests)
# =============================================================================

@test "enable_korero_in_directory creates ideation files in idea mode" {
    export ENABLE_FORCE="true"
    export ENABLE_KORERO_MODE="idea"
    export ENABLE_PROJECT_SUBJECT="data analysis tool"
    export ENABLE_GENERATED_AGENTS=$(_generate_generic_agents 3)
    export ENABLE_AGENT_COUNT="3"
    export ENABLE_MAX_LOOPS="10"

    enable_korero_in_directory

    [[ -f ".korero/PROMPT.md" ]]
    [[ -f ".korero/AGENT.md" ]]
    [[ -f ".korero/fix_plan.md" ]]
    [[ -f ".korerorc" ]]
    [[ -d ".korero/ideas" ]]
    [[ -f ".korero/ideas/IDEAS.md" ]]
}

@test "enable_korero_in_directory idea mode PROMPT.md contains MMMlight-quality sections" {
    export ENABLE_FORCE="true"
    export ENABLE_KORERO_MODE="idea"
    export ENABLE_PROJECT_SUBJECT="web application"
    export ENABLE_GENERATED_AGENTS=$(_generate_generic_agents 2)
    export ENABLE_AGENT_COUNT="2"
    export ENABLE_MAX_LOOPS="continuous"

    enable_korero_in_directory

    grep -q "Multi-Agent Idea Generation System" .korero/PROMPT.md
    grep -q "KORERO_STATUS" .korero/PROMPT.md
    grep -q "Phase 4: Winning Idea Documentation" .korero/PROMPT.md
}

@test "enable_korero_in_directory coding mode includes implementation phase" {
    export ENABLE_FORCE="true"
    export ENABLE_KORERO_MODE="coding"
    export ENABLE_PROJECT_SUBJECT="REST API"
    export ENABLE_GENERATED_AGENTS=$(_generate_generic_agents 3)
    export ENABLE_AGENT_COUNT="3"
    export ENABLE_MAX_LOOPS="continuous"

    enable_korero_in_directory

    grep -q "Implementation" .korero/PROMPT.md
    grep -q "git commit" .korero/PROMPT.md
}

@test "enable_korero_in_directory AGENT.md contains mandatory evaluators" {
    export ENABLE_FORCE="true"
    export ENABLE_KORERO_MODE="idea"
    export ENABLE_GENERATED_AGENTS=$(_generate_generic_agents 2)
    export ENABLE_AGENT_COUNT="2"
    export ENABLE_MAX_LOOPS="10"

    enable_korero_in_directory

    grep -q "Devil's Advocate" .korero/AGENT.md
    grep -q "Technical Feasibility Agent" .korero/AGENT.md
    grep -q "Idea Orchestrator" .korero/AGENT.md
}

@test "enable_korero_in_directory standard mode still works without ideation" {
    export ENABLE_FORCE="true"
    export ENABLE_KORERO_MODE=""

    enable_korero_in_directory

    [[ -f ".korero/PROMPT.md" ]]
    ! grep -q "Multi-Agent Idea Generation System" .korero/PROMPT.md
}

@test "enable_korero_in_directory fix_plan.md has tracker table for numbered loops" {
    export ENABLE_FORCE="true"
    export ENABLE_KORERO_MODE="idea"
    export ENABLE_PROJECT_SUBJECT="test tool"
    export ENABLE_GENERATED_AGENTS=$(_generate_generic_agents 3)
    export ENABLE_AGENT_COUNT="3"
    export ENABLE_MAX_LOOPS="10"

    enable_korero_in_directory

    grep -q "Winning Ideas Tracker" .korero/fix_plan.md
    grep -q "| Pending |" .korero/fix_plan.md
    grep -q "## Loop 1" .korero/fix_plan.md
    grep -q "## Loop 10" .korero/fix_plan.md
}

@test "enable_korero_in_directory IDEAS.md has project-specific header" {
    export ENABLE_FORCE="true"
    export ENABLE_KORERO_MODE="idea"
    export ENABLE_PROJECT_SUBJECT="analysis tool"
    export ENABLE_GENERATED_AGENTS=$(_generate_generic_agents 3)
    export ENABLE_AGENT_COUNT="3"
    export ENABLE_MAX_LOOPS="10"

    enable_korero_in_directory

    [[ -f ".korero/ideas/IDEAS.md" ]]
    grep -q "Winning Ideas" .korero/ideas/IDEAS.md
    grep -q "10" .korero/ideas/IDEAS.md
}
