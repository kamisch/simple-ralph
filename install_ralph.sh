#!/usr/bin/env bash
set -euo pipefail

# install_ralph.sh
# Installs the Ralph framework globally to ~/.ralph and creates 'simple-ralph' command

RALPH_HOME="$HOME/.ralph"
TEMPLATES_DIR="$RALPH_HOME/templates"
BIN_DIR="$RALPH_HOME/bin"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing Ralph framework globally..."

# 1. Setup ~/.ralph directories
echo "Creating $RALPH_HOME..."
mkdir -p "$TEMPLATES_DIR"
mkdir -p "$BIN_DIR"

# 2. Copy templates (Clean install)
echo "Installing templates..."
rm -rf "$TEMPLATES_DIR"/* # Ensure clean slate for updates
cp "$SOURCE_DIR"/plans/* "$TEMPLATES_DIR/"
chmod +x "$TEMPLATES_DIR/ralph.sh"
chmod +x "$TEMPLATES_DIR/setup_project.sh"
echo "✓ Templates installed to $TEMPLATES_DIR"

# 3. Create simple-ralph wrapper script
WRAPPER_SCRIPT="$BIN_DIR/simple-ralph"
cat > "$WRAPPER_SCRIPT" << EOF
#!/usr/bin/env bash
set -euo pipefail

# simple-ralph
# Wrapper to run the Ralph setup script from the global template directory

TEMPLATES_DIR="$TEMPLATES_DIR"
SETUP_SCRIPT="\$TEMPLATES_DIR/setup_project.sh"

if [ ! -f "\$SETUP_SCRIPT" ]; then
    echo "Error: Ralph setup script not found at \$SETUP_SCRIPT"
    echo "Please reinstall Ralph using install_ralph.sh"
    exit 1
fi

"\$SETUP_SCRIPT" "\$@"
EOF

chmod +x "$WRAPPER_SCRIPT"
echo "✓ Created simple-ralph command at $WRAPPER_SCRIPT"

# 4. Configure PATH
echo ""
echo "Configuring PATH..."

add_path_to_config() {
    local config_file="$1"
    local bin_dir="$2"
    
    if [ -f "$config_file" ]; then
        if grep -q "$bin_dir" "$config_file"; then
            echo "✓ PATH already configured in $config_file"
        else
            echo "" >> "$config_file"
            echo "# Added by Ralph installer" >> "$config_file"
            echo "export PATH=\"\$PATH:$bin_dir\"" >> "$config_file"
            echo "✓ Added $bin_dir to $config_file"
            echo "  Refreshed shell configuration is required. Please restart your terminal or run: source $config_file"
        fi
    fi
}

# Check common shell config files
FOUND_CONFIG=false
for config in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    if [ -f "$config" ]; then
        add_path_to_config "$config" "$BIN_DIR"
        FOUND_CONFIG=true
    fi
done

if [ "$FOUND_CONFIG" = false ]; then
    echo "Could not find .zshrc, .bashrc, or .bash_profile."
    echo "Please manually add the following to your shell configuration:"
    echo "export PATH=\"\$PATH:$BIN_DIR\""
fi

echo ""
echo "Installation complete!"
echo "Run 'simple-ralph --help' or 'simple-ralph --setup' to get started."
