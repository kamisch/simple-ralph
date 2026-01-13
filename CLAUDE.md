# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**simple-ralph** is a bash-based orchestration framework for AI coding agents. It implements the "Ralph Wiggum Technique" - a simple for-loop approach to incrementally complete tasks from a backlog (PRD), with tight feedback loops and automatic verification.

The framework is designed to be installed globally (`~/.ralph`) and used across multiple projects via the `simple-ralph` command.

## Key Architecture

### Core Components

1. **ralph.sh** - Main orchestration loop
   - Iterates through tasks in `prd.json`
   - Executes each task via Docker sandbox (AI agent invocation)
   - Runs verification checks (typecheck, tests, lint)
   - Commits completed tasks to git
   - Stops when all tasks are complete or max iterations reached

2. **prd.json** - Product Requirements Document
   - JSON array of task objects with `id`, `description`, `passes`, `priority`, `context`
   - Tasks marked `passes: false` are incomplete
   - Tasks marked `passes: true` are complete

3. **progress.txt** - Append-only execution log
   - Records iteration history, task descriptions, timestamps
   - Serves as memory across iterations

4. **setup_project.sh** - Project initialization
   - Copies Ralph templates into a project's `plans/` directory
   - Attempts to auto-generate `prd.json` using Claude CLI or Docker
   - Falls back to template PRD if AI generation fails

5. **install_ralph.sh** - Global installation
   - Installs Ralph to `~/.ralph/templates` and `~/.ralph/bin`
   - Creates `simple-ralph` wrapper command
   - Adds `~/.ralph/bin` to PATH

### File Structure

```
plans/
├── ralph.sh              # Main orchestration script
├── prd.json              # Task backlog (state)
├── progress.txt          # Execution log (memory)
├── RALPH_EXPLANATION.md  # Documentation
└── GENERATE_PRD_PROMPT.md # Prompt template for AI PRD generation
```

## Common Commands

### Installation

```bash
# Install Ralph globally
./install_ralph.sh

# Initialize Ralph in a new project
simple-ralph --new /path/to/project

# Initialize Ralph in existing project (creates template PRD)
simple-ralph /path/to/project

# Verify installation works correctly
./verify_install.sh
```

### Docker Sandbox Authentication (Required)

Ralph uses Docker Desktop's AI Sandboxes with Claude Code. **Before running ralph.sh, you must authenticate once:**

```bash
# 1. Start interactive Claude session
docker sandbox run claude

# 2. In the Claude session, authenticate
/login

# 3. Follow the prompts to log in with your Anthropic account

# 4. Exit the session (Ctrl+D or type 'exit')

# 5. Now ralph.sh can use the authenticated sandbox
```

**Important Notes:**
- Authentication persists across sandbox sessions (you only need to do this once)
- Ralph uses `expect` to automate the docker sandbox interaction
- The sandbox runs with `--dangerously-skip-permissions` and `-p` (print mode) for non-interactive execution
- If you see "Invalid API key" errors, re-run the authentication steps above

### Running Ralph

```bash
# Run up to 10 iterations (default)
./plans/ralph.sh

# Run up to N iterations
./plans/ralph.sh 20

# Ralph stops when:
# - All tasks are complete (outputs "promise complete here")
# - Max iterations reached
# - Any verification check fails
```

### PRD Management

```bash
# View remaining tasks
jq '.[] | select(.passes == false)' plans/prd.json

# Count incomplete tasks
jq '[.[] | select(.passes == false)] | length' plans/prd.json

# Manually mark task complete
jq 'map(if .id == "task-2" then .passes = true else . end)' \
   plans/prd.json > tmp.json && mv tmp.json plans/prd.json
```

## Development Workflow

1. **Define Tasks**: Create `plans/prd.json` with clear, atomic tasks
2. **Run Ralph**: Execute `./plans/ralph.sh <max_iterations>`
3. **Verification**: Script auto-runs typecheck/tests/lint after each task
4. **Review**: Check git commits and `progress.txt` for what was done
5. **Iterate**: Continue until "promise complete here" signal

## AI Agent Integration

The `execute_task()` function in `ralph.sh` invokes the AI agent via Docker Desktop's AI Sandboxes:

```bash
# Uses expect to automate docker sandbox interaction
docker sandbox run claude --dangerously-skip-permissions -p "$task_desc"
```

**Current Implementation**:
- Uses Docker Desktop's `docker sandbox` command with Claude Code
- Requires one-time authentication (see "Docker Sandbox Authentication" section)
- Uses `expect` to provide TTY for non-interactive automation
- Runs with `--dangerously-skip-permissions` (safe in sandbox) and `-p` (print mode)

**Required Dependencies**:
- Docker Desktop with AI Sandboxes enabled
- `expect` command (usually pre-installed on macOS/Linux)
- One-time authentication via `/login` in docker sandbox

**Customization Points**:
- Modify the `execute_task()` function in `ralph.sh` to use different AI agents
- Adjust timeout in expect script (default: 300 seconds)
- Change flags passed to claude command

