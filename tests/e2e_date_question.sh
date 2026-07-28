#!/bin/bash
# Run the E2E date question test in headless mode
# Usage: ./tests/e2e_date_question.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Running E2E date question test..."
echo "Project root: $PROJECT_ROOT"

# Run nvim in headless mode with the test file
nvim --headless -c "PlenaryBustedFile lua/ask-openai/agents/e2e.tests.lua" -c "quit!"

echo "Test completed."
