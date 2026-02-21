#!/usr/bin/env bats

# Tests for lib/path_utils.sh — Path Separator Normalization

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    source "$REPO_ROOT/lib/path_utils.sh"
}

# --- normalize_path ---

@test "normalize_path converts backslashes to forward slashes" {
    result=$(normalize_path 'C:\Users\test\project')
    [ "$result" = "C:/Users/test/project" ]
}

@test "normalize_path handles mixed separators" {
    result=$(normalize_path 'C:\Users/test\project/src')
    [ "$result" = "C:/Users/test/project/src" ]
}

@test "normalize_path removes trailing slash" {
    result=$(normalize_path "/home/user/project/")
    [ "$result" = "/home/user/project" ]
}

@test "normalize_path preserves root slash" {
    result=$(normalize_path "/")
    [ "$result" = "/" ]
}

@test "normalize_path handles empty input" {
    result=$(normalize_path "")
    [ "$result" = "" ]
}

@test "normalize_path handles unix paths unchanged" {
    result=$(normalize_path "/home/user/project")
    [ "$result" = "/home/user/project" ]
}

# --- join_path ---

@test "join_path joins two segments" {
    result=$(join_path "/home/user" "project")
    [ "$result" = "/home/user/project" ]
}

@test "join_path handles trailing slash in base" {
    result=$(join_path "/home/user/" "project")
    [ "$result" = "/home/user/project" ]
}

@test "join_path handles leading slash in segment" {
    result=$(join_path "/home/user" "/project")
    [ "$result" = "/home/user/project" ]
}

@test "join_path normalizes backslashes" {
    result=$(join_path 'C:\Users' 'test\project')
    [ "$result" = "C:/Users/test/project" ]
}

@test "join_path handles empty base" {
    result=$(join_path "" "project")
    [ "$result" = "project" ]
}

@test "join_path handles empty segment" {
    result=$(join_path "/home/user" "")
    [ "$result" = "/home/user" ]
}

# --- get_dir_path ---

@test "get_dir_path returns parent directory" {
    result=$(get_dir_path "/home/user/file.txt")
    [ "$result" = "/home/user" ]
}

@test "get_dir_path normalizes backslashes" {
    result=$(get_dir_path 'C:\Users\test\file.txt')
    [ "$result" = "C:/Users/test" ]
}

@test "get_dir_path returns dot for filename only" {
    result=$(get_dir_path "file.txt")
    [ "$result" = "." ]
}

# --- get_filename ---

@test "get_filename returns filename" {
    result=$(get_filename "/home/user/file.txt")
    [ "$result" = "file.txt" ]
}

@test "get_filename normalizes backslashes" {
    result=$(get_filename 'C:\Users\test\file.txt')
    [ "$result" = "file.txt" ]
}

# --- is_absolute_path ---

@test "is_absolute_path detects unix absolute" {
    run is_absolute_path "/home/user"
    [ "$status" -eq 0 ]
}

@test "is_absolute_path detects windows absolute" {
    run is_absolute_path "C:/Users/test"
    [ "$status" -eq 0 ]
}

@test "is_absolute_path detects windows backslash absolute" {
    run is_absolute_path 'C:\Users\test'
    [ "$status" -eq 0 ]
}

@test "is_absolute_path rejects relative" {
    run is_absolute_path "src/main.sh"
    [ "$status" -eq 1 ]
}

# --- normalize_env_paths ---

@test "normalize_env_paths normalizes exported variables" {
    export TEST_PATH_VAR='C:\Users\test'
    normalize_env_paths TEST_PATH_VAR
    [ "$TEST_PATH_VAR" = "C:/Users/test" ]
    unset TEST_PATH_VAR
}

@test "normalize_env_paths handles multiple variables" {
    export TEST_P1='C:\a'
    export TEST_P2='D:\b'
    normalize_env_paths TEST_P1 TEST_P2
    [ "$TEST_P1" = "C:/a" ]
    [ "$TEST_P2" = "D:/b" ]
    unset TEST_P1 TEST_P2
}

@test "normalize_env_paths skips unset variables" {
    unset TEST_UNSET_VAR 2>/dev/null || true
    run normalize_env_paths TEST_UNSET_VAR
    [ "$status" -eq 0 ]
}
