#!/usr/bin/env bats

# Tests for the mock Claude response library

load '../helpers/mocks'

setup() {
    TEST_DIR="$(mktemp -d)"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "load_mock_response loads existing mock" {
    result=$(load_mock_response "success" "simple_completion")
    [ -n "$result" ]
    [[ "$result" == *"_mock_metadata"* ]]
}

@test "load_mock_response fails for missing mock" {
    run load_mock_response "nonexistent" "fake"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Mock not found"* ]]
}

@test "load_mock_response_content strips metadata" {
    result=$(load_mock_response_content "success" "simple_completion")
    [[ "$result" != *"_mock_metadata"* ]]
    [[ "$result" == *"result"* ]]
}

@test "load_mock_response_content preserves result field" {
    result=$(load_mock_response_content "success" "simple_completion")
    echo "$result" | jq -e '.result' > /dev/null
}

@test "get_mock_expected_behavior returns behavior string" {
    result=$(get_mock_expected_behavior "success" "simple_completion")
    [[ "$result" == *"Loop continues"* ]]
}

@test "get_mock_scenario returns scenario string" {
    result=$(get_mock_scenario "success" "simple_completion")
    [[ "$result" == *"Simple successful completion"* ]]
}

@test "write_mock_to_file creates valid JSON file" {
    write_mock_to_file "success" "simple_completion" "$TEST_DIR/response.json"
    [ -f "$TEST_DIR/response.json" ]
    jq -e '.' "$TEST_DIR/response.json" > /dev/null
}

@test "permission mock contains permission_denials array" {
    result=$(load_mock_response_content "permission" "single_denial")
    count=$(echo "$result" | jq '.permission_denials | length')
    [ "$count" -eq 1 ]
}

@test "multiple denials mock has correct count" {
    result=$(load_mock_response_content "permission" "multiple_denials")
    count=$(echo "$result" | jq '.permission_denials | length')
    [ "$count" -eq 2 ]
}

@test "error mock contains is_error field" {
    result=$(load_mock_response_content "errors" "rate_limit")
    is_error=$(echo "$result" | jq -r '.is_error')
    [ "$is_error" = "true" ]
}

@test "status mock with exit signal contains KORERO_STATUS" {
    result=$(load_mock_response_content "status" "complete_exit")
    [[ "$(echo "$result" | jq -r '.result')" == *"EXIT_SIGNAL: true"* ]]
}

@test "success mock with file changes reports files modified" {
    result=$(load_mock_response_content "success" "with_file_changes")
    [[ "$(echo "$result" | jq -r '.result')" == *"FILES_MODIFIED: 3"* ]]
}
