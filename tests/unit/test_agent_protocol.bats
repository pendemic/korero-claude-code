#!/usr/bin/env bats

# Tests for Agent Communication Protocol v1 schema

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
PROTOCOL_FILE="$REPO_ROOT/templates/protocols/agent-protocol-v1.json"

setup() {
    # Ensure jq is available
    command -v jq &>/dev/null || skip "jq not installed"
}

@test "agent-protocol-v1.json exists in templates" {
    [ -f "$PROTOCOL_FILE" ]
}

@test "agent-protocol-v1.json is valid JSON" {
    run jq empty "$PROTOCOL_FILE"
    [ "$status" -eq 0 ]
}

@test "schema has correct id" {
    result=$(jq -r '."$id"' "$PROTOCOL_FILE")
    [ "$result" = "korero-agent-protocol-v1" ]
}

@test "schema has correct title" {
    result=$(jq -r '.title' "$PROTOCOL_FILE")
    [[ "$result" == *"Agent Communication Protocol"* ]]
}

@test "schema contains all 5 message types" {
    result=$(jq -r '.definitions.messageType.enum | join(",")' "$PROTOCOL_FILE")
    [[ "$result" == *"PROPOSAL"* ]]
    [[ "$result" == *"CHALLENGE"* ]]
    [[ "$result" == *"DEFENSE"* ]]
    [[ "$result" == *"EVALUATION"* ]]
    [[ "$result" == *"SELECTION"* ]]
}

@test "schema defines exactly 5 message types" {
    count=$(jq '.definitions.messageType.enum | length' "$PROTOCOL_FILE")
    [ "$count" -eq 5 ]
}

@test "schema includes 3 mandatory evaluation agents" {
    result=$(jq -r '.definitions.evaluationAgentId.enum | join(",")' "$PROTOCOL_FILE")
    [[ "$result" == *"devils-advocate"* ]]
    [[ "$result" == *"technical-feasibility-analyst"* ]]
    [[ "$result" == *"idea-orchestrator"* ]]
}

@test "schema defines exactly 3 evaluation agents" {
    count=$(jq '.definitions.evaluationAgentId.enum | length' "$PROTOCOL_FILE")
    [ "$count" -eq 3 ]
}

@test "agentId is generic (not project-specific enum)" {
    # agentId should be a plain string type, not an enum — domain agents are project-specific
    agent_type=$(jq -r '.definitions.agentId.type' "$PROTOCOL_FILE")
    [ "$agent_type" = "string" ]
    # Should NOT have an enum on agentId (only evaluationAgentId has one)
    has_enum=$(jq '.definitions.agentId | has("enum")' "$PROTOCOL_FILE")
    [ "$has_enum" = "false" ]
}

@test "baseMessage requires messageId, type, sender, timestamp, loop" {
    required=$(jq -r '.definitions.baseMessage.required | sort | join(",")' "$PROTOCOL_FILE")
    [ "$required" = "loop,messageId,sender,timestamp,type" ]
}

@test "proposal definition includes required fields" {
    # Check the second allOf entry (the proposal-specific fields)
    required=$(jq -r '.definitions.proposal.allOf[1].required | sort | join(",")' "$PROTOCOL_FILE")
    [[ "$required" == *"brief"* ]]
    [[ "$required" == *"description"* ]]
    [[ "$required" == *"ideaType"* ]]
    [[ "$required" == *"title"* ]]
}

@test "challenge definition references proposalRef" {
    required=$(jq -r '.definitions.challenge.allOf[1].required | join(",")' "$PROTOCOL_FILE")
    [[ "$required" == *"proposalRef"* ]]
    [[ "$required" == *"concern"* ]]
    [[ "$required" == *"question"* ]]
}

@test "defense definition references both proposalRef and challengeRef" {
    required=$(jq -r '.definitions.defense.allOf[1].required | join(",")' "$PROTOCOL_FILE")
    [[ "$required" == *"proposalRef"* ]]
    [[ "$required" == *"challengeRef"* ]]
    [[ "$required" == *"response"* ]]
}

@test "evaluation definition includes scores and verdict" {
    required=$(jq -r '.definitions.evaluation.allOf[1].required | join(",")' "$PROTOCOL_FILE")
    [[ "$required" == *"scores"* ]]
    [[ "$required" == *"verdict"* ]]
}

@test "evaluation scores allow additional properties" {
    additional=$(jq '.definitions.evaluation.allOf[1].properties.scores.additionalProperties' "$PROTOCOL_FILE")
    [ "$additional" = "true" ]
}

@test "selection definition includes winnerId and rankings" {
    required=$(jq -r '.definitions.selection.allOf[1].required | join(",")' "$PROTOCOL_FILE")
    [[ "$required" == *"winnerId"* ]]
    [[ "$required" == *"rankings"* ]]
    [[ "$required" == *"rationale"* ]]
}

@test "ideaType enum includes standard types" {
    result=$(jq -r '.definitions.ideaType.enum | join(",")' "$PROTOCOL_FILE")
    [[ "$result" == *"New Feature"* ]]
    [[ "$result" == *"Usability Improvement"* ]]
    [[ "$result" == *"Bug Fix"* ]]
}

@test "all message definitions use allOf with baseMessage" {
    for msg_type in proposal challenge defense evaluation selection; do
        ref=$(jq -r ".definitions.${msg_type}.allOf[0].\"\$ref\"" "$PROTOCOL_FILE")
        [ "$ref" = "#/definitions/baseMessage" ]
    done
}

@test "protocol README exists in templates" {
    [ -f "$REPO_ROOT/templates/protocols/README.md" ]
}

@test "protocol README documents all message types" {
    readme="$REPO_ROOT/templates/protocols/README.md"
    grep -q "PROPOSAL" "$readme"
    grep -q "CHALLENGE" "$readme"
    grep -q "DEFENSE" "$readme"
    grep -q "EVALUATION" "$readme"
    grep -q "SELECTION" "$readme"
}

# Integration: verify protocols directory gets created in korero structure
@test "create_korero_structure includes protocols directory" {
    source "$REPO_ROOT/lib/enable_core.sh" 2>/dev/null

    local test_dir
    test_dir=$(mktemp -d)
    cd "$test_dir"

    ENABLE_KORERO_MODE="coding" create_korero_structure

    [ -d ".korero/protocols" ]

    rm -rf "$test_dir"
}
