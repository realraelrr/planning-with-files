#!/usr/bin/env bash
# Check if all phases in the active task_plan.md are complete.
# Always exits 0 — uses stdout for status reporting.
# Used by Stop hook to report task completion status.
#
# Plan-file resolution:
#   1. $1 (explicit path)
#   2. resolve-plan-dir.sh: Knot task roots -> $PLAN_ID -> .planning/.active_plan -> newest mtime -> .state
#   3. Legacy ./task_plan.md

if [ -n "${1:-}" ]; then
    PLAN_FILE="$1"
else
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd 2>/dev/null)" || SCRIPT_DIR="."
    RESOLVER="${SCRIPT_DIR}/resolve-plan-dir.sh"
    PLAN_DIR=""
    if [ -f "${RESOLVER}" ]; then
        PLAN_DIR="$(sh "${RESOLVER}" 2>/dev/null)"
    fi
    if [ -n "${PLAN_DIR}" ] && [ -f "${PLAN_DIR}/task_plan.md" ]; then
        PLAN_FILE="${PLAN_DIR}/task_plan.md"
    else
        PLAN_FILE="task_plan.md"
    fi
fi

if [ ! -f "$PLAN_FILE" ]; then
    echo "[planning-with-files] No $PLAN_FILE found — no active planning session."
    exit 0
fi

INCOMPLETE=$(grep -n "Status.*pending\\|Status.*in_progress\\|Status.*blocked" "$PLAN_FILE" || true)

if [ -z "$INCOMPLETE" ]; then
    echo "[planning-with-files] All phases complete."
    exit 0
fi

echo "[planning-with-files] Task incomplete:"
echo "$INCOMPLETE"
echo ""
echo "Complete all phases or update $PLAN_FILE before ending the session."
exit 0
