# The Ralph Wiggum Technique

> "I'm helping!" - Ralph Wiggum

## Overview

The Ralph Wiggum Technique is a simple, focused orchestration pattern for AI coding agents. Instead of complex planning systems, it uses a straightforward for-loop to incrementally complete a backlog of tasks, one at a time.

## Core Philosophy

1. **Single Task Focus**: Work on ONE task at a time, never multitask
2. **Tight Feedback Loops**: Verify after every change (typecheck, tests, etc.)
3. **Keep CI Green**: Never commit breaking changes
4. **Simple State Management**: JSON file for tasks, text file for memory
5. **Incremental Progress**: Small commits, frequent progress updates

## Architecture

```
plans/
├── ralph.sh       # Main orchestration script
├── prd.json       # Product Requirements Document (your todo list)
├── progress.txt   # Sprint memory/log (append-only)
└── RALPH_EXPLANATION.md
```

### The Loop

```
for iteration in 1..max_iterations:
    1. Find next incomplete task from prd.json
    2. Execute task (AI agent implements the feature)
    3. Verify (typecheck, tests, lint)
    4. Update prd.json (set passes: true)
    5. Append to progress.txt
    6. Git commit
    7. Check if all tasks complete → exit with "promise complete here"
```

## Files

### prd.json Structure

```json
[
  {
    "id": "task-1",
    "description": "Clear, actionable task description",
    "passes": false,
    "priority": 1,
    "context": "Additional context, dependencies, or notes"
  }
]
```

- **id**: Unique identifier for the task
- **description**: What needs to be done (clear, specific)
- **passes**: Boolean flag (false = incomplete, true = complete)
- **priority**: Optional numeric priority (lower = higher priority)
- **context**: Optional additional information for the AI agent

### progress.txt Format

```
================================================================================
Iteration 1 | 2026-01-11 14:30:00
Task: task-2
Description: Implement core Task class with JSON serialization
--------------------------------------------------------------------------------
Status: ✓ COMPLETE
Verification: All checks passed
```

Append-only log that serves as the AI agent's memory across iterations.

## Usage

### Basic Usage

```bash
# Run up to 10 iterations
./plans/ralph.sh 10

# Run up to 5 iterations
./plans/ralph.sh 5

# Run with default (10 iterations)
./plans/ralph.sh
```

### Integration with AI Agent

The script has a clearly marked section in the `execute_task()` function where you integrate your AI agent:

```bash
# AI AGENT INVOCATION POINT
# Examples:
#   1. Using Claude Code CLI:
#      echo "$task_desc" | claude-code --non-interactive
#
#   2. Using Anthropic API:
#      curl https://api.anthropic.com/v1/messages ...
#
#   3. Using custom agent:
#      your-ai-agent execute --task "$task_desc"
```

### Typical Workflow

1. **Define Tasks**: Create your `prd.json` with all tasks marked `passes: false`
2. **Run Ralph**: Execute `./plans/ralph.sh 20`
3. **Monitor Progress**: Watch the colored output as tasks complete
4. **Review Commits**: Check git history for what was done
5. **Read Progress**: Review `progress.txt` for AI's notes and decisions

## Verification Checks

The script automatically runs verification checks after each task. These checks are project-specific and should be adapted to your project's language and tools.

Examples:

- **Node.js/TypeScript**: `pnpm typecheck`, `pnpm test`, `pnpm lint`
- **Python**: `mypy .`, `pytest`, `flake8`
- **Rust**: `cargo check`, `cargo test`, `cargo clippy`

If any check fails (except linting warnings), the script stops and reports the error.

## Completion Signal

When all tasks have `passes: true`, the script outputs:

```
promise complete here
```

This signals that the entire backlog is complete.

## Benefits

### Context Window Management
- Single task focus prevents context overflow
- Each iteration is a clean slate
- Progress file provides continuity

### Reliability
- Tight verification loops catch issues early
- Git commits provide rollback points
- CI stays green (enforced)

### Simplicity
- No complex state machines
- Easy to understand and debug
- Bash script = minimal dependencies

### Transparency
- Clear logging at each step
- Git history shows exact work done
- Progress file captures AI reasoning

## Best Practices

### Task Sizing
- Keep tasks small (completable in one iteration)
- Break large features into multiple tasks
- Each task should be independently verifiable

### Task Ordering
- Use priority field for dependencies
- Start with foundational tasks (setup, core classes)
- Build incrementally

### Context Field
- Include relevant file paths
- Mention dependencies on other tasks
- Provide examples or specifications

### Progress Notes
- The AI should append useful notes to progress.txt
- Include key decisions made
- Note any technical debt or future work

## Example Session

```bash
$ ./plans/ralph.sh 10

[INFO] Starting Ralph Wiggum Technique orchestration
[INFO] Max iterations: 10

[INFO] ========================================
[INFO] Iteration 1 of 10
[INFO] ========================================
[INFO] Remaining tasks: 6
[INFO] Task ID: task-2
[INFO] Description: Implement core Task class with JSON serialization
[INFO] Executing task...
[INFO] Verifying implementation...
[INFO] Running TypeScript type check...
[SUCCESS] TypeScript type check passed
[INFO] Running tests...
[SUCCESS] Tests passed
[SUCCESS] Marked task 'task-2' as complete in PRD
[SUCCESS] Created commit for task task-2
[SUCCESS] Iteration 1 complete

[INFO] ========================================
[INFO] Iteration 2 of 10
[INFO] ========================================
[INFO] Remaining tasks: 5
...
```

## Customization

### Adding Custom Verification
Edit the `verify_implementation()` function to add checks:

```bash
verify_implementation() {
    # ... existing checks ...

    # Add custom check
    if [ -f "my-custom-check.sh" ]; then
        log_info "Running custom verification..."
        if ! ./my-custom-check.sh; then
            log_error "Custom check failed"
            return 1
        fi
    fi
}
```

### Changing Task Selection
Edit `get_next_task()` to change priority logic:

```bash
get_next_task() {
    # Get highest priority incomplete task
    local task=$(jq -r '.[] | select(.passes == false) | @json' "$PRD_FILE" \
        | jq -s 'sort_by(.priority) | .[0]')
    echo "$task"
}
```

## Troubleshooting

### Script fails with "jq: command not found"
Install jq: `brew install jq` (macOS) or `apt-get install jq` (Linux)

### Script fails with "git: command not found"
Install git: `brew install git` (macOS) or `apt-get install git` (Linux)

### Tasks not completing
- Check that your AI agent invocation in `execute_task()` is working
- Verify the AI agent is making actual code changes
- Check git status to see if files were modified

### Verification failing
- Run your project's verification commands manually (e.g., `pnpm typecheck`, `cargo check`, `pytest`)
- Fix the issues before continuing
- Ralph enforces CI green!

## Philosophy

The name "Ralph Wiggum" comes from The Simpsons character who, despite being simple, is genuinely helpful and sincere. This technique embodies that spirit:

- **Simple**: Just a bash script with a for-loop
- **Helpful**: Gets work done incrementally
- **Sincere**: No tricks, no magic, just honest iteration
- **Focused**: One task at a time, like Ralph focused on one thing

"I'm learnding!" - Ralph captures the essence of incremental progress.
