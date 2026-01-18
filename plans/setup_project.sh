#!/usr/bin/env bash
set -euo pipefail

# setup_project.sh
# Installs the Ralph framework into a target directory using templates from this script's directory

SKIP_PRD_GENERATION=false
TARGET_DIR="."
AI_AGENT="claude"  # Default AI agent

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --no-generate)
      SKIP_PRD_GENERATION=true
      shift # past argument
      ;;
    --agent=*)
      AI_AGENT="${1#*=}"
      shift # past argument
      ;;
    --agent)
      AI_AGENT="$2"
      shift # past argument
      shift # past value
      ;;
    *)
      TARGET_DIR="$1"
      shift # past argument
      ;;
  esac
done

# Validate AI agent selection
if [[ "$AI_AGENT" != "claude" && "$AI_AGENT" != "gemini" ]]; then
    echo "Error: Invalid AI agent '$AI_AGENT'. Must be 'claude' or 'gemini'."
    exit 1
fi

# The directory where this script (and the templates) resides
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Setting up Ralph framework in: $TARGET_DIR/plans"

# Create target plans directory
mkdir -p "$TARGET_DIR/plans"

# Copy Ralph script and make executable
if [ -f "$SOURCE_DIR/ralph.sh" ]; then
    cp "$SOURCE_DIR/ralph.sh" "$TARGET_DIR/plans/ralph.sh"
    chmod +x "$TARGET_DIR/plans/ralph.sh"
    echo "✓ Copied plans/ralph.sh"
else
    echo "Error: ralph.sh not found in template directory ($SOURCE_DIR)"
    exit 1
fi

# Copy explanation if it exists
if [ -f "$SOURCE_DIR/RALPH_EXPLANATION.md" ]; then
    cp "$SOURCE_DIR/RALPH_EXPLANATION.md" "$TARGET_DIR/plans/RALPH_EXPLANATION.md"
    echo "✓ Copied plans/RALPH_EXPLANATION.md"
fi

# Copy PRD generation prompt if it exists
if [ -f "$SOURCE_DIR/GENERATE_PRD_PROMPT.md" ]; then
    cp "$SOURCE_DIR/GENERATE_PRD_PROMPT.md" "$TARGET_DIR/plans/GENERATE_PRD_PROMPT.md"
    echo "✓ Copied plans/GENERATE_PRD_PROMPT.md"
fi

# Function to create default template PRD
create_template_prd() {
    cat > "$TARGET_DIR/plans/prd.json" << EOF
[
  {
    "id": "task-1",
    "description": "Initial task",
    "passes": false,
    "context": "This is a placeholder task."
  }
]
EOF
    echo "✓ Created default plans/prd.json"
}

# Handle PRD creation
if [ -f "$TARGET_DIR/plans/prd.json" ]; then
    echo "⚠ plans/prd.json already exists, skipping"
