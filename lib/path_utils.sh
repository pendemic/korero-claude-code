#!/usr/bin/env bash

# path_utils.sh - Cross-platform path normalization
# Converts backslashes to forward slashes for consistent path handling
# across Windows Git Bash, WSL, MSYS2, Cygwin, and native Unix.

# Normalize a path by converting backslashes to forward slashes
# and removing trailing slashes
# Usage: normalize_path <path>
normalize_path() {
    local path="${1:-}"
    # Convert backslashes to forward slashes
    path="${path//\\//}"
    # Remove trailing slash (unless root)
    if [[ ${#path} -gt 1 ]]; then
        path="${path%/}"
    fi
    echo "$path"
}

# Join two path segments with a forward slash
# Usage: join_path <base> <segment>
join_path() {
    local base="${1:-}"
    local segment="${2:-}"

    base=$(normalize_path "$base")
    segment=$(normalize_path "$segment")

    # Remove trailing slash from base
    base="${base%/}"
    # Remove leading slash from segment
    segment="${segment#/}"

    if [[ -z "$base" ]]; then
        echo "$segment"
    elif [[ -z "$segment" ]]; then
        echo "$base"
    else
        echo "$base/$segment"
    fi
}

# Get directory part of a path
# Usage: get_dir_path <path>
get_dir_path() {
    local path
    path=$(normalize_path "${1:-}")

    if [[ "$path" == */* ]]; then
        echo "${path%/*}"
    else
        echo "."
    fi
}

# Get filename part of a path
# Usage: get_filename <path>
get_filename() {
    local path
    path=$(normalize_path "${1:-}")
    echo "${path##*/}"
}

# Check if path is absolute
# Usage: is_absolute_path <path>
is_absolute_path() {
    local path
    path=$(normalize_path "${1:-}")

    # Unix absolute
    [[ "$path" == /* ]] && return 0
    # Windows drive letter (C:/)
    [[ "$path" =~ ^[A-Za-z]:/ ]] && return 0

    return 1
}

# Normalize multiple paths from environment variables
# Usage: normalize_env_paths VAR1 VAR2 ...
normalize_env_paths() {
    for var_name in "$@"; do
        local current_value="${!var_name:-}"
        if [[ -n "$current_value" ]]; then
            local normalized
            normalized=$(normalize_path "$current_value")
            export "$var_name=$normalized"
        fi
    done
}

export -f normalize_path
export -f join_path
export -f get_dir_path
export -f get_filename
export -f is_absolute_path
export -f normalize_env_paths
