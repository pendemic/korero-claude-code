#!/usr/bin/env bats

# Tests for lib/permission_presets.sh — Permission Template Presets

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    source "$REPO_ROOT/lib/permission_presets.sh"
}

# --- expand_tool_preset ---

@test "expand_tool_preset expands @conservative" {
    result=$(expand_tool_preset "@conservative")
    [ "$result" = "Write,Read,Edit" ]
}

@test "expand_tool_preset expands @standard" {
    result=$(expand_tool_preset "@standard")
    [[ "$result" == *"Write"* ]]
    [[ "$result" == *"Bash(git *)"* ]]
    [[ "$result" == *"Bash(npm *)"* ]]
}

@test "expand_tool_preset expands @permissive" {
    result=$(expand_tool_preset "@permissive")
    [[ "$result" == *"Bash(*)"* ]]
}

@test "expand_tool_preset returns error for unknown preset" {
    run expand_tool_preset "@unknown"
    [ "$status" -eq 1 ]
}

@test "expand_tool_preset returns error for non-preset" {
    run expand_tool_preset "Write"
    [ "$status" -eq 1 ]
}

# --- expand_allowed_tools ---

@test "expand_allowed_tools expands pure preset" {
    result=$(expand_allowed_tools "@standard")
    [[ "$result" == *"Write"* ]]
    [[ "$result" == *"Read"* ]]
    [[ "$result" == *"Edit"* ]]
    [[ "$result" == *"Bash(git *)"* ]]
}

@test "expand_allowed_tools expands preset with custom tools" {
    result=$(expand_allowed_tools "@conservative,Bash(docker *)")
    [[ "$result" == *"Write"* ]]
    [[ "$result" == *"Read"* ]]
    [[ "$result" == *"Edit"* ]]
    [[ "$result" == *"Bash(docker *)"* ]]
}

@test "expand_allowed_tools passes through plain tool list" {
    result=$(expand_allowed_tools "Write,Read,Edit")
    [ "$result" = "Write,Read,Edit" ]
}

@test "expand_allowed_tools handles empty input" {
    result=$(expand_allowed_tools "")
    [ "$result" = "" ]
}

@test "expand_allowed_tools warns on unknown preset" {
    result=$(expand_allowed_tools "@bogus" 2>&1)
    [[ "$result" == *"Unknown preset"* ]]
}

@test "expand_allowed_tools combines multiple presets" {
    result=$(expand_allowed_tools "@conservative,Bash(pytest)")
    [[ "$result" == *"Write,Read,Edit"* ]]
    [[ "$result" == *"Bash(pytest)"* ]]
}

# --- list_presets ---

@test "list_presets shows all three presets" {
    run list_presets
    [ "$status" -eq 0 ]
    [[ "$output" == *"@conservative"* ]]
    [[ "$output" == *"@standard"* ]]
    [[ "$output" == *"@permissive"* ]]
}

@test "list_presets shows usage example" {
    run list_presets
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALLOWED_TOOLS"* ]]
}
