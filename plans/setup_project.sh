#!/usr/bin/env bash
set -euo pipefail

# setup_project.sh
# Installs the Ralph framework into a target directory using templates from this script's directory

IS_NEW_PROJECT=false
TARGET_DIR="."

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --new)
      IS_NEW_PROJECT=true
      shift # past argument
      ;;
    *)
      TARGET_DIR="$1"
      shift # past argument
      ;;
  esac
done

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
    "priority": 1,
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
    if [ "$IS_NEW_PROJECT" = true ]; then
        create_template_prd
    else
        # Try to use Claude to generate PRD
        # Strategy: Try local 'claude' -> Try Docker 'claude' -> Fallback to template

        generate_prd_with_command() {
            local cmd="$1"
            local prompt_text="$2"

            echo "Attempting to generate prd.json using AI..."
            echo "  Command: ${cmd%% *}..."  # Show first part of command
            local temp_prd=$(mktemp)
            local temp_err=$(mktemp)

            # Execute command with prompt as argument
            set +e  # Temporarily disable exit on error to capture exit code
            $cmd "$prompt_text" > "$temp_prd" 2> "$temp_err"
            local exit_code=$?
            set -e  # Re-enable exit on error

            if [ $exit_code -eq 0 ]; then
                 # Basic validation: check if it's valid JSON array
                 if jq -e '. | type == "array"' "$temp_prd" >/dev/null 2>&1; then
                     mv "$temp_prd" "$TARGET_DIR/plans/prd.json"
                     echo "✓ Generated plans/prd.json using AI"
                     rm -f "$temp_prd" "$temp_err"
                     return 0
                 else
                     echo "⚠ Command succeeded but output is not a valid JSON array"
                     echo "  Output preview:"
                     head -5 "$temp_prd" | sed 's/^/    /'
                 fi
            else
                 echo "⚠ Command execution failed (exit code: $exit_code)"
            fi

            # Show error output if available
            if [ -s "$temp_err" ]; then
                echo "  Error output:"
                head -10 "$temp_err" | sed 's/^/    /'
            fi

            # Show stdout if it contains useful information
            if [ -s "$temp_prd" ] && [ ! -s "$temp_err" ]; then
                echo "  Output:"
                head -10 "$temp_prd" | sed 's/^/    /'
            fi

            rm -f "$temp_prd" "$temp_err"
            return 1
        }

        PRD_GENERATED=false
        PROMPT_FILE="$TARGET_DIR/plans/GENERATE_PRD_PROMPT.md"

        if [ -f "$PROMPT_FILE" ]; then
            # Read prompt content once
            PROMPT_CONTENT=$(cat "$PROMPT_FILE")

            # 1. Try local 'claude'
            if command -v claude &> /dev/null; then
                echo "Found local 'claude' command at: $(which claude)"
                # Check if it's Claude Code CLI (which won't work for simple text generation)
                if claude --version 2>&1 | grep -q "Claude Code"; then
                    echo "⚠ Detected Claude Code CLI, which may not work for PRD generation"
                    echo "  Claude Code is interactive and doesn't output JSON directly to stdout"
                    echo "  Skipping local claude and trying Docker instead..."
                else
                    if generate_prd_with_command "claude" "$PROMPT_CONTENT"; then
                        PRD_GENERATED=true
                    else
                        echo "⚠ Local 'claude' command failed"
                    fi
                fi
            fi

            # 2. Docker Sandbox is interactive and won't work for PRD generation
            # PRD generation requires outputting pure JSON to stdout, but docker sandbox
            # and Claude Code CLI are both interactive tools designed for coding sessions.
            # Users should either:
            # - Manually create prd.json
            # - Use the Anthropic API with GENERATE_PRD_PROMPT.md
            # - Use --new flag for template PRD
            if [ "$PRD_GENERATED" = false ]; then
                echo "⚠ Skipping Docker sandbox (interactive tool, not suitable for PRD generation)"
            fi
        fi

        if [ "$PRD_GENERATED" = false ]; then
            echo ""
            echo "⚠ Could not generate PRD using AI. Falling back to template."
            echo ""
            echo "Why PRD generation failed:"
            echo "  • Claude Code CLI (both local and docker sandbox) is an INTERACTIVE tool"
            echo "  • It requires a TTY (terminal) and doesn't output JSON to stdout"
            echo "  • Even with authentication, it opens an interactive coding session"
            echo ""
            echo "Solutions for PRD generation:"
            echo "  1. Manually edit plans/prd.json with your tasks (recommended)"
            echo "  2. Use plans/GENERATE_PRD_PROMPT.md with Anthropic API to generate PRD"
            echo "  3. Start with template and modify: simple-ralph --new <project>"
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
