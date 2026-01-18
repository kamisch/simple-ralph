# Simple Ralph 🚀

> "I'm helping!" - Ralph Wiggum

A minimal, focused orchestration framework for AI coding agents inspired by the Ralph Wiggum Technique. Simple Ralph uses a straightforward for-loop to incrementally complete a backlog of tasks, one at a time.

## Quick Summary

Simple Ralph implements the **Ralph Wiggum Technique**: a simple orchestration pattern that:

- **Single Task Focus**: Works on ONE task at a time, never multitasks
- **Agentic Selection**: The AI agent analyzes context and decides which task to work on
- **Tight Feedback Loops**: Verifies after every change (tests, type checks, linting)
- **Keeps CI Green**: Never commits breaking changes
- **Simple State**: JSON file for tasks (`prd.json`), text file for memory (`progress.txt`)

## Installation

### Quick Install

```bash
# Clone the repository
git clone <repository-url>
cd simple-ralph

# Run the installer
./install_ralph.sh
```

This installs Simple Ralph to `~/.ralph/` and creates the `simple-ralph` command.

The installer automatically adds `~/.ralph/bin` to your PATH by updating your shell config (`~/.zshrc`, `~/.bashrc`, or `~/.bash_profile`). Restart your terminal or run `source ~/.zshrc` (or equivalent) to apply.

## Usage

### 1. Initialize Your Project

Navigate to your project and run:

```bash
simple-ralph /path/to/your/project
```

This will:
1. Copy the template files into your project
2. **Auto-generate `prd.json`** by analyzing your codebase using AI

