#!/bin/bash
# planning-with-files: User prompt submit hook for Codex
# Reused from the Cursor integration.

if [ -f .state/task_plan.md ]; then
    echo "[planning-with-files] ACTIVE PLAN — current state:"
    head -50 .state/task_plan.md
    echo ""
    echo "=== recent progress ==="
    tail -20 .state/progress.md 2>/dev/null
    echo ""
    echo "[planning-with-files] Read .state/findings.md for research context. Continue from the current phase."
fi
exit 0
