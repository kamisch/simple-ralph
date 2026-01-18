#!/usr/bin/env bash

# Ralph Wiggum Technique: Simple for-loop orchestration for AI coding agents
# "I'm helping!" - Ralph Wiggum

set -euo pipefail

# Configuration
MAX_ITERATIONS="${1:-10}"
PRD_FILE="plans/prd.json"
PROGRESS_FILE="plans/progress.txt"
COMPLETION_SIGNAL="promise complete here"

# AI Agent selection: claude, gemini, or codex (default: claude)
AI_AGENT="${RALPH_AI_AGENT:-claude}"

# Validate AI agent selection
if [[ "$AI_AGENT" != "claude" && "$AI_AGENT" != "gemini" && "$AI_AGENT" != "codex" ]]; then
    echo "Error: Invalid AI_AGENT '$AI_AGENT'. Must be 'claude', 'gemini', or 'codex'." >&2
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging helpers (all output to stderr to avoid polluting stdout captures)
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
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

# Get all incomplete tasks as JSON array
get_incomplete_tasks() {
    jq '[.[] | select(.passes == false)]' "$PRD_FILE"
}

# Get the last 250 lines of progress.txt for context
get_progress_context() {
    if [ -f "$PROGRESS_FILE" ]; then
        tail -n 250 "$PROGRESS_FILE"
    else
        echo "(no progress history yet)"
    fi
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

# Execute a task cycle - agent selects and implements a task
# Returns the completed task ID via stdout, or empty on failure
execute_task_cycle() {
    log_info "Gathering context for AI agent..."

    local incomplete_tasks=$(get_incomplete_tasks)
    local progress_context=$(get_progress_context)
    local task_count=$(echo "$incomplete_tasks" | jq 'length')

    if [ "$task_count" -eq 0 ]; then
        log_info "No incomplete tasks found."
        echo ""  # Return empty
        return 0
    fi

    log_info "Found $task_count incomplete task(s)"

    # Build the full prompt for the agent
    local prompt="You are an autonomous developer working on this project.

## Your Backlog (Incomplete Tasks)
Review these tasks and determine highest priority taskto work on next based on dependencies and context.

\`\`\`json
$incomplete_tasks
\`\`\`

## Recent Progress History
Here is the recent work done on this project:

\`\`\`
$progress_context
\`\`\`

## Instructions
1. Analyze the backlog and recent history.
2. Determine the most logical next task based on:
   - Dependencies between tasks (check context field)
   - What has already been completed
   - Logical ordering (foundational tasks before dependent ones)
3. Implement that task completely.
4. After you have successfully implemented and verified the task, you MUST output the following line EXACTLY:

   COMPLETED_TASK_ID: <task-id>

   (IMPORTANT: Replace <task-id> with the actual ID strings from the backlog above, e.g., 'setup-ci' or 'fix-login'. Do NOT use placeholders.)

This output is critical for the orchestration script to track progress."

    # ============================================================================
    # AI AGENT INVOCATION POINT
    # ============================================================================

    # Create a temporary file for the prompt (handles special characters safely)
    local temp_prompt=$(mktemp)
    printf '%s' "$prompt" > "$temp_prompt"

    local exit_code=0

    if [ "$AI_AGENT" = "codex" ]; then
        # ======================================================================
        # CODEX: Run directly from host machine (not supported in Docker sandbox)
        # ======================================================================
        log_info "Invoking AI agent ($AI_AGENT) directly from host machine..."

        # Check if codex command is available
        if ! command -v codex &> /dev/null; then
            log_error "'codex' command not found"
            log_error "Please install Codex CLI: https://github.com/openai/codex"
            rm -f "$temp_prompt"
            return 1
        fi

        # Run codex with the prompt
        # --full-auto: runs without user confirmation
        # --quiet: reduces output noise
        log_info "Running Codex in full-auto mode..."
        codex --full-auto --quiet "$(cat "$temp_prompt")" > /tmp/ralph_${AI_AGENT}_output.log 2>&1 || exit_code=$?

        rm -f "$temp_prompt"

        if [ $exit_code -ne 0 ]; then
            log_error "Codex execution failed"
            log_error "Check /tmp/ralph_${AI_AGENT}_output.log for details"

            if grep -q "OPENAI_API_KEY" /tmp/ralph_${AI_AGENT}_output.log; then
                log_error ""
                log_error "API Key Error Detected!"
                log_error "Make sure OPENAI_API_KEY is set in your environment"
                log_error ""
            fi
            return 1
        fi
    else
        # ======================================================================
        # CLAUDE/GEMINI: Run via Docker sandbox
        # ======================================================================
        log_info "Invoking AI agent ($AI_AGENT) via Docker sandbox..."

        # Check if docker sandbox command is available (Docker Desktop feature)
        if ! docker sandbox --help &> /dev/null; then
            log_error "Docker sandbox command not available"
            log_error "This requires Docker Desktop with AI Sandboxes enabled"
            log_error "See: https://docs.docker.com/ai/sandboxes/"
            rm -f "$temp_prompt"
            return 1
        fi

        # Check if a sandbox exists for this workspace (for logging only)
        local workspace_dir="$(pwd)"
        local existing_sandbox=$(docker sandbox ls | awk -v ws="$workspace_dir" 'NR > 1 && $4 == ws {print $1; exit}')

        if [ -n "$existing_sandbox" ]; then
            log_info "Found existing sandbox: $existing_sandbox (will be reused with auth state)"
        else
            log_info "No existing sandbox found - will create new one for this workspace"
        fi

        # Create a temporary expect script to automate docker sandbox interaction
        local temp_expect=$(mktemp)
        cat > "$temp_expect" <<'EOFEXPECT'
#!/usr/bin/expect -f
set timeout 600
set prompt_file [lindex $argv 0]
set ai_agent [lindex $argv 1]

# Read prompt from file
set fp [open $prompt_file r]
set prompt_content [read $fp]
close $fp

# Spawn docker sandbox run with the selected AI agent
spawn docker sandbox run $ai_agent --dangerously-skip-permissions -p $prompt_content

# Wait for the command to complete
expect {
    eof {
        exit 0
    }
    timeout {
        puts "ERROR: Command timed out after 600 seconds"
        exit 1
    }
}
EOFEXPECT

        chmod +x "$temp_expect"

        # Execute the expect script with AI agent as second argument
        "$temp_expect" "$temp_prompt" "$AI_AGENT" > /tmp/ralph_${AI_AGENT}_output.log 2>&1 || exit_code=$?

        rm -f "$temp_expect" "$temp_prompt"

        if [ $exit_code -ne 0 ]; then
            log_error "AI Agent ($AI_AGENT) execution failed in Docker sandbox"
            log_error "Check /tmp/ralph_${AI_AGENT}_output.log for details"

            if grep -q "Invalid API key" /tmp/ralph_${AI_AGENT}_output.log; then
                log_error ""
                log_error "Authentication Error Detected!"
                log_error "To fix this, you need to authenticate the Docker sandbox:"
                log_error "  1. Run: docker sandbox run $AI_AGENT"
                log_error "  2. In the interactive session, run: /login"
                log_error "  3. Follow the authentication prompts"
                log_error "  4. After successful login, exit the session (Ctrl+D)"
                log_error "  5. Run ralph.sh again"
                log_error ""
            fi
            return 1
        fi
    fi

    # Check for rate limit errors
    if grep -q "hit your limit" /tmp/ralph_${AI_AGENT}_output.log 2>/dev/null; then
        log_error "AI Agent ($AI_AGENT) hit rate limit. Wait for reset and try again."
        return 1
    fi

    # Parse the completed task ID from the output
    local completed_id=$(grep -oE 'COMPLETED_TASK_ID:[[:space:]]*[a-zA-Z0-9_-]+' /tmp/ralph_${AI_AGENT}_output.log | tail -1 | sed 's/COMPLETED_TASK_ID:[[:space:]]*//')

    if [ -z "$completed_id" ]; then
        log_error "Agent did not report a COMPLETED_TASK_ID"
        log_error "Check /tmp/ralph_${AI_AGENT}_output.log for agent output"
        return 1
    fi

    # Validate task exists in PRD
    if ! jq -e --arg id "$completed_id" '.[] | select(.id == $id)' "$PRD_FILE" > /dev/null 2>&1; then
        log_error "Task '$completed_id' not found in $PRD_FILE"
        log_error "Agent may have reported wrong task ID or used example ID"
        return 1
    fi

    log_success "Agent reported completion of task: $completed_id"
    echo "$completed_id"  # Return the task ID
    return 0
}

# Create git commit for completed task
# Handles pre-commit hook failures gracefully
commit_task() {
    local task_id="$1"
    local task_desc="$2"

    git add -A

    local commit_msg="feat: Complete task $task_id

$task_desc

- Implemented feature as specified
- Updated PRD to mark task complete
- Logged progress

Co-Authored-By: Ralph Wiggum (AI Agent) <ralph@ai.local>"

    if git diff --cached --quiet; then
        log_warning "No changes to commit for task $task_id"
        return 0
    fi

    log_info "Attempting git commit..."
    local commit_exit_code=0
    git commit -m "$commit_msg" 2>&1 || commit_exit_code=$?

    if [ $commit_exit_code -eq 0 ]; then
        log_success "Created commit for task $task_id"
        return 0
    fi

    log_warning "Commit failed (exit code: $commit_exit_code). Checking for auto-formatted files..."

    # Check if pre-commit hooks modified files (auto-formatters)
    if ! git diff --quiet; then
        log_info "Detected files modified by pre-commit hooks. Re-staging and retrying..."
        git add -A

        local retry_exit_code=0
        git commit -m "$commit_msg" 2>&1 || retry_exit_code=$?

        if [ $retry_exit_code -eq 0 ]; then
            log_success "Created commit for task $task_id (after re-staging auto-formatted files)"
            return 0
        fi
        log_error "Commit failed after retry (exit code: $retry_exit_code)"
    else
        log_error "Commit failed - pre-commit hooks found issues that cannot be auto-fixed"
    fi

    # Optional: --no-verify fallback
    if [ "${RALPH_ALLOW_NO_VERIFY:-false}" = "true" ]; then
        log_warning "RALPH_ALLOW_NO_VERIFY is set. Attempting commit with --no-verify..."
        local noverify_exit_code=0
        git commit --no-verify -m "$commit_msg" 2>&1 || noverify_exit_code=$?

        if [ $noverify_exit_code -eq 0 ]; then
            log_warning "Created commit for task $task_id (with --no-verify, hooks skipped)"
            return 0
        fi
    fi

    log_error "Failed to commit task $task_id"
    return 1
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

        if [ "$remaining" -eq 0 ]; then
            log_success "All tasks complete!"
            echo "$COMPLETION_SIGNAL"
            exit 0
        fi

        # Execute task cycle - agent selects and implements
        log_info "Starting agentic task cycle..."
        local completed_task_id
        completed_task_id=$(execute_task_cycle)
        local exec_status=$?

        if [ $exec_status -ne 0 ] || [ -z "$completed_task_id" ]; then
            log_error "Task cycle failed"
            echo "Status: FAILED - Agentic task cycle error" >> "$PROGRESS_FILE"
            exit 1
        fi

        # Get description for logging
        local task_desc=$(jq -r --arg id "$completed_task_id" '.[] | select(.id == $id) | .description' "$PRD_FILE")

        # Append progress
        append_progress "$iteration" "$completed_task_id" "$task_desc"

        # Verify implementation
        log_info "Verifying implementation..."
        if ! verify_implementation; then
            log_error "Verification failed - CI must stay green!"
            echo "Status: FAILED - Verification checks failed" >> "$PROGRESS_FILE"
            exit 1
        fi

        # Mark task complete
        mark_task_complete "$completed_task_id"

        # Append success to progress
        echo "Status: ✓ COMPLETE" >> "$PROGRESS_FILE"
        echo "Verification: All checks passed" >> "$PROGRESS_FILE"

        # Commit changes
        if ! commit_task "$completed_task_id" "$task_desc"; then
            log_error "Failed to commit changes for task $completed_task_id"
            echo "Status: FAILED - Git commit failed (pre-commit hook issues)" >> "$PROGRESS_FILE"
            exit 1
        fi

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
