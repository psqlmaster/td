#!/usr/bin/env bash
set -euo pipefail

# Test script for td - runs a scenario exercising main commands
# Usage: make the script executable and run it from the repository root:
#   chmod +x test.sh && ./test.sh

TD_PROG="$(cd "$(dirname "$0")" && pwd)/td"

TMP_XDG_DIR="$(mktemp -d)"
export XDG_CONFIG_HOME="${TMP_XDG_DIR}"

# Seed a test config so td will read predictable options for the test run.
mkdir -p "${XDG_CONFIG_HOME}/td"
cat > "${XDG_CONFIG_HOME}/td/tdrc" <<'EOF'
# td test config (isolated)
DEFAULT_ACTION=list
PRESERVE_QUEUE=false
PROJECTS_ONLY=false
QUEUE_MODE=lifo
LIST_ORDER=desc
EOF

cleanup() {
    echo "\nCleaning up: removing ${TMP_XDG_DIR}"
    rm -rf "${TMP_XDG_DIR}"
}
trap cleanup EXIT

echo "Using isolated XDG_CONFIG_HOME=${XDG_CONFIG_HOME}"

echo "\n=== Help ==="
"${TD_PROG}" H || true

echo "\n=== Show generated config (tdrc) ==="
cat "${XDG_CONFIG_HOME}/td/tdrc" || true

echo "\n=== Add tasks ==="
"${TD_PROG}" a "First task (no file)"
"${TD_PROG}" a README.md "Edit README for examples"
"${TD_PROG}" a src/main.py "Implement feature X"

echo "\n=== List (default LIST_ORDER=desc) ==="
LIST_ORDER=desc "${TD_PROG}" l

echo "\n=== List override: LIST_ORDER=asc ==="
# Rewrite the isolated config to use ascending order for this check
cat > "${XDG_CONFIG_HOME}/td/tdrc" <<'EOF'
DEFAULT_ACTION=list
PRESERVE_QUEUE=false
PROJECTS_ONLY=false
QUEUE_MODE=lifo
LIST_ORDER=asc
EOF
"${TD_PROG}" l

echo "\n=== Search for 'README' ==="
"${TD_PROG}" s README || true

echo "\n=== Pop/next (automatic context) ==="
"${TD_PROG}" n || true

echo "\n=== Add two more tasks ==="
"${TD_PROG}" a util.sh "Write helper script"
"${TD_PROG}" a docs.txt "Update docs"

echo "\n=== List now ==="
"${TD_PROG}" l

echo "\n=== Pop specific ID (2) ==="
"${TD_PROG}" n 2 || true

echo "\n=== Remove task ID 1 ==="
"${TD_PROG}" rm 1 || true

echo "\n=== Show history ==="
"${TD_PROG}" h || true

echo "\n=== Undo last change (restore last history) ==="
"${TD_PROG}" u || true

echo "\n=== Show history again ==="
"${TD_PROG}" h || true

echo "\n=== Undo specific history ID (if exists: 1) ==="
"${TD_PROG}" u 1 || true

echo "\n=== Show list after restores ==="
"${TD_PROG}" l || true

echo "\n=== Delete history entry 1 (rmh 1) ==="
HIST_PATH="${XDG_CONFIG_HOME}/td/td.lst.hist"
if [[ -s "${HIST_PATH}" ]]; then
    # delete the first history entry (HID 1)
    "${TD_PROG}" rmh 1 || true
else
    echo "No history entries to delete; skipping rmh."
fi

echo "\n=== Clear history (ch) ==="
"${TD_PROG}" ch || true

echo "\n=== Test clear active list (c) ==="
# add items again
"${TD_PROG}" a tmp1 "temp 1"
"${TD_PROG}" a tmp2 "temp 2"
"${TD_PROG}" l
"${TD_PROG}" c
"${TD_PROG}" l || true

echo "\n=== Test QUEUE_MODE=fifo ==="
# modify config to set fifo
echo "QUEUE_MODE=fifo" >> "${XDG_CONFIG_HOME}/td/tdrc"
echo "PRESERVE_QUEUE=false" >> "${XDG_CONFIG_HOME}/td/tdrc"
# ensure list is shown in oldest-first order for FIFO check
echo "LIST_ORDER=asc" >> "${XDG_CONFIG_HOME}/td/tdrc"
"${TD_PROG}" a fifo1 "fifo first"
"${TD_PROG}" a fifo2 "fifo second"
echo "List (should show fifo1 then fifo2):"
"${TD_PROG}" l
echo "Pop (should pop fifo1):"
"${TD_PROG}" n || true

echo "\n=== Test PRESERVE_QUEUE=true ==="
# enable preserve, add tasks and pop, item should remain
sed -i 's/PRESERVE_QUEUE=false/PRESERVE_QUEUE=true/' "${XDG_CONFIG_HOME}/td/tdrc" || true
"${TD_PROG}" a preserve_me "should remain after pop"
echo "Before pop:"
"${TD_PROG}" l
echo "Pop with preserve (task should remain):"
"${TD_PROG}" n || true
echo "After pop (task should still be listed):"
"${TD_PROG}" l || true

echo "\n=== Final state (list + history) ==="
"${TD_PROG}" l || true
"${TD_PROG}" h || true

echo "\nTest script finished. Temporary config removed on exit."
