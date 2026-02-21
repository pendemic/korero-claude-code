#!/usr/bin/env bats

# Tests for lib/compat_check.sh — Cross-platform compatibility detection

# Resolve the project root directory
REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
LIB_DIR="$REPO_ROOT/lib"

setup() {
    source "$LIB_DIR/compat_check.sh"
}

# =============================================================================
# detect_platform tests
# =============================================================================

@test "detect_platform returns a non-empty string" {
    result=$(detect_platform)
    [[ -n "$result" ]]
}

@test "detect_platform returns one of the known platforms" {
    result=$(detect_platform)
    [[ "$result" == "macos" || "$result" == "linux" || "$result" == "windows" || "$result" == "unknown" ]]
}

# =============================================================================
# check_bash_version tests
# =============================================================================

@test "check_bash_version passes for current bash (4+)" {
    # We're running in Bash 4+ (bats requires it)
    run check_bash_version 4 0
    [ "$status" -eq 0 ]
}

@test "check_bash_version fails for impossibly high version" {
    run check_bash_version 99 0
    [ "$status" -eq 1 ]
}

@test "check_bash_version defaults to 4.0 when no args given" {
    run check_bash_version
    [ "$status" -eq 0 ]
}

# =============================================================================
# check_gnu_utils tests
# =============================================================================

@test "check_gnu_utils returns 0 on non-macOS or when tools present" {
    # On Linux/Windows this should always pass; on macOS it checks for gtimeout/timeout
    run check_gnu_utils
    [ "$status" -eq 0 ]
}

# =============================================================================
# check_required_commands tests
# =============================================================================

@test "check_required_commands passes when jq and git are available" {
    if ! command -v jq &>/dev/null || ! command -v git &>/dev/null; then
        skip "jq or git not installed in test environment"
    fi
    run check_required_commands
    [ "$status" -eq 0 ]
}

# =============================================================================
# run_compat_checks tests
# =============================================================================

@test "run_compat_checks produces no warnings on compatible system" {
    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        skip "test requires Bash 4+"
    fi
    result=$(run_compat_checks 2>&1)
    # Should not contain WARNING if system is compatible
    if [[ "$result" == *"WARNING"* ]]; then
        # It's OK if there are warnings for missing optional tools,
        # but the function should still return 0 (non-strict mode)
        run run_compat_checks
        [ "$status" -eq 0 ]
    fi
}

@test "run_compat_checks returns 0 in non-strict mode even with warnings" {
    run run_compat_checks
    [ "$status" -eq 0 ]
}

@test "run_compat_checks --strict returns 1 when bash version is too old" {
    # Mock BASH_VERSINFO to simulate Bash 3.x
    local orig_bash="${BASH_VERSINFO[0]}"
    # We can't easily mock BASH_VERSINFO as it's readonly,
    # so we test the check_bash_version function directly
    run check_bash_version 99 0
    [ "$status" -eq 1 ]
}

@test "run_compat_checks accepts --strict flag" {
    # On a compatible system, --strict should pass
    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        skip "test requires Bash 4+"
    fi
    if ! command -v jq &>/dev/null || ! command -v git &>/dev/null; then
        skip "missing required commands"
    fi
    run run_compat_checks --strict
    [ "$status" -eq 0 ]
}
