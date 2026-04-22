#!/bin/bash
# ACTS Bash Helper Library
# Source this file in bash operations: source .acts/lib/helpers.sh

# Read JSON input from stdin and parse with jq
acts_read_input() {
    cat
}

# Get a value from input JSON
acts_get_input() {
    local input_json="$1"
    local key="$2"
    echo "$input_json" | jq -r ".$key // empty"
}

# Build and output success result
acts_success() {
    local results="${1:-{}}"
    local artifacts="${2:-{}}"
    
    cat <<EOF
{
  "status": "success",
  "results": $results,
  "artifacts": $artifacts
}
EOF
}

# Build and output approved result
acts_approved() {
    local results="${1:-{}}"
    local artifacts="${2:-{}}"
    
    cat <<EOF
{
  "status": "approved",
  "results": $results,
  "artifacts": $artifacts
}
EOF
}

# Build and output changes_requested result
acts_changes_requested() {
    local results="${1:-{}}"
    local artifacts="${2:-{}}"
    
    cat <<EOF
{
  "status": "changes_requested",
  "results": $results,
  "artifacts": $artifacts
}
EOF
}

# Build and output error result
acts_error() {
    local message="$1"
    
    cat <<EOF
{
  "status": "error",
  "error": "$message"
}
EOF
}

# Call another operation synchronously
acts_call() {
    local operation_id="$1"
    shift
    
    # Build input JSON
    local inputs="{}"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --input)
                local key="${2%%=*}"
                local val="${2#*=}"
                inputs=$(echo "$inputs" | jq --arg k "$key" --arg v "$val" '.[$k] = $v')
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Build full invocation
    local invocation=$(jq -n \
        --arg op "$operation_id" \
        --arg caller "${ACTS_OPERATION_ID:-}" \
        --argjson inputs "$inputs" \
        '{operation_id: $op, caller: $caller, inputs: $inputs}')
    
    # Call operation and return output
    echo "$invocation" | acts run "$operation_id" --parent-operation "${ACTS_OPERATION_ID:-}"
}

# Log to stderr
acts_log() {
    local level="$1"
    shift
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $level: $*" >&2
}

# Get current operation ID from environment
acts_current_operation() {
    echo "${ACTS_OPERATION_ID:-}"
}

# Get caller operation ID from environment
acts_caller() {
    echo "${ACTS_CALLER:-}"
}
