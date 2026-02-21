#!/usr/bin/env bash

# security_scanner.sh - Sensitive config pattern scanner
# Scans .korerorc for potential secrets (API keys, tokens, credentials)
# to prevent accidental git commits of sensitive data.

# Pattern definitions: name -> regex
declare -A SENSITIVE_PATTERNS
SENSITIVE_PATTERNS=(
    ["OpenAI API Key"]='sk-[A-Za-z0-9]{20,}'
    ["GitHub Token"]='gh[pousr]_[A-Za-z0-9]{36,}'
    ["AWS Access Key"]='AKIA[0-9A-Z]{16}'
    ["AWS Secret Key"]='[A-Za-z0-9/+=]{40}'
    ["Generic API Key"]='["\x27]?[A-Za-z0-9]{32,}["\x27]?'
    ["Bearer Token"]='Bearer [A-Za-z0-9._\-]{20,}'
    ["Base64 Secret"]='[A-Za-z0-9+/]{40,}={0,2}'
)

# Scan a file for sensitive patterns
# Usage: scan_sensitive_patterns <file_path>
# Returns: 0 if clean, 1 if warnings found
scan_sensitive_patterns() {
    local file_path="${1:-.korerorc}"
    local warnings=0
    local line_num=0

    if [[ ! -f "$file_path" ]]; then
        return 0
    fi

    local findings=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))

        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Skip lines with trusted annotation
        [[ "$line" == *"# korero: trusted"* ]] && continue

        # Skip lines that are just variable names or simple values
        # Only check lines that have a value assignment
        [[ ! "$line" == *=* ]] && continue

        # Extract the value part (after the =)
        local value="${line#*=}"
        # Remove surrounding quotes
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"

        # Skip known safe values (preset names, simple configs)
        [[ "$value" == "@"* ]] && continue
        [[ "$value" == "true" || "$value" == "false" ]] && continue
        [[ "$value" == "coding" || "$value" == "idea" ]] && continue
        [[ "$value" == "continuous" ]] && continue
        [[ ${#value} -lt 16 ]] && continue

        # Check for OpenAI key pattern
        if [[ "$value" =~ sk-[A-Za-z0-9]{20,} ]]; then
            findings+=("  Line $line_num: Possible OpenAI API Key detected")
            warnings=$((warnings + 1))
            continue
        fi

        # Check for GitHub token pattern
        if [[ "$value" =~ gh[pousr]_[A-Za-z0-9]{36,} ]]; then
            findings+=("  Line $line_num: Possible GitHub Token detected")
            warnings=$((warnings + 1))
            continue
        fi

        # Check for AWS Access Key pattern
        if [[ "$value" =~ AKIA[0-9A-Z]{16} ]]; then
            findings+=("  Line $line_num: Possible AWS Access Key detected")
            warnings=$((warnings + 1))
            continue
        fi

        # Check for Bearer token pattern
        if [[ "$value" =~ Bearer\ [A-Za-z0-9._-]{20,} ]]; then
            findings+=("  Line $line_num: Possible Bearer Token detected")
            warnings=$((warnings + 1))
            continue
        fi

        # Check for generic long hex/alphanumeric strings that look like secrets
        # Must be a standalone value (not a tool list or path)
        if [[ ! "$value" == *","* && ! "$value" == *"/"* && ! "$value" == *" "* ]]; then
            if [[ "$value" =~ ^[A-Za-z0-9+/=_-]{40,}$ ]]; then
                findings+=("  Line $line_num: Possible secret/token (long encoded string)")
                warnings=$((warnings + 1))
                continue
            fi
        fi
    done < "$file_path"

    if [[ $warnings -gt 0 ]]; then
        echo "WARNING: Potential secrets found in $file_path:"
        for finding in "${findings[@]}"; do
            echo "$finding"
        done
        echo ""
        echo "Suppress warnings with '# korero: trusted' comment on the line."
        echo "Consider using environment variables for sensitive values."
        return 1
    fi

    return 0
}

# Run scan and display results (for use in startup)
# Usage: run_security_scan [file_path]
run_security_scan() {
    local file_path="${1:-.korerorc}"
    local result
    result=$(scan_sensitive_patterns "$file_path" 2>&1)
    local status=$?

    if [[ $status -ne 0 ]]; then
        echo "$result" >&2
    fi

    return $status
}

export -f scan_sensitive_patterns
export -f run_security_scan
