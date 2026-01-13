#!/usr/bin/env bash

# Ralph Wiggum Technique: Simple for-loop orchestration for AI coding agents
# "I'm helping!" - Ralph Wiggum

set -euo pipefail

# Configuration
MAX_ITERATIONS="${1:-10}"
PRD_FILE="plans/prd.json"
PROGRESS_FILE="plans/progress.txt"
COMPLETION_SIGNAL="promise complete here"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging helpers
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check dependencies
check_dependencies() {
    local deps=("jq" "git")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "Required dependency '$dep' not found"
            exit 1
        fi
    done
}

# Get the next incomplete task from PRD
get_next_task() {
    local task=$(jq -r '.[] | select(.passes == false) | @json' "$PRD_FILE" | head -1)
    echo "$task"
}

# Count incomplete tasks
count_incomplete_tasks() {
    jq '[.[] | select(.passes == false)] | length' "$PRD_FILE"
}

# Mark task as complete
mark_task_complete() {
    local task_id="$1"
    local temp_file=$(mktemp)

    jq --arg id "$task_id" \
       'map(if .id == $id then .passes = true else . end)' \
       "$PRD_FILE" > "$temp_file"

    mv "$temp_file" "$PRD_FILE"
    log_success "Marked task '$task_id' as complete in PRD"
}

# Append progress note
append_progress() {
    local iteration="$1"
    local task_id="$2"
    local task_desc="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    cat >> "$PROGRESS_FILE" << EOF

================================================================================
Iteration $iteration | $timestamp
Task: $task_id
Description: $task_desc
--------------------------------------------------------------------------------
EOF
}

# Verify code quality (type checking, tests, etc.)
verify_implementation() {
    log_info "Running verification checks..."

    # TypeScript type checking (if package.json has typecheck script)
    if [ -f "package.json" ] && jq -e '.scripts.typecheck' package.json > /dev/null 2>&1; then
        log_info "Running TypeScript type check..."
        if ! pnpm typecheck; then
            log_error "TypeScript type check failed"
            return 1
        fi
        log_success "TypeScript type check passed"
    fi

    # Run tests (if package.json has test script)
    if [ -f "package.json" ] && jq -e '.scripts.test' package.json > /dev/null 2>&1; then
        log_info "Running tests..."
        if ! pnpm test; then
            log_error "Tests failed"
            return 1
        fi
        log_success "Tests passed"
    fi

    # Linting (if package.json has lint script)
    if [ -f "package.json" ] && jq -e '.scripts.lint' package.json > /dev/null 2>&1; then
        log_info "Running linter..."
        if ! pnpm lint; then
            log_warning "Linting issues found (non-blocking)"
        else
            log_success "Linting passed"
        fi
    fi

    return 0
}

# Execute a single task
# This is where the AI agent does the actual work
execute_task() {
    local task_json="$1"
    local task_id=$(echo "$task_json" | jq -r '.id')
    local task_desc=$(echo "$task_json" | jq -r '.description')
    local task_context=$(echo "$task_json" | jq -r '.context // ""')

    log_info "Task ID: $task_id"
    log_info "Description: $task_desc"

    # ============================================================================
    # AI AGENT INVOCATION POINT
    # ============================================================================
    # Run the task in the sandbox container
    # We mount the current directory to /app to allow the agent to modify files
    # defined in the current workspace.
    log_info "Invoking AI agent via Docker sandbox..."
    
    if ! docker run sandbox claude -p "$task_desc"; then
        log_error "AI Agent execution failed in Docker sandbox"
        return 1
    fi

    return 0
}

# Create git commit for completed task
commit_task() {
    local task_id="$1"
    local task_desc="$2"

    # Stage all changes including PRD and progress files
    git add -A

    # Create commit with descriptive message
    local commit_msg="feat: Complete task $task_id

$task_desc

- Implemented feature as specified
- Updated PRD to mark task complete
- Logged progress

Co-Authored-By: Ralph Wiggum (AI Agent) <ralph@ai.local>"

    if git diff --cached --quiet; then
        log_warning "No changes to commit for task $task_id"
    else
        git commit -m "$commit_msg"
        log_success "Created commit for task $task_id"
    fi
}

# Main iteration loop
main() {
    log_info "Starting Ralph Wiggum Technique orchestration"
    log_info "Max iterations: $MAX_ITERATIONS"
    echo ""

    check_dependencies

    # Initialize progress file if it doesn't exist
    if [ ! -f "$PROGRESS_FILE" ]; then
        touch "$PROGRESS_FILE"
        echo "Ralph Wiggum Technique Progress Log" > "$PROGRESS_FILE"
        echo "====================================" >> "$PROGRESS_FILE"
    fi

    for iteration in $(seq 1 "$MAX_ITERATIONS"); do
        echo ""
        log_info "========================================"
        log_info "Iteration $iteration of $MAX_ITERATIONS"
        log_info "========================================"

        # Count remaining tasks
        local remaining=$(count_incomplete_tasks)
        log_info "Remaining tasks: $remaining"

        # Get next task
        local task=$(get_next_task)

        if [ -z "$task" ] || [ "$task" = "null" ]; then
            log_success "All tasks complete!"
            echo "$COMPLETION_SIGNAL"
            exit 0
        fi

        local task_id=$(echo "$task" | jq -r '.id')
        local task_desc=$(echo "$task" | jq -r '.description')

        # Append progress header
        append_progress "$iteration" "$task_id" "$task_desc"

        # Execute the task (AI agent does the work)
        log_info "Executing task..."
        if ! execute_task "$task"; then
            log_error "Task execution failed"
            echo "Status: FAILED - Task execution error" >> "$PROGRESS_FILE"
            exit 1
        fi

        # Verify implementation
        log_info "Verifying implementation..."
        if ! verify_implementation; then
            log_error "Verification failed - CI must stay green!"
            echo "Status: FAILED - Verification checks failed" >> "$PROGRESS_FILE"
            exit 1
        fi

        # Mark task complete
        mark_task_complete "$task_id"

        # Append success to progress
        echo "Status: ✓ COMPLETE" >> "$PROGRESS_FILE"
        echo "Verification: All checks passed" >> "$PROGRESS_FILE"

        # Commit changes
        commit_task "$task_id" "$task_desc"

        log_success "Iteration $iteration complete"

        # Brief pause to avoid overwhelming the system
        sleep 1
    done

    log_warning "Reached maximum iterations ($MAX_ITERATIONS)"
    local remaining=$(count_incomplete_tasks)
    if [ "$remaining" -gt 0 ]; then
        log_warning "$remaining tasks still pending"
        exit 1
    fi
}

# Run main loop
main "$@"
