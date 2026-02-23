#!/usr/bin/env bats

# Tests for lib/permission_presets.sh — Permission Template Presets

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    source "$REPO_ROOT/lib/permission_presets.sh"
}

# =============================================================================
# expand_tool_preset tests (5 tests)
# =============================================================================

@test "expand_tool_preset expands @conservative" {
    result=$(expand_tool_preset "@conservative")
    [ "$result" = "Write,Read,Edit" ]
}

@test "expand_tool_preset expands @standard" {
    result=$(expand_tool_preset "@standard")
    [[ "$result" == *"Write"* ]]
    [[ "$result" == *"Bash(git *)"* ]]
    [[ "$result" == *"Bash(npm *)"* ]]
    [[ "$result" == *"Bash(pytest)"* ]]
}

@test "expand_tool_preset expands @permissive" {
    result=$(expand_tool_preset "@permissive")
    [[ "$result" == *"Write"* ]]
    [[ "$result" == *"Bash(*)"* ]]
}

@test "expand_tool_preset returns error for unknown preset" {
    run expand_tool_preset "@unknown"
    [ "$status" -eq 1 ]
}

@test "expand_tool_preset returns error for non-preset string" {
    run expand_tool_preset "Write"
    [ "$status" -eq 1 ]
}

# =============================================================================
# expand_allowed_tools tests (7 tests)
# =============================================================================

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

@test "expand_allowed_tools passes through plain tool list unchanged" {
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

@test "expand_allowed_tools handles multiple presets combined" {
    result=$(expand_allowed_tools "@conservative,Bash(pytest)")
    [[ "$result" == *"Write,Read,Edit"* ]]
    [[ "$result" == *"Bash(pytest)"* ]]
}

@test "expand_allowed_tools @standard matches explicit default" {
    result=$(expand_allowed_tools "@standard")
    [ "$result" = "Write,Read,Edit,Bash(git *),Bash(npm *),Bash(pytest)" ]
}

# =============================================================================
# Integration: expanded output works with build_claude_command pattern (3 tests)
# =============================================================================

@test "expanded @standard is comma-splittable for CLI args" {
    local expanded
    expanded=$(expand_allowed_tools "@standard")

    local IFS=','
    read -ra tools_array <<< "$expanded"

    # Should have at least 5 tools: Write, Read, Edit, Bash(git *), Bash(npm *)
    [[ ${#tools_array[@]} -ge 5 ]]

    # First tool should be Write
    local trimmed
    trimmed=$(echo "${tools_array[0]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ "$trimmed" = "Write" ]
}

@test "expanded @conservative,custom is comma-splittable" {
    local expanded
    expanded=$(expand_allowed_tools "@conservative,Bash(docker *)")

    local IFS=','
    read -ra tools_array <<< "$expanded"

    # Should have 4: Write, Read, Edit, Bash(docker *)
    [[ ${#tools_array[@]} -eq 4 ]]
}

# =============================================================================
# list_presets tests (2 tests)
# =============================================================================

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
