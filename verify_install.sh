#!/usr/bin/env bash
set -euo pipefail

# verify_install.sh
# Verifies install_ralph.sh functionality

TEST_DIR_NEW="test_install_new"
TEST_DIR_EXISTING="test_install_existing"
INSTALL_SCRIPT="./install_ralph.sh"

echo "Verifying install_ralph.sh..."

# Cleanup previous test runs
rm -rf "$TEST_DIR_NEW" "$TEST_DIR_EXISTING" "mock_claude_bin"

# Test Case 1: New Project (--new flag)
echo "---------------------------------------------------"
echo "Test 1: New Project (--new)"
echo "---------------------------------------------------"
mkdir -p "$TEST_DIR_NEW"
if ! "$INSTALL_SCRIPT" --new "$TEST_DIR_NEW"; then
    echo "Error: install_ralph.sh failed with --new"
    exit 1
fi
# Verify template PRD (simple check for "placeholder task")
if grep -q "placeholder task" "$TEST_DIR_NEW/plans/prd.json"; then
    echo "Pass: Template PRD created"
else
    echo "Fail: Template PRD content mismatch"
    exit 1
fi


# Test Case 2: Existing Project (Auto-gen attempt)
echo "---------------------------------------------------"
echo "Test 2: Existing Project (Auto-gen)"
echo "---------------------------------------------------"
mkdir -p "$TEST_DIR_EXISTING"

# Create a mock 'claude' command
mkdir -p mock_claude_bin
cat > "mock_claude_bin/claude" << 'EOF'
#!/bin/bash
# Mock Claude outputting a valid JSON PRD
echo '[{"id":"generated-1","description":"Generated Task","passes":false,"priority":1}]'
EOF
chmod +x "mock_claude_bin/claude"

# Run install script with mock claude in PATH
export PATH="$(pwd)/mock_claude_bin:$PATH"

if ! "$INSTALL_SCRIPT" "$TEST_DIR_EXISTING"; then
    echo "Error: install_ralph.sh failed for existing project"
    exit 1
fi

# Verify Generated PRD
if grep -q "Generated Task" "$TEST_DIR_EXISTING/plans/prd.json"; then
     echo "Pass: Generated PRD created using mock 'claude'"
else
     echo "Fail: Generated PRD content mismatch. Got:"
     cat "$TEST_DIR_EXISTING/plans/prd.json"
     exit 1
fi

echo "---------------------------------------------------"
echo "Verification Passed!"

# Cleanup
rm -rf "$TEST_DIR_NEW" "$TEST_DIR_EXISTING" "mock_claude_bin"