else
    if [ "$SKIP_PRD_GENERATION" = true ]; then
        create_template_prd
    else
        # Try to use Claude to generate PRD
        # Strategy: Try local 'claude' -> Try Docker 'claude' -> Fallback to template

        generate_prd_with_docker() {
            local prompt_file="$1"
            local project_path="$2"
            local agent="$3"

            echo "Attempting to generate prd.json using Docker sandbox ($agent)..."

            # Check if docker sandbox command is available
            if ! docker sandbox --help &> /dev/null; then
                echo "⚠ Docker sandbox command not available"
                echo "  This requires Docker Desktop with AI Sandboxes enabled"
                return 1
            fi

            # Read the PRD generation prompt
            local base_prompt=$(cat "$prompt_file")

            # Add project context by listing files
            echo "  Analyzing project structure..."
            local project_files=""
            if command -v rg &> /dev/null; then
                project_files=$(cd "$project_path" && rg --files 2>/dev/null | head -50 | sed 's/^/  - /')
            elif command -v fd &> /dev/null; then
                project_files=$(cd "$project_path" && fd -t f 2>/dev/null | head -50 | sed 's/^/  - /')
            else
                project_files=$(cd "$project_path" && find . -type f -not -path '*/\.*' 2>/dev/null | head -50 | sed 's/^/  - /')
            fi

            # Create full prompt with project context
            local full_prompt="${base_prompt}

## Project Files
${project_files}

## Instructions
Please analyze this project and generate a prd.json file with tasks to complete or improve this project.
Write the output to a file called 'prd.json' in the current directory.
The file should contain ONLY valid JSON (a JSON array of task objects), no markdown formatting."

            # Create temporary expect script
            local temp_expect=$(mktemp)
            cat > "$temp_expect" << 'EOFEXPECT'
#!/usr/bin/expect -f
set timeout 300
set prompt [lindex $argv 0]
set ai_agent [lindex $argv 1]

# Spawn docker sandbox run with the selected AI agent
spawn docker sandbox run $ai_agent --dangerously-skip-permissions -p $prompt

# Wait for command to complete
expect {
    eof {
        exit 0
    }
    timeout {
        puts "ERROR: Command timed out after 300 seconds"
        exit 1
    }
}
EOFEXPECT

            chmod +x "$temp_expect"

            # Execute in the target directory so PRD is written there
            local exit_code=0
            (cd "$project_path" && "$temp_expect" "$full_prompt" "$agent") 2>&1 | tee /tmp/ralph_prd_generation.log || exit_code=$?

            rm -f "$temp_expect"

            if [ $exit_code -ne 0 ]; then
                echo "⚠ Docker sandbox execution failed"

                # Check for authentication error
                if grep -q "Invalid API key" /tmp/ralph_prd_generation.log 2>/dev/null; then
                    echo ""
                    echo "Authentication Error Detected!"
                    echo "To fix this, authenticate the Docker sandbox:"
                    echo "  1. Run: docker sandbox run $agent"
                    echo "  2. In the session, run: /login"
                    echo "  3. Follow the authentication prompts"
                    echo "  4. Exit the session (Ctrl+D)"
                    echo "  5. Run simple-ralph again"
                    echo ""
                fi

                return 1
            fi

            # Check if prd.json was created in the target directory
            if [ -f "$project_path/prd.json" ]; then
                # Validate it's a JSON array
                if jq -e '. | type == "array"' "$project_path/prd.json" >/dev/null 2>&1; then
                    # Move to plans directory
                    mv "$project_path/prd.json" "$TARGET_DIR/plans/prd.json"
                    echo "✓ Generated plans/prd.json using Docker sandbox"
                    return 0
                else
                    echo "⚠ Generated file is not a valid JSON array"
                    cat "$project_path/prd.json" | head -10
                    rm -f "$project_path/prd.json"
                    return 1
                fi
            else
                echo "⚠ prd.json was not created by Claude"
                return 1
            fi
        }

        PRD_GENERATED=false
        PROMPT_FILE="$TARGET_DIR/plans/GENERATE_PRD_PROMPT.md"

        if [ -f "$PROMPT_FILE" ]; then
            # Get absolute path to project
            PROJECT_PATH="$(cd "$TARGET_DIR" && pwd)"

            # Try to generate PRD using Docker sandbox
            if generate_prd_with_docker "$PROMPT_FILE" "$PROJECT_PATH" "$AI_AGENT"; then
                PRD_GENERATED=true
            fi
        fi

        if [ "$PRD_GENERATED" = false ]; then
            echo ""
            echo "⚠ Could not generate PRD using AI. Falling back to template."
            echo ""
            echo "Solutions for PRD generation:"
            echo "  1. Manually edit plans/prd.json with your tasks (recommended)"
            echo "  2. Ensure Docker sandbox authentication: docker sandbox run $AI_AGENT, then /login"
            echo "  3. Use --no-generate flag for template PRD: simple-ralph --no-generate <project>"
            echo ""
            create_template_prd
        fi
    fi
fi

# Create progress.txt if it doesn't exist
if [ ! -f "$TARGET_DIR/plans/progress.txt" ]; then
    touch "$TARGET_DIR/plans/progress.txt"
    echo "✓ Created empty plans/progress.txt"
else
    echo "⚠ plans/progress.txt already exists, skipping"
fi

echo ""
echo "Ralph framework setup complete!"
echo "Usage: ./plans/ralph.sh [max_iterations]"