### PRD Generation

The `setup_project.sh` script **does not auto-generate** `prd.json` because:

1. **Claude Code CLI is Interactive**: Requires TTY and user interaction, cannot output pure JSON to stdout
2. **Docker Sandbox Limitations**: Same interactive requirements as local CLI
3. **Authentication Required**: Even with auth, output format isn't suitable for JSON generation

**Solutions for PRD Creation**:
1. **Manual Creation** (Recommended): Edit `plans/prd.json` directly with your tasks
2. **API Generation**: Use `plans/GENERATE_PRD_PROMPT.md` with Anthropic API to generate custom PRD
3. **Template Start**: Use `--new` flag for template PRD: `simple-ralph --new /path/to/project`

## Verification Checks

Ralph enforces "CI green" by running these checks after each task (if available):

- **TypeScript**: `pnpm typecheck` (if `scripts.typecheck` exists in package.json)
- **Tests**: `pnpm test` (if `scripts.test` exists)
- **Linting**: `pnpm lint` (if `scripts.lint` exists, non-blocking)

Verification failures stop the script and prevent task completion.

## Task Best Practices

### Task Structure

```json
{
  "id": "task-X",
  "description": "Imperative, specific description (e.g., 'Add user login endpoint')",
  "passes": false,
  "priority": 1,
  "context": "File paths, dependencies, technical constraints, examples"
}
```

### Sizing Guidelines

- **Atomic**: Each task should be completable in one iteration
- **Verifiable**: Task completion should be testable
- **Independent**: Minimize cross-task dependencies
- **Clear**: Description should be unambiguous

### Priority Ordering

- Lower number = higher priority
- Order by dependencies (foundation → features)
- `ralph.sh` processes tasks sequentially from `prd.json`

## Dependencies

### Required System Tools
- `bash` (with `set -euo pipefail` support)
- `jq` (JSON processing)
- `git` (version control)
- `docker` - specifically Docker Desktop with AI Sandboxes enabled
- `expect` (for TTY automation) - usually pre-installed on macOS/Linux

### Docker Setup
1. Install [Docker Desktop](https://www.docker.com/products/docker-desktop/)
2. Enable AI Sandboxes (should be enabled by default in recent versions)
3. Pull the Claude Code image: `docker pull docker/sandbox-templates:claude-code`
4. Authenticate once: `docker sandbox run claude` then `/login`

### Optional (Project-Specific Verification)
- Node.js + pnpm (for TypeScript projects)
- Python + pytest (for Python projects)
- Rust + cargo (for Rust projects)

## Key Philosophy

1. **Single Task Focus**: One task at a time, never multitask
2. **Tight Feedback Loops**: Verify immediately after every change
3. **Keep CI Green**: Never commit breaking changes
4. **Simple State**: JSON file for tasks, text file for memory
5. **Incremental Progress**: Small commits, frequent updates

## Completion Signal

When all tasks have `passes: true`, Ralph outputs:
```
promise complete here
```

This signals the entire backlog is complete.

## Troubleshooting

### PRD Generation Fails

**Symptom**: `simple-ralph` falls back to template PRD with message "Could not generate PRD using AI"

**Common Causes**:
1. **Authentication Required**: Claude Code CLI requires login
   - Error: "Invalid API key · Please run /login"
   - Solution: Run `claude /login` or use Anthropic API directly

2. **Claude Code CLI Limitations**: Interactive tool, not suitable for simple text generation
   - Claude Code outputs to files, not stdout
   - Solution: Manually create `prd.json` or use the API

3. **Docker Image Missing**: Image not pulled
   - Solution: `docker pull docker/sandbox-templates:claude-code`

**Workarounds**:
- **Manual PRD**: Edit `plans/prd.json` directly with your tasks
- **API Generation**: Use `plans/GENERATE_PRD_PROMPT.md` with Anthropic API
- **Template Start**: Use `--new` flag for template PRD: `simple-ralph --new /path/to/project`

### Ralph Execution Fails

**Symptom**: `./plans/ralph.sh` fails with "Invalid API key" error

**Solution**: Authenticate the Docker sandbox once:
```bash
# 1. Start interactive session
docker sandbox run claude

# 2. Run login command
/login

# 3. Follow prompts to authenticate with Anthropic account

# 4. Exit session (Ctrl+D)

# 5. Try ralph.sh again
```

**Other Common Issues**:

1. **No Docker Desktop**: Error about `docker sandbox` command not found
   - Solution: Install Docker Desktop (docker sandbox requires Docker Desktop, not just Docker Engine)

2. **No expect command**: Error about expect not found
   - macOS/Linux: Usually pre-installed, otherwise `brew install expect` or `apt-get install expect`

3. **Sandbox already exists with different credentials**:
   - Solution: Remove existing sandbox with `docker sandbox rm <sandbox-id>`
   - Check sandboxes with `docker sandbox ls`

4. **TTY Issues**: Errors about "input device is not a TTY"
   - This should be handled by the expect script
   - If you see this, ensure `expect` is installed and executable
