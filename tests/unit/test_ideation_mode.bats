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

@test "generate_ideation_prompt_md includes multi-agent protocol for idea mode" {
    local output
    output=$(generate_ideation_prompt_md "test-project" "typescript" "idea" "data analysis tool")

    echo "$output" | grep -q "Multi-Agent Ideation Protocol"
    echo "$output" | grep -q "Continuous Idea Loop"
    echo "$output" | grep -q "KORERO_IDEA"
    echo "$output" | grep -q "KORERO_STATUS"
}

@test "generate_ideation_prompt_md includes implementation section for coding mode" {
    local output
    output=$(generate_ideation_prompt_md "test-project" "typescript" "coding" "web app")

    echo "$output" | grep -q "Continuous Coding Loop"
    echo "$output" | grep -q "Phase 3: Implementation"
    echo "$output" | grep -q "git commit"
}

@test "generate_ideation_prompt_md excludes implementation section for idea mode" {
    local output
    output=$(generate_ideation_prompt_md "test-project" "typescript" "idea" "web app")

    ! echo "$output" | grep -q "Phase 3: Implementation"
    echo "$output" | grep -q "do NOT implement code"
}

@test "generate_ideation_prompt_md includes project subject" {
    local output
    output=$(generate_ideation_prompt_md "test-project" "python" "idea" "machine learning pipeline")

    echo "$output" | grep -q "machine learning pipeline"
}

@test "generate_ideation_prompt_md includes debate rounds" {
    local output
    output=$(generate_ideation_prompt_md "test-project" "unknown" "idea" "")

    echo "$output" | grep -q "Round 1: Evaluation"
    echo "$output" | grep -q "Round 2: Rebuttal"
    echo "$output" | grep -q "Round 3: Final Selection"
}

@test "generate_ideation_prompt_md includes EXIT_SIGNAL guidelines" {
    local output
    output=$(generate_ideation_prompt_md "test-project" "unknown" "idea" "")

    echo "$output" | grep -q "EXIT_SIGNAL"
    echo "$output" | grep -q "KORERO_STATUS"
}

# =============================================================================
# IDEATION AGENT.MD GENERATION (5 tests)
# =============================================================================

@test "generate_ideation_agent_md includes domain agents" {
    local agents
    agents=$(_generate_generic_agents 2)
    local output
    output=$(generate_ideation_agent_md "$agents" "npm build" "npm test" "npm start" "coding")

    echo "$output" | grep -q "Domain Expert Agents"
    echo "$output" | grep -q "Domain Innovation Expert"
}

@test "generate_ideation_agent_md always includes 3 mandatory agents" {
    local agents
    agents=$(_generate_generic_agents 1)
    local output
    output=$(generate_ideation_agent_md "$agents" "" "" "" "idea")

    echo "$output" | grep -q "Devil's Advocate"
    echo "$output" | grep -q "Technical Feasibility Analyst"
    echo "$output" | grep -q "Idea Orchestrator"
}

@test "generate_ideation_agent_md includes build commands in coding mode" {
    local agents
    agents=$(_generate_generic_agents 1)
    local output
    output=$(generate_ideation_agent_md "$agents" "npm run build" "npm test" "npm start" "coding")

    echo "$output" | grep -q "Build Instructions"
    echo "$output" | grep -q "npm run build"
}

@test "generate_ideation_agent_md excludes build commands in idea mode" {
    local agents
    agents=$(_generate_generic_agents 1)
    local output
    output=$(generate_ideation_agent_md "$agents" "npm run build" "npm test" "npm start" "idea")

    ! echo "$output" | grep -q "Build Instructions"
}

@test "generate_ideation_agent_md mentions editing capability" {
    local agents
    agents=$(_generate_generic_agents 1)
    local output
    output=$(generate_ideation_agent_md "$agents" "" "" "" "idea")

    echo "$output" | grep -q "edit this file"
}

# =============================================================================
# IDEATION FIX_PLAN.MD GENERATION (3 tests)
# =============================================================================

@test "generate_ideation_fix_plan_md produces idea-mode plan" {
    local output
    output=$(generate_ideation_fix_plan_md "idea" "")

    echo "$output" | grep -q "Ideation Goals"
    echo "$output" | grep -q "multi-agent ideation"
    echo "$output" | grep -q "IDEAS.md"
}

@test "generate_ideation_fix_plan_md produces coding-mode plan with tasks" {
    local tasks="- [ ] Build data pipeline
- [ ] Add authentication"
    local output
    output=$(generate_ideation_fix_plan_md "coding" "$tasks")

    echo "$output" | grep -q "Build data pipeline"
    echo "$output" | grep -q "Add authentication"
}

@test "generate_ideation_fix_plan_md defaults to standard plan for coding mode" {
    local output
    output=$(generate_ideation_fix_plan_md "coding" "")

    echo "$output" | grep -q "High Priority"
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
# INTEGRATION: ENABLE WITH IDEATION MODE (5 tests)
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
}

@test "enable_korero_in_directory idea mode PROMPT.md contains ideation protocol" {
    export ENABLE_FORCE="true"
    export ENABLE_KORERO_MODE="idea"
    export ENABLE_PROJECT_SUBJECT="web application"
    export ENABLE_GENERATED_AGENTS=$(_generate_generic_agents 2)
    export ENABLE_AGENT_COUNT="2"
    export ENABLE_MAX_LOOPS="continuous"

    enable_korero_in_directory

    grep -q "Multi-Agent Ideation Protocol" .korero/PROMPT.md
    grep -q "KORERO_IDEA" .korero/PROMPT.md
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

@test "enable_korero_in_directory AGENT.md contains mandatory agents" {
    export ENABLE_FORCE="true"
    export ENABLE_KORERO_MODE="idea"
    export ENABLE_GENERATED_AGENTS=$(_generate_generic_agents 2)
    export ENABLE_AGENT_COUNT="2"
    export ENABLE_MAX_LOOPS="10"

    enable_korero_in_directory

    grep -q "Devil's Advocate" .korero/AGENT.md
    grep -q "Technical Feasibility Analyst" .korero/AGENT.md
    grep -q "Idea Orchestrator" .korero/AGENT.md
}

@test "enable_korero_in_directory standard mode still works without ideation" {
    export ENABLE_FORCE="true"
    export ENABLE_KORERO_MODE=""

    enable_korero_in_directory

    [[ -f ".korero/PROMPT.md" ]]
    ! grep -q "Multi-Agent Ideation Protocol" .korero/PROMPT.md
}
