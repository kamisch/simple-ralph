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

    # 1. Custom Post-Hook Script (Highest Priority)
    if [ -f "./ralph-post-hook.sh" ]; then
        if [ -x "./ralph-post-hook.sh" ]; then
            log_info "Found custom verification script: ./ralph-post-hook.sh"
            if ! ./ralph-post-hook.sh; then
                log_error "Custom verification script failed"
                return 1
            fi
            log_success "Custom verification script passed"
            return 0
        else
            log_warning "Found ./ralph-post-hook.sh but it is not executable. Skipped."
        fi
    fi

    local checks_run=0

    # 2. auto-detection: Node.js
    if [ -f "package.json" ]; then
        log_info "Detected Node.js project"
        # TypeScript type checking
        if jq -e '.scripts.typecheck' package.json > /dev/null 2>&1; then
            log_info "Running TypeScript type check..."
            if ! pnpm typecheck; then
                log_error "TypeScript type check failed"
                return 1
            fi
            checks_run=$((checks_run + 1))
        fi

        # Tests
        if jq -e '.scripts.test' package.json > /dev/null 2>&1; then
            log_info "Running tests..."
            if ! pnpm test; then
                log_error "Tests failed"
                return 1
            fi
            checks_run=$((checks_run + 1))
        fi

        # Linting
        if jq -e '.scripts.lint' package.json > /dev/null 2>&1; then
            log_info "Running linter..."
            if ! pnpm lint; then
                log_warning "Linting issues found (non-blocking)"
            fi
            checks_run=$((checks_run + 1))
        fi
    fi

    # 3. auto-detection: Rust
    if [ -f "Cargo.toml" ]; then
        log_info "Detected Rust project"
        
        log_info "Running cargo test..."
        if ! cargo test; then
             log_error "Cargo tests failed"
             return 1
        fi
        checks_run=$((checks_run + 1))

        # Optional: check formatting
        log_info "Checking formatting..."
        if ! cargo fmt -- --check; then
             log_warning "Formatting issues found (non-blocking)"
        fi
    fi

    # 4. auto-detection: Python
    if [ -f "pyproject.toml" ] || [ -f "requirements.txt" ]; then
        log_info "Detected Python project"
        
        if command -v pytest &> /dev/null; then
             log_info "Running pytest..."
             if ! pytest; then
                 log_error "Pytest failed"
                 return 1
             fi
             checks_run=$((checks_run + 1))
        else
             log_warning "pytest not found, skipping python tests"
        fi
    fi

    if [ "$checks_run" -eq 0 ]; then
        log_warning "No verification checks were run (custom script missing and no known project structure detected)"
    else
        log_success "All verification checks passed"
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
    # Docker Desktop's 'docker sandbox' command handles authentication automatically
    log_info "Invoking AI agent via Docker sandbox..."

    # Check if docker sandbox command is available (Docker Desktop feature)
    if ! docker sandbox --help &> /dev/null; then
        log_error "Docker sandbox command not available"
        log_error "This requires Docker Desktop with AI Sandboxes enabled"
        log_error "See: https://docs.docker.com/ai/sandboxes/claude-code"
        return 1
    fi

    # Check if a sandbox exists for this workspace (for logging only)
    # Docker sandbox run will automatically reuse existing sandboxes with their auth state
    local workspace_dir="$(pwd)"
    local existing_sandbox=$(docker sandbox ls | awk -v ws="$workspace_dir" 'NR > 1 && $4 == ws {print $1; exit}')

    if [ -n "$existing_sandbox" ]; then
        log_info "Found existing sandbox: $existing_sandbox (will be reused with auth state)"
    else
        log_info "No existing sandbox found - will create new one for this workspace"
    fi

    # Pass the task description to Claude via docker sandbox
    # The sandbox runs in the current directory and can modify files
    log_info "Task: $task_desc"

    # Create a temporary expect script to automate docker sandbox interaction
    # Docker sandbox requires a TTY and runs interactively, so we use expect to automate it
    local temp_expect=$(mktemp)
    cat > "$temp_expect" << EOFEXPECT
#!/usr/bin/expect -f
set timeout 300
set task_desc [lindex \$argv 0]

# Spawn docker sandbox run claude with non-interactive flags
spawn docker sandbox run claude --dangerously-skip-permissions -p "\$task_desc"

# Wait for the command to complete
expect {
    eof {
        # Command finished
        exit 0
    }
    timeout {
        puts "ERROR: Command timed out after 300 seconds"
        exit 1
    }
}
EOFEXPECT

    chmod +x "$temp_expect"

    # Execute the expect script with the task description
    local exit_code=0
    "$temp_expect" "$task_desc" 2>&1 | tee /tmp/ralph_claude_output.log || exit_code=$?

    if [ $exit_code -ne 0 ]; then
        log_error "AI Agent execution failed in Docker sandbox"
        log_error "Check /tmp/ralph_claude_output.log for details"

        # Check if it's an authentication error
        if grep -q "Invalid API key" /tmp/ralph_claude_output.log; then
            log_error ""
            log_error "Authentication Error Detected!"
            log_error "To fix this, you need to authenticate the Docker sandbox:"
            log_error "  1. Run: docker sandbox run claude"
            log_error "  2. In the interactive session, run: /login"
            log_error "  3. Follow the authentication prompts"
            log_error "  4. After successful login, exit the session (Ctrl+D)"
            log_error "  5. Run ralph.sh again"
            log_error ""
            log_error "Note: Authentication persists across sandbox sessions"
        fi

        rm -f "$temp_expect"
        return 1
    fi

    rm -f "$temp_expect"
    log_success "Task completed successfully"
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