> **Important**: You must authenticate Docker sandbox first before running this command (see [Docker Sandbox Authentication](#docker-sandbox-authentication)).

#### Using Gemini Instead of Claude

To use Gemini for PRD generation:

```bash
simple-ralph --agent gemini /path/to/your/project
```

#### Skip PRD Generation

To copy just the empty templates without AI-generated tasks:

```bash
simple-ralph --no-generate /path/to/your/project
```

#### Files Created

- `plans/ralph.sh` - Main orchestration script
- `plans/prd.json` - Your task backlog (auto-generated or empty template)
- `plans/progress.txt` - AI agent's memory log
- `plans/RALPH_EXPLANATION.md` - Explanation of the Ralph technique
- `plans/GENERATE_PRD_PROMPT.md` - Prompt template for PRD generation

### 2. Define Your Tasks

Edit `plans/prd.json` to define your backlog:

```json
[
  {
    "id": "task-1",
    "description": "Set up project structure with configuration",
    "passes": false,
    "context": "Initialize the basic project scaffolding."
  },
  {
    "id": "task-2",
    "description": "Implement user authentication",
    "passes": false,
    "context": "Use JWT tokens for auth. Depends on task-1."
  }
]
```

- **id**: Unique identifier
- **description**: Clear, actionable task description
- **passes**: `false` = incomplete, `true` = complete
- **context**: Additional details for the AI agent

### 3. Run Ralph

```bash
cd your-project
./plans/ralph.sh 10  # Run up to 10 iterations
```

#### Selecting an AI Agent

By default, Ralph uses Claude. To use Gemini instead:

```bash
# Set the AI agent via environment variable
export RALPH_AI_AGENT=gemini
./plans/ralph.sh 10

# Or inline
RALPH_AI_AGENT=gemini ./plans/ralph.sh 10
```

Valid agents: `claude`, `gemini`

The script will:
1. Send the full backlog + recent history to the AI agent
2. Agent selects highest priority task and implements it
3. Runs verification checks
4. Marks task complete and commits changes
5. Repeats until all tasks are done or max iterations reached

## Custom Verification with `ralph-post-hook.sh`

Create a custom verification script in your project root:

```bash
#!/usr/bin/env bash
# ralph-post-hook.sh

set -euo pipefail

echo "Running custom verification..."

# Add your project-specific checks here:
npm test
npm run lint
npm run typecheck

# Python example:
# pytest
# mypy .
# flake8

# Rust example:
# cargo test
# cargo clippy

echo "All checks passed!"
```

Make it executable:

```bash
chmod +x ralph-post-hook.sh
```

If this file exists and is executable, Ralph will use it instead of auto-detected checks.

## Docker Sandbox Authentication

Simple Ralph uses Docker Desktop's sandbox feature to run AI coding agents in isolation. For more details, see the [Docker AI Sandboxes documentation](https://docs.docker.com/ai/sandboxes/).

### First-Time Setup

Before running `ralph.sh`, you must authenticate your workspace for the AI agent you want to use:

#### Claude

```bash
# Start an interactive sandbox session
docker sandbox run claude

# Inside the sandbox, authenticate:
/login

# Follow the prompts to complete authentication
# Then exit the sandbox
exit
```

#### Gemini

```bash
# Start an interactive sandbox session
docker sandbox run gemini

# Inside the sandbox, authenticate:
/login

# Follow the prompts to complete authentication
# Then exit the sandbox
exit
```

> **Note**: Authentication persists across sandbox sessions for the same workspace.

### Common Issues

| Issue | Solution |
|-------|----------|
| `Docker sandbox command not available` | Enable AI Sandboxes in Docker Desktop settings |
| `Invalid API key` | Run `/login` in an interactive sandbox session for your selected agent |
| Sandbox times out | Increase timeout in `ralph.sh` (default: 600s) |
| Wrong agent selected | Use `RALPH_AI_AGENT=gemini` or `RALPH_AI_AGENT=claude` |

## Project Structure

```
your-project/
├── plans/
│   ├── ralph.sh              # Orchestration script
│   ├── prd.json              # Task backlog
│   ├── progress.txt          # AI memory/log
│   ├── RALPH_EXPLANATION.md  # Technique explanation
│   └── GENERATE_PRD_PROMPT.md # PRD generation prompt
├── ralph-post-hook.sh        # (Optional) Custom verification
└── ... your code ...
```

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                    Ralph Main Loop                          │
├─────────────────────────────────────────────────────────────┤
│  for iteration in 1..max_iterations:                        │
│    1. Gather incomplete tasks from prd.json                 │
│    2. Read last 250 lines of progress.txt                   │
│    3. Send backlog + history to AI agent                    │
│    4. Agent selects highest priority task                   │
│    5. Agent implements the task                             │
│    6. Agent reports: COMPLETED_TASK_ID: task-X              │
│    7. Run verification (ralph-post-hook.sh or auto-detect)  │
│    8. Mark task complete in prd.json                        │
│    9. Append to progress.txt                                │
│   10. Git commit                                            │
│   11. If all tasks done → "promise complete here" → exit    │
└─────────────────────────────────────────────────────────────┘
```

## Best Practices

### Task Sizing
- Keep tasks small (completable in one iteration)
- Break large features into multiple tasks
- Each task should be independently verifiable

### Task Ordering
- The AI agent determines task order at runtime
- It analyzes dependencies, context, and project state
- Use the `context` field to hint at dependencies between tasks

### Context Field
- Include relevant file paths
- Mention dependencies on other tasks
- Provide examples or specifications

## Troubleshooting

### Script fails with "jq: command not found"
```bash
# macOS
brew install jq

# Linux
apt-get install jq
```

### Script fails with "expect: command not found"
```bash
# macOS
brew install expect

# Linux
apt-get install expect
```

### Agent did not report a COMPLETED_TASK_ID
Check `/tmp/ralph_claude_output.log` for the full agent output. The agent must include this exact line in its output:
```
COMPLETED_TASK_ID: task-X
```

### Verification failing
- Run your verification commands manually to debug
- Check that `ralph-post-hook.sh` is executable
- Ralph enforces CI green - fix issues before continuing

## License

MIT
